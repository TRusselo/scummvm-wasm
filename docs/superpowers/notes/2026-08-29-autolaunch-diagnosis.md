# Auto-launch gap diagnosis

## Root cause: confirmed

The game does not fail to be detected. `retro_load_game()` is called, correctly
receives `/00.LFL` as the content path, and successfully auto-detects Zak
McKracken via `testGame(parent_dir, true)` (the `TEST_GAME_OK_ID_AUTODETECTED`
branch). It then calls `retro_init_emu_thread()` to start ScummVM's actual
engine loop — **and that call fails**, causing `retro_load_game()` to return
`false`, which is why RetroArch falls back to its contentless main menu
instead of starting the game.

Confirmed via RetroArch's own verbose logging (`EJS_DEBUG_XX = true`, which
adds `-v` to the core's argv), which surfaced this exact log line — the
literal string the wrapper's own `retro_load_game()` emits on this failure
path:

```
[libretro ERROR] [scummvm] Failed to initialize emulation thread!
```

## Why: a threading-model mismatch between the core and the RetroArch build

- The core object (`scummvm_libretro_emscripten.bc`, built in Task 2) was
  compiled with the emscripten platform's `USE_LIBCO=0` setting (fixed by
  `scummvm-core/backends/platform/libretro/Makefile`'s `emscripten` platform
  block) — this routes the build through `rthreads.o` (libretro-common's
  real-pthread-based coroutine implementation), not the fiber-based `libco`
  used on desktop platforms. The core expects genuine pthread support to
  exist at runtime for whatever `retro_init_emu_thread()` does (almost
  certainly: spawning ScummVM's own engine loop on a separate thread from
  RetroArch's frontend loop).
- Task 3's RetroArch link step built with `HAVE_THREADS=0` (matching the
  design-time spike's default, non-threaded build) — meaning the RetroArch
  WASM runtime has no actual Web Worker/pthread support compiled in at all.
- Result: the core's thread-init call has nothing to actually spawn a thread
  onto, and fails.

## Path/extension hypotheses: ruled out

Two hypotheses from the original brief were checked and ruled out as the
cause (though both were reasonable things to check first):

- **Wrong `game->path` reaching the core**: traced precisely.
  `emulator.js`'s `startGame()` calls
  `this.Module.callMain(["/" + this.fileName])` — i.e. it runs RetroArch's
  own `main()` with the content path as a CLI positional argument (like
  running `retroarch /00.LFL` from a terminal), not a direct
  `retro_load_game()` API call. `this.fileName` resolved to `"00.LFL"` (the
  first extracted zip entry, since no core report JSON gives EmulatorJS an
  extension to prefer — see below). The resulting path, `/00.LFL`, is a real
  file EmulatorJS's generic zip-extraction (Task 3/4's earlier finding: it
  writes every zip entry to `/<filename>` at the FS root) had already placed
  correctly, in the same `Module.FS` instance the core reads from (confirmed
  directly via `EJS_emulator.gameManager.FS.readdir("/")` in the live page,
  which listed all of Zak's `.LFL`/`.EXE` files). This path is exactly what
  the wrapper's directory-autodetect logic is designed to handle, and it did.
- **Missing core-report-JSON metadata gating content loading**: the
  "Could not fetch core report JSON!" warning is real and present, but
  tracing `retroarch.c`'s CLI argument parsing (`retroarch_parse_input_and_config`,
  `runloop_path_set_basename(argv[optind])`) found no extension-matching gate
  on a directly-specified CLI content path — that check exists for the GUI
  file browser (explaining the earlier "empty `/` in Load Content" finding,
  via `valid_extensions = "scummvm"`) but not for content passed via argv.
  The verbose log confirms this: detection ran and succeeded, so nothing
  blocked the content from reaching the core.

## Which Task 6 candidate applies

**Neither Candidate A nor Candidate B from the plan.** Both were written
before this root cause was known. The actual fix is a new candidate:

**Candidate C — rebuild with real thread support.** Task 3's
`build-retroarch-core.sh` needs `HAVE_THREADS=1` (with a non-zero
`PTHREAD_POOL_SIZE`, matching `build-emulatorjs.sh`'s own `--threads` flag
behavior) instead of `HAVE_THREADS=0`. This has a real, non-optional
deployment consequence beyond just a build flag: **Emscripten pthreads
require the page to be served with cross-origin-isolation headers**
(`Cross-Origin-Opener-Policy: same-origin` and
`Cross-Origin-Embedder-Policy: require-corp`) for `SharedArrayBuffer` to be
available — without them, thread creation fails in the browser regardless of
build flags. Python's plain `http.server` does not send these headers, so
Task 6 will need either a small custom Python server subclass that adds
them, or an equivalent alternative, for local testing.

This was a genuinely unknown risk named (but not resolved) in the design
spec's "Approach" section — this diagnosis resolves it: the risk is real,
and confirmed to require the COOP/COEP-serving fix above, not just a
recompile.

## Post-fix status (after Task 6's rebuild)

Task 6 applied the mechanical fix above (`HAVE_THREADS=1`,
`PTHREAD_POOL_SIZE=4` in `build/build-retroarch-core.sh`; matching pthread
compile flags on the ScummVM core side in `build/build-core.sh`; the
COOP/COEP-serving test server). This fix was verified correct and
necessary: reverting it and rebuilding reproduces the exact wasm-ld
feature-mismatch error it fixes (`--shared-memory is disallowed by
pngerror.o because it was not compiled with 'atomics' or 'bulk-memory'
features`), confirming the fix addresses a real, load-bearing build
requirement, not a red herring.

**Real progress**: with the fix applied, the ScummVM splash logo now
renders in the browser. Thread initialization no longer fails outright the
way it did before this fix (no more "Failed to initialize emulation
thread!" abort) — this is a genuine step forward from the pre-fix state.

**But**: execution then crashes with `RuntimeError: memory access out of
bounds`, reproduced across multiple runs with varying failure points (the
crash does not occur at a single deterministic instruction/offset each
time).

**What is actually known — precisely, and no further**: this crash was
observed in exactly one configuration:

- `HAVE_THREADS=1`
- `ASYNC=1` (forced on whenever `HAVE_AL=1`, which is
  `Makefile.emulatorjs`'s default — see its `else ifeq ($(HAVE_AL), 1) /
  override ASYNC = 1` block)
- `ASSERTIONS=0` (the default; `Makefile.emulatorjs` only turns
  `ASSERTIONS` on for its unrelated `same_cdi` target)
- `HAVE_WASMFS=0` (the default)
- `PROXY_TO_PTHREAD=0` (the default)
- the ScummVM tree was compiled *without* an explicit C++ standard override
  reaching the compiler — `build/build-core.sh` was passing `CFLAGS=`/
  `CXXFLAGS=` as GNU Make command-line variables, which silently discarded
  the `-std=c++11` that
  `scummvm-core/backends/platform/libretro/Makefile`'s own `emscripten`
  platform block adds via `CXXFLAGS +=`. This has since been fixed (see
  Fix 4 in the final-review fix wave — the build now uses `EMCC_CFLAGS`
  instead, which appends rather than replaces, so `-std=c++11` reaches the
  compiler as originally intended). The crash described here was observed
  *before* that fix, so this variable changed too between diagnosis and
  today; it is listed for completeness, not because it's implicated.

Given all of the above, **it is not yet established that "the threading
model doesn't work."** That conclusion was reached prematurely in earlier
notes on this branch. The crash is equally consistent with a cheap
configuration problem (e.g. an asyncify stack overflow — Asyncify's stack
is hardcoded to a mere 8192 bytes via `ASYNCIFY_STACK_SIZE=8192` in
`Makefile.emulatorjs`, and `ASYNC=1`'s full-asyncify transform is exactly
the kind of thing that overflows a stack that small) as it is with a
genuine C++ concurrency bug in the wrapper's own code.

**Concrete next diagnostic steps, in order of cheapness:**

1. Rebuild with `EMCC_CFLAGS="-sASSERTIONS=1"` set for the link step. If
   the generic `RuntimeError: memory access out of bounds` turns into a
   clear `Asyncify stack overflow` message, the fix is very likely just
   raising `ASYNCIFY_STACK_SIZE` (currently hardcoded to 8192 in
   `retroarch/Makefile.emulatorjs`), not a wrapper rewrite.
2. If that's inconclusive, try `HAVE_WASMFS=1` — `Makefile.emulatorjs`'s
   own comment above that flag says it is the "recommended FS when using
   HAVE_THREADS," and this build has never tried it (it shipped with the
   default `HAVE_WASMFS=0`).
3. If still inconclusive, try `PROXY_TO_PTHREAD=1` (also never tried on
   this branch).

Only if all three of these are tried and the crash persists unchanged
does this genuinely indicate a deeper concurrency bug in the wrapper's own
code — at that point, and not before, the spec's named "pivot to a
clean-room wrapper" option would be earned. That conclusion is not yet
earned as of this writing.

## Follow-up (2026-08-30, second pass): worker error identified — `midiOutputMap is not defined`

The `window.Worker`-patching debug script (temporarily added to
`test-page/index.html`, not committed) did capture the error on this run —
it was just buried under an enormous flood of benign
`MainLoop_runner`/`requestAnimationFrame` console spam, which is why it
looked empty at a glance:

```
[WORKER-DEBUG] message=Uncaught ReferenceError: midiOutputMap is not defined
  filename=blob:http://localhost:8934/065bdffa-86e4-4624-9c23-4e8a5e4b9c6e
  lineno=3 colno=343558
```

with a stack trace through `_midiGetOutputNames` → `imports.<computed>` →
compiled wasm → `___pthread_create_js` → `spawnThread` — i.e. this fires
inside a **newly spawned pthread worker**, during what looks like a MIDI
output-device enumeration call ScummVM's sound driver init performs at
startup.

**Root cause (high confidence, not yet proven by source inspection):**
Emscripten's Web MIDI JS library (`library_webmidi.js`) backs
`_midiGetOutputNames` with a `midiOutputMap` populated asynchronously via
`navigator.requestMIDIAccess()`, which only resolves/exists on the main
thread (`window`) — the Web MIDI API is not exposed inside Worker global
scope in browsers. Because `HAVE_THREADS=1` now runs ScummVM's engine loop
on a spawned pthread (not the main thread), the worker's copy of the
compiled JS never had `midiOutputMap` initialized, so the first call to
enumerate MIDI outputs throws this exact `ReferenceError`.

**Compounding symptom:** immediately after this uncaught exception, the
same run hits *another* stack overflow —
`Aborted(stack overflow (Attempt to set SP to 0x0027e180, with stack
limits [0x0027e2d0 - 0x0127e2d0]))` — despite the stack limits shown being
exactly 16MB apart, i.e. the `STACK_SIZE=16777216` fix from the first
follow-up **is** in effect and is not itself insufficient. This second
overflow is most likely the asyncify/exception-unwind machinery re-entering
badly after the uncaught JS exception from `_midiGetOutputNames` corrupts
the call chain, not a fresh instance of the original stack-size problem.

**Not yet confirmed, but the clear next step:** find what in ScummVM's
libretro/emscripten audio backend triggers MIDI device enumeration at
startup and disable it (or make it a no-op on the emscripten platform),
since ScummVM's SCUMM engine doesn't need real MIDI hardware output in this
build. Likely candidates: a `USE_FLUIDSYNTH`/MIDI-driver auto-detect build
flag in `scummvm-core/backends/platform/libretro/Makefile`'s `emscripten`
block, or a runtime check in the sound driver init that should skip device
probing when no MIDI output is configured. This has not yet been located
in source — that is the next concrete action, not a rebuild-and-hope guess.

The debug patch in `test-page/index.html` (the `window.Worker`
interception script) and the temporary `EJS_gameUrl = "zak.scm"` /
`EJS_DEBUG_XX = true` values remain uncommitted and must be reverted before
any future commit, per the established pattern for this file.

## Follow-up (2026-08-30, third pass): midiOutputMap fixed and verified; a second, different stack overflow remains

**Fix applied and verified via direct browser console reads** (using
`mcp__claude-in-chrome__read_console_messages`, not manual pasting — see
`[[feedback_read_console_directly]]`): added `build/midi-stub-pre.js`
(`var midiOutputMap = new Map();`) via `--pre-js` in
`build/build-retroarch-core.sh`'s `EMCC_CFLAGS`. Root cause was
`scummvm-core/backends/midi/webmidi.cpp`'s `EM_JS`/`EM_ASYNC_JS` blocks
referencing a bare `midiOutputMap` global that only ScummVM's own
standalone-Emscripten shell (`scummvm-core/dists/emscripten/custom_shell-pre.js`,
not used by this RetroArch-based build) ever declares — and
`scummvm-core/backends/module.mk` compiles `midi/webmidi.o` in
unconditionally for any `EMSCRIPTEN` build, with no gating flag. Confirmed
across two fresh reloads: the `Uncaught ReferenceError: midiOutputMap is
not defined` and the `_midiGetOutputNames`-triggered stack overflow that
followed it in the second follow-up are both gone.

**A second, different stack overflow remains, now isolated as the sole
blocker.** With midiOutputMap fixed, the splash screen renders and then
stalls indefinitely (~15-20s and counting, no further progress) exactly as
before -- but this time, reading the console directly (not pasting) shows
the *only* error present is a fresh `RuntimeError: Aborted(stack overflow
...)`, with limits again exactly 16MB apart (`0x0027e2d0 - 0x0127e2d0`,
matching `STACK_SIZE=16777216`) but appearing roughly 15-20 seconds after
load, not immediately. Its stack trace is materially different from the
Task-6-era overflow this note already documented as fixed: it runs through
`MainLoop_runner` -> `runIter` -> `callUserCallback` -> `iterFunc` ->
`__asyncify_wrapper_13048` -> `$dynCall_v` -> `$func543` ->
`___handle_stack_overflow` -- i.e. **Emscripten's main-loop scheduler
(`emscripten_set_main_loop`, driven by `requestAnimationFrame` on the main
thread)**, not a one-off pthread-init call. The delayed onset (consistent
~15-20s, not instant) is the key new fact: a single too-deep call would
overflow on its very first invocation, not after N successful frames. This
is much more consistent with **stack space never being reclaimed between
per-frame asyncify-wrapped calls** -- i.e. the per-frame call chain
appears to accumulate stack depth across frames rather than fully
unwinding each `MainLoop_runner` tick, until ~15-20 seconds' worth of
frames finally exceeds even a 16MB budget. Raising `STACK_SIZE` further
would likely only delay the same failure, not fix it, if this theory is
correct.

**This has not yet been confirmed against source** -- it is the leading
hypothesis from the trace shape and timing alone, not a proven root cause.
**Concrete next steps, cheapest first:**

1. Re-run with `EMCC_CFLAGS` also including `-sASYNCIFY_STACK_SIZE=<much
   larger value than the hardcoded 8192>` (see `Makefile.emulatorjs`'s
   hardcoded `ASYNCIFY_STACK_SIZE=8192`) -- if growing *this* value (not
   `STACK_SIZE`) delays or removes the overflow, the leak is in Asyncify's
   own state-save stack specifically, which is a different, smaller,
   separately-configured region from the native `STACK_SIZE` this note has
   been tuning so far.
2. If that doesn't help, instrument (or find existing) periodic stack-depth
   logging across successive `MainLoop_runner` ticks (e.g. via
   `-sSTACK_OVERFLOW_CHECK=2`'s own stack-pointer reporting, called once
   per frame) to directly confirm or refute "stack depth grows frame over
   frame" versus "a single frame's calls are simply deep."
3. Only after 1-2 are tried does escalating to a source-level audit of
   ScummVM's/RetroArch's main-loop callback under `ASYNC=1` (looking for a
   callback that re-enters itself, or an asyncify unwind/rewind pairing
   that leaves state behind) become the next cheapest step -- not before.

## Resolution (2026-08-30, fifth pass): the MIDI fix was incomplete, and that was the actual root cause all along

The "fourth pass" conclusion above -- that the `MainLoop_runner` stack
overflow was independent of the WebMIDI bugs -- **was wrong**, and the
error was in the experiment, not the reasoning. That test compared against
a build using only `midi-stub-pre.js` (fixing the `midiOutputMap`
`ReferenceError`), which left the *second* MIDI bug
(`Module.setValue is not a function`, see the "third-and-a-half pass"
section above) fully intact and still throwing uncaught mid-execution.
That uncaught exception -- inside `_midiGetOutputNames`, called from
`WebMIDIMusicPlugin::getDevices()`, whose `while (strcmp(*iter, "") != 0)`
loop has no bounds check on the pointer it gets back -- was still corrupting
engine state on every run of that "refutation." The overflow persisting in
that test was consistent with the corruption theory the whole time; it was
never actually tested with a truly MIDI-free build.

**Also discovered along the way (a real methodology trap, not a build
bug):** after editing `backends/module.mk` to exclude `midi/webmidi.o`,
several rebuild-and-test cycles kept showing the exact same MIDI errors
despite the source change being correct and confirmed in place. The cause
turned out to be twofold:

1. Removing an object from `MODULE_OBJS` in `backends/module.mk` does not,
   by itself, invalidate a stale already-built `backends/libbackends.a` /
   `libtemp/libbackends.a` / the final `scummvm_libretro_emscripten.bc` --
   this build's dependency tracking did not reliably detect the change
   across incremental `make` runs. The fix was to explicitly `rm` the
   stale `.o`/`.a`/`.bc` files before rebuilding, then verify with `strings
   <artifact> | grep midiOutputMap` (expect 0) *before* spending a further
   rebuild cycle on the next link step -- checking the actual compiled
   output directly is far cheaper than another full rebuild-and-browser-test
   cycle, and should be standard practice before every retest going forward.
2. A separate, hand-written registration table
   (`base/plugins.cpp`'s `#ifdef EMSCRIPTEN / LINK_PLUGIN(WEBMIDI)`, using
   the `g_WEBMIDI_type` symbol `REGISTER_PLUGIN_STATIC` generates in
   `webmidi.cpp`) was not covered by the `module.mk` change at all and
   caused a hard link failure (`undefined symbol: g_WEBMIDI_type`) the
   first time the stale-archive problem above was actually fixed. This was
   also commented out. **Both edits are required** for a genuinely
   WebMIDI-free build: `backends/module.mk`'s `MODULE_OBJS` exclusion, and
   `base/plugins.cpp`'s `LINK_PLUGIN(WEBMIDI)` exclusion.
3. Separately, the `Bash` tool's `bash script.sh | tail -N` pattern
   silently swallows `script.sh`'s own exit code even when the script uses
   `set -euo pipefail` internally (the documented "pipe-swallowing exit
   code bug" from earlier in this project) -- this caused one rebuild
   failure to go unnoticed and `package-core.sh` to re-package stale
   artifacts. Always redirect to a log file and check the exit code
   explicitly (`... > log 2>&1; echo "EXIT_CODE=$?" >> log`) instead of
   piping through `tail` when the exit code matters.

**With both `module.mk` and `plugins.cpp` changes applied, verified via
`strings` on the actual linked `scummvm_libretro.js` (0 occurrences of
`midiOutputMap`/`_midiGetOutputNames`/`g_WEBMIDI_type` as live code -- one
harmless, unreferenced `var midiOutputMap = new Map();` remains from the
now-unnecessary-but-harmless `midi-stub-pre.js`), the game genuinely boots
end to end**: Zak McKracken's actual first game scene (the National
Inquisitor office) rendered correctly, and after a user click (required by
the browser's standard audio-autoplay policy -- not a bug in this build),
the game ran live with sound. The `MainLoop_runner` stack overflow this
note spent three follow-ups chasing as an "independent" problem does not
reproduce with the fully-fixed build; it was the MIDI corruption the whole
time.

**Mouse UX fix (same session):** the OS cursor stayed visible and
independently-moving alongside the in-game cursor during play (the in-game
cursor's direction/movement already worked correctly -- that's the
existing relative-mouse-delta libretro input pipeline functioning as
designed). Fixed by adding `EJS_defaultOptions = { lockMouse: "enabled" }`
to `test-page/index.html` -- EmulatorJS's documented mechanism for
defaulting its own menu settings (`loader.js` maps this directly to
`this.config.defaultOptions`, consumed by `changeSettingOption` at
startup). This engages the browser's Pointer Lock API on the first canvas
click, hiding the OS cursor and switching mouse events to
`movementX`/`movementY`-only, which is exactly the input model the
existing pipeline already consumes -- no new input-handling code needed.
Verified via `document.pointerLockElement === canvas` after a real click.

**Known, already-scoped-out limitation (not a regression):** EmulatorJS's
generic `GameManager.getState()` (used for its own save-state UI/auto-save
polling) throws/logs an error, because the SCUMM libretro core's
`_save_state_info` doesn't return the `|`-delimited success string
EmulatorJS expects. This is the generic-save-state mechanism the original
design brainstorming explicitly deferred in favor of ScummVM's own
built-in save-anytime/load-anytime system -- not a new bug, and does not
affect gameplay (video/audio/input all confirmed working). Left as-is;
revisit only if generic browser-side save states become an actual
requirement later.

**Remaining cleanup before this can be considered done:**
- Revert the temporary diagnostics in `test-page/index.html` (the
  `requestAnimationFrame`-wrapping `[RAF-DEBUG]` script, `EJS_gameUrl =
  "zak.scm"`, `EJS_DEBUG_XX = true`) -- not for commit, per the established
  pattern for this file.
- Commit the real fixes: `scummvm-core/backends/module.mk`,
  `scummvm-core/base/plugins.cpp`, `build/midi-stub-pre.js` (kept as
  harmless defense-in-depth), `build/build-retroarch-core.sh`'s `--pre-js`
  reference, and `test-page/serve-coop-coep.py`'s new `Cache-Control:
  no-store` header (needed after repeated same-session rebuilds showed
  browsers can otherwise serve stale `.data`/`.wasm` on a plain reload).
- Validate the remaining 5 target games (Maniac Mansion, Loom, Indiana
  Jones and the Last Crusade, Indiana Jones and the Fate of Atlantis, Day
  of the Tentacle) against the spec's original checklist now that the
  underlying engine boots correctly.

The debug artifacts in `test-page/index.html` remain uncommitted, per the
established pattern; they were not needed for this pass since the browser
console tool surfaced the relevant errors directly.

## Follow-up (2026-08-30, third-and-a-half pass): a second MIDI bug found, and the real fix

An unfiltered console read (not `onlyErrors`-filtered -- a gap in the
previous pass's methodology, corrected here per
`[[feedback_read_console_directly]]`) surfaced a **second**, chronologically
earlier bug in the same `_midiGetOutputNames` EM_JS block that the
midi-stub-pre.js fix did not address:

```
Uncaught TypeError: Module.setValue is not a function
    at ... _midiGetOutputNames ...
```

This build's `EXPORTED_RUNTIME_METHODS` list includes `getValue` but not
`setValue`; `_midiGetOutputNames` (line ~164 of
`scummvm-core/backends/midi/webmidi.cpp`) calls `Module.setValue(...)`
directly. The `midiOutputMap` stub let execution reach this *second*,
independent landmine in the same function rather than fixing the function.

Patching individual missing JS exports one at a time as they surface is a
losing game -- there is no guarantee a third one isn't waiting past this
one. **The durable fix: stop compiling the WebMIDI plugin into this build
at all**, by removing `midi/webmidi.o` from the unconditional `ifdef
EMSCRIPTEN` block in `scummvm-core/backends/module.mk`. Real MIDI hardware
output was never a goal for the SCUMM engine targets this build ships;
ScummVM's other built-in music drivers (AdLib/MT-32 emulation etc.) are
completely unaffected by this plugin's absence. `build/midi-stub-pre.js`
and its `--pre-js` reference in `build/build-retroarch-core.sh` are left in
place as harmless defense-in-depth (in case anything else ever references
the bare global), but the actual fix is the exclusion in `module.mk`.

**Rebuilt both the ScummVM core (`build/build-core.sh`) and the RetroArch
link (`build/build-retroarch-core.sh`), repackaged, and retested with a
fully unfiltered console read.** Confirmed: both MIDI errors (the
`ReferenceError` and the `TypeError`) are gone -- not suppressed, actually
eliminated, since the function that threw them is no longer linked in at
all.

**Important negative result this also produced:** before this fix, it was
a live hypothesis that the MIDI plugin's uncaught exception mid-execution
returns a garbage/`undefined`-derived pointer to
`WebMIDIMusicPlugin::getDevices()`'s C++ caller, whose
`while (strcmp(*iter, "") != 0)` loop has no bounds check on that pointer
-- and that this could plausibly corrupt engine state badly enough to
manifest, later and seemingly unrelated, as the `MainLoop_runner` stack
overflow documented below. **This is now refuted by direct test**: with
the WebMIDI plugin entirely removed (both MIDI bugs gone), the exact same
stack overflow still occurs, byte-for-byte identical (same stack limits
`0x0027e2d0 - 0x0127e2d0`, same call chain through `MainLoop_runner`). The
two problems are independent; fixing MIDI does not touch the overflow.
That said, this refutation is exactly why chasing the earliest error in
the log first was the right call here, not a wasted step -- it closed off
a real, plausible causal link with actual evidence instead of leaving it
as an open assumption while tuning the downstream symptom.

## Follow-up (2026-08-30, fourth pass): step 1 tried and refuted

Rebuilt with `EMCC_CFLAGS` also including `-sASYNCIFY_STACK_SIZE=1048576`
(128x the hardcoded default of 8192) and retested via direct console reads.
**Result: no change whatsoever.** The exact same `RuntimeError: Aborted
(stack overflow...)` recurs, with the *exact same* reported stack limits
(`0x0027e2d0 - 0x0127e2d0`, still precisely 16MB apart, matching
`STACK_SIZE=16777216` -- not the asyncify stack size at all) and the
identical call stack through `MainLoop_runner`. This cleanly rules out the
Asyncify-bookkeeping-stack theory from the previous follow-up's step 1: the
overflow is unambiguously in the **native** stack region, not Asyncify's
separate, much smaller unwind/rewind stack. Step 1 from the prior
follow-up is done and negative -- move directly to step 2 (per-frame
stack-depth instrumentation to confirm/refute "depth grows frame over
frame" vs. "a single frame's calls are simply too deep") or step 3 (source
audit of the main-loop callback under `ASYNC=1`) next, not further
Asyncify-specific tuning.

## Follow-up (2026-08-30): diagnostic step 1 run — real stack overflow found and fixed

Step 1 above was run, in two passes:

**Pass A — `EMCC_CFLAGS="-sASSERTIONS=1"` alone.** Rebuilt and reloaded
against a real game (`zak.scm`). Result: inconclusive as originally
worried — the crash was still a generic `RuntimeError: memory access out
of bounds`, not a specific Asyncify message. Plain `ASSERTIONS=1` does not
add the specific stack-instrumentation needed to distinguish an Asyncify
stack overflow from other memory errors; it needed to be paired with the
same flags `Makefile.emulatorjs`'s own `DEBUG=1` block uses.

**Pass B — `EMCC_CFLAGS="-sASSERTIONS=1 -sSAFE_HEAP=2 -sSTACK_OVERFLOW_CHECK=2"`.**
This surfaced a precise, actionable error:

```
RuntimeError: Aborted(stack overflow (Attempt to set SP to 0x0027ddd0,
with stack limits [0x0027e2d0 - 0x0067e2d0]). If you require more stack
space build with -sSTACK_SIZE=<bytes>)
```

The stack limits shown are exactly 4,194,304 bytes (4MB) apart — matching
this build's `STACK_SIZE=4194304` setting precisely. **This is a genuine,
ordinary stack overflow, not an Asyncify-specific one and not a data
race.** ScummVM's own call depth on this thread simply exceeds a 4MB
stack under this build configuration.

**Fix applied and verified**: rebuilt with `STACK_SIZE=16777216` (16MB,
still passed as a normal `Makefile.emulatorjs` variable, not a new
mechanism). Reloaded against the same real game: **no crash**. The
`RuntimeError: memory access out of bounds` (and the more specific stack
overflow message from Pass B) is gone entirely at 16MB.

**This resolves the open question from above.** The crash was the cheap
configuration problem, not a wrapper-level concurrency bug. The spec's
"pivot to a clean-room wrapper" option is **not warranted** by this
evidence — a simple `STACK_SIZE` increase in
`build/build-retroarch-core.sh` is the actual fix (not yet committed as of
this writing; confirmed working via a manual rebuild, not yet folded into
the build scripts).

**New, separate, not-yet-diagnosed symptom**: with the crash gone, the
ScummVM splash screen renders and then **the page stalls indefinitely**
(20+ seconds observed, no further progress, no new crash) rather than
proceeding into the game or ScummVM's own Launcher. A `worker.onerror`
`ErrorEvent` appears in the console on every threaded run so far,
including this successful-past-the-crash one, but its actual message
content was never captured (the console tooling used only surfaced the
event's type, not its `.message`/`.filename`/`.lineno` properties) — it
has not been established whether this error is the cause of the stall or
an unrelated, non-fatal side effect. This is genuinely new territory, not
covered by this doc's earlier diagnosis, and is the next thing to
investigate — likely by extracting the actual `ErrorEvent` properties
(e.g. via `javascript_tool` reading `event.message`/`event.error` at the
moment it fires, which requires attaching a listener before reload rather
than reading console output after the fact) rather than by guessing
further from output already captured.
