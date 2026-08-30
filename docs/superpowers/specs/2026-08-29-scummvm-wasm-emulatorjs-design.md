# ScummVM as a WASM Libretro Core for EmulatorJS — Design

## Goal

Get ScummVM's SCUMM engine running as a real libretro core inside EmulatorJS — i.e.
selectable via `EJS_core`, driven through RetroArch's standard `retro_*` callback
API — rather than as a standalone browser app running alongside EmulatorJS.

Target games (all SCUMM engine, no other engines needed):

- Maniac Mansion (SCUMM v3) — **first spike target**
- Zak McKracken and the Alien Mindbenders (SCUMM v3)
- Loom (SCUMM v4/v5)
- Indiana Jones and the Last Crusade (SCUMM v4/v5)
- Indiana Jones and the Fate of Atlantis (SCUMM v5/v6)
- Day of the Tentacle (SCUMM v6, CD speech variant exists — single disc, not affected
  by RetroArch's flaky multi-disc handling)

## Prior Art (research summary)

- ScummVM has an official, working standalone Emscripten port
  (`scummvm/scummvm` repo, `dists/emscripten/`), plus a polished unofficial demo
  (`chkuendig/scummvm-demo`, live at scummvm.kuendig.io). This proves the ScummVM
  C++ codebase — engines, codecs, detection tables — compiles to WASM cleanly.
- The separate `libretro/scummvm` core (used by desktop RetroArch) has **zero
  emscripten platform support** in its Makefile, confirmed by direct inspection.
  This is the actual gap: "ScummVM compiles to WASM" and "ScummVM as a libretro
  core" have never been combined.
- EmulatorJS support for ScummVM has been requested repeatedly since 2022
  (EmulatorJS#315, linuxserver/docker-emulatorjs#30) and never implemented. The
  docker-emulatorjs issue was auto-closed by a stale-bot, not a deliberate
  maintainer rejection — this reads as neglect, not infeasibility.
- `dosbox_pure`, an existing production libretro core shipped in EmulatorJS,
  already solves the closely analogous "multi-file game directory, not a single
  ROM" problem: it bundles its own zip reader and mounts a zip's contents as a
  virtual drive, without the underlying emulator (DOSBox) needing native zip
  support. This is the direct model for this project's zip-mount approach.
- ScummVM's own code deliberately refuses to read games directly from zip
  archives (stated anti-piracy policy in their FAQ). This means the unzip/mount
  step must live in the libretro wrapper layer, never inside ScummVM's own
  detection code.

## Scope Decisions

- **Engine: SCUMM only.** All target games use one engine; every other engine
  (~59 of them) is compiled out via the build's engine-gating flags. This
  shrinks the WASM binary and removes unrelated risk (3D/WebGL engines, MT-32
  emulation, etc. don't apply here).
- **Repo: new standalone repo** (this directory), not a fork of
  `libretro/scummvm`. ScummVM engine source is vendored as a git submodule
  pointed at upstream `scummvm/scummvm` directly (same lineage as the proven
  Emscripten port), while the libretro wrapper code is adapted from
  `libretro/scummvm`'s existing desktop wrapper (see Approach, below).
- **Deployment: self-host first, upstream later if it's solid.** No commitment
  yet to getting this merged into EmulatorJS's official `cores.json` — that's a
  stretch goal once the core is proven to actually work well.
- **Hosting for testing: a plain static HTML page** with the standard EmulatorJS
  `<script>` embed (`EJS_core`, `EJS_gameUrl`). Not coupled to
  linuxserver/emulatorjs's Docker image or RomM's library-manager conventions.
- **Save-game persistence: deferred for v1.** ScummVM's own in-game save/load
  system (native to each game) is the backup even without wiring persistent
  browser storage — "boots and is playable in one sitting" is enough for v1.
  Wiring saves to IndexedDB is a fast-follow, not a v1 requirement.
- **Packaging convention:** each game is a flat zip (`.scm` extension) with
  all game files at the zip root, no wrapping folder — same rule `dosbox_pure`
  enforces since its v0.9.0. Confirmed against a real fixture (`zak.scm`,
  provided during design): a valid zip with `00.LFL`–`58.LFL` room files,
  `ADVENTUR.ES`, and `ZAK.EXE` all sitting at the root. `.scm` is registered
  as a distinct extension (alongside plain `.zip`) in the core's metadata so
  frontends doing extension-based core routing don't collide with the dozens
  of other cores that also claim `.zip`.

## Approach

**Extend the existing `libretro/scummvm` desktop wrapper with a new emscripten
platform target**, rather than writing a clean-room wrapper. Reuse its
`OSystem_libretro` video backend, audio callback wiring, and launcher-suppression
logic — code that's already debugged for the libretro API surface — and teach
its build system to target `emcc`/`em++` with static engine linking (mirroring
flags already proven in `scummvm/dists/emscripten/build.sh`).

**Named risk and pivot trigger:** this wrapper was written assuming desktop
threading/blocking behavior (real OS threads, synchronous dialogs), which may
not translate to WASM's single-event-loop model — particularly ScummVM's audio
mixer, whose pull-vs-push sample model relative to `retro_run()`'s expectations
is unknown until tested. **If the spike shows the wrapper fighting WASM's
execution model harder than plausible incremental fixes can resolve, stop and
pivot to a fresh, minimal wrapper written non-blocking from the start,**
rather than sinking further time into forcing the desktop wrapper to comply.
This is a deliberate, named decision point — not a fallback to reach for on
the first sign of friction.

## Repo Structure

```
scummvm-wasm/
├── scummvm/                  # git submodule -> scummvm/scummvm (upstream), pinned to a release tag
├── libretro-wrapper/         # libretro core glue code (retro_run, callbacks, etc.)
│   ├── libretro.cpp          # adapted from libretro/scummvm's wrapper
│   └── Makefile.emscripten   # new build target, modeled on dists/emscripten/build.sh flags
├── zip-mount/                # core-side zip -> virtual Common::Archive layer
├── build/                    # emsdk setup, engine-gating (SCUMM only), .bc -> .wasm pipeline
├── test-page/                # minimal static HTML page embedding EmulatorJS for manual testing
└── docs/                     # spec/plan docs (this file)
```

## Components & Data Flow

1. **Zip-backed virtual archive** (`zip-mount/`): implements ScummVM's
   `Common::Archive` interface over an in-memory view of the `.scm` file's zip
   central directory (via a small vendored library — `miniz` is the likely
   choice: single-header, WASM-friendly). Files decompress into memory on
   read, on demand — no physical extraction step.
2. **Boot sequence** in `retro_load_game()`: receive content path → open as a
   zip-backed archive → register it as a search path → call ScummVM's
   internal detect-and-launch path directly (the same function `--auto-detect`
   wraps on the CLI — there is no argv/process boundary inside a libretro
   core, so this must be a direct API call, not a shelled-out CLI invocation)
   → fall through to normal `retro_run()` frame pump once a game is running.
3. **Video**: reuse `OSystem_libretro`'s existing frame buffer copy into
   `retro_video_refresh_cb`, called once per `retro_run()`.
4. **Audio (flagged risk)**: `retro_run()` expects to pull a fixed sample
   batch per frame via `audio_batch_cb`. Whether ScummVM's mixer already
   supports a "pull N samples on demand" model, or pushes from a background
   thread on desktop (requiring Asyncify or a thread-emulation shim in WASM),
   is the central unknown the spike must answer.
5. **Input**: map RetroArch's pointer device (`RETRO_DEVICE_POINTER`) to
   ScummVM's mouse cursor for point-and-click; `retro_keyboard_callback` for
   rare text-entry needs (copy-protection code entry, etc.). Touch-device
   virtual mouse UX is explicitly deferred.
6. **Engine gating** (`build/`): SCUMM-only is enforced by the build script
   itself (`--enable-engine=scumm --disable-all-engines` or the libretro
   Makefile's equivalent), not left as a manual flag someone could forget.

## Error Handling

Since there's no interactive Launcher GUI available at boot, all error states
surface through the video frame:

- **Zero games detected in the zip** → render ScummVM's existing "no games
  detected" message to the video buffer instead of its normal Launcher
  destination.
- **Multiple games detected in one zip** → launch the first match, per
  `--auto-detect` semantics. Documented as a packaging constraint ("one game
  per `.scm`"), not a bug to solve.
- **Wrong/unsupported engine data** (non-SCUMM game zipped, since other
  engines are compiled out) → same "no games detected" path, since no plugin
  exists to match it.
- **Corrupted/unreadable zip** → `retro_load_game()` returns `false`, which
  libretro frontends already surface as a load failure. No custom error UI
  needed.

## Testing & Validation Strategy

No automated test suite for v1 — this is a feasibility-driven project, not a
maintained library with contributors to protect against regressions yet.
Manual validation instead.

**Spike pass/fail gate** (the entire bet on the chosen Approach rides on
this): does `zak.scm` boot to a playable state through the full chain —
`test-page/` → EmulatorJS → `scummvm_libretro.wasm` → zip-mount → internal
detect-and-launch → rendered frame → mouse click registers as game input.

Manual checklist:

1. `zak.scm` loads without a `retro_load_game()` failure.
2. Video: intro/title frame renders correctly (validates the `OSystem_libretro`
   video path).
3. Audio: any sound plays at all, even if choppy (validates the pull-vs-push
   mixer question — the named risk above).
4. Input: a mouse click on a verb/object registers as in-game input (validates
   pointer mapping).
5. Play far enough to confirm the game loop is stable across multiple rooms,
   not just the intro.

If audio requires real OS-thread-style behavior that doesn't have a clean WASM
equivalent, that is the concrete trigger to stop and pivot to the clean-room
wrapper approach named above.

Once the checklist passes for Zak McKracken, it's re-run for the other five
target games before v1 is considered done.

## Explicitly Out of Scope for v1

- Save-game persistence to browser storage (IndexedDB) — ScummVM's native
  save/load system covers single-session play.
- Touch-device virtual mouse / mobile UX.
- Multi-disc swap handling (not needed — none of the six target games require
  it).
- Getting this merged into EmulatorJS's official core list.
- Automated testing infrastructure.

## Next Steps

Hand this spec to the writing-plans skill to produce a concrete implementation
plan, starting with the spike: standing up the `emscripten` platform target in
the adapted libretro wrapper, scoped to the SCUMM engine only, and getting a
`.bc` to build at all — before any EmulatorJS-side integration work begins.
