# RomM master rebase, v2 as the target, 2026-10-01

**Goal:** move our RomM staging work from `b834b35cb` (5.3.1 plus 221) onto
current master, with the v2 UI as the one we test and support.

**Flow:** as last time. Re-cut and check on the workstation, push a new
branch, check it out on the box, build `:local` over ssh, and Tristyn
force-updates `/romm`. The core and EmulatorJS do not change: libretro
`staging_master`, EmulatorJS `main` and RetroArch `v1.22.2` have not moved
since 2026-09-24.

## Global constraints

- Commit trailer `Assisted-by: Claude:claude-opus-5-5`; no co-author lines.
  No comments in submitted code.
- Unraid: read and back up freely. **Nothing on the box is stopped or
  deleted.** Build and stage `:local`, retagging the old one `:rollback`
  first. Tristyn force-updates.
- Rewrite history only on the workstation, never through the `/mnt/unraid`
  mount.
- `vite build` does not typecheck. Run `npm run typecheck` and `npm test`.

---

## What was measured (2026-10-01)

| | |
|---|---|
| RomM master | `e23b04969`, **689** commits past our base. The newest tag is still 5.3.1 |
| Our commits | 31 on `unraid-stage-20260916`. `git cherry` marks none of them as upstream |
| New migrations | **13**, `0135` to `0147`. Two drop columns (`0135` play-session sync link, `0145` derivable columns) |
| Straight replay | conflicts; see below |

### v2 costs almost nothing

`frontend/src/v2/views/Player/EmulatorJS.vue` says it in its header: it is a
"v2 shell around the v1 <Player> component". v2 rewrote the pre-game screen
(v1's `Base.vue`, now frozen upstream). The running emulator in **both** UIs is
v1's `Player.vue` together with `utils.ts`.

| Our commits | Where they live | In v2? |
|---|---|---|
| 10 (retries, quick-load routing, state-landing hold-back, severity, messages) | `Player.vue`, `utils.ts` | **yes**, unchanged |
| 3 (Clear cache) | `emulatorjsCache.ts` and **both** cache dialogs | **yes** |
| 1 (`8c4e75a72`, scummvm platform and core) | `utils/index.ts`, shared | **yes** |
| 1 (`8f2f9d94f`, HTTPS-required-core message) | v1 `Base.vue` only | v2 has upstream's own version (#4313). **Drop.** |
| 16 (Dockerfile, README, `.gitignore`, nginx) | image | either UI |

### RomM's EmulatorJS 4.2.3 workarounds, checked against our `f4f0f1c`

All six are installed from one `EJS_emulator` setter in `utils.ts`, so they
run on our EmulatorJS for **every** system, not just ScummVM.

| Hook | What it relies on | On our EmulatorJS |
|---|---|---|
| `lookUpGamepadsByBrowserIndex` | returns early if `getGamepadSelectionValue` exists | **steps aside**: ours has it (`emulator.js:1143`) |
| `keepArcadeBiosWhole` | returns early unless `downloadGameFile` exists | **steps aside**: ours has no `downloadGameFile`. Ours keeps arcade BIOS whole natively (`downloadType.bios.dontExtractIfCore`). Had it run, it would have broken: our `externalFiles` writer unzips, and writes the first member under the zip's name |
| `skipDiskSelectionBeforeStart` | wraps `menuOptionChanged` | present (`emulator.js:2010`). Harmless; EmulatorJS #1260 itself is closed |
| `replayConnectedGamepads` | `gamepad.gamepads`, `dispatchEvent` | same API (`gamepad.js:21/130`) |
| `applyOnlyEnabledCheats` | `cheats`, `cheatChanged`, `gameManager` | present |
| `installDefaultOptionsFallback` | `getCoreSettings`, `getLocalStorageKey`, `preGetSetting` | present |

All are safe by reading. Round 12 still runs a controller game, a multi-disc
game and an arcade BIOS game, because reading is not running.

### The conflicts

| Our commit | Conflict | Size |
|---|---|---|
| `8e7dcf60c` and the Dockerfile chain | `.gitignore` (upstream CI change). The Dockerfile EmulatorJS block was rewritten upstream from `wget` + `sha256sum` to `ADD --checksum` (`6002b8fda`), and our chain replaces that same block | small, mechanical |
| `83d3dcfbf` Clear cache | `v2/components/Player/EmulatorJSCacheDialog.vue` (upstream's comment sweep, `54a6ca6c9`) | trivial |

Everything after these two is a cascade: commits that failed only because an
earlier one did not apply.

Upstream also moved the v1 frontend to **Vuetify 4** (`4bfec16cb`), and #4877
plus 11 more commits changed `Player.vue` and `utils.ts`. Neither conflicts
textually. Typecheck and the unit tests are the check.

## Approach: re-cut as a new branch, not a rebase in place

Sixteen of our 31 commits are the Dockerfile and nginx history of one
design, written in steps. Replaying those steps through upstream's rewrite is
the expensive part, and it buys nothing. Instead:

- **New branch `unraid-stage-20261001`** from `upstream/master`. The old
  branch stays untouched as the rollback source until round 12 passes. That
  means no force-push and no backup branch to manage.
- **The image commits collapse to their final state:**
  1. "Stage the ScummVM core and a pinned EmulatorJS build into the image":
     the Dockerfile emulator stage, `.gitignore`, and
     `docker/scummvm-core/README.md`. The obsolete mkdir backport (`ee427cc41`)
     disappears, since its own successor already removed it.
  2. "Revalidate EmulatorJS code and cache cores by build": nginx, taken
     verbatim from the old branch tip (upstream has 0 commits there). The
     test-only no-cache block still has to come out before any release.
- **The frontend commits are cherry-picked one by one, in order:** 14 of them
  (the shared `8c4e75a72`, the 10 player commits, the 3 cache commits).
  `8f2f9d94f` is dropped.
- **Result:** 16 commits instead of 31. `git range-diff` against the old
  branch must show the 14 frontend commits matching, and nothing else changed.

## Tasks

### Task 1: Re-cut (workstation)

```bash
cd /home/user/git/romm && git fetch upstream
git switch -c unraid-stage-20261001 upstream/master
# commit 1: the image (hand-merge the emulator stage, take ours for the rest)
git checkout unraid-stage-20260916 -- docker/scummvm-core/README.md
# docker/Dockerfile: replace master's EMULATORJS_VERSION/SHA256 + ADD + RUN 7z
#   block with ours (ARG EMULATORJS_COMMIT=f4f0f1c, COPY docker/emulatorjs/,
#   the two core COPYs, the report JSON, the engine-data dir). Keep master's
#   `apk add 7zip`; Ruffle still needs it.
# .gitignore: add our docker/emulatorjs/ and docker/scummvm-core/ lines
git commit -m "Stage the ScummVM core and a pinned EmulatorJS build into the image"
# commit 2: nginx
git checkout unraid-stage-20260916 -- docker/nginx/templates/default.conf.template
git commit -m "Revalidate EmulatorJS code and cache cores by build"
# commits 3-16
git cherry-pick 8c4e75a72 57ec44c2b a4dc1bd8b 7186ba6ef 83d3dcfbf 62b17bac9 \
  6354f8add 3fc252504 1561946c7 c55d0f281 bb289ee9c 77fcb760f 967057f6e 3f5591dad
```

The final list is checked against `git log --reverse` of the old branch at run
time. Then:

```bash
git range-diff upstream/master..unraid-stage-20260916 upstream/master..unraid-stage-20261001
git diff unraid-stage-20260916 unraid-stage-20261001 -- docker/ frontend/src/utils/emulatorjsCache.ts
```

### Task 2: Check (workstation)

`cd frontend && npm ci && npm run typecheck && npm test`. The known flake is
`v2/views/Settings/MetadataSources.test.ts`: it fails under full-suite load
and passes alone.

### Task 3: Build (box)

1. Push `unraid-stage-20261001`, then on the box: `git fetch origin && git
   checkout -b unraid-stage-20261001 origin/unraid-stage-20261001` (over ssh,
   never `git clean`).
2. The staged core and EmulatorJS are already in the checkout and are
   unchanged. Verify their md5s (`ce5a3b72…`) and do not restage.
3. Headroom (unraid skill), then retag `:local` to `:rollback` and build.
   `:rollback` becomes `1492a2bbe193`, and `ab904bf82537` goes on the orphan
   list for Tristyn.
4. Verify inside the image: core md5, the patched bundle, migrations to `0147`.
5. **DB dump** to `/mnt/user/Backups/Unraid/Docker/romm-db/`, before the
   force-update. With column drops in `0135` and `0145`, a rollback is the old
   image **plus** this restore.

### Task 4: Round 12, in the v2 UI

| # | Test |
|---|---|
| 0 | Switch this browser to v2 (Settings > User interface) |
| 1 | RomM upgrade: the database reaches `0147`, then a scan and an edit |
| 2 | Zak from v2's Resume column, with a state: accepted on attempt 1. Then save, then load. One toast per save |
| 3 | Clear cache from v2's Setup column |
| 4 | A controller game with the pad connected before launch (the gamepad hooks) |
| 5 | A multi-disc game, e.g. PS1 (the disc hook and the disc-set default) |
| 6 | An arcade game that needs a BIOS zip, e.g. NeoGeo |
| + | The regression list |

### Task 5: After round 12 passes

Delete `unraid-stage-20260916`, and repoint the plan docs and the `.gitmodules`
comment at the new branch name.

## Open, not blocking

- RomM moves fast: 689 commits in a week. Rebasing after each passing round
  keeps every rebase this size or smaller.
- Our quick-load fix for upstream (`fix-quickload-undefined-state`) is still
  live and still unsubmitted.
