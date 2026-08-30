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
