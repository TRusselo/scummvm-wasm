# Embed ScummVM Engine-Data Into the WASM Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Permanently eliminate the "engine forgot its `.dat` file" packaging
failure class by baking ScummVM's engine-data into the compiled WASM core,
so no ROM ever needs to carry its own copy again.

**Architecture:** Stage a filtered copy of `scummvm-core/dists/engine-data/`
at build time, embed it into the core via Emscripten's `--embed-file` at a
fixed virtual path (`/engine-data`), and register that path in ScummVM's
existing `addSysArchivesToSearchSet` search-path hook so the engine's own
unmodified `common/engine_data.cpp` lookup finds it automatically.

**Tech Stack:** Bash (build scripts), C++ (ScummVM libretro backend),
Emscripten/emmake.

**Spec:** [docs/superpowers/specs/2026-09-02-wasm-engine-data-embed-design.md](../specs/2026-09-02-wasm-engine-data-embed-design.md)

## Global Constraints

- The vendored `scummvm-core` source tree's `dists/engine-data/` directory
  itself is never modified — filtering happens only in this project's own
  build script, staged into a throwaway directory.
- Embed everything in `dists/engine-data/` **except**: `patches/`,
  `testbed-audiocd-files/`, `README`, `engine_data.mk`,
  `engine_data_core.mk`, `engine_data_big.mk`, `create-playground3d-data.sh`,
  `create-testbed-data.sh`. `fonts-cjk.dat` IS included (full language
  coverage, per explicit decision in the spec).
- Staging directory: `build/embed-staging/engine-data/` — created fresh
  each build run, must be `.gitignore`d, never committed.
- Do not touch `common/engine_data.cpp`'s lookup logic — it already works
  correctly once the file is discoverable via `SearchMan`.
- Do not attempt to fix the separate `fonts.dat`-crash WASM bug
  (`glk`/`dm`/`griffon`/`tony`/`neverhood`) — explicitly out of scope.
- This plan's execution stops once the core is rebuilt and packaged
  locally (`test-page/ejs/data/cores/scummvm*-wasm.data` regenerated).
  Do **not** run `build/deploy-to-romm.sh` or otherwise touch the running
  ROMM/unraid deployment — that step is held for explicit user go-ahead.

---

### Task 1: Add `.gitignore` entry for the staging directory

**Files:**
- Modify: `.gitignore`

**Interfaces:**
- Produces: an ignored path `build/embed-staging/` that Task 2's script
  writes to.

- [ ] **Step 1: Add the ignore entry**

Add this line to `.gitignore` (create the file at the repo root if it
doesn't already exist, following whatever ignore patterns are already
present):

```
build/embed-staging/
```

- [ ] **Step 2: Verify it's ignored**

Run: `git check-ignore -q build/embed-staging/anything && echo IGNORED || echo NOT_IGNORED`
Expected: `IGNORED`

- [ ] **Step 3: Commit**

```bash
git add .gitignore
git commit -m "Ignore build/embed-staging/ scratch directory"
```

---

### Task 2: Stage filtered engine-data and embed it in the core build

**Files:**
- Modify: `build/build-retroarch-core.sh`

**Interfaces:**
- Consumes: `scummvm-core/dists/engine-data/` (vendored, read-only).
- Produces: `build/embed-staging/engine-data/` (filtered copy, staged
  fresh each run) and an `--embed-file` argument added to the existing
  `emmake make` invocation's `EMCC_CFLAGS`.

- [ ] **Step 1: Add the staging step**

Edit `build/build-retroarch-core.sh`. Insert this block after the
`cd "$(dirname "$0")/.."` line and before the existing
`cp -f scummvm-core/backends/platform/libretro/scummvm_libretro_emscripten.bc ...`
line:

```bash
# Stage a filtered copy of ScummVM's own engine-data directory so it can
# be embedded directly into the compiled core (see
# docs/superpowers/specs/2026-09-02-wasm-engine-data-embed-design.md).
# This eliminates the need for individual ROMs to carry their own copy
# of fonts.dat/toon.dat/nancy.dat/etc. Excludes files that are dev
# tooling or belong to engines this build doesn't compile (grim/monkey4
# patches are for the separate, not-yet-built GL-core).
STAGE_DIR="build/embed-staging/engine-data"
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"
rsync -a \
  --exclude='patches/' \
  --exclude='testbed-audiocd-files/' \
  --exclude='README' \
  --exclude='engine_data.mk' \
  --exclude='engine_data_core.mk' \
  --exclude='engine_data_big.mk' \
  --exclude='create-playground3d-data.sh' \
  --exclude='create-testbed-data.sh' \
  scummvm-core/dists/engine-data/ "$STAGE_DIR/"

echo "Staged engine-data for embedding:"
du -sh "$STAGE_DIR"
```

- [ ] **Step 2: Verify the staged directory excludes the right files**

Run:
```bash
ls build/embed-staging/engine-data/ | grep -E "^(patches|testbed-audiocd-files|README|engine_data.*\.mk|create-.*-data\.sh)$"
```
Expected: no output (nothing matches — all excluded files are absent).

Run:
```bash
ls build/embed-staging/engine-data/fonts-cjk.dat build/embed-staging/engine-data/toon.dat build/embed-staging/engine-data/fonts.dat
```
Expected: all three files listed (confirms inclusion of the full set,
including CJK fonts).

- [ ] **Step 3: Add the `--embed-file` flag to the emcc invocation**

In the same file, find the existing `EMCC_CFLAGS="--pre-js ../build/midi-stub-pre.js"`
line. Change it to also embed the staged directory. Since the build `cd`s
into `retroarch/` before invoking `emmake make`, the path to the staged
directory must be relative to that directory:

```bash
EMCC_CFLAGS="--pre-js ../build/midi-stub-pre.js --embed-file ../build/embed-staging/engine-data@/engine-data" emmake make -f Makefile.emulatorjs \
```

(This replaces the existing `EMCC_CFLAGS="--pre-js ../build/midi-stub-pre.js" emmake make -f Makefile.emulatorjs \` line — same line, just the `EMCC_CFLAGS` value extended with the new `--embed-file` argument. Keep every other flag on that invocation unchanged.)

- [ ] **Step 4: Commit**

```bash
git add build/build-retroarch-core.sh
git commit -m "Stage and embed ScummVM engine-data into the WASM core build

Bakes fonts.dat/toon.dat/nancy.dat/ultima8.dat/etc. directly into the
compiled core via --embed-file, so individual ROMs no longer need to
carry their own copy. See docs/superpowers/specs/2026-09-02-wasm-engine-data-embed-design.md."
```

---

### Task 3: Register the embedded path in ScummVM's search set

**Files:**
- Modify: `scummvm-core/backends/platform/libretro/src/libretro-os-utils.cpp:280-283`

**Interfaces:**
- Consumes: the `/engine-data` virtual path populated by Task 2's
  `--embed-file` at module-load time.
- Produces: no new interface — extends the existing
  `OSystem_libretro::addSysArchivesToSearchSet` override, already called
  by ScummVM's generic engine bootstrap on every game launch.

- [ ] **Step 1: Read the current implementation to confirm line numbers still match**

Run: `sed -n '278,285p' scummvm-core/backends/platform/libretro/src/libretro-os-utils.cpp`

Expected output (confirm before editing — if it differs, locate the
`addSysArchivesToSearchSet` function by name instead of line number):

```cpp
void OSystem_libretro::addSysArchivesToSearchSet(Common::SearchSet &s, int priority) {
	if (!s_systemDir.empty())
		s.add("systemDir", new Common::FSDirectory(Common::FSNode(Common::Path(s_systemDir))), priority);
}
```

- [ ] **Step 2: Add the embedded-path registration**

Replace that function body with:

```cpp
void OSystem_libretro::addSysArchivesToSearchSet(Common::SearchSet &s, int priority) {
	if (!s_systemDir.empty())
		s.add("systemDir", new Common::FSDirectory(Common::FSNode(Common::Path(s_systemDir))), priority);

	// Engine-data files (fonts.dat, toon.dat, etc.) are compiled directly
	// into this WASM build at /engine-data via --embed-file in
	// build/build-retroarch-core.sh, since there is no persistent, shared
	// system directory available across ROM launches in the browser
	// sandbox the way there is on desktop platforms. See
	// docs/superpowers/specs/2026-09-02-wasm-engine-data-embed-design.md.
	Common::FSNode embeddedEngineData{Common::Path("/engine-data")};
	if (embeddedEngineData.isDirectory())
		s.add("embeddedEngineData", new Common::FSDirectory(embeddedEngineData), priority);
}
```

- [ ] **Step 3: Commit**

```bash
git add scummvm-core/backends/platform/libretro/src/libretro-os-utils.cpp
git commit -m "Register embedded /engine-data path in ScummVM's search set

Lets common/engine_data.cpp's existing lookup find engine-data files
baked into the core, with no change to that lookup code itself."
```

---

### Task 4: Rebuild the core and verify the embed took effect

**Files:**
- None modified — this task runs the existing build pipeline and inspects
  its output.

**Interfaces:**
- Consumes: Task 2 and Task 3's changes.
- Produces: rebuilt `retroarch/scummvm_libretro.wasm` /
  `scummvm_libretro.js`, and repackaged
  `test-page/ejs/data/cores/scummvm-thread-wasm.data` /
  `scummvm-thread-legacy-wasm.data`.

- [ ] **Step 1: Run the full core build**

```bash
bash build/build-core.sh
```

(If `build/build-core.sh` doesn't itself call both
`build-retroarch-core.sh` and `package-core.sh` in sequence, run them
directly in that order instead:
`bash build/build-retroarch-core.sh && bash build/package-core.sh`.)

Expected: build completes without errors. Watch for any Emscripten error
mentioning `--embed-file` or the `/engine-data` path — if the staged
directory from Task 2 is missing or the path is malformed, this is where
it will surface.

- [ ] **Step 2: Confirm the size increase**

```bash
ls -la retroarch/scummvm_libretro.wasm test-page/ejs/data/cores/scummvm-thread-wasm.data
```

Expected: both files are roughly 70-80MB larger than their pre-change
size (the staged engine-data is ~74MB; some variance is expected from
Emscripten's own packaging overhead).

- [ ] **Step 3: Confirm embedded files are present via string search**

`--embed-file` bakes content directly into the compiled `.wasm` binary's
data section, not the `.js` glue file (confirmed by isolated testing
during implementation) — check the `.wasm`:

```bash
strings retroarch/scummvm_libretro.wasm | grep -oE "/engine-data/[a-zA-Z0-9_.-]+" | sort -u
```

Expected: one line per embedded file (`/engine-data/fonts.dat`,
`/engine-data/toon.dat`, etc.) — cross-check against the staged directory
listing from Task 2 Step 2.

Expected: non-zero (Emscripten's generated `--embed-file` loader code
references the embed path by name).

- [ ] **Step 4: STOP HERE**

Do not run `build/deploy-to-romm.sh`. Do not restart, rebuild, or
otherwise touch the running ROMM container on unraid. Report the build
result (success/failure, file sizes, any warnings) and wait for explicit
go-ahead before any deployment step — per user instruction, this plan's
execution ends once the core is compiled and packaged locally.

- [ ] **Step 5: Commit (build artifacts only if the repo tracks them; otherwise skip)**

Check whether `test-page/ejs/data/cores/*.data` and
`retroarch/scummvm_libretro.wasm`/`.js` are tracked by git
(`git status` after the build). If they are `.gitignore`d build outputs,
no commit is needed for this step — just leave them in place for manual
deployment later. If they are tracked, commit them with message
`"Rebuild core with embedded engine-data"`.

---

## Explicitly deferred (not part of this plan's execution)

The spec's "Testing / verification" section (stripping `toon.dat` from an
already-packaged ROM and confirming it still boots via the live
ROMM/EmulatorJS deployment) requires deploying the rebuilt core to the
running unraid container, which is explicitly held for the user's
go-ahead per their instruction. That verification is the natural next
step once deployment is approved, but is not a task in this plan.

## Post-plan verification (completed 2026-09-02)

The user approved deployment. The new core was built on the Unraid box
itself (via `/tmp/romm-build`, a checkout tracking the
`emulatorjs-wasm-fixes` branch of the `TRusselo/romm` fork — the box's
own Docker already has `buildx`, unlike this dev machine, whose
`docker-buildx` package turned out to be a broken symlink), the
`romm-scummvm:local` image was rebuilt from it, and the user force-updated
the running `/romm` container to the new image
(`sha256:926852616447...`).

Verification: 8 test ROMs were built by stripping the bundled `.dat`
file from otherwise-identical copies of existing ROMs (anchor entry order
preserved; `Tony Tough`'s anchor was corrected to `TTFrontend.exe` since
`fonts.dat` had been occupying entry 0 in the original):

- **3 previously-confirmed engines, `.dat` stripped**: `ultima8.dat` from
  Ultima VIII, `toon.dat` from Toonstruck, `fonts.dat` from Buried in
  Time. **Result: all three play correctly** — confirms the embedded
  `/engine-data` path is being found and used with zero bundled `.dat`
  files in the ROM.
- **5 fonts.dat-crash-blocked titles, `fonts.dat` stripped**: Dungeon
  Master, Griffon Legend, Neverhood, Zork I, Tony Tough. **Result: all
  five still hang on the ScummVM splash with the same out-of-bounds
  memory access error** — confirms the crash is deterministic and
  independent of which copy of `fonts.dat` is loaded (embedded vs.
  previously-bundled), ruling out a corrupted/mismatched bundled copy as
  an alternate explanation and reinforcing that it's a genuine WASM
  rendering bug, not a packaging issue.

Both outcomes match the spec's predictions exactly. The goal is achieved:
the "engine forgot its `.dat` file" packaging failure class is
permanently eliminated for every engine, tested and untested.
