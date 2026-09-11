#!/usr/bin/env python3
"""Check our engine lists and docs against what ScummVM upstream actually says.

scummvm-core is the source of truth. Everything this project asserts about an
engine -- whether ScummVM ships it, whether its games are stable, whether it is
a top-level engine or a subengine -- is read from the submodule here and diffed
against our lists and README. Those assertions go stale silently on every
rebase: on 2026-09-10 four of them were wrong at once (colony's renderer,
sixteen "inert" engines that were being built, sludge's stability, chamber's
build flag), each written down once and trusted for weeks.

Run it directly, or let build/build-core.sh run it after a build.
Exit status is 0 unless --strict is passed, so it never breaks a build by
itself.
"""
import argparse
import collections
import os
import re
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


def read_list(name):
    path = os.path.join(LISTS, name)
    if not os.path.exists(path):
        return []
    with open(path) as fh:
        return [ln.strip() for ln in fh if ln.strip()]


def upstream_engines():
    """Every add_engine declaration upstream, keyed by engine name.

    Parses every line of every configure.engine, not just the first, and does
    not split on whitespace -- both traps cost real time on 2026-09-08. A
    one-word quoted description shifts the columns, and subengines are declared
    on later lines of the same file.
    """
    out = {}
    pattern = re.compile(r'add_engine\s+(\S+)\s+"([^"]*)"\s+(\S+)')
    for entry in sorted(os.listdir(CORE)):
        cfg = os.path.join(CORE, entry, "configure.engine")
        if not os.path.isfile(cfg):
            continue
        with open(cfg, encoding="utf-8", errors="ignore") as fh:
            for line in fh:
                if line.lstrip().startswith("#"):
                    continue
                m = pattern.search(line)
                if m:
                    name, desc, default = m.group(1), m.group(2), m.group(3)
                    out[name] = {
                        "desc": desc,
                        "default": default,
                        "toplevel": os.path.isdir(os.path.join(CORE, name)),
                    }
    return out


def detection_flags(engine):
    """Count detection entries that ScummVM vouches for, and ones it does not.

    Classified per line, not per flag token. Counting tokens is wrong: an entry
    flagged ADGF_TESTING routinely also carries ADGF_DROPPLATFORM or
    ADGF_DEMO, so a token tally makes an engine whose every game is in testing
    look like it has stable ones. A detection entry is stable only if its own
    flags include neither ADGF_UNSTABLE nor ADGF_TESTING.
    """
    counts = collections.Counter()
    base = os.path.join(CORE, engine)
    if not os.path.isdir(base):
        return counts
    for dirpath, _dirs, files in os.walk(base):
        for fn in files:
            if not fn.endswith((".h", ".cpp")):
                continue
            if not re.search(r"detect|table", fn, re.I):
                continue
            try:
                txt = open(os.path.join(dirpath, fn), encoding="utf-8",
                           errors="ignore").read()
            except OSError:
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

    if not os.path.isdir(CORE) or not os.listdir(CORE):
        print("check-engines: scummvm-core/engines is empty -- submodule not "
              "checked out here. Nothing checked.", file=sys.stderr)
        return 0

    main_list = read_list("all-engines.list")
    gl_list = read_list("gl-core.list")
    ours = set(main_list) | set(gl_list)
    up = upstream_engines()
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

    # --- engines upstream that we list nowhere ---
    unlisted = [n for n in sorted(up)
                if n not in ours and n not in ("testbed", "playground3d")]
    # Engines ScummVM itself does not ship are expected to be absent from our
    # lists -- that is the policy, not a finding. Only default=yes engines we
    # do not carry actually need a decision.
    needs_triage = [n for n in unlisted if up[n]["default"] == "yes"]
    expected = [n for n in unlisted if up[n]["default"] != "yes"]

    if needs_triage:
        problems += 1
        print("\nUPSTREAM SHIPS THESE, WE DO NOT -- need triage (%d):"
              % len(needs_triage))
        for n in needs_triage:
            f = detection_flags(n)
            stable = "no stable games" if f["stable"] == 0 and f["unvouched"] \
                else ("stable games" if f["unvouched"] == 0 else "mixed")
            print("  %-16s %-18s %s" % (n, stable, up[n]["desc"]))
        print("  -> newly added upstream, or dropped by mistake. Add to"
              " all-engines.list or gl-core.list, or record why not.")
    if expected:
        print("\nnot carried, as intended (build-by-default=no upstream): %d"
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
        print("\nWE SHIP, SCUMMVM DOES NOT (build-by-default=no) (%d):"
              % len(shipped_but_not))
        for e in shipped_but_not:
            print("  %s" % e)
        print("  -> ScummVM's releases omit these; ours should too.")

    # --- what is actually left to test ---
    worth, out_of_scope = [], []
    for e in unconfirmed:
        f = detection_flags(e)
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
