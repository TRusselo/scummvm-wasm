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
