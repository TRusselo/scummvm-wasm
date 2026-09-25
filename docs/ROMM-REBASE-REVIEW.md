# What the RomM rebase brought, and what to do about it

> **Superseded 2026-09-24** by `docs/superpowers/plans/2026-09-24-upstream-rebase-and-cleanup.md`. Kept as the record of the September 19 rebases.

Written 2026-09-19, after the rebase landed. The rebase itself is done:
`unraid-stage-20260916` is **0 behind `rommapp/romm`** with 20 of our commits on
top. This is about what arrived with it, not how to do it.

The short version: upstream has spent this window building **in our problem
space**. Several of our 20 commits are now adjacent to, or arguably superseded
by, work they did independently. That is the thing to settle before the next
round of player work, not after.

## Deployment risk: low

- **No database migrations.** The head migration is `0128_hltb_main_story_column`
  at both ends. Fifteen existing migration files were modified, but only to
  refactor them, not to change schema. So the upgrade needs no `alembic upgrade`
  step and carries no data risk.
- **No commits flagged breaking** (`!:`) in the 546.
- `vue-tsc --noEmit` passes on the rebased tree. Note the Docker build does not
  typecheck: it runs `vite build`, which strips types without checking them.

## What the 546 commits are

| Type | Count |
| --- | --- |
| fix | 185 |
| feat | 56 |
| refactor | 48 |
| style | 30 |
| chore | 27 |
| review | 25 |
| docs | 19 |
| test | 15 |
| perf | 7 |

Two themes dominate the 56 features: a **v2 UI** (27 of them) and a sustained
push on the **player, saves and states** (23).

## The overlap, which is the point of this document

Upstream built save and state machinery that touches the same surfaces we have
been patching:

| Upstream commit | What it does |
| --- | --- |
| `24cd55abe` | flushes SRAM every 5s so in-game saves upload seconds after the game writes them, and defaults the flag on |
| `001975055` | polls the SRAM every second and flushes a pending save on exit |
| `d12c3b5d6` | retries held-back states, and stops a loaded state syncing back as a save |
| `82be55306` | retries a held-back save from anywhere in the app |
| `dfa8eb8d6` | stops retrying the save every second while the server is down |
| `0293c7d2f` | confirms save/state loads, and **translates the EmulatorJS ribbon** |
| `bee249b7e` | simplifies save/state loading outright |
| `e7476c150` | persists state-restored SRAM |
| `cf48d371f` | `emulatorjs.default_cores`: preselect a core per platform in `config.yml` |

`8c7b2c64f fix(player): stop hiding EmulatorJS's own messages` is **our own
commit, merged upstream**. `git cherry` marked it and the rebase dropped it.
That is the second time this week one of ours came back as upstream's (the other
being four EmulatorJS PRs), and it is why the drop rule has to be `git cherry`
rather than memory.

### What this means for our 20

Needs deciding, not assuming:

- **Our quick-load and retry work (`#12`, `#13`, `#19`)** now sits next to
  upstream's own retry-and-hold-back machinery. During this rebase, upstream's
  new `applyState()` had to be threaded through our code by hand, and our local
  fallback was found bypassing it. That is a warning sign: two retry systems in
  one player will eventually disagree. Decide whether ours still earns its place
  or should be folded into theirs.
- **`0293c7d2f` translates the EmulatorJS ribbon.** We have our own message
  work in flight (patch 08, PR #1270) and the en-GB fix (patch 11, PR 27). Check
  whether their translation layer changes what those should look like.
- **`cf48d371f default_cores` is worth adopting**, not resisting: it would let an
  instance preselect the ScummVM core for the scummvm platform rather than
  relying on "first supported core".

### An open question worth answering before issues #23 and #24

Upstream's new SRAM sync uploads **battery-SRAM in-game saves**. ScummVM does
not write battery SRAM; it writes save files into its virtual filesystem. So
the new sync probably does not see a ScummVM save at all.

**Verify this before doing any more work on #23 or #24.** If their SRAM poll
does surface ScummVM's saves, both issues shrink dramatically. If it does not,
both stand as written, and that is worth saying in the issues so nobody assumes
upstream solved it.

## The other repos

Asked directly: yes, two others are behind, and one of them repeats the pattern
we just untangled in EmulatorJS.

### `scummvm-core` -- 7 behind, 42 ahead. Do this one.

`git cherry` marks **3 of our 42 as already upstream** in
`libretro/scummvm staging_master`:

- `LIBRETRO: Keep warning() in release builds`
- `LIBRETRO: Log the unknown-game report when autodetection finds nothing` (PR #113)
- `LIBRETRO: Implement kFeatureOpenUrl on Emscripten` (PR #114)

Exactly the EmulatorJS situation: our merged PRs came back as upstream commits
and we are still carrying duplicates. A rebase onto `staging_master` drops them
mechanically. The 7 we are behind also include `364e70216ab` (PR #116, the
`retro_message_ext` severity work) and two merges from `scummvm/master`, one of
which is a PhoenixVR detector fix.

Note `364e70216ab` was **not** marked as a duplicate, which suggests our local
copy differs from what was merged. Expect a conflict there and check whether a
maintainer amended it.

### `retroarch` -- 53 behind, 1675 "ahead". Leave it.

The 1675 is misleading: our branch sits on the v1.22.2 line, which carries a
large amount of upstream RetroArch history that `EmulatorJS/RetroArch master`
does not have. Our actual changes are the handful on top (the Emscripten canvas
dimension fixes, the `save_state_info()` dangling pointer fix, core options
JSON). This is issue #7's territory and deliberate, not drift.

### `EmulatorJS` -- current.

Pin at `13ce942`, with `f4f0f1c` (the frontend split) rebased and built as
`:buildD`, awaiting a test round.

## Suggested order

1. **Test `:local`** (`23053efba24e`). Nothing below matters until the rebase is
   known good.
2. **Answer the SRAM question** above. It is a ten-minute check that decides the
   scope of two open issues.
3. **Rebase `scummvm-core` onto `staging_master`**, dropping the three
   duplicates. Same shape as the EmulatorJS bump, and it also picks up our own
   merged PR #116.
4. **Decide the retry overlap.** Either fold our retry into upstream's
   hold-back machinery or state plainly why ours stays separate.
5. **Adopt `default_cores`** for the scummvm platform.
6. Leave `retroarch` alone.
