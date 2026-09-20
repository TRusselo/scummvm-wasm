# Carrying EmulatorJS divergence on a branch, exported to patches

Design, 2026-09-19. Approved in outline before writing; see "Decision" for
what was chosen over what.

## Goal

Make an EmulatorJS pin bump a reviewable operation instead of a hand re-cut,
without changing how the build consumes our changes, and without losing the
distinction between the three kinds of change we carry.

## Why now

Upstream `f4f0f1c` ("Split backend and frontend", #1247) moved 4535 lines out
of `data/src/emulator.js` into a new `data/src/frontend.js`. Six of our ten
patches stopped applying at once. `patch(1)` cannot follow code that moves: it
matches context and rejects, so a restructure upstream costs us a manual re-cut
of everything that touched the moved region.

That is the recurring cost this design removes. It is not a one-off.

## The three categories

Every change we carry is exactly one of:

1. **An open upstream PR.** Patch 08 is EmulatorJS/EmulatorJS#1270.
2. **A prospective PR.** Patch 11, drafted as PR 27, held for test and rebase.
3. **Legitimate divergence.** Patches 01, 02, 04, 09, 10. Not upstreamable as
   PRs. The only route they could ever take upstream is as build-time patches,
   if EmulatorJS one day builds our core the way it builds its others.

The design has to keep these separable, because the correct action on a bump
differs per category: a merged PR is dropped, a prospective PR is kept and
rebased, and divergence is kept indefinitely.

## Measured findings

Dry runs against a clean worktree, full chain in `assemble.sh` order.

At `13ce942`, the commit immediately below the split:

| Patch | Result |
| --- | --- |
| 01 cache-streaming | applies clean |
| 02 emulator-onfile | 3 of 9 hunks rejected -- all three are the decompression-progress work merged as #1271 |
| 03b canvas-pointer | already applied upstream (#1268) |
| 04 savestate-retry | applies clean |
| 05 download-debug | already applied upstream (#1267) |
| 06 parse-core-report | already applied upstream (#1269) |
| 08 message-severity | applies clean |
| 09 loadstate-retry | applies clean |
| 10 quickload-host-event | applies clean |
| 11 english-variant | applies clean |

At `f4f0f1c`, head, the same chain additionally needs 04 and 08 relocated into
`frontend.js` with every `this.config`, `this.debug` and `this.displayMessage`
rewritten to `this.ejs.*`, because `frontend.js` is a separate class holding a
back-reference to the emulator.

The split is the newest commit. All four of our merged PRs sit below it, so
pinning below the split loses nothing we want.

A caution recorded because it produced a wrong answer during this work:
dry-running patch 08 on a pristine tree reports failures that are not real. It
expects 04 and 09 to have been applied first, which `assemble.sh` does and an
isolated dry run does not. Per-patch dry runs are not evidence; the chain in
order is.

## Decision

Three steps, in order, rather than one bump to head.

Rejected: **bump straight to head.** It is the hardest re-cut we have faced,
against a one-day-old restructure, with no machinery to help, landing in the
same round as three patch deletions -- so a test failure could not be
attributed to either half.

Rejected: **pin below the split and stop.** Correct as far as it goes, but the
debt grows as upstream builds on the new layout, and it leaves the recurring
cost unaddressed.

Chosen: **prove the machinery where the answer is already known, then use it
for the hard bump.**

## Step 1 -- machinery only, pin unchanged

Pin stays `0b1c5e9`. Build the branch from today's patches, export them back
out, and require `assemble.sh` to produce a tree **byte-identical to what it
produces today**.

Not the patch files: those differ in header format by design. The output tree,
which is what ships.

At the current pin every patch applies clean by definition, so any difference
is the machinery being wrong and says so immediately. This is the only moment
where the correct answer is known in advance. After the pin moves, a
discrepancy is ambiguous -- machinery bug, or genuine upstream change, with no
way to distinguish them.

No behaviour change, so no game testing.

## Step 2 -- the bump (Build B)

Rebase the branch onto `13ce942`. Drop the three commits `git cherry` marks as
already upstream. Delete the three merged hunks from the `onFile` commit.
Export, assemble, build, test.

The output tree should now differ, and every difference should be attributable
to a commit deliberately dropped.

## Step 3 -- the split (Build D)

Rebase the branch onto `f4f0f1c`, as its own build with its own test pass,
after the restructure has had time to settle upstream.

**What the branch does not do here.** Git detects renames on whole files. This
was a partial extraction, not a rename: git will see one heavily modified file
and one new file, and will not follow our hunks into `frontend.js` nor rewrite
`this.` into `this.ejs.`. Build D is manual work either way.

What the branch does give:

- conflicts arrive one commit at a time with three-way context, instead of a
  pile of `.rej` files with no base to compare against
- each resolution is reviewable as an ordinary diff, and `git rerere` remembers
  it if the rebase has to be redone
- a botched resolution fails an `assemble.sh` verification marker rather than
  landing a hunk silently in the wrong place

## The branch

Base is the upstream pin; one commit per logical change. Pushed to
`TRusselo/EmulatorJS` as a long-lived branch, so PR branches cut straight off
it and it survives this machine.

At Build B it carries seven commits: cache streaming, onFile plumbing,
savestate retry, message severity, loadstate retry, quickload host event, and
the English-locale langJson fix.

`zipstream.js` stays a file copy in `assemble.sh`. It is a new file we add,
never a modification of theirs, so nothing about it benefits from the branch.

Category is recorded as a commit trailer:

```
Upstream-PR: EmulatorJS/EmulatorJS#1270
Upstream-PR: draft
Divergence: build-time only
```

In the commit rather than a side table, because it survives every rebase
automatically and cannot drift from the code it describes. `docs/pr/PR-DRAFTS.md`
remains the narrative record; the trailer is the machine-checkable fact, and
answers "which of these are build-time patches" with one `git log --grep`.

## Export

`build/emulatorjs/export-patches.sh`: for each commit in `<pin>..ours`, write
`git diff` of that commit to `patches/NN-name.patch`. Filenames keep their
existing numbers and slugs so `assemble.sh` references and its ordering
comments do not move.

**Format is unified to `-p1`.** Today most patches are headerless `diff -u`
applied to an explicitly named file, while 08 keeps headers and uses `-p1`;
`assemble.sh` documents the reason as "the patches come from plain `diff -u`".
That was a consequence of hand-production. Git emits headers for free, so every
patch applies with `patch -p1 -d "$WORK/ejs"` uniformly.

This deletes the special case and removes a footgun: a headerless patch aimed at
the wrong file produces a plausible-looking failure, which is exactly the error
that made an isolated dry run of 08 misreport during this work.

## Bump procedure, once in place

```
git fetch upstream
git rebase --onto <new-pin> <old-pin> ours
git cherry -v <new-pin> ours      # '-' marks what upstream already has
# drop the '-' commits, resolve conflicts
./build/emulatorjs/export-patches.sh
./build/emulatorjs/assemble.sh <out> --force
```

**The drop rule is `git cherry`, not judgement.** It marks every commit whose
change upstream already carries. This is what identifies 03b, 05 and 06
mechanically instead of by grepping for a marker and guessing, and it is the
only check that catches a *partial* uptake -- patch 02's three merged hunks are
precisely the case where inspection says "still ours" and `git cherry` does not.

When a PR merges, the same motion applies: the commit is marked, dropped, and
its patch file, `assemble.sh` line and verification marker go with it.

## Verification

`assemble.sh`'s per-patch grep markers stay unchanged. They check the assembled
tree rather than the patches, so they are independent of this machinery and
remain the backstop when an export or a rebase goes wrong.

Per step:

- Step 1: output tree byte-identical to today's. No game testing.
- Step 2: full round-5 test set. Differences in the tree all attributable to
  dropped commits.
- Step 3: full test set, treated as the highest-risk build of the three.

## Out of scope

- The RomM rebase (Build C). Independent, tracked in `docs/REBASE-PLAN.md`.
- Opening PR 27. Held for test and rebase, tracked in `docs/pr/PR-DRAFTS.md`.
- Completing `en.json`'s 81 missing strings. Separate upstream change, and it
  would not fix the dynamic labels anyway.
