# ROMM ScummVM Integration Design

## Goal

Make the scummvm-wasm libretro core (built and proven working in this
project's local `test-page/` EmulatorJS harness) playable from inside the
user's real ROMM instance, via ROMM's own Play button. This is the "cross
that bridge" step referenced earlier in the project: moving from a local
test harness to the actual target deployment environment.

## Background / what we already confirmed

Before writing this spec, we inspected both the target repo (`rommapp/romm`)
and the user's actual running Unraid setup, rather than assuming either.

**ROMM's backend already fully supports ScummVM as a platform, with zero
changes needed:**
- `UPS.SCUMMVM = "scummvm"` is a defined universal platform slug (IGDB
  platform id 143) in `backend/handler/metadata/base_handler.py`.
- `igdb_handler.py` special-cases ScummVM ROM filename matching via
  `_scummvm_format()`, which resolves a ROM's base filename against ROMM's
  own cached ScummVM game-ID index (`SCUMMVM_INDEX_KEY`) — the same
  game-ID-as-filename convention this project's own `.scummvm` hook files
  already use.
- **Confirmed live**: the user reorganized `emulation/scummvm/roms/` and
  ROMM's library scan already identified the games correctly under the
  ScummVM platform. No backend work is needed at all.

**ROMM's frontend hardcodes the platform→core mapping, and has no
`scummvm` entry:**
- `frontend/src/utils/index.ts` defines `_EJS_CORES_MAP`, a
  `Record<platformSlug, coreName[]>`. There is no `scummvm` key.
  `getSupportedEJSCores("scummvm")` currently returns `[]`.
- `Player.vue` sets `window.EJS_core = supportedCores.find(...) ??
  supportedCores[0]` — with an empty array this becomes `undefined`, and
  `isEJSEmulationSupported()` (which checks this list is non-empty) hides
  the Play button for the platform entirely.
- `areThreadsRequiredForEJSCore()` is a separate hardcoded whitelist
  (`["dosbox_pure", "ppsspp", "azahar"]`) controlling `window.EJS_threads`.
  Our core is built with `HAVE_THREADS=1` / SharedArrayBuffer and needs
  `EJS_threads = true`, matching the same requirement this project's own
  `test-page/index.html` already documents (`EJS_threads = true`).

**ROMM self-hosts EmulatorJS v4.2.3, same version this project targets:**
- `docker/Dockerfile` downloads the official EmulatorJS v4.2.3 release
  `.7z` from GitHub and copies its extracted contents to
  `${WEBSERVER_FOLDER}/assets/emulatorjs` in the final image.
  `Play.vue`/`EmulatorJS.vue` set `EJS_pathtodata = "/assets/emulatorjs/data"`
  to load from this local copy (falling back to EmulatorJS's CDN only when
  netplay is enabled).
- The running `romm` container (image `rommapp/romm:latest`, unmodified)
  has no bind mount over this path, so our core files cannot reach it
  without building a custom image from a patched Dockerfile.

**The user's actual Unraid deployment:**
- `romm` container mounts `/mnt/user/emulation` → `/romm/library`
  (network-visible to this project's tooling at `/mnt/unraid/emulation`).
- `emulation/scummvm/roms/` already contains all six target games as
  `.scm` files, and ROMM's scanner has already matched them to the
  ScummVM platform metadata (confirmed live by the user).
- A separate `emulatorjs` container (`lscr.io/linuxserver/emulatorjs`) also
  shares this library folder, but that image is abandoned upstream (per
  linuxserver's own recommendation to move to ROMM) — not a candidate for
  this integration, ruled out during design.
- `romm-db` (mariadb) and `adminer` run alongside `romm`; neither needs to
  change for this work.

## Scope

**In scope (this design):**
- Add `scummvm` as a recognized EJS platform/core in ROMM's frontend.
- Get our pre-built core files served from ROMM's self-hosted EmulatorJS
  data path.
- Redeploy the user's `romm` container from the patched image.
- Verify one SCUMM game boots and plays via ROMM's own Play button, with
  EmulatorJS's native (client-side download/upload) save states working —
  mirroring exactly what's already proven in the local test-page harness.

**Out of scope (confirmed with the user):**
- Server-backed save-state persistence (`EJS_onSaveState`/`EJS_onLoadState`/
  `EJS_loadStateURL` wired to ROMM's own save-state backend API). This is a
  separate, later integration step.
- Any UI polish beyond making the Play button work.
- Upstreaming a PR to `rommapp/romm` (the fork may make this easy later,
  but it's not a goal of this pass).

## Architecture

Fork `rommapp/romm` → `TRusselo/romm`, branch `emulatorjs-wasm-fixes` —
matching the existing pattern used for the `scummvm-core` and `RetroArch`
forks (both at `TRusselo/*`, same branch name). Two independent pieces of
work land on this branch:

1. A minimal source patch (two lines) making ROMM's frontend recognize
   `scummvm` as a playable EJS platform/core.
2. A `docker/Dockerfile` change that layers our pre-built core files on
   top of the official EmulatorJS release during image build, from a
   gitignored build-context folder — so the fork's git history stays
   binary-free, consistent with how this project itself never commits
   build artifacts (game files, emsdk toolchain, etc. are all gitignored).

The user then builds this fork's image and repoints their existing
Unraid `romm` container's Docker template at it, replacing
`rommapp/romm:latest`.

## Components

### 1. Frontend patch — `frontend/src/utils/index.ts`

```ts
const _EJS_CORES_MAP: Record<string, string[]> = {
  ...
  scummvm: ["scummvm"],
  ...
};
```

```ts
export function areThreadsRequiredForEJSCore(core: string): boolean {
  return ["dosbox_pure", "ppsspp", "azahar", "scummvm"].includes(core);
}
```

No other frontend files need changes: `Player.vue`'s core-selection and
thread-flag logic already reads from these two functions generically.

### 2. Dockerfile patch — `docker/Dockerfile`

Add a `COPY` in the `emulator-stage` build stage, after the existing
EmulatorJS `.7z` extraction and before the final-image `COPY --from=
emulator-stage /emulatorjs ...` line, pulling our core's three files
(`scummvm-thread-wasm.js`, `scummvm-thread-wasm.wasm`,
`scummvm-thread-wasm.data` — the exact triple this project's own
`build/package-core.sh` already produces) into
`/emulatorjs/data/cores/` inside that stage, so they ride along with the
official release's own core files into the final image.

The source for that `COPY` is a new, gitignored directory in the fork
(e.g. `docker/scummvm-core/`), populated by copying this project's
`build/` output there immediately before running `docker build` — a
one-line manual step or a tiny script, not committed to either repo's git
history.

### 3. Deployment

- Build the patched image from the fork (`docker build` on the branch).
- Update the Unraid `romm` container's template to reference this custom
  image tag instead of `rommapp/romm:latest`.
- Restart the container. No changes to `romm-db`, `adminer`, mounts, or
  ports are needed — this only changes the image, not the container's
  configuration.

### 4. Test content

Already done: `emulation/scummvm/roms/` has all six target games as
`.scm` files, and ROMM has already scanned and identified them under the
ScummVM platform. No further test-content work needed — just verify the
Play button now appears and works once the frontend/image changes are
deployed.

## Data flow

1. User clicks Play on a ScummVM-platform ROM in ROMM's UI.
2. `getSupportedEJSCores("scummvm")` now returns `["scummvm"]` (was `[]`).
3. `window.EJS_core = "scummvm"`; `areThreadsRequiredForEJSCore("scummvm")`
   now returns `true`, so `window.EJS_threads = true`.
4. EmulatorJS's `loader.js` fetches the `scummvm` core's files from ROMM's
   local `/assets/emulatorjs/data/cores/` — now present because of the
   Dockerfile patch.
5. From here, boot behavior is identical to the local `test-page/` harness
   already proven working (SCUMM engine autodetection or `.scummvm` hook
   file, video/audio/input, native EJS save/load).

## Testing

Manual, mirroring the checklist already used for the local harness:
1. Deploy the patched image; confirm the `romm` container comes up healthy.
2. Confirm the ScummVM platform's games still show (already true before
   this change — regression check only).
3. Click Play on one game (e.g. Zak McKracken). Confirm: Play button is
   present (was previously absent/disabled for this platform), core loads,
   game boots to a playable state, video/audio/mouse input all work.
4. Test EmulatorJS's native Save State / Load State buttons — client-side
   download/upload round-trip, same as already proven in the local harness.
5. Regression-check one or two of ROMM's existing working platforms (e.g.
   whatever the user already plays via ROMM) to confirm the frontend patch
   didn't break anything else — it's a pure addition to both maps, so this
   should be a quick sanity check, not a deep test.

## Global constraints

- No changes to ROMM's backend (Python) — confirmed unnecessary.
- No committed binary artifacts in the `TRusselo/romm` fork's git history.
- No changes to the `romm` container's mounts, ports, or environment
  variables — this is an image-only change.
- Core files used must be the same `scummvm-thread-wasm.js/.wasm/.data`
  triple this project's own `build/package-core.sh` already produces —
  no separate build path for ROMM.
