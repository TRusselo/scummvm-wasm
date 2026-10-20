# Upstream rebase, 2026-10-20

**Status:** branches rebased and pushed; nothing built yet. Round 12
(`tests.list`) has not run, so it runs on this build instead of the Oct 1 one.

RomM rebases go onto RomM's latest **release tag**, not master (Tristyn,
2026-10-20).

| Repo | Was | Now | Backup |
|---|---|---|---|
| EmulatorJS `scummvm-wasm-split` | `b319839` on `f4f0f1c` | `33e28af` on `0235603` | `backup-scummvm-wasm-split-20261020` |
| RetroArch `emulatorjs-wasm-fixes` | `f21b106` on `1eb5edf` | `08b9892` on `97f2cfa` | `backup-emulatorjs-wasm-fixes-20261020` |
| RomM | `unraid-stage-20261001` `c31c1f6e` on master `e23b0496` | `unraid-stage-20261020` `3688bd05` on `5.4.0` | old branch left as is |
| scummvm-core | `54c585c` on `staging_master` `92366fad` | unchanged; libretro has not moved | — |

## What dropped

- EJS patch 08 (#1270) and 12 (#1273): merged. `assemble.sh` now checks the pin
  carries them instead of patching them in.
- RetroArch `7587e3e` (static `save_state_info` buffer): superseded by
  EmulatorJS/RetroArch#49, which also stops JS freeing that buffer and frees
  the state by address. Our old build freed a static address on every save.
- RetroArch `f21b106`: merged as #48.

## Resolved by hand

- EJS 04 and 09 conflicted with the merged #1270 in the quick save/load block.
  Resolved to the old branch's final behaviour. 09's retry messages called
  `displayMessage(msg, time, "error")`, which only worked because 08 later
  rewrote them; with 08 gone they now pass `undefined, "error"` themselves.
  One of them was still the 3-argument form on the old branch too (it showed
  "error" as a suffix); that is fixed.
- RomM nginx template: kept upstream's EasyRPG location beside our two core
  cache locations.
- RomM `EmulatorJSCacheDialog.vue`: upstream moved to `useEmitterEvent`; kept
  that and our `clearEmulatorJSCaches` import.
- RomM Dockerfile: `EMULATORJS_COMMIT` moved to `0235603`.

## Checked here

- `assemble.sh` at `0235603`: all patches apply, every marker check passes.
- RomM frontend `npm run typecheck`: clean. `npm test`: 3284 unit tests pass;
  the Storybook browser project could not launch Chromium in the cloud
  session, so those 62 story files did not run.

## Not checked, needs the build and round 12

- Core and RetroArch rebuild against `08b9892`, image build on Unraid.
- RomM 5.4.0's #5091 rewrote browser save sync in the EmulatorJS player
  (`Player.vue`, `utils.ts`). Our save/load commits applied without conflict,
  but only round 12 shows whether they still behave together.
