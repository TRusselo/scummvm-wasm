#!/usr/bin/env python3
"""Check our engine lists and docs against what ScummVM upstream actually says.

Every upstream fact here -- whether ScummVM ships an engine, whether its games
are stable, whether it is a top-level engine or a subengine -- is read from the
`upstream/master` ref of the scummvm-core checkout, via git, never from the
working tree. The working tree is whatever we last rebased onto, and a check
that reads it only agrees with itself: on 2026-09-08 macs2 and macventure were
dropped from our list because the pinned tree still said `no` after upstream
had flipped them to `yes`, and this script blessed it for four days.

Fetch first if you want today's answer (`git -C scummvm-core fetch upstream`);
the header line prints the commit and date actually used. If the ref is
missing the script falls back to the working tree and says so loudly.

Run it directly, or let build/build-core.sh run it after a build.
Exit status is 0 unless --strict is passed, so it never breaks a build by
itself.
"""
import argparse
import collections
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CORE = os.path.join(ROOT, "scummvm-core", "engines")
LISTS = os.path.join(ROOT, "build", "engine-lists")

# Detection flags that mean an entry is not a testable target.
# UNSUPPORTED is explicitly "ScummVM will not run this"; PIRATED entries are
# refused by cleanupPirated(). Both were missing from an earlier version of
# this list, which made gamos -- every game ADGF_TESTING or ADGF_UNSUPPORTED --
# look like it had stable games to test.
UNVOUCHED = ("UNSTABLE", "TESTING", "UNSUPPORTED", "PIRATED")


UPSTREAM_REF = "upstream/master"


def read_list(name):
    path = os.path.join(LISTS, name)
    if not os.path.exists(path):
        return []
    with open(path) as fh:
        return [ln.strip() for ln in fh if ln.strip()]


class GitSource:
    """Reads engines/ from a git ref of the scummvm-core checkout."""

    def __init__(self, core, ref):
        self.core, self.ref = core, ref
        self._files = None

    def _git(self, *args):
        return subprocess.run(["git", "-C", self.core, *args],
                              capture_output=True, text=True, check=True).stdout

    def describe(self):
        out = self._git("log", "-1", "--format=%h %cs", self.ref).strip()
        return "%s @ %s" % (self.ref, out)

    def files(self):
        if self._files is None:
            out = self._git("ls-tree", "-r", "--name-only", self.ref, "engines/")
            self._files = out.split()
        return self._files

    def engine_dirs(self):
        return sorted({f.split("/")[1] for f in self.files()
                       if f.count("/") >= 2})

    def read(self, path):
        try:
            return self._git("show", "%s:%s" % (self.ref, path))
        except subprocess.CalledProcessError:
            return None


class TreeSource:
    """Fallback: the working tree. Only used when the ref is missing."""

    def __init__(self, core):
        self.core = core

    def describe(self):
        return "WORKING TREE (no %s ref found -- flags may be stale)" % UPSTREAM_REF

    def files(self):
        out = []
        for dirpath, _d, fns in os.walk(os.path.join(self.core, "engines")):
            for fn in fns:
                out.append(os.path.relpath(os.path.join(dirpath, fn), self.core))
        return out

    def engine_dirs(self):
        base = os.path.join(self.core, "engines")
        return sorted(e for e in os.listdir(base)
                      if os.path.isdir(os.path.join(base, e)))

    def read(self, path):
        try:
            with open(os.path.join(self.core, path), encoding="utf-8",
                      errors="ignore") as fh:
                return fh.read()
        except OSError:
            return None


def open_source(core):
    try:
        subprocess.run(["git", "-C", core, "rev-parse", "--verify", "--quiet",
                        UPSTREAM_REF + "^{commit}"],
                       capture_output=True, check=True)
        return GitSource(core, UPSTREAM_REF)
    except (subprocess.CalledProcessError, OSError):
        return TreeSource(core)


def upstream_engines(src):
    """Every add_engine declaration upstream, keyed by engine name.

    Parses every line of every configure.engine, not just the first, and does
    not split on whitespace -- both traps cost real time on 2026-09-08. A
    one-word quoted description shifts the columns, and subengines are declared
    on later lines of the same file.
    """
    out = {}
    pattern = re.compile(r'add_engine\s+(\S+)\s+"([^"]*)"\s+(\S+)')
    dirs = set(src.engine_dirs())
    for entry in sorted(dirs):
        txt = src.read("engines/%s/configure.engine" % entry)
        if txt is None:
            continue
        for line in txt.splitlines():
            if line.lstrip().startswith("#"):
                continue
            m = pattern.search(line)
            if m:
                name, desc, default = m.group(1), m.group(2), m.group(3)
                out[name] = {
                    "desc": desc,
                    "default": default,
                    "toplevel": name in dirs,
                }
    return out


def detection_flags(src, engine):
    """Count detection entries that ScummVM vouches for, and ones it does not.

    Classified per line, not per flag token. Counting tokens is wrong: an entry
    flagged ADGF_TESTING routinely also carries ADGF_DROPPLATFORM or
    ADGF_DEMO, so a token tally makes an engine whose every game is in testing
    look like it has stable ones. A detection entry is stable only if its own
    flags include neither ADGF_UNSTABLE nor ADGF_TESTING.
    """
    counts = collections.Counter()
    prefix = "engines/%s/" % engine
    for path in src.files():
        if not path.startswith(prefix):
            continue
        fn = path.rsplit("/", 1)[-1]
        if not fn.endswith((".h", ".cpp")):
            continue
        if not re.search(r"detect|table", fn, re.I):
            continue
        txt = src.read(path)
        if txt is None:
            continue
        for line in txt.splitlines():
            if "ADGF_" not in line:
                continue
            if re.search(r"#\s*define|^\s*(//|\*)", line):
                continue
            unvouched = any(("ADGF_" + f) in line for f in UNVOUCHED)
            counts["unvouched" if unvouched else "stable"] += 1
    return counts


def readme_status():
    """Map engine name -> status symbol, across every table format in README.

    The README carries several tables describing the same engines with the
    status in different columns, and in one case inline as prose. Matching a
    symbol anywhere in a row keyed by the engine name is the only read that
    sees all of them; a stricter parse silently undercounts (it missed
    freescape, grim, tinsel and wintermute on 2026-09-10).
    """
    syms = ["✅", "⚠️", "🚫", "🔒", "⏸️", "❓", "⬜"]
    found = collections.defaultdict(set)
    path = os.path.join(ROOT, "README.md")
    if not os.path.exists(path):
        return {}
    for line in open(path, encoding="utf-8").read().splitlines():
        m = re.match(r"^\|\s*([a-z0-9_]+)\s*\|", line)
        if not m:
            continue
        for s in syms:
            if s in line:
                found[m.group(1)].add(s)
    return {e: next((s for s in syms if s in v), None) for e, v in found.items()}


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--strict", action="store_true",
                    help="exit non-zero if anything needs attention")
    args = ap.parse_args()

    core = os.path.dirname(CORE)
    if not os.path.isdir(CORE) or not os.listdir(CORE):
        print("check-engines: scummvm-core/engines is empty -- submodule not "
              "checked out here. Nothing checked.", file=sys.stderr)
        return 0

    src = open_source(core)
    main_list = read_list("all-engines.list")
    gl_list = read_list("gl-core.list")
    ours = set(main_list) | set(gl_list)
    up = upstream_engines(src)
    status = readme_status()

    top = [e for e in main_list if up.get(e, {}).get("toplevel")]
    subs = [e for e in main_list if e not in top]
    confirmed = [e for e in top if status.get(e) == "✅"]
    unconfirmed = [e for e in top if status.get(e) != "✅"]

    problems = 0

    print("=" * 72)
    print("ENGINE CHECK")
    print("=" * 72)
    print("  all-engines.list : %3d  (%d top-level + %d subengines)"
          % (len(main_list), len(top), len(subs)))
    print("  gl-core.list     : %3d" % len(gl_list))
    print("  confirmed        : %3d of %d top-level" % (len(confirmed), len(top)))
    print("  upstream            : %3d declarations" % len(up))
    print("  source           : %s" % src.describe())

    # --- engines upstream that we list nowhere ---
    unlisted = [n for n in sorted(up)
                if n not in ours and n not in ("testbed", "playground3d")]
    # Our list tracks ScummVM's release set (what a stock ./configure builds,
    # which is the add_engine flag -- see docs/GOTCHAS.md "Our engine list
    # overrides..."). Engines outside that set are expected to be absent from
    # our lists; that is the policy, not a finding. Only engines ScummVM ships
    # and we do not carry need a decision.
    needs_triage = [n for n in unlisted if up[n]["default"] == "yes"]
    expected = [n for n in unlisted if up[n]["default"] != "yes"]

    if needs_triage:
        problems += 1
        print("\nUPSTREAM SHIPS THESE, WE DO NOT -- need triage (%d):"
              % len(needs_triage))
        for n in needs_triage:
            f = detection_flags(src, n)
            stable = "no stable games" if f["stable"] == 0 and f["unvouched"] \
                else ("stable games" if f["unvouched"] == 0 else "mixed")
            print("  %-16s %-18s %s" % (n, stable, up[n]["desc"]))
        print("  -> newly added upstream, or dropped by mistake. Add to"
              " all-engines.list or gl-core.list, or record why not.")
    if expected:
        print("\nnot in ScummVM's release set, so not in our lists: %d"
              % len(expected))

    # --- engines we list that upstream no longer declares ---
    gone = sorted(e for e in ours if e not in up)
    if gone:
        problems += 1
        print("\nLISTED BUT GONE FROM UPSTREAM (%d):" % len(gone))
        for e in gone:
            print("  %s" % e)

    # --- engines we ship that ScummVM does not ---
    shipped_but_not = sorted(e for e in main_list
                             if up.get(e, {}).get("default") == "no")
    if shipped_but_not:
        problems += 1
        print("\nIN OUR LIST, NOT IN SCUMMVM'S RELEASE SET (%d):"
              % len(shipped_but_not))
        for e in shipped_but_not:
            print("  %s" % e)
        print("  -> our list tracks ScummVM's release set; remove these or"
              " record why not (gl-core.list is the recorded exception).")

    # --- what is actually left to test ---
    worth, out_of_scope = [], []
    for e in unconfirmed:
        f = detection_flags(src, e)
        (out_of_scope if f["stable"] == 0 and f["unvouched"] else worth).append(e)
    print("\nUNCONFIRMED TOP-LEVEL ENGINES (%d):" % len(unconfirmed))
    print("  worth testing (have stable games) : %2d  %s"
          % (len(worth), " ".join(sorted(worth))))
    print("  every game TESTING/UNSTABLE       : %2d  %s"
          % (len(out_of_scope), " ".join(sorted(out_of_scope))))
    print("  -> the second group is out of scope by the"
          " no-unstable/testing-games rule.")

    # --- do the README's own numbers still hold ---
    readme = open(os.path.join(ROOT, "README.md"), encoding="utf-8").read()
    # Only sentences that are actually about engine counts -- a bare
    # "N of M" also matches prose like "2 of 3" and produces noise.
    claims = set(re.findall(
        r"(\d+)\s+of\s+(?:the\s+)?(\d+)(?=[^.\n]{0,40}engines?\b)"
        r"|(\d+)\s+of\s+(?:the\s+)?(\d+)\s+confirmed", readme))
    claims = set((a or c, b or d) for a, b, c, d in claims)
    bad = [c for c in claims
           if (int(c[0]), int(c[1])) != (len(confirmed), len(top))]
    if bad:
        problems += 1
        print("\nREADME COUNT CLAIMS THAT NO LONGER MATCH (%d of %d):"
              % (len(confirmed), len(top)))
        for a, b in sorted(bad):
            print("  README says %s of %s" % (a, b))

    print()
    if problems:
        print("check-engines: %d area(s) need attention." % problems)
    else:
        print("check-engines: lists and counts agree with upstream.")
    print("=" * 72)
    return 1 if (problems and args.strict) else 0


if __name__ == "__main__":
    sys.exit(main())
