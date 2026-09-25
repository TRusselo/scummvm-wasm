# Rebase and next-build plan

> **Superseded 2026-09-24** by `docs/superpowers/plans/2026-09-24-upstream-rebase-and-cleanup.md`. Kept as the record of the September 19 rebases.

Written 2026-09-19, after round 4 passed. Splits the queued work into builds
that can each be tested on their own. Measured, not estimated: every number
below came from a dry run against the current upstream head.

Baseline is image `c5597ef9ca27`, the round-4 build. It is the only rollback
that exists, so it stays until a later build has passed.

## Why split at all

Three of the queued items are additive and cannot plausibly break a load. The
other two re-cut patches against a restructured upstream. Shipping them
together means a failed round cannot say which half caused it, and the rebases
are the half that will need iterating.

Order below is Tristyn's: strings first, then the rest.

## Build A -- strings and instrumentation

No rebase, no upstream movement, no patch re-cutting.

1. **Three reworded core messages.** Already committed to `scummvm-core`, never
   built. SCI leads with the action, the two busy messages lead with what to do.
2. **Retry-budget instrumentation.** One log line per iteration in patch 09
   carrying `attempts`, `maxAttempts` and remaining budget. The 5-attempt cap
   has never been observed working and three theories have died on evidence;
   this is the measurement that replaces a fourth theory.
3. **Patch 11**, already committed as `ba21036`, rides along.

**Test:** the round-4 set. Pass criteria: no regression, zero
`Translation not found` lines, and a launch-with-state log that states its own
budget arithmetic.

This build produces the rollback image that Builds B and C need.

## Build B -- EmulatorJS pin bump

`0b1c5e9` -> `64a3b5b03`, 13 commits. Four are ours (#1267, #1268, #1269,
#1271). The complication is `f4f0f1c` ("Split backend and frontend", #1247),
which moved 4535 lines out of `data/src/emulator.js` into a new
`data/src/frontend.js` and renamed the call path to
`EJS_emulator.frontend.adBlocked`.

Dry-run of every patch against head:

| Patch | Result | Action |
|---|---|---|
| 01 cache-streaming | applies, offsets only | keep as is |
| 02 emulator-onfile | hunk 2 of N failed | re-cut one hunk |
| 03b canvas-pointer | failed; `supportsMouse` present at head | **delete**, merged as #1268 |
| 04 savestate-retry | 2 of 2 failed | re-cut, moves to `frontend.js` |
| 05 download-debug | reversed/already applied | **delete**, merged as #1267 |
| 06 parse-core-report | reversed/already applied | **delete**, merged as #1269 |
| 08 message-severity | 6 hunks failed across 3 files; css clean | re-cut, still open as #1270 |
| 09 loadstate-retry | hunk 3 of 3 failed | re-cut one hunk |
| 10 quickload-host-event | clean | keep as is |
| 11 english-variant | clean | keep as is |

So: three patches deleted, three clean, and about ten hunks to re-cut, most of
it relocating from `emulator.js` to `frontend.js`. `emulator.js` still holds
the core and loading logic, so patch 02 likely stays there while 04 and 08
follow the frontend class across.

`ARG EMULATORJS_COMMIT` in the RomM checkout's `docker/Dockerfile` must move
with `EJS_COMMIT` in `assemble.sh`. They are two separate pins of the same
thing.

**Test:** full round, not a spot check. The patches that moved are the save and
load retry paths, which is exactly what rounds 3 and 4 were about.

## Build C -- RomM rebase

546 commits behind `rommapp/romm`, 12 of our own on top. Wider than it sounds
but narrow where it matters: our 12 commits touch 6 files, and upstream churn
on them is

- `frontend/src/views/Player/EmulatorJS/Player.vue` -- 33 upstream commits
- `docker/Dockerfile` -- 5
- `frontend/src/views/Player/EmulatorJS/Base.vue` -- 1
- `frontend/src/utils/index.ts` -- 1

`Player.vue` is the whole job. The other five files are near-trivial.

**Do this one on its own and last.** Tristyn uses this fork outside this
project, so the rebase is not purely ours to sequence, and 546 commits of
upstream change is a large behavioural delta to land in the same round as a
core change.

Carry forward, not to be lost in the rebase:

- `docker/nginx/templates/default.conf.template` holds a **temporary** no-cache
  block on `/assets/emulatorjs/`. Test instrumentation, issue #12. Revert
  before release; do not let a rebase quietly preserve it into one.
- `frontend/src/utils/emulatorjsCache.ts` and the `Player.vue` quick-state
  wiring are ours and unreleased upstream. PR 26 is drafted from upstream
  master directly, not from the fork, so it does not depend on this rebase.

## Not in any build

- **PR 27** (English-locale translation logging) is held for test plus a rebase
  onto the frontend split. It applies unchanged at head.
- **PR 26** (RomM clear-cache) needs `trunk fmt && trunk check`, a devtools
  before/after, and a decision on filing a RomM issue to carry `Fixes #`.
