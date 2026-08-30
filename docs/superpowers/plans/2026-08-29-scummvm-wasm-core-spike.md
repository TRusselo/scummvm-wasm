# ScummVM WASM Core for EmulatorJS — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reproduce, inside this project's real repo (not a throwaway scratchpad), the build/link/package pipeline already proven live during design, then diagnose and fix the one open problem it surfaced: a real ScummVM game (`zak.scm`) loads into the WASM core without crashing, but doesn't auto-launch — it lands on RetroArch's own contentless menu instead.

**Architecture:** Vendor `libretro/scummvm` as a single git submodule (it already contains a working `emscripten` platform target for its libretro wrapper — no wrapper code changes needed for the build itself). Build the SCUMM-only core `.bc` from that submodule, link it into a submoduled `EmulatorJS/RetroArch` checkout with one required flag fix (`LD=em++`), package the result into EmulatorJS's `.data` bundle format, and serve it from a minimal static test page. The remaining problem — the game not auto-launching — gets root-caused by tracing what `game->path` string actually reaches `retro_load_game()`, since the wrapper's own directory-autodetect code path is already correct, tested, existing code that should handle it once the input is right.

**Tech Stack:** Emscripten (emsdk, "latest" channel — resolved to 6.0.8 during the spike), GNU Make, C++ (ScummVM's own codebase, untouched), JavaScript (EmulatorJS v4.2.3 loader — same version RomM ships), 7-Zip (`7z`) for core packaging, Python's `http.server` for local testing, `git submodule`.

**Spec:** `docs/superpowers/specs/2026-08-29-scummvm-wasm-emulatorjs-design.md`

**Deviation from the spec's repo structure, by design:** the spec lists a
dedicated `zip-mount/` component (client-side JS to unzip a `.scm` and write
it into the module's virtual FS). This plan does not create that directory.
The spike found EmulatorJS's own loader already does generic zip/7z
extraction into the FS for any core (see spec's Spike Results, point 5) —
so the real open problem isn't "how do we unzip," it's "why doesn't the
already-extracted content reach `retro_load_game` correctly," which is what
Tasks 5-6 diagnose and fix. If Task 6's fix ends up requiring genuinely new
client-side code beyond a small hook script, create `zip-mount/` at that
point and update the spec's repo structure to match reality — don't create
it speculatively now.

## Global Constraints

- Engine scope: SCUMM only — enforced by overwriting `lite_engines.list` to contain just `scumm`, building with `LITE=1`. Never build with all engines enabled; that was not tested and isn't needed for any target game.
- Target games are all single-disc — no multi-disc/CD-swap handling needed anywhere in this plan.
- No save-game persistence work in this plan — out of scope per spec.
- No automated test suite — every task's verification is a build-success check or a manual browser check, per the spec's testing strategy.
- Never commit copyrighted game data (`.scm` files) to git — the repo's `.gitignore` already excludes `*.scm`; keep it that way.
- Every submodule is pinned to an explicit tag/commit, never left tracking a floating branch, so builds stay reproducible.

---

### Task 1: Vendor `libretro/scummvm` and `EmulatorJS/RetroArch` as pinned submodules

**Files:**
- Create: `.gitmodules` (via `git submodule add`)
- Create: `scummvm-core/` (submodule → `libretro/scummvm`)
- Create: `retroarch/` (submodule → `EmulatorJS/RetroArch`, branch `next`)
- Modify: `.gitignore` (add emsdk install location if vendored under the repo — see step 1)

**Interfaces:**
- Produces: `scummvm-core/backends/platform/libretro/` (the wrapper + emscripten Makefile target, used unmodified in Task 2), `retroarch/Makefile.emulatorjs` and `retroarch/emulatorjs/build-emulatorjs.sh` (used in Task 3).

- [ ] **Step 1: Decide and create the emsdk install location**

Run:
```bash
mkdir -p toolchain
echo "toolchain/emsdk/" >> .gitignore
```
This keeps the multi-GB emsdk checkout out of git, matching how it was handled during the spike (scratchpad, never committed).

- [ ] **Step 2: Add the `libretro/scummvm` submodule, pinned to its latest tag**

Run:
```bash
git submodule add https://github.com/libretro/scummvm.git scummvm-core
cd scummvm-core
git fetch --tags
git tag --sort=-creatordate | head -5
```
Pick the newest tag from that list (do not use a tag older than late 2025 — the emscripten build fix commit found during design landed 2025-12-24). Check it out:
```bash
git checkout <chosen-tag>
cd ..
git add scummvm-core .gitmodules
```

- [ ] **Step 3: Add the `EmulatorJS/RetroArch` submodule on branch `next`**

Run:
```bash
git submodule add -b next https://github.com/EmulatorJS/RetroArch.git retroarch
cd retroarch
git rev-parse HEAD > /tmp/retroarch-pinned-commit.txt
cd ..
git add retroarch .gitmodules
```
Record the exact commit (from the temp file) in the commit message in Step 5 — `next` is a moving branch, so pin to this specific commit going forward (later tasks should use `git -C retroarch checkout <that-commit>` if the submodule ever gets updated unintentionally).

- [ ] **Step 4: Verify submodule contents match what the spike used**

Run:
```bash
test -f scummvm-core/backends/platform/libretro/Makefile && echo "wrapper Makefile OK"
grep -q "platform), emscripten" scummvm-core/backends/platform/libretro/Makefile && echo "emscripten target present"
test -f retroarch/Makefile.emulatorjs && echo "Makefile.emulatorjs OK"
test -f retroarch/emulatorjs/build-emulatorjs.sh && echo "build-emulatorjs.sh OK"
```
All four checks must print their OK/present message. If the emscripten target check fails, the pinned tag is too old — go back to Step 2 and pick an older or newer tag until it's present (it should be present in essentially any recent tag given when the fix commit landed).

- [ ] **Step 5: Commit**

```bash
git commit -m "$(cat <<'EOF'
Vendor libretro/scummvm and EmulatorJS/RetroArch as pinned submodules

RetroArch pinned commit: <paste from /tmp/retroarch-pinned-commit.txt>

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Build script for the SCUMM-only core `.bc`

**Files:**
- Create: `build/setup-emsdk.sh`
- Create: `build/build-core.sh`
- Test: manual (build-success check, no unit test framework applies here)

**Interfaces:**
- Consumes: `scummvm-core/backends/platform/libretro/` (Task 1)
- Produces: `scummvm-core/backends/platform/libretro/scummvm_libretro_emscripten.bc` — consumed by Task 3's link step.

- [ ] **Step 1: Write `build/setup-emsdk.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ ! -d toolchain/emsdk ]; then
  git clone https://github.com/emscripten-core/emsdk.git toolchain/emsdk
fi
cd toolchain/emsdk
./emsdk install latest
./emsdk activate latest
```

- [ ] **Step 2: Run it and verify emcc is installed**

```bash
bash build/setup-emsdk.sh
source toolchain/emsdk/emsdk_env.sh
emcc --version | head -1
```
Expected: prints an `emcc (Emscripten gcc/clang-like replacement...)` version line. (The spike resolved "latest" to 6.0.8 — a different version is fine as long as this prints successfully.)

- [ ] **Step 3: Write `build/build-core.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Scope the build to the SCUMM engine only.
echo "scumm" > scummvm-core/backends/platform/libretro/lite_engines.list

source toolchain/emsdk/emsdk_env.sh

cd scummvm-core/backends/platform/libretro
emmake make platform=emscripten LITE=1 -j"$(nproc)"

echo "Build artifact:"
ls -la scummvm_libretro_emscripten.bc
```

- [ ] **Step 4: Run it and verify the artifact**

```bash
bash build/build-core.sh
```
Expected: exits 0, and the final `ls -la` line shows `scummvm_libretro_emscripten.bc` sized roughly 20-30MB (the spike produced ~24MB; exact size will vary slightly by submodule tag/emsdk version, but a multi-megabyte `.bc` is the pass criterion — a few-KB file means the build silently produced nothing useful).

- [ ] **Step 5: Commit**

```bash
git add build/setup-emsdk.sh build/build-core.sh
git commit -m "$(cat <<'EOF'
Add SCUMM-only emscripten core build script

Reproduces the build verified during design: overwrite
lite_engines.list to scope to the scumm engine only, then
emmake make platform=emscripten LITE=1.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

Note: `scummvm-core/backends/platform/libretro/lite_engines.list` gets modified in-place by this script inside the submodule checkout. This is intentional (matches what the spike did) but means the submodule will always show as "dirty" after building. Do not commit that dirty submodule state — it's a build artifact, not a tracked change. If a `git status` check in a later task flags it, that's expected and fine to leave uncommitted.

---

### Task 3: Link into RetroArch's emulatorjs pipeline and package the core

**Files:**
- Create: `build/build-retroarch-core.sh`
- Create: `build/package-core.sh`
- Test: manual (build-success + file-existence checks)

**Interfaces:**
- Consumes: `scummvm-core/backends/platform/libretro/scummvm_libretro_emscripten.bc` (Task 2)
- Produces: `retroarch/scummvm_libretro.js`, `retroarch/scummvm_libretro.wasm`, then `test-page/ejs/data/cores/scummvm-wasm.data` and `test-page/ejs/data/cores/scummvm-legacy-wasm.data` — consumed by Task 4.

- [ ] **Step 1: Write `build/build-retroarch-core.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source toolchain/emsdk/emsdk_env.sh

cp -f scummvm-core/backends/platform/libretro/scummvm_libretro_emscripten.bc \
      retroarch/libretro_emscripten.a

cd retroarch
emmake make -f Makefile.emulatorjs \
  LD=em++ \
  HAVE_7ZIP=1 HAVE_CHD=1 \
  HAVE_THREADS=0 PTHREAD_POOL_SIZE=0 \
  ASYNC=1 HAVE_OPENGLES3=1 \
  STACK_SIZE=4194304 INITIAL_HEAP=134217728 \
  TARGET=scummvm_libretro.js \
  -j"$(nproc)"

echo "Build artifacts:"
ls -la scummvm_libretro.js scummvm_libretro.wasm
```

The `LD=em++` flag is the one required fix found during the spike: the shared `Makefile.emulatorjs` links with `emcc` by default, which doesn't pull in `libc++abi`'s RTTI support that ScummVM's C++ codebase needs, and fails with `undefined symbol: vtable for __cxxabiv1::__si_class_type_info` without it.

- [ ] **Step 2: Run it and verify both artifacts**

```bash
bash build/build-retroarch-core.sh
```
Expected: exits 0. `scummvm_libretro.js` should be on the order of a few hundred KB; `scummvm_libretro.wasm` on the order of 10-20MB (the spike produced 274KB and 14MB respectively). If the link fails with `undefined symbol` errors mentioning `__cxxabiv1`, the `LD=em++` flag was dropped somewhere — check the script wasn't edited to remove it.

- [ ] **Step 3: Write `build/package-core.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p test-page/ejs/data/cores

7z a -y test-page/ejs/data/cores/scummvm-wasm.data \
  retroarch/scummvm_libretro.wasm retroarch/scummvm_libretro.js

# EmulatorJS's loader requests the "-legacy" variant by default (confirmed
# during the spike). Until Task 5/6 investigates GLES3 vs legacy properly,
# ship both variants identically so the loader's default request succeeds.
cp test-page/ejs/data/cores/scummvm-wasm.data \
   test-page/ejs/data/cores/scummvm-legacy-wasm.data

ls -la test-page/ejs/data/cores/scummvm*
```

- [ ] **Step 4: Run it and verify both `.data` bundles exist**

```bash
bash build/package-core.sh
```
Expected: both `scummvm-wasm.data` and `scummvm-legacy-wasm.data` exist, each a few MB (7z-compressed; the spike's bundle was ~3.1MB).

- [ ] **Step 5: Commit**

```bash
git add build/build-retroarch-core.sh build/package-core.sh
git commit -m "$(cat <<'EOF'
Add RetroArch link + packaging scripts for the scummvm core

Requires LD=em++ (not the emmake default of emcc) because ScummVM's
C++ codebase needs libc++abi's RTTI support, which emcc alone doesn't
link in. Packages into both -wasm.data and -legacy-wasm.data since
EmulatorJS's loader requests the legacy variant by default.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```
(Do not commit the `.data` files themselves — they're large build artifacts. Add `test-page/ejs/data/cores/*.data` to `.gitignore` before this commit.)

---

### Task 4: Minimal test page, vendored EmulatorJS loader, and a clean-boot smoke test

**Files:**
- Create: `test-page/download-emulatorjs.sh`
- Create: `test-page/index.html`
- Modify: `.gitignore` (exclude the downloaded EmulatorJS release and `.data` core bundles)
- Test: manual, in-browser

**Interfaces:**
- Consumes: `test-page/ejs/data/cores/scummvm-wasm.data` (Task 3)
- Produces: a servable `test-page/` directory — consumed by Task 5/6's diagnosis work.

- [ ] **Step 1: Write `test-page/download-emulatorjs.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
EJS_VERSION="4.2.3"
if [ -d ejs/data ]; then
  echo "EmulatorJS already present at test-page/ejs — skipping download."
  exit 0
fi
curl -sL -o ejs.7z "https://github.com/EmulatorJS/EmulatorJS/releases/download/v${EJS_VERSION}/${EJS_VERSION}.7z"
mkdir -p ejs
7z x -y ejs.7z -o./ejs
rm ejs.7z
```
Pinned to v4.2.3 — the same version RomM currently ships, chosen for consistency with a real-world deployment rather than always tracking latest.

- [ ] **Step 2: Add to `.gitignore` and run the download**

```bash
cat >> ../.gitignore <<'EOF'
test-page/ejs/
test-page/ejs.7z
test-page/ejs/data/cores/*.data
EOF
cd test-page
bash download-emulatorjs.sh
test -f ejs/data/loader.js && echo "loader.js present"
```

- [ ] **Step 3: Write `test-page/index.html`**

```html
<!doctype html>
<html>
<head><title>ScummVM WASM Core</title></head>
<body style="background:#222;color:#eee;font-family:monospace;">
<h3>ScummVM WASM core</h3>
<div id="game" style="width:640px;height:480px;background:#000;"></div>
<script>
  EJS_player = "#game";
  EJS_core = "scummvm";
  EJS_pathtodata = "ejs/data/";
  EJS_startOnLoaded = true;
  EJS_gameUrl = "";
</script>
<script src="ejs/data/loader.js"></script>
</body>
</html>
```
`EJS_gameUrl` is deliberately empty for this task's smoke test — it isolates "does the core download and initialize" from "does a game load," which is exactly the split the spike found useful (the empty-content run crashed differently than the real-content run, and conflating them would make failures harder to diagnose).

- [ ] **Step 4: Serve and check for a clean core download (manual browser check)**

```bash
cd test-page
python3 -m http.server 8934 &
```
Open `http://localhost:8934/index.html` in a browser (use the `claude-in-chrome` tools if working inside this session), wait ~5 seconds, then check the browser console.

Expected: **no** "Error downloading core" message. You should see log lines like "File not found, attempting to fetch from emulatorjs cdn" only if the packaging step's filename doesn't match what the loader requests — if that appears, re-check Task 3 Step 3's exact output filename (`scummvm-legacy-wasm.data`) against what the console error names.

Known-acceptable outcome at this task's stage: the core loads and then throws an `ErrnoError` in the console (confirmed cause during the spike: no game content, no bundled system files — this is expected and is what Task 5 investigates, not a regression to fix here). A clean core *download* with no 404/fetch error is this task's actual pass condition.

Stop the server when done: `kill %1` (or find and kill the `http.server` process).

- [ ] **Step 5: Commit**

```bash
cd ..
git add test-page/download-emulatorjs.sh test-page/index.html .gitignore
git commit -m "$(cat <<'EOF'
Add minimal EmulatorJS test page for manual core validation

Pinned to EmulatorJS v4.2.3, the same version RomM currently ships.
EJS_gameUrl left empty deliberately -- isolates "does the core
download/init" from "does a game load," matching how the design
spike diagnosed the two failure modes separately.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Diagnose why a loaded game doesn't auto-launch

**Files:**
- Modify: `test-page/index.html` (temporarily, for `EJS_gameUrl`)
- Create: `docs/superpowers/notes/2026-08-29-autolaunch-diagnosis.md` (findings, not code)
- No production code changes in this task — it is purely investigative, per the spec's explicit note that the root cause wasn't known at design time.

**Interfaces:**
- Consumes: the test page from Task 4, a real game zip (e.g. `zak.scm`, provided by the project owner — never commit it) placed at `test-page/zak.scm`.
- Produces: a written diagnosis that Task 6 implements a fix against. Task 6 cannot be written concretely until this task's findings exist.

**Context carried over from the spike (do not re-discover these — verify against them):**
- The wrapper's `retro_get_system_info()` (in `scummvm-core/backends/platform/libretro/src/libretro-core.cpp`, around line 900) registers `info->valid_extensions = "scummvm"`. This means RetroArch's own file browser only lists `.scummvm` files — the observed "empty `/` in Load Content" during the spike is fully explained by this and is not evidence of a deeper bug.
- `retro_load_game()` (same file, starts around line 1141) already contains working, existing directory-autodetect logic: if `game->path` is a directory, or a non-`.scummvm` file whose parent directory contains detectable game data, it calls `LIBRETRO_G_SYSTEM->testGame(parent_dir, true)` and on success builds `-p "<dir>" --auto-detect` via `parse_command_params()`. This code path is not the suspect — the question is what `game->path` value actually reaches it.
- EmulatorJS's `downloadRom()` (in `test-page/ejs/data/src/emulator.js`, search for that function name) already generically extracts zip content and writes every entry to `/<filename>` at the FS root via `this.gameManager.FS.writeFile`, then sets `this.fileName` to either a "supported extension" match or `fileNames[0]`. This is also not necessarily the suspect — but exactly what gets passed onward to `retro_load_game` (is it `this.fileName`, `this.config.gameUrl`, something else?) was not traced during the spike.
- The console repeatedly logged "Could not fetch core report JSON! Core caching will be disabled!" in both spike runs — this core has no `cores.json`/report-JSON entry, unlike official EmulatorJS cores. This is a real candidate root cause: if EmulatorJS's decision to call `retro_load_game` with real content (vs. `NULL`) depends on metadata this core doesn't have, that would explain landing on the contentless menu despite `EJS_startOnLoaded = true` and despite real content having been fetched and extracted.

- [ ] **Step 1: Reproduce the exact spike scenario**

Copy a real game zip into place (do this manually — never via a script that could commit it):
```bash
cp /path/to/zak.scm test-page/zak.scm
```
Edit `test-page/index.html`, change `EJS_gameUrl = "";` to `EJS_gameUrl = "zak.scm";`. Serve and load as in Task 4 Step 4.

Expected (matching the spike): no `ErrnoError`; RetroArch's own menu renders; "Load Content" → "/" shows no matching files (expected, per `valid_extensions = "scummvm"` above).

- [ ] **Step 2: Find the actual `game->path` string passed into the core**

The compiled module exports `EXPORTED_RUNTIME_METHODS` including `cwrap`/`ccall`-style access (confirmed in the link command from Task 3). Use the browser console directly (via `claude-in-chrome`'s console tools, or manually) to inspect what EmulatorJS's `emulator.js` passes as the game path right before calling into the compiled `Module`. Concretely:
```bash
grep -n "gameManager.loadRom\|Module\[.callMain\|retro_load_game\|startGame()" test-page/ejs/data/src/emulator.js
```
Read the ~30 lines around each match. Identify the exact variable/string that ends up as the content path argument. Record the literal value observed at runtime (add a temporary `console.log` in a local copy if the unminified source is being loaded, or use a browser breakpoint) in the findings doc from Step 4.

- [ ] **Step 3: Check whether missing core metadata (cores.json) gates real-content loading**

```bash
grep -n "core report\|Could not fetch core report\|coreManager\|cores.json" test-page/ejs/data/src/emulator.js
```
Read the surrounding logic. Determine: does the absence of a report-JSON entry for `"scummvm"` change whether `retro_load_game` receives the extracted content path, or does it only affect unrelated caching behavior (as the log message's wording suggests, but verify rather than trust the message)? If it does gate content loading, identify what a minimal valid report JSON / `cores.json` entry needs to contain (check an existing core's entry, e.g. `dosbox_pure`'s, as a template) and where the test page would need to serve it from.

- [ ] **Step 4: Write the findings**

Create `docs/superpowers/notes/2026-08-29-autolaunch-diagnosis.md` containing: the literal `game->path` value observed in Step 2, whether Step 3's metadata hypothesis was confirmed or ruled out, and — based on those two facts — which single fix from Task 6's candidate list (below) applies. This file is a diagnosis record, not a spec or plan; keep it short (the actual fact plus a one-line pointer to which Task 6 candidate to implement).

- [ ] **Step 5: Commit the findings (not the game zip)**

```bash
git status
```
Confirm `zak.scm` does NOT appear in the output as staged/tracked (it's gitignored — if it somehow appears, do not add it). Then:
```bash
git add docs/superpowers/notes/2026-08-29-autolaunch-diagnosis.md
git commit -m "$(cat <<'EOF'
Document root cause of the auto-launch gap found during the spike

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Fix the auto-launch gap

This task's exact steps depend on Task 5's findings and cannot be fully specified until that diagnosis exists — per the "no placeholders" rule, this section defines the **complete decision procedure and every candidate fix concretely**, so whichever branch applies has real, ready-to-use content rather than a vague "implement the fix."

**Files:**
- Modify: `test-page/index.html` and/or a new `test-page/cores.json` (Candidate A)
- Modify: `test-page/index.html`'s `EJS_gameUrl` handling, or add a small `test-page/pre-load.js` (Candidate B)
- Test: manual, in-browser — same procedure as Task 5 Step 1, checking for the game actually starting (ScummVM's own UI or the Zak McKracken intro, not RetroArch's menu).

**Candidate A — missing core metadata gated content loading (if Task 5 Step 3 confirmed this):**

Create `test-page/cores.json` modeled on an existing core's entry (fetch `dosbox_pure`'s entry from `https://raw.githubusercontent.com/EmulatorJS/EmulatorJS/main/cores.json` as the template — read it during this task, don't guess its shape), adapted with `"name": "scummvm"` and `"extensions": ["scm"]`. Point `EJS_pathtodata` or a dedicated config option at it per what Step 3's research found `emulator.js` expects for a locally-served (non-CDN) report JSON. Re-run the Task 5 Step 1 procedure; confirm the "Could not fetch core report JSON" warning is gone and the game now auto-launches.

**Candidate B — wrong path/filename reaches `retro_load_game` (if Task 5 Step 2 found a mismatch):**

Based on the exact literal path Step 2 recorded, either: (a) if EmulatorJS passes the original `zak.scm` name rather than an extracted file's real path, add a `test-page/pre-load.js` hook (loaded before `loader.js`) that renames/re-registers `EJS_gameUrl`'s resolved filename to match one of the actually-extracted files' names, using whatever hook `emulator.js` exposes for this (identify the exact hook name from Task 5 Step 2's reading — EmulatorJS has documented lifecycle hooks like `EJS_onGameStart`; confirm the closest match by reading `emulator.js`'s hook-invocation call sites, not by assuming a name); or (b) if the path format itself is wrong (e.g., missing leading slash, wrong mount point), fix the path construction at that exact call site identified in Step 2 — this may require patching the vendored `test-page/ejs/data/src/emulator.js` locally (acceptable for this project's own test page; not an upstream EmulatorJS contribution) and rebuilding `emulator.min.js` is not required since `loader.js` can be pointed at the unminified `src/emulator.js` directly for local testing (check `loader.js` for how it selects min vs unminified — grep for `emulator.min.js` in `loader.js` and see if a debug/dev flag already exists).

- [ ] **Step 1: Apply whichever candidate Task 5's findings doc points to**

(Concrete sub-steps are in the candidate description above — follow the one matching the diagnosis.)

- [ ] **Step 2: Re-run the manual validation from Task 5 Step 1**

Expected: the core boots directly into Zak McKracken (or at minimum ScummVM's own Launcher showing Zak McKracken as a detected game, if full auto-start doesn't trigger but detection now succeeds) — not RetroArch's contentless main menu.

- [ ] **Step 3: Run the spec's full manual validation checklist against this one game**

From the spec's Testing & Validation Strategy section:
1. Loads without a load failure.
2. Video: intro/title frame renders correctly.
3. Audio: any sound plays at all, even if choppy.
4. Input: a mouse click on a verb/object registers as in-game input.
5. Play far enough to confirm the game loop is stable across multiple rooms.

Record which of these pass/fail — item 3 (audio) is the spec's other named open risk (the `rthreads.o`/pthread question) and may surface a new, separate problem even after auto-launch is fixed. If it does, that's a new finding for a follow-up plan, not something to force-fix inside this task.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
Fix game auto-launch gap

<one line: which candidate, and the actual root cause per Task 5's
diagnosis>

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## What's Explicitly Not in This Plan

Per the spec: save-game persistence, touch/mobile input, multi-disc handling, upstreaming to EmulatorJS's official core list, and automated testing. Also not in this plan: repeating the validation checklist against the other five target games (Maniac Mansion, Loom, both Indiana Jones titles, Day of the Tentacle) — that's mechanical repetition of Task 6 Step 3 once this plan's core problem is solved for one game, not new design work, and can be done as a fast follow-up once Task 6 lands.
