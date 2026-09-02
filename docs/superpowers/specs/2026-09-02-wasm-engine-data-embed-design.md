# Embed ScummVM Engine-Data Into the WASM Core

## Problem

Many ScummVM engines require an auxiliary "engine-data" file — `fonts.dat`,
`toon.dat`, `nancy.dat`, `ultima8.dat`, `tony.dat`, `neverhood.dat`, and
others — containing resources the engine's reimplementation needs (fonts,
string/version tables, translations) that aren't part of the original
game's own files. This is a completely standard ScummVM requirement on
every platform, not something specific to this project.

On a normal desktop install, this is invisible: ScummVM's installer drops
its whole `dists/engine-data/` directory into a fixed, shared location
next to the binary once, and ScummVM's own file-search system
(`SearchMan`) checks that location automatically for every game, forever.

This project's deployment has no equivalent shared, persistent location.
EmulatorJS's WASM core runs in a browser sandbox where each ROM launch
only sees what's inside that ROM's own zip — there is no install-once
system folder the core can reach across different ROM launches. The
current workaround has been to manually discover (usually via a runtime
crash-to-debugger) which `.dat` file a given engine needs and bundle a
copy of it inside that specific ROM's zip, every time, per engine. This
has caused repeated, avoidable delays and near-misses across the ongoing
engine-testing sweep (documented across many `docs/GOTCHAS.md` and
`docs/ENGINE-TEST-PLAN.md` entries — `toon`, `nancy`, `ultima8`, `tony`,
and the shared `fonts.dat` bug affecting five engines).

## Goal

Eliminate this entire failure class permanently, for every engine —
already-tested and not-yet-tested alike — without depending on any
external system (RetroArch's internal path conventions, ROMM's bios
delivery mechanism, or anything outside this repo's own build).

## Non-goals

- **Not fixing the shared `fonts.dat` WASM crash** (`glk`, `dm`, `griffon`,
  `tony`, `neverhood` — `RuntimeError: memory access out of bounds`). That
  is a rendering defect that occurs *after* the file is successfully
  loaded; this work only ensures the file is always available. Those five
  engines remain blocked on that separate bug.
- **Not fixing detection-vs-runtime file gaps** (e.g. `groovie`'s `icons.ph`
  /`sample.AD`/`sample.OPL`, which are original game files ScummVM's
  detector doesn't hash but the engine needs at runtime). Those are game
  files, not ScummVM engine-data, and still must be packaged into the ROM.
- **Not cleaning up already-packaged ROMs** that currently carry a
  redundant bundled copy of a `.dat` file. Harmless duplication; not
  addressed here.
- **Not changing ScummVM's own `common/engine_data.cpp` lookup logic.**
  It already does exactly the right thing (searches `SearchMan` for the
  file, validates its version, mounts it) — nothing about that code needs
  to change.

## Architecture

Two changes, both entirely within this repo's own build script and
libretro backend source — no dependency on RetroArch's internal directory
conventions and no dependency on any ROMM/EmulatorJS bios-delivery
feature.

### 1. Build-time: embed engine-data into the compiled core

`build/build-retroarch-core.sh` currently invokes `emmake make` with a set
of `EMCC_CFLAGS`. This gets extended to stage a filtered copy of
`scummvm-core/dists/engine-data/` into a scratch directory, then pass that
staged directory to Emscripten's `--embed-file` flag, which bakes the
files directly into the compiled core's own virtual filesystem at a fixed
path — populated automatically before `main()`/`retro_init()` runs, with
no extra runtime download step.

**What gets embedded:** the entire `dists/engine-data/` directory,
*including* `fonts-cjk.dat` (full language coverage, per explicit
decision — see Open Questions/Decisions below), **except**:
- `patches/` (168K) — script patches for the `grim`/`monkey4` engines,
  which belong to the separate GL-core build this project hasn't built
  yet; irrelevant to the current core.
- `testbed-audiocd-files/` (1.8M) — fixtures for ScummVM's internal
  self-test engine (`testbed`), not a real game engine; never built into
  this project's engine list.
- `README`, `engine_data.mk`, `engine_data_core.mk`, `engine_data_big.mk`,
  `create-playground3d-data.sh`, `create-testbed-data.sh` — build
  metadata and dev tooling, not runtime data.

Resulting embed size: **~74MB**, added once to the shared core file (the
`.wasm`/`.js` pair EmulatorJS downloads once and caches across every
ScummVM ROM launch) — not per-ROM.

The vendored `scummvm-core` source tree is never modified. Trimming
happens by staging a filtered copy at `build/embed-staging/engine-data/`
(created fresh by the build script each run, `.gitignore`d — never
committed), so the exclusion list lives in this project's own script,
easy to revisit later (e.g. if the GL-core build eventually needs
`patches/` too).

**Embed path:** a fixed, project-chosen virtual path, `/engine-data`,
unrelated to any RetroArch-internal directory naming.

### 2. Runtime: register the embedded path as a search location

`scummvm-core/backends/platform/libretro/src/libretro-os-utils.cpp`
already implements `OSystem_libretro::addSysArchivesToSearchSet()`
(lines 280-283), which registers RetroArch's own system directory (via
`retro_get_system_dir()`) into ScummVM's search set:

```cpp
void OSystem_libretro::addSysArchivesToSearchSet(Common::SearchSet &s, int priority) {
	if (!s_systemDir.empty())
		s.add("systemDir", new Common::FSDirectory(Common::FSNode(Common::Path(s_systemDir))), priority);
}
```

This method is already called by ScummVM's own generic engine bootstrap
code on **every single game launch, for every engine** — no new call
site is needed. The fix adds a second, unconditional registration for the
embedded path:

```cpp
void OSystem_libretro::addSysArchivesToSearchSet(Common::SearchSet &s, int priority) {
	if (!s_systemDir.empty())
		s.add("systemDir", new Common::FSDirectory(Common::FSNode(Common::Path(s_systemDir))), priority);

	// Engine-data files (fonts.dat, toon.dat, etc.) are compiled directly
	// into this WASM build at /engine-data via --embed-file in
	// build/build-retroarch-core.sh, since there is no persistent, shared
	// system directory available across ROM launches in the browser
	// sandbox the way there is on desktop platforms.
	Common::FSNode embeddedEngineData{Common::Path("/engine-data")};
	if (embeddedEngineData.isDirectory())
		s.add("embeddedEngineData", new Common::FSDirectory(embeddedEngineData), priority);
}
```

Once registered, `common/engine_data.cpp`'s existing lookup
(`Common::File::exists(datFilename)`, which searches the global
`SearchMan`) finds the embedded file automatically. Nothing about that
lookup code changes.

## Data flow

1. Build time: `build-retroarch-core.sh` stages the filtered engine-data
   directory and passes it to `--embed-file`.
2. Emscripten's generated `scummvm_libretro.js` glue code populates the
   in-memory virtual filesystem at `/engine-data` automatically, before
   the module's `main()` runs — this happens on every page load that
   instantiates the core, independent of which ROM is being launched.
3. `package-core.sh` zips the resulting `.wasm`/`.js` exactly as it does
   today — no changes needed there, since the embedded data lives inside
   the `.js` glue file's own asset-loading mechanism (Emscripten's
   standard `--embed-file` output), not as a separate file `package-core.sh`
   needs to know about.
4. At game-launch time, ScummVM's generic bootstrap calls
   `addSysArchivesToSearchSet`, which now also registers `/engine-data`.
5. When an engine needs its `.dat` file, `common/engine_data.cpp`'s
   existing `Common::File::exists()` check finds it via `SearchMan`,
   without needing a copy inside the ROM's own zip.

## Error handling

None new. If the embed step is ever skipped, or a specific file is
missing from the embedded set, `/engine-data` either doesn't exist or
doesn't contain that file — `addSysArchivesToSearchSet` simply doesn't
add a redundant/missing entry (identical to how it already handles an
empty `s_systemDir` today), and `engine_data.cpp` falls through to its
existing, already-correct error message (`"Could not locate engine data
%s"`). No new failure modes are introduced.

## Testing / verification

1. Rebuild the core with the embed change.
2. Pick at least one already-confirmed engine whose ROM currently bundles
   its own copy of a `.dat` file (e.g. `toon`, which bundles `toon.dat`).
   Repackage that ROM **with the `.dat` file stripped out**, redeploy, and
   confirm it still boots and plays — this proves the embedded path is
   being found end-to-end, not just that the build succeeded.
3. Repeat for at least one more engine from a different `.dat` file
   (e.g. `nancy` or `ultima8`) to rule out a fluke.
4. Confirm total core file size grew by roughly the expected ~74MB and
   that EmulatorJS still loads/caches it correctly (no regression in the
   core-download step itself).
5. Do **not** attempt to verify the `fonts.dat`-crash engines
   (`glk`/`dm`/`griffon`/`tony`/`neverhood`) as "fixed" — they are
   expected to still crash after this change, since that bug is separate
   (see Non-goals).

## Decisions made during design

- **Scope: embed the full engine-data set, including `fonts-cjk.dat`**
  (all languages), not just the ~6 engines already known to need one.
  Rationale: covers every future untested engine automatically, not just
  the ones already discovered; explicit user decision given the modest
  one-time size cost relative to the recurring cost of hitting this issue
  engine-by-engine.
- **Registration point: `addSysArchivesToSearchSet`, not a new call
  site or a dependency on `retro_get_system_dir()`.** Piggybacking on
  RetroArch's own system-dir resolution was considered and rejected — its
  internal path composition depends on `$HOME` and a `HAVE_EXTRA_WASMFS`
  build flag, both fragile assumptions this project doesn't control.
- **Delivery via EmulatorJS's `biosUrl`/ROMM bios mechanism was considered
  and rejected** as the primary fix — traced through `emulator.js` and
  confirmed it writes bios content into the same directory as the game
  ROM itself, not a true shared system directory, so it doesn't solve
  "install once" the way embedding in the core does, and depends on a
  ROMM capability outside this repo's control.
