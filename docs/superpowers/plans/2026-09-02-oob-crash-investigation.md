# Shared `fonts.dat` OOB Crash Investigation Plan

> **For agentic workers:** This is an investigation plan, not a feature
> implementation. Tasks 1-4 gather evidence; Task 5 is a checkpoint to
> decide next steps based on what's found, not a predetermined fix.
> Use superpowers:executing-plans or run it directly in this session --
> subagent-driven-development doesn't fit well here since each task's
> exact content depends on the previous task's findings.

**Goal:** Find the actual root cause of the `RuntimeError: memory access
out of bounds` crash shared identically across 9 engines
(`griffon`/`glk`/`dm`/`tony`/`neverhood`/`bbvs`/`gnap`/`mutationofjb`/`ngi`)
once each engine's `fonts.dat` requirement is satisfied. This is a
diagnostic investigation, not a fix -- the deliverable is a confirmed
root cause (exact function, exact faulting operation), which then informs
a separate follow-up plan to actually fix it.

**Why now:** this was deferred all session as "needs debug-build
investigation" without ever actually doing it. It affects 9 of 102
engines -- the single largest concentration of failures outside genuine
sourcing/tooling gaps. Worth resolving properly rather than leaving
parked indefinitely.

**Architecture:** Two-phase diagnostic approach in an isolated worktree:
(1) rebuild with real Emscripten debug info instead of guessing at
`printf` placement, reproduce the crash, and get an actual symbolicated
C++ stack trace instead of raw `wasm-function[N]` indices; (2) once the
exact function is known, add targeted diagnostic logging inside it to
find the specific faulting operation (which array index, which pointer,
which buffer size). Test locally via `test-page/` rather than the
production ROMM/Unraid deployment, to allow fast iterative rebuild-test
cycles without disrupting the live library.

**Tech Stack:** C++ (ScummVM/libretro core), Emscripten build flags,
bash, local EmulatorJS test harness.

**Spec:** none -- this is an investigation, not a designed feature. This
plan itself is the specification of the investigation method.

## Global Constraints

- Do this work in an isolated git worktree/branch, not directly on
  `engines-2d-sweep` -- the debug build config and any exploratory
  logging are throwaway and must not pollute the main sweep branch.
  Only a confirmed *fix* (a separate, later plan) gets merged back.
- Do not touch the production ROMM/Unraid deployment for this
  investigation. Use the local `test-page/` harness
  (`python3 test-page/serve-coop-coep.py`, drop the ROM in `test-page/`,
  point `EJS_gameUrl` in `test-page/index.html` at it) for every test
  cycle in this plan.
- Use `griffon` as the test engine: smallest source (18 files, ~10K
  lines, vs. 25K-308K lines for the other 8 affected engines), an
  official freeware ROM already correctly packaged and sitting in
  `/mnt/unraid/emulation/scummvm/non-running/Griffon Legend.zip`, and a
  already-confirmed reliable, fast repro of this exact crash.
- Known context ruling out one plausible-sounding theory already: `griffon`'s
  own font rendering (`engines/griffon/resources.cpp`'s `loadFont()`)
  loads its on-screen text from the game's own `art/font.bmp` asset --
  it never touches `fonts.dat` or `graphics/fonts/ttf.cpp` at all. Since
  `griffon` still needs `fonts.dat` to pass ScummVM's own startup check
  and still crashes once it's supplied, the actual buggy code must be in
  some **generic, engine-independent** startup/GUI codepath that
  consumes `fonts.dat` regardless of whether the specific engine's own
  gameplay code ever calls a font-rendering function -- not
  engine-specific code, and (per `buried`'s working counter-example)
  probably not `graphics/fonts/ttf.cpp`'s direct TTF path either, since
  `buried` uses that exact path successfully with the same file.
- Crash timing varies by engine/dump -- confirmed via user testing on
  `toon`'s non-German dump (hangs on the screen *after* the ScummVM
  splash, not the splash itself) vs. the "typical" pattern of hanging at
  the splash. This is consistent with the trigger being "whenever this
  specific engine first needs to render text through the buggy
  codepath," not a fixed point in ScummVM's own startup sequence.
- The known crash signature (for reference, from `docs/GOTCHAS.md`):
  ```
  RuntimeError: memory access out of bounds
      at wasm-function[15670]:0xf50294
      at wasm-function[2124]:0x1cf60c
      at wasm-function[75474]:0x4bd58df
      at wasm-function[39904]:0x2dace62
      ... (MainLoop_runner)
  ```
  identical function indices and byte offsets were confirmed across
  multiple unrelated engines with no shared game-specific code.

---

### Task 1: Set up an isolated worktree for this investigation

**Files:** none (workspace setup only)

- [ ] **Step 1: Create the worktree**

Use the `superpowers:using-git-worktrees` skill to create an isolated
workspace off `engines-2d-sweep` (branch name suggestion:
`debug/fonts-oob-crash`). This keeps the throwaway debug build config
and exploratory logging completely separate from the sweep branch.

- [ ] **Step 2: Verify the worktree builds cleanly before changing anything**

```bash
bash build/build-core.sh
bash build/build-retroarch-core.sh
bash build/package-core.sh
```

Expected: succeeds, matching the current `engines-2d-sweep` state (this
just confirms the worktree is a working baseline before Task 2's changes).

---

### Task 2: Build a debug-info-enabled diagnostic core

**Files:**
- Create: `build/build-retroarch-core-debug.sh` (copy of
  `build/build-retroarch-core.sh` with debug flags added -- kept
  separate from the production script so this throwaway variant never
  accidentally becomes the default build path)

**Interfaces:**
- Consumes: the same `scummvm_libretro_emscripten.bc` Task 1 already
  confirmed builds cleanly.
- Produces: `retroarch/scummvm_libretro.wasm` /
  `scummvm_libretro.js` built with debug info and lower optimization,
  for accurate symbolication (overwrites the same output paths as the
  production script -- that's fine, this worktree is isolated).

- [ ] **Step 1: Create the debug build script**

Copy `build/build-retroarch-core.sh` to
`build/build-retroarch-core-debug.sh`. In the copy, change the
`EMCC_CFLAGS` line to add debug-info and drop optimization, so real
source-level symbolication is possible (an `-O3` build's inlining makes
stack traces much less reliable):

```bash
EMCC_CFLAGS="--pre-js ../build/midi-stub-pre.js --embed-file ../build/embed-staging/engine-data@/engine-data -g -gsource-map" emmake make -f Makefile.emulatorjs \
  LD=em++ \
  HAVE_7ZIP=1 HAVE_CHD=1 \
  HAVE_THREADS=1 PTHREAD_POOL_SIZE=4 \
  ASYNC=1 HAVE_OPENGLES3=1 \
  STACK_SIZE=16777216 INITIAL_HEAP=134217728 \
  TARGET=scummvm_libretro.js \
  -j"$(nproc)"
```

Note: `Makefile.emulatorjs`'s own link line hardcodes `-O3` at the end
(confirmed in the current build log) -- if `-g`/`-gsource-map` combined
with `-O3` doesn't produce a usable enough trace in Step 3 below (verify
by testing, don't assume), the fallback is editing
`retroarch/Makefile.emulatorjs` directly in this worktree to change that
specific `-O3` to `-O1` for this debug build only, then re-testing. Keep
that change local to this worktree; never touch the production
`Makefile.emulatorjs` line -- that's vendored source shared with the
regular build.

- [ ] **Step 2: Rebuild with the debug script**

```bash
bash build/build-retroarch-core-debug.sh
bash build/package-core.sh
```

Expected: builds successfully, produces a larger `.wasm` (debug info
included) than the production build.

- [ ] **Step 3: Verify debug info actually improves the stack trace**

This is the checkpoint for the `-O3` vs `-O1` fallback in Step 1. Deploy
to the local test harness (see Task 3) and reproduce the crash once
before continuing to Task 3 for real. If the resulting stack trace is
still just raw `wasm-function[N]` entries with no C++ symbol names or
file/line info, the flags in Step 1 aren't sufficient -- apply the `-O3`
to `-O1` fallback noted in Step 1 and rebuild before proceeding.

---

### Task 3: Reproduce the crash locally and capture a symbolicated stack trace

**Files:**
- Modify: `test-page/index.html` (point `EJS_gameUrl` at the griffon ROM)

**Interfaces:**
- Consumes: Task 2's debug-built core, and the existing griffon ROM at
  `/mnt/unraid/emulation/scummvm/non-running/Griffon Legend.zip`.
- Produces: a captured, symbolicated stack trace (saved to a file in
  this plan's scratch area, not committed) identifying the actual C++
  function where the crash occurs.

- [ ] **Step 1: Serve the local test harness**

```bash
bash test-page/download-emulatorjs.sh   # only if not already present
cp "/mnt/unraid/emulation/scummvm/non-running/Griffon Legend.zip" test-page/griffon.zip
python3 test-page/serve-coop-coep.py
```

- [ ] **Step 2: Point the test page at the griffon ROM**

Edit `test-page/index.html`'s `EJS_gameUrl` to `"griffon.zip"` (or
whatever relative path Step 1 used).

- [ ] **Step 3: Load it in a browser and capture the crash**

Navigate to the local test harness URL, let it boot. Griffon's known
crash point is either at the ScummVM splash or shortly after (per the
`toon` data point in this plan's Global Constraints, exact timing can
vary) -- let it run far enough to hit the crash.

Read the browser console (if using `mcp__claude-in-chrome__read_console_messages`,
filter with a pattern like `RuntimeError|wasm-function|memory access`).
Save the full stack trace text to a file for reference in Task 4 (this
plan's own scratch directory, e.g.
`docs/superpowers/plans/scratch/2026-09-02-oob-crash/stack-trace-1.txt` --
create that directory if needed).

- [ ] **Step 4: Identify the crashing function**

With debug info, the trace should now show real function names (possibly
still with some inlining-related gaps, but recognizable ScummVM
function/file names) instead of only `wasm-function[N]:0xADDR`. Note
which file/function it points to. Cross-reference against the
suspects already identified in this plan's Global Constraints
(`graphics/fonts/` non-TTF readers -- `bdf.cpp`, `consolefont.cpp`,
`amigafont.cpp`, `winfont.cpp`, `dosfont.cpp`, `macfont.cpp`,
`freetype.cpp`, `newfont.cpp`/`newfont_big.cpp` -- or shared GUI code in
`gui/` that initializes a fallback font at startup for every engine
regardless of its own font usage).

---

### Task 4: Add targeted diagnostic logging in the identified function

**Files:**
- Modify: whichever file Task 3 Step 4 identified (cannot be named more
  precisely until that step completes -- this is genuinely investigative
  work, not a predetermined change)

**Interfaces:**
- Consumes: Task 3's finding of the specific crashing function.
- Produces: console log output (via `retro_log_cb(RETRO_LOG_DEBUG, ...)`,
  matching this codebase's existing logging convention -- see
  `libretro-core.cpp`'s existing calls for the exact signature) tracing
  the function's actual runtime values immediately before the crash.

- [ ] **Step 1: Read the identified function completely**

Before adding any logging, read the whole function (and its immediate
callers/callees if short) to form a specific hypothesis about what's
likely out of bounds -- an array index derived from font/glyph data, a
buffer size assumption, a pointer arithmetic step, etc. Do not add
logging blindly across the whole file; target the specific operations
that plausibly explain an out-of-bounds *memory* access (not a logical
error) -- array subscripts, pointer offsets, `memcpy`/`memmove`-style
calls, buffer length calculations.

- [ ] **Step 2: Add logging immediately before each suspect operation**

Example pattern (adapt to the actual variables in the real function):

```cpp
retro_log_cb(RETRO_LOG_DEBUG, "[fonts-oob-debug] about to index array at %d (size=%d)\n", idx, arraySize);
```

Log every value that feeds into a pointer/array computation on the
suspect line(s), immediately before the crash would occur, so the last
log line before the crash pinpoints the exact operation and its
runtime values.

- [ ] **Step 3: Rebuild (debug config), retest, capture new output**

```bash
bash build/build-retroarch-core-debug.sh
bash build/package-core.sh
```

Repeat Task 3 Steps 1-3 (test harness already set up, just needs the
rebuilt core). Save this run's console output alongside Task 3's stack
trace file.

- [ ] **Step 4: Analyze**

The last `[fonts-oob-debug]` log line before the `RuntimeError` should
show the exact operation and its runtime values (e.g. an index that's
clearly beyond the logged array size). If the crash happens before any
added log line fires, the fault is earlier than hypothesized -- move the
logging earlier and repeat Steps 2-3. If multiple candidate operations
were logged and none show an obviously invalid value, broaden the
hypothesis (re-read Task 3's stack trace for the next frame up/down) and
repeat.

---

### Task 5: Checkpoint -- confirm root cause, decide next steps

**Files:** none (analysis/decision task)

- [ ] **Step 1: Write up the confirmed root cause**

Once Task 4 pinpoints the exact faulting operation, write a summary:
what function, what operation, what invalid value, and why it's invalid
(e.g. "an index computed from `fonts.dat`'s own glyph count field is
read without validating it against the actual bitmap array's allocated
size"). This becomes the basis for a separate, follow-up plan to
implement and verify the actual fix -- not part of this plan.

- [ ] **Step 2: Report back and stop**

This plan's job ends at a confirmed root cause. Report the finding, and
do not proceed to implementing a fix in this same session/worktree
without the user's go-ahead on the fix approach -- per the standing
"research before proposing fixes" practice, the fix itself deserves its
own short design discussion once the actual bug is known, since the
right fix (bounds-check and skip vs. bounds-check and use a fallback vs.
fixing the value's computation upstream) depends entirely on what Task 4
finds.

- [ ] **Step 3: Clean up worktree state**

Do not merge the debug build script or diagnostic logging into
`engines-2d-sweep`. Once the root cause is confirmed and reported, use
`superpowers:finishing-a-development-branch` to decide what happens to
this investigation worktree (likely: keep it as-is until the follow-up
fix plan is ready to use it, or discard once the fix is implemented
fresh on a clean branch -- user's call at that point).
