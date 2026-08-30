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

## Prior Art (research summary, corrected after live verification)

- ScummVM has an official, working standalone Emscripten port
  (`scummvm/scummvm` repo, `dists/emscripten/`), plus a polished unofficial demo
  (`chkuendig/scummvm-demo`, live at scummvm.kuendig.io). This proves the ScummVM
  C++ codebase — engines, codecs, detection tables — compiles to WASM cleanly.
- **Correction (found by actually building it — see "Spike Results" below):**
  the separate `libretro/scummvm` core (used by desktop RetroArch) **already
  has a working `emscripten` platform target**, in
  `backends/platform/libretro/Makefile`. An earlier pass at this research
  checked the wrong Makefile (the repo root one) and wrongly concluded there
  was no support at all. The real gap is narrower than originally scoped: the
  existing target isn't covered by any CI (the GitHub Actions `emscripten` job
  builds the separate standalone `dists/emscripten` port, not this core), so
  it had never been exercised against RetroArch's actual EmulatorJS build
  pipeline before this project did it. That gap is now closed — see below.
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
- **Repo: new standalone repo** (this directory), which vendors
  `libretro/scummvm` as a single git submodule — **corrected from the
  original plan** to submodule vanilla `scummvm/scummvm` separately from an
  "adapted" wrapper. `libretro/scummvm` is not a thin wrapper repo; it's a
  full source fork containing the entire ScummVM engine tree *and* the
  libretro wrapper together, patched as a pair. The spike (see Spike Results)
  proved this combined tree builds correctly for emscripten as-is, so
  splitting it back into "vanilla engine submodule + separately-adapted
  wrapper" would introduce a graft-mismatch risk (patches in one but not the
  other) for no benefit. One submodule, pinned to a release tag, is simpler
  and matches what was actually proven to work.
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

**Use the existing `libretro/scummvm` wrapper and its existing `emscripten`
platform target as-is** — no new build-system code is needed (this was the
original Approach A/B framing's central risk, and it's now resolved: see
Spike Results). Remaining work is: fixing the one real build gap found (the
link step), wiring the zip-mount + auto-detect boot sequence described below,
and diagnosing the runtime issue the spike surfaced (an `ErrnoError` on boot
with no game content — see Spike Results).

**Named risk, still open:** the emscripten platform sets `USE_LIBCO=0`, which
routes the build through `rthreads.o` (real pthread-based coroutines) instead
of `libco` (fiber-based). This means the existing port is attempting genuine
Emscripten pthreads (Web Workers + SharedArrayBuffer) for whatever ScummVM
uses coroutines/threads for internally — likely audio mixing and/or the
engine-vs-frontend execution split. This has real deployment implications
(pthreads need cross-origin-isolation headers: COOP/COEP, HTTPS) and the
spike did not get far enough to observe it in action (it crashed during boot
before reaching steady-state `retro_run()`). **If wiring a real game reveals
this threading model doesn't work cleanly in the browser (deadlocks, silent
audio, requires infrastructure this project doesn't want to depend on), stop
and pivot to a fresh, minimal wrapper written non-blocking from the start,**
rather than sinking further time into forcing the existing wrapper to comply.
This is a deliberate, named decision point — not a fallback to reach for on
the first sign of friction.

## Spike Results (empirical, from live build-and-run during design)

Before writing the implementation plan, the core pipeline was actually built
and run once, live, to ground this spec in fact rather than assumption. What
was verified:

1. **`emmake make platform=emscripten LITE=1` builds cleanly**, scoped to
   SCUMM only by overwriting `backends/platform/libretro/lite_engines.list`
   to contain just `scumm` (default list has ~33 engines; `LITE=1` reads that
   file). Produced `scummvm_libretro_emscripten.bc` (~24MB), zero real errors,
   ~440 warnings (all pre-existing codebase noise — pragma-pack, fribidi enum
   casts, missing-override — none introduced by or relevant to this project).
2. **Linking that `.bc` via `EmulatorJS/RetroArch`'s `Makefile.emulatorjs`
   fails by default** with `wasm-ld: undefined symbol: vtable for
   __cxxabiv1::__si_class_type_info` and friends — `emcc`'s own error message
   correctly diagnoses it: the shared Makefile links with `emcc` (C driver),
   which doesn't pull in `libc++abi`'s RTTI support that ScummVM's heavily
   C++ (RTTI/exceptions-using) codebase needs. **Fix: pass `LD=em++` on the
   make command line** (overrides the `LD=emcc` that `emmake` sets by
   default). With that one flag, the link succeeds and produces a real
   `scummvm_libretro.js` (274KB) + `scummvm_libretro.wasm` (14MB).
3. **EmulatorJS's actual loader (v4.2.3, same version RomM ships) downloads
   and begins executing this core** when packaged into its expected bundle
   format (`7z a scummvm-wasm.data scummvm_libretro.wasm scummvm_libretro.js`)
   and referenced via `EJS_core = "scummvm"`. One naming detail learned:
   **the frontend requests the `-legacy` variant by default**
   (`scummvm-legacy-wasm.data`), not the plain name — the real build needs to
   produce both variants (`build-emulatorjs.sh`'s `--legacy` flag toggles
   `HAVE_OPENGLES3`), or the test page needs to be configured to not request
   legacy, whichever proves simpler once revisited.
4. **It crashes with an `ErrnoError`** (an Emscripten filesystem error) during
   WASM init when given no game content (`EJS_gameUrl = ""`, no zip-mount
   code exists yet). This was tested as a fast, low-cost check of whether
   ScummVM's content-less boot path (straight to its Launcher GUI, a feature
   that exists on desktop RetroArch) would "just work" in the browser before
   any zip-mount code was written — it doesn't, at least not with zero setup.
   This is the concrete next problem: most likely the core's boot path
   expects either real game content or bundled system/theme files that
   aren't present in this minimal setup. Not yet diagnosed further — that's
   implementation-plan work, not spec-time work.

**What this means for scope:** the foundational "can this even be built and
loaded" risk is resolved. The remaining unknowns are narrower and more
tractable: fix the `ErrnoError` (likely by wiring real game content via
zip-mount rather than testing content-less boot), and then observe whether
audio/threading behaves once the core actually reaches steady-state
execution with a real game loaded.

5. **Follow-up test, same session: pointed `EJS_gameUrl` directly at
   `zak.scm`** (a real, valid zip — no custom zip-mount code written yet).
   Result, concrete and informative:
   - **The `ErrnoError` is gone.** Confirms it was specifically about
     missing/empty content, not a deeper systemic problem with the core or
     the emscripten platform.
   - **Video and mouse input both work**: the core rendered RetroArch's own
     menu (crisp, correct, multiple submenus navigable), and clicking
     genuinely moved menu focus, confirming pointer input is at least
     partially wired. (Confirming a *click* as a "select" action needed
     keyboard Enter, not a second click — worth investigating exactly what
     RetroArch's default input mapping expects from a libretro
     `RETRO_DEVICE_POINTER` press vs its "confirm" bind, but this is a
     mapping/config detail, not a fundamental gap.)
   - **The game did not auto-launch**, despite `EJS_startOnLoaded = true` —
     it landed on RetroArch's normal contentless main menu rather than
     going straight into Zak McKracken. The theory that EmulatorJS's
     generic zip-extraction (writing every entry to `/<filename>` at the FS
     root) would combine with `retro_load_game`'s existing
     parent-directory-autodetect fallback to "just work" was **not
     confirmed** — something in that chain didn't fire as traced. Not yet
     root-caused.
   - **RetroArch's own "Load Content" file browser shows `/` as empty**,
     despite files having been written there by EmulatorJS's extraction
     step. Most likely explanation: RetroArch's content browser filters by
     the core's registered `valid_extensions` (from `retro_get_system_info`),
     and this wrapper hasn't been told `.LFL`/`.EXE`/`.scm` are valid
     extensions for it — so the browser hides files it doesn't recognize
     even though they're present on disk. Not yet confirmed by reading the
     wrapper's `retro_get_system_info` implementation.

**Revised next-step priority:** the single highest-value remaining
investigation is tracing why `retro_load_game`'s directory-autodetect branch
didn't fire (or fired but failed) when EmulatorJS handed it a path. Two
concrete hypotheses to check first, in order: (1) what literal `game->path`
string EmulatorJS actually passes for a zip-sourced ROM (may not point where
assumed — needs a console.log/breakpoint check in `emulator.js` around
`startGame()`), and (2) whether `testGame()`'s auto-detect scan requires
`.scummvm`-style companion metadata this raw file layout doesn't provide.
This is real implementation-plan work, not something to guess at further
here.

## Repo Structure

```
scummvm-wasm/
├── scummvm-core/              # git submodule -> libretro/scummvm (pinned to a release tag)
│   └── backends/platform/libretro/   # the existing wrapper + emscripten platform target (used as-is)
├── zip-mount/                 # JS: unzip .scm client-side, write into the module's virtual FS
│                               # before calling into the core (no C++ wrapper changes needed)
├── retroarch/                 # git submodule -> EmulatorJS/RetroArch (branch "next"), for the link step
├── build/                     # build scripts: emsdk setup, lite_engines.list override, the two-stage
│                               # build (core .bc, then RetroArch link with LD=em++), .data packaging
├── test-page/                 # minimal static HTML page embedding EmulatorJS for manual testing
└── docs/                      # spec/plan docs (this file)
```

## Components & Data Flow

1. **Zip-mount — corrected after reading the actual wrapper source
   (`backends/platform/libretro/src/libretro-core.cpp`'s `retro_load_game`)**:
   no C++ changes to the wrapper are needed for this at all. Two relevant
   facts changed the design:
   - `retro_load_game` already handles directory-based auto-detection as
     existing, already-tested code: if `game->path` is a directory, it calls
     `LIBRETRO_G_SYSTEM->testGame(parent_dir, true)`, and on
     `TEST_GAME_OK_ID_AUTODETECTED` builds the string `-p "<dir>"
     --auto-detect` and feeds it to `parse_command_params()` — i.e. it
     already does the "call the internal function `--auto-detect` wraps"
     behavior this spec originally called for writing.
   - The compiled module already exports Emscripten's `FS` object (confirmed
     in the working link command's `EXPORTED_RUNTIME_METHODS`), so JS can
     write arbitrary files into the module's virtual filesystem before
     calling into the core.
   - **Design: unzip the `.scm` file client-side in JS** (a small JS zip
     library, not a C++ one) and write its contents into the module's
     virtual FS at a real directory path (e.g. `/home/game/`), then invoke
     the core's content loading pointed at that directory. The existing,
     unmodified `retro_load_game` directory-autodetect branch handles
     everything from there. (ScummVM also has its own built-in zip reader,
     `Common::makeZipArchive()` in `common/compression/unzip.h` — used
     internally for engine data packs and DLC, proving the "no zip" FAQ
     answer is a Launcher-GUI product policy, not a technical limitation —
     but it's not needed here since the JS-side approach is simpler and
     requires zero wrapper changes.)
2. **Boot sequence** in `retro_load_game()`: receive content path → open as a
   zip-backed archive → register it as a search path → call ScummVM's
   internal detect-and-launch path directly (the same function `--auto-detect`
   wraps on the CLI — there is no argv/process boundary inside a libretro
   core, so this must be a direct API call, not a shelled-out CLI invocation)
   → fall through to normal `retro_run()` frame pump once a game is running.
   **Current status: the existing wrapper's content-less boot path throws an
   `ErrnoError` before this code exists** (see Spike Results) — diagnosing
   that and confirming a real game (via zip-mount) gets past it is the first
   implementation-plan task.
3. **Video**: reuse `OSystem_libretro`'s existing frame buffer copy into
   `retro_video_refresh_cb`, called once per `retro_run()`. Not yet observed
   running (the spike crashed before reaching steady-state `retro_run()`).
4. **Audio (flagged risk, sharpened by the spike)**: `retro_run()` expects to
   pull a fixed sample batch per frame via `audio_batch_cb`. The build
   confirmed the wrapper compiles against `rthreads.o` (real pthread-based
   coroutines, not fiber-based `libco`) for the emscripten platform — meaning
   whatever ScummVM uses coroutines for (likely audio mixing) is attempting
   genuine Emscripten pthreads. Not yet observed working or failing at
   runtime; see the Approach section's named risk.
5. **Input**: map RetroArch's pointer device (`RETRO_DEVICE_POINTER`) to
   ScummVM's mouse cursor for point-and-click; `retro_keyboard_callback` for
   rare text-entry needs (copy-protection code entry, etc.). Touch-device
   virtual mouse UX is explicitly deferred.
6. **Engine gating** (`build/`): SCUMM-only is enforced by overwriting
   `backends/platform/libretro/lite_engines.list` to contain just `scumm`
   before building with `LITE=1` — verified working in the spike. (The
   generic `--enable-engine=scumm --disable-all-engines` configure flags
   exist upstream but aren't how this specific wrapper's build is invoked;
   `LITE=1` plus a trimmed `lite_engines.list` is the actual mechanism this
   Makefile uses.)

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

The feasibility spike (build → link → load in EmulatorJS) is done — see Spike
Results. Hand this spec to the writing-plans skill to produce a concrete
implementation plan, starting from where the spike left off: reproduce the
verified build/link steps inside this project's actual repo structure
(rather than the throwaway scratchpad they were first proven in), then
diagnose and fix the `ErrnoError` on boot — most likely by building the
zip-mount layer and testing with real content (`zak.scm`) rather than a
content-less boot — before moving on to audio/input validation.
