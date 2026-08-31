# Gotchas

Everything in this file was learned the hard way -- by hitting the actual
failure, misdiagnosing it at least once, and eventually finding the real
cause. If you're extending this project and something breaks in a way
that looks familiar, check here before re-deriving the answer from
scratch. Each entry names the actual file/flag involved, not just the
symptom, so you can grep for it.

The full chronological investigation (including the false starts) lives
in `docs/superpowers/notes/2026-08-29-autolaunch-diagnosis.md`, if you
want the "how we figured this out" narrative rather than just the
conclusion.

## Build flags and linking

### `LD=em++`, not the default `emcc`

`retroarch/Makefile.emulatorjs`'s default link driver is `emcc`, which
does not link `libc++abi`. ScummVM's C++ code uses RTTI, and without
`libc++abi` the link fails with `undefined symbol: vtable for
__cxxabiv1::__si_class_type_info`. `build/build-retroarch-core.sh` passes
`LD=em++` explicitly. If you ever see that exact undefined-symbol error,
this is why.

### Passing extra compiler flags: use `EMCC_CFLAGS`, never `CFLAGS=`/`CXXFLAGS=` on the make command line

`scummvm-core/backends/platform/libretro/Makefile`'s `emscripten`
platform block appends its own required flags via `CXXFLAGS += -std=c++11`
(plus warning suppressions). GNU Make **command-line variable
assignments** (`make CXXFLAGS=...`) override *all* in-makefile
assignments to that variable, including `+=` accumulator lines -- so
`make CXXFLAGS="-pthread"` silently discards `-std=c++11` too, and the
whole tree compiles at Emscripten's default C++ standard instead. This is
not a hypothetical: it happened, and produced no error, just quietly
different (and eventually broken) behavior.

The fix: set the `EMCC_CFLAGS` **environment variable** instead of a make
command-line variable. Emscripten's own `emcc.py` driver reads
`EMCC_CFLAGS` directly and appends it to every compiler/linker invocation
unconditionally -- it *adds* to whatever CFLAGS/CXXFLAGS the Makefile
built up internally, rather than replacing them. Both `build-core.sh` and
`build-retroarch-core.sh` use this pattern:

```bash
EMCC_CFLAGS="-pthread -sSHARED_MEMORY" emmake make platform=emscripten LITE=1 ...
```

### Real pthreads require matching compile flags on *both* sides of the link

The ScummVM core is built with `USE_LIBCO=0` (a platform-Makefile default
for the `emscripten` target), which routes threading through
libretro-common's real-pthread-based `rthreads.o`, not the fiber-based
`libco` used elsewhere. That means:

- `build-core.sh` must compile with `-pthread -sSHARED_MEMORY` (via
  `EMCC_CFLAGS`, see above).
- `build-retroarch-core.sh`'s RetroArch link must use `HAVE_THREADS=1
  PTHREAD_POOL_SIZE=4` (not `HAVE_THREADS=0`, which is
  `Makefile.emulatorjs`'s own default).

Mismatch between these two produces a `wasm-ld` error at link time:
`--shared-memory is disallowed by <object>.o because it was not compiled
with 'atomics' or 'bulk-memory' features` -- which is actually a *good*
error, because it fails loudly at build time rather than at runtime.

### `HAVE_THREADS=1` requires cross-origin isolation at serve time

Real pthreads need `SharedArrayBuffer`, which browsers only expose on
pages served with `Cross-Origin-Opener-Policy: same-origin` and
`Cross-Origin-Embedder-Policy: require-corp`. Plain `python3 -m
http.server` doesn't send these. Use `test-page/serve-coop-coep.py`
(or add the equivalent headers to whatever you actually deploy with). If
`HAVE_THREADS=1` is correctly built but pthreads still silently fail to
spawn in the browser, this is the first thing to check -- `curl -sI` the
page and grep for `cross-origin`.

**⚠️ HTTPS (or `localhost`) IS ALSO REQUIRED -- sending the headers above
is not enough on its own.** Per spec, browsers only honor
`Cross-Origin-Opener-Policy`/`Cross-Origin-Embedder-Policy` on a
*"potentially trustworthy origin"* -- HTTPS, or the special-cased
`localhost`. Serve this core over plain HTTP to any other origin (a bare
LAN IP like `http://192.168.1.12:8787`, a non-`localhost` hostname over
HTTP, etc.) and the browser silently **ignores** both headers rather than
erroring on them. The failure mode is easy to miss because it doesn't look
like a networking problem:

- The browser console logs a real but easy-to-scroll-past warning: *"The
  Cross-Origin-Opener-Policy header has been ignored, because the URL's
  origin was untrustworthy... deliver the response using the HTTPS
  protocol. You can also use the 'localhost' origin instead."*
- The actual, load-bearing error appears later and looks unrelated at
  first glance: `Threads is set to true, but the SharedArrayBuffer
  function is not exposed.`
- Non-threaded cores on the exact same host/page continue to work fine
  (they never touch `SharedArrayBuffer`), which makes this look like a
  core-specific bug rather than a page-level one -- confirmed during this
  project's own ROMM integration testing: `dosbox_pure` (also
  `HAVE_THREADS=1`) fails identically on the same plain-HTTP origin scummvm
  fails on, while every non-threaded core on that same ROMM instance works.

**Practical takeaway:** any real deployment of this core (or any other
`HAVE_THREADS=1` EmulatorJS core) needs either a real TLS certificate in
front of it (a reverse proxy like Caddy/nginx/Traefik/SWAG with
Let's Encrypt, etc.) or must only ever be accessed as `localhost` -- a bare
LAN IP or internal hostname over plain HTTP will never work no matter how
correctly the COOP/COEP headers are configured server-side. This is not
something fixable in this project's own code -- it's a browser security
policy on the client side. See the "Access via HTTPS" step in
[README.md](../README.md)'s Known Limitations if you're deploying this
somewhere other than the local `test-page/` harness (which sidesteps this
entirely by using `localhost`).

### Native stack size: 4MB (Emscripten's default) is not enough

ScummVM's own call depth exceeded a 4MB native stack under this specific
build (Emscripten default `STACK_SIZE`), producing
`RuntimeError: memory access out of bounds` with no further detail. This
looked, for a while, like a genuine architectural problem with the
threading model -- it wasn't. Rebuilding with
`EMCC_CFLAGS="-sASSERTIONS=1 -sSAFE_HEAP=2 -sSTACK_OVERFLOW_CHECK=2"`
turned the generic error into an exact one:

```
RuntimeError: Aborted(stack overflow (Attempt to set SP to 0x0027ddd0,
with stack limits [0x0027e2d0 - 0x0067e2d0]))
```

The stack limits shown are exactly 4MB apart, confirming it precisely.
Fix: `build/build-retroarch-core.sh` passes `STACK_SIZE=16777216` (16MB)
to the RetroArch link step -- a genuinely necessary, permanent fix, not a
diagnostic-only flag. (The three `ASSERTIONS`/`SAFE_HEAP`/
`STACK_OVERFLOW_CHECK` flags used to *find* this were removed again once
the fix landed -- they add real per-operation runtime overhead and were
only needed to get the specific error message.)

**Don't confuse this with `ASYNCIFY_STACK_SIZE`** (hardcoded to a tiny
8192 bytes in `Makefile.emulatorjs`) -- that's Emscripten's Asyncify
unwind/rewind bookkeeping stack, a completely separate, much smaller
region from the native call stack `STACK_SIZE` controls. Bumping
`ASYNCIFY_STACK_SIZE` was tried as a hypothesis for an unrelated crash
(see the WebMIDI section below) and had zero effect -- confirmed via the
exact same stack-limit numbers reappearing unchanged. If you're chasing a
stack-related crash, check which limits the error message actually
reports before changing either flag; they're not interchangeable.

## The WebMIDI plugin: exclude it, don't patch around it

This was the single biggest time sink in this project, and it's worth
understanding fully because the failure mode is deeply misleading: it
manifests as an apparently-unrelated stack overflow in the main render
loop, seconds after the actual root cause has already run and failed.

**Root cause:** `scummvm-core/backends/midi/webmidi.cpp` is compiled in
unconditionally for any Emscripten build (see
`scummvm-core/backends/module.mk`'s unconditional `ifdef EMSCRIPTEN`
block -- no gating flag). Its `EM_JS`/`EM_ASYNC_JS` blocks reference a
bare `midiOutputMap` JS global and call `Module.setValue(...)`. Both only
exist in ScummVM's own **standalone-Emscripten shell**
(`scummvm-core/dists/emscripten/custom_shell-pre.js`), which this
RetroArch/EmulatorJS-based libretro-core build never includes. The result:
ScummVM's sound driver enumerates MIDI outputs at engine startup, calls
into this plugin, and throws an **uncaught exception mid-execution**
(`Uncaught ReferenceError: midiOutputMap is not defined`, and after a
naive stub fix, `Uncaught TypeError: Module.setValue is not a function`
right behind it).

That uncaught exception happens inside
`WebMIDIMusicPlugin::getDevices()`'s C++ caller, whose
`while (strcmp(*iter, "") != 0)` loop has **no bounds check** on the
pointer the (now-aborted) JS call returns. This corrupts engine state
badly enough that, several seconds and many frames later, the *unrelated*
main render loop (`MainLoop_runner`) crashes with a generic
`RuntimeError: Aborted(stack overflow ...)`. Chasing that overflow
directly -- raising `STACK_SIZE` further, tuning `ASYNCIFY_STACK_SIZE`,
auditing the main-loop callback for asyncify re-entrancy bugs -- is a
dead end. **Fix the MIDI crash first; the overflow disappears on its
own.**

**The fix requires two separate edits, not one:**

1. `scummvm-core/backends/module.mk` -- remove `midi/webmidi.o` from the
   `ifdef EMSCRIPTEN` block's `MODULE_OBJS`.
2. `scummvm-core/base/plugins.cpp` -- comment out
   `#ifdef EMSCRIPTEN / LINK_PLUGIN(WEBMIDI) / #endif`.

Doing only (1) produces a **link failure**, not a quiet fix:
`wasm-ld: undefined symbol: g_WEBMIDI_type`. That symbol comes from
`REGISTER_PLUGIN_STATIC(WEBMIDI, ...)` in `webmidi.cpp`, referenced by a
separate, hand-written static-plugin registration table in
`base/plugins.cpp` that is **completely independent of the object-file
list** in `module.mk`. If you're excluding any other plugin the same way,
check `base/plugins.cpp` for a `LINK_PLUGIN(...)` reference to it too --
this is a general pattern in ScummVM's build, not specific to WebMIDI.

Real MIDI hardware output was never a goal for this project (these are
SCUMM adventure games using their own AdLib/MT-32/etc. music emulation);
excluding the plugin loses nothing.

## Save states: implementing retro_serialize()/retro_unserialize()

`scummvm-core/backends/platform/libretro/src/libretro-core.cpp`'s
`retro_serialize()`/`retro_serialize_size()`/`retro_unserialize()` used
to be permanent stubs (`return 0`/`return false`) -- meaning EmulatorJS's
own "Save State"/"Load State" toolbar buttons always failed, even though
ScummVM's own in-game Save/Load menu worked fine. Getting real save-state
support working required finding and fixing **three separate, unrelated
bugs** across two different codebases (ScummVM and RetroArch/EmulatorJS)
that all happened to produce the exact same user-visible symptom
("FAILED TO SAVE STATE"). If you're touching this code, read all three --
fixing only one or two still leaves it broken.

**The design**, for context on why the fix looks the way it does: ScummVM
has no API to serialize a running engine's state into a memory buffer --
`Engine::saveGameState()`/`loadGameState()` only know how to read/write
*named slots* via `SaveFileManager`. So the bridge works by driving a real
engine save/load into a reserved slot (see below for why 200, not some
rounder number), then copying that slot's save-file bytes to/from the
buffer libretro provides. This reuses the exact same save mechanism as
ScummVM's own in-game Save/Load menu, just made reachable through
EmulatorJS's own save-state UI instead of requiring the GMM.

A real complication this design has to handle: `retro_serialize()`/
`retro_unserialize()` run on what this backend calls the "main" thread,
but `g_engine` and everything reachable from it belong to the "emu
thread" -- a real pthread parked wherever the running engine last yielded
(see `libretro-threads.cpp`'s `retro_switch_to_emu_thread()`/
`retro_switch_to_main_thread()`). Calling `g_engine->saveGameState()`
directly from `retro_serialize()` would be touching engine state from the
wrong thread mid-execution. The fix sets a pending-operation flag and
drives the emu thread forward with `retro_switch_to_emu_thread()` (the
same primitive `retro_run()` already uses once per frame) until a hook
added to `OSystem_libretro::pollEvent()` -- which *does* run on the emu
thread -- sees the flag, does the actual save/load, and reports back.

### Bug 1 (ScummVM): `saveGameState()`/`loadGameState()` don't all complete synchronously

The generic `Engine::saveGameState()`/`loadGameState()` do their file I/O
synchronously. SCUMM's override doesn't: `ScummEngine::saveGameState()`
just calls `requestSave()`, which sets an internal flag
(`_saveLoadFlag`) for SCUMM's own main loop to act on later, in
`scummLoop_handleSaveLoad()`. Code that needs to know when a save/load
has *actually* finished -- not just been accepted -- has no generic way
to ask. Fixed by adding a new virtual, `Engine::isSaveOrLoadPending()`
(default `false`, since most engines' base implementation is already
synchronous), overridden in `ScummEngine` as `_saveLoadFlag != 0`. The
save-state bridge polls this after arming a request and waits for it to
clear before treating the request as finished.

### Bug 2 (ScummVM): `_saveLoadSlot` is a `byte` -- slot numbers above 255 silently wrap

The reserved slot originally used was 990 (chosen to sit comfortably
above SCUMM's UI-visible slot range of 0-99 and away from slot 100,
which `ScummEngine::requestLoad()` treats specially as a temporary-restart
slot). This is wrong: `ScummEngine::_saveLoadSlot` (`scumm.h`) is declared
`byte`. Assigning 990 to it silently truncates to `990 % 256 = 222` --
SCUMM saved to and loaded from slot 222 the entire time, while the
save-state bridge kept asking about slot 990. No error anywhere in the
chain indicates this; the save write genuinely succeeds, just under a
different slot than the one being asked about afterward. The tell was a
`ssdbg_list_saves()`-style directory listing (see the debugging note
below) showing a `zak.s222` file nobody had ever explicitly saved to.
Fixed by using slot 200 instead -- still outside the UI range, still not
100, and comfortably inside a byte.

### Bug 3 (ScummVM): SCUMM never overrides the generic `getSaveStateName()`

`Engine::getSaveStateName(slot)`'s generic default produces
`"<target>.<slot:03d>"` (e.g. `zak.990`). Nothing inside SCUMM's own
save/load code calls this generic virtual -- `ScummEngine::saveState()`/
`loadState()` use their own `makeSavegameName()`, which produces
`"<target>.s<slot:02d>"` (e.g. `zak.s200`, with an `s`/`c` prefix
character SCUMM has always used to distinguish real saves from
temporary/restart state). These two naming schemes silently disagree,
and nothing before this bridge ever needed to call the generic
`getSaveStateName()` on a SCUMM engine, so the mismatch was invisible.
The save-state bridge calls `saveGameState()` (writes to the *real*
`.s200` name), then calls the generic `getSaveStateName()` to figure out
what to `openForLoading()` (asks for the *wrong* `.990` name) -- a
`SaveFileManager` lookup that fails every time. Fixed by overriding
`ScummEngine::getSaveStateName()` to delegate to `makeSavegameName()`,
making the generic virtual finally agree with what SCUMM actually does.

### Bug 4 (RetroArch/EmulatorJS): `save_state_info()` returns a dangling stack pointer

Separate from all of the above, and the one that made the first three
much harder to diagnose: `retroarch/tasks/task_save.c`'s
`save_state_info()` (EmulatorJS-specific, `#ifdef EMULATORJS`) declared
its result buffer as a **local stack array** (`char state_data[300]`)
and returned a pointer to it. The JS side
(`emulatorjs.js`'s `saveStateInfo` -- `Module.cwrap(..., "string", [])`)
reads that pointer back via Emscripten's `UTF8ToString()`, and never
calls back into C to free anything, despite this function's own comment
claiming "This must be freed by the JavaScript side!" -- the comment
describes intent that was never actually implemented on either side.
Since the buffer is stack-local, it's invalid the instant the C function
returns; whatever JS reads back is just whatever happened to still be
sitting at that stack address. The observed result: **every single**
save-state attempt, success or failure, logged garbled, non-ASCII
console output (e.g. `֧_F4`) instead of the intended message, and
EmulatorJS's UI showed a generic "FAILED TO SAVE STATE" regardless of
what actually happened underneath. This bug alone was enough to make the
three ScummVM-side bugs above look identical from the browser console --
fixing it first (change `state_data` to `static`, so the buffer survives
after the function returns) is what turned that garbled text into an
actual, legible error message ("Error writing data", "Size is zero",
etc.), which was the only way to make any further progress diagnosing
the ScummVM-side bugs. If you only take one lesson from this section,
take this one: **when a JS-visible C string comes back corrupted, check
whether the C function is returning a pointer to its own stack frame
before assuming the bug is anywhere near where the corruption shows up.**

### Debugging note: neither console logging nor OSD notifications were visible from the emu thread

Two debugging approaches that seemed obvious both turned out to be
dead ends for this specific bridge, because the code being debugged runs
on the emu thread (a separate real pthread/Web Worker under
`HAVE_THREADS=1`):

- `fprintf(stderr, ...)`/ScummVM's own `retro_log_cb` -- console output
  from a pthread Worker is not automatically visible to a DevTools
  Protocol listener attached only to the main page's target. Even
  `retro_init()`'s own always-present debug log line never once appeared
  across an entire session of testing, in hindsight a clear early sign
  of this.
- `retro_osd_notification()` -- goes through
  `RETRO_ENVIRONMENT_SET_MESSAGE_EXT`, which doesn't appear to be
  rendered anywhere visible in this EmulatorJS build.

What actually worked: exporting small C functions with
`__attribute__((used, visibility("default")))` (the same thing
`EMSCRIPTEN_KEEPALIVE` expands to) returning `int`/`const char *`
diagnostic values from static counters, then calling them from the
browser console via
`Module.ccall('function_name', 'number'|'string', [...])`. This reads
state directly out of the WASM instance's memory from JS, sidestepping
the console-visibility problem entirely. Remove these before shipping --
they're not needed once the underlying bug is fixed, and they cost a
`used` attribute's worth of dead-code-elimination protection for no
runtime benefit in the final build.

## Build-system traps that produce misleading "it's still broken" results

These two cost the most wall-clock time in this project, not because they
were hard to fix, but because they made *already-correct* fixes look like
they hadn't worked.

### Editing `module.mk` doesn't reliably invalidate already-built archives

After removing `midi/webmidi.o` from `MODULE_OBJS`, several
rebuild-and-retest cycles kept showing the exact same MIDI errors, even
though the source edit was correct and confirmed present. The cause: this
build's incremental `make` did not reliably detect that
`backends/libbackends.a` (and the intermediate `libtemp/libbackends.a`,
and the final `scummvm_libretro_emscripten.bc`) needed to be regenerated
just because a `module.mk` variable changed.

**Fix:** after any change to a module's object list, explicitly delete
the stale artifacts before rebuilding:

```bash
rm -f scummvm-core/backends/platform/libretro/backends/libbackends.a \
      scummvm-core/backends/platform/libretro/libtemp/libbackends.a \
      scummvm-core/backends/platform/libretro/scummvm_libretro_emscripten.bc \
      retroarch/libretro_emscripten.a
```

(Adjust the archive name to whichever module you actually changed.)

**Verify before spending another full rebuild-and-browser-test cycle:**
`strings` the actual compiled artifact for whatever symbol/string you
expected to remove. This is far cheaper than a rebuild + repackage +
browser reload, and it would have caught the stale-archive problem
immediately instead of after several confusing "still broken" cycles:

```bash
strings scummvm-core/backends/platform/libretro/scummvm_libretro_emscripten.bc \
  | grep -c midiOutputMap   # expect 0 after a real fix
```

### `bash script.sh | tail -N` silently swallows the script's real exit code

Even with `set -euo pipefail` *inside* `script.sh`, piping its output
through `tail` (or any command) in the *outer* shell means the pipeline's
reported exit code is `tail`'s (almost always 0), not the script's. This
let one real build failure go completely unnoticed, and a downstream
packaging step went on to silently re-package stale, already-broken
artifacts as if the rebuild had succeeded.

**Fix:** when the exit code matters (basically always, for build
scripts), redirect to a file and check explicitly instead of piping
through a pager:

```bash
bash build/build-retroarch-core.sh > /tmp/build.log 2>&1
echo "EXIT_CODE=$?" >> /tmp/build.log
tail -20 /tmp/build.log   # now safe -- exit code already captured above
```

### Browsers can serve a stale core after a same-session rebuild

During active development, the RetroArch core gets rebuilt many times
while the test server keeps running. Plain `http.server` sends no
`Cache-Control` header at all, and Chrome's heuristic caching can serve a
previous build's `.data`/`.wasm` on an ordinary reload, silently testing
old code and producing misleading results. `test-page/serve-coop-coep.py`
sends `Cache-Control: no-store` for exactly this reason. If test results
seem inexplicably inconsistent between runs where nothing should have
changed, suspect this before suspecting nondeterminism in the actual
code -- and confirm with a hard reload (Ctrl+Shift+R / Cmd+Shift+R) or by
checking response headers with `curl -sI`, not just a normal reload.

## EmulatorJS / packaging conventions

### `.data` bundle naming: `-thread` and `-legacy` suffixes are capability flags, not arbitrary names

EmulatorJS's loader (see `retroarch/emulatorjs/build-emulatorjs.sh` for
the canonical naming logic) appends `-thread` when the core was built
with real pthread support, and `-legacy` when GLES3 support is *absent*
(`HAVE_OPENGLES3=0`). This build uses `HAVE_THREADS=1 HAVE_OPENGLES3=1`,
so the correct, honest name is `scummvm-thread-wasm.data` --
`package-core.sh` produces exactly that, not `scummvm-wasm.data` or a
`-legacy` copy.

**Caveat:** without a core-report JSON (`ejs/data/cores/reports/*.json`)
that sets `options.defaultWebGL2: true`, EmulatorJS's own
`downloadGameCore()` (`emulator.js`) defaults every core to the
`-legacy` filename on a user's *first visit* -- unconditional, not a real
check of the browser's actual WebGL2 support (confirmed: `dosbox_pure`'s
own shipped report doesn't set it either). Until a real core-report JSON
exists for this core, both `scummvm-thread-wasm.data` and
`scummvm-thread-legacy-wasm.data` need to exist and be identical.
`package-core.sh` now handles this for you: it produces
`scummvm-thread-wasm.data` and then `cp`s it to
`scummvm-thread-legacy-wasm.data` as its last step, so both are always in
sync after a single run. `build/deploy-to-romm.sh` likewise stages both
files into the ROMM fork checkout. There's no manual copy step and no
stale-copy hazard anymore.

### Zip packaging: flat structure, always

See the README's [Adding a game](../README.md#adding-a-game) section.
The short version: `cd` into the game's actual data folder before
zipping, so the zip's internal paths have no parent directory component.
EmulatorJS's generic zip extraction writes every entry to the filesystem
root by basename; a nested zip structure doesn't get flattened for you in
a way ScummVM's directory-based auto-detection can rely on, so don't
create the ambiguity in the first place.

### Content loads via `argv`, not a direct `retro_load_game()` call from JS

`emulator.js`'s `startGame()` calls
`this.Module.callMain(["/" + this.fileName])` -- i.e. it runs RetroArch's
own compiled `main()` with the content path as a CLI positional argument
(the WASM equivalent of running `retroarch /00.LFL` from a terminal), not
a direct JS-to-`retro_load_game()` API call. This matters if you're
debugging why content isn't being picked up: check RetroArch's own CLI
argument parsing and content-path handling
(`retroarch_parse_input_and_config`,
`runloop_path_set_basename(argv[optind])`), not EmulatorJS's JS-side
loading code -- by the time JS hands off to `callMain`, EmulatorJS's job
is basically done.

## `USE_HIGHRES`: a global compile-time engine gate, not just a canvas-size cosmetic flag

`USE_HIGHRES` (`backends/platform/libretro/Makefile.common`) is a
preprocessor macro baked into `portdefs.h` at compile time, not a runtime
setting:

```c
#ifndef USE_HIGHRES
#define RES_W_OVERLAY 320
#define RES_H_OVERLAY 200
#else
#define RES_W_OVERLAY 1280
#define RES_H_OVERLAY 720
#endif
```

This project originally built with `USE_HIGHRES=0` (see `build-core.sh`
history) specifically so SCUMM's real 320x200 output wouldn't get padded
into a fixed 1280x720 overlay with permanent black bars baked into the
canvas's own framebuffer -- see the section below for the distinct,
already-fixed *container-shape* pillarboxing problem, which this is not.

**It's also a silent dependency gate, discovered while sweeping additional
engines.** `configure_engines.sh`'s enable loop treats `highres` as a
regular engine dependency: any engine whose own `configure.engine` lists
`highres` in its deps field gets disabled outright when
`USE_HIGHRES=0` -- not a build warning, not a log line (the whole
`configure` invocation runs with stdout redirected to `/dev/null`), just
absent from the final linked binary. A 103-engine compile-only sweep
(every ScummVM engine except the 13 declaring a `3d`/`tinygl` dependency --
see `build/engine-lists/README.md`) reported exit 0 but linked only 55
engines; the other 48 were, without exception, exactly the ones declaring
`highres` as a dep. This isn't a niche gap -- it includes Broken Sword 1 &
2 (`sword1`/`sword2`), Little Big Adventure (`twine`), Starship Titanic
(`titanic`), Blade Runner, Director, and the Mohawk engine. It also
silently excludes SCUMM's own `he` subengine (Humongous Entertainment kids'
games -- Freddi Fish, Pajama Sam) from every build shipped so far, since
`he`'s own `configure.engine` also declares `highres` -- an existing gap in
this project's SCUMM-only binary, not something introduced by adding more
engines.

**Two ways to resolve the conflict, both legitimate:**

1. **Two binaries, split by resolution profile** (`USE_HIGHRES=0` for
   SCUMM-shaped engines, `=1` for the 48 requiring highres), shipped as two
   named EJS cores under the same ROMM "ScummVM" platform entry (ROMM's
   `_EJS_CORES_MAP` already takes an array per platform --
   `scummvm: ["scummvm", "scummvm-hi"]` -- the same mechanism used when one
   console has multiple valid cores, e.g. NES's fceumm vs. nestopia).
   Eliminates pillarboxing entirely for the lowres-native engines. Cost:
   two cores to build/ship/maintain, and no automatic per-ROM engine
   detection at the ROMM/EJS layer -- the user picks the right core
   manually per game (same friction as any other multi-core EJS platform).
2. **One binary, `USE_HIGHRES=1` globally.** Simpler to build and deploy
   (one core, one ROMM registration, no manual per-game core picking), at
   the cost of real pillarboxing for every lowres-native engine, SCUMM
   included -- a *different*, deeper kind than the section below fixes
   (see the note at the end of that section). Confirmed **cosmetic, not
   functional**: ScummVM clamps mouse/input coordinates to the actual
   rendered sub-rect regardless of the padded overlay size, so gameplay is
   correct either way. Real secondary cost: a 1280x720 framebuffer is
   ~14x the pixel count of 320x200, composited every frame even though
   most of it is black -- a genuine (if usually minor) CPU/bandwidth cost
   for lightweight 2D games, not purely aesthetic.

**Decision for this project: option 2, single binary, `USE_HIGHRES=1`.**
Chosen for build/deploy simplicity over eliminating pillarboxing. Revisit
option 1 if the pillarboxing on lowres titles turns out to matter more in
practice than it does on paper.

## GL/3D engines: a second core, grouped by GL involvement not by strict necessity

The 13 engines this project's main core excludes (declaring a `3d`
dependency or `tinygl` component in their own `configure.engine`) turned
out to split into two very different groups on closer inspection, not one:

- **Only 3 (`hpl1`, `twp`, `watchmaker`) actually require anything.** Their
  deps include the literal `opengl_game_shaders`/`opengl_game_classic`
  tokens, which `Makefile.common` genuinely gates behind
  `FORCE_OPENGLES2=1` (adds them to `UNAVAILABLE_DEPS` otherwise).
- **The other 10 (`alcachofa`, `freescape`, `grim`, `myst3`, `stark`,
  `tetraedge`, `tinsel`, `wintermute`, plus the internal-only `testbed`/
  `playground3d`) only reference `3d`/`tinygl`.** `USE_TINYGL = 1` is
  unconditional in `Makefile.common` -- no availability check gates it at
  all -- and ScummVM's own `configure` derives `_3d=yes` directly from
  `_tinygl=yes` (see `configure` around line 7273), with no dependency on
  `FORCE_OPENGLES2`/real hardware GL whatsoever. TinyGL is ScummVM's own
  bundled *software* 3D rasterizer -- pure CPU, no GPU/WebGL context, a
  completely different code path from the real `retro_hw_render_callback`
  wiring in `libretro-graphics-opengl.cpp`. Confirmed empirically: an
  isolated `grim`-only build compiled and linked cleanly with no GL flag
  set at all, producing `gfx_tinygl.o` in its archive (`gfx_opengl.o`/
  `gfx_opengl_shaders.o` are also always compiled in, alongside it, for
  every engine that references 3D -- presumably inert without
  `HAVE_OPENGL`/`HAVE_OPENGLES2` defined, though this hasn't been proven
  by actually running the binary yet).

That means the 10 TinyGL-only engines would compile fine in the main
core -- they don't need a separate binary on technical grounds. **They're
kept out anyway, by choice:** one core for pure 2D, a second core for
anything GL-touching at all, rather than a small set of "mostly excluded,
except these 10 which are actually fine" exceptions to remember. All 11
real games (`testbed`/`playground3d` excluded as ScummVM's own internal
non-game test harnesses) go into `build/engine-lists/gl-core.list`,
meant to be built as its own core with `FORCE_OPENGLES2=1` -- harmless for
the 8 TinyGL-only engines in that list, required for the 3 that actually
gate on it. See `build/engine-lists/README.md` for the current list
contents and status (not yet built or runtime-tested as a group).

**Whether TinyGL's software rendering actually performs acceptably under
Emscripten/WASM for a real 3D game is a separate, still-open question.**
Compiling proves nothing about runtime behavior -- see the WebMIDI and
save-state sections above for two prior cases where a clean compile hid a
real runtime bug. TinyGL is CPU-only real-time 3D rendering for games
(Grim Fandango, Myst III) that assumed a real GPU on their original
hardware; whether that's fast enough in a browser is unverified.

## Pillarboxing/letterboxing: constrain a wrapper around `#game`, not `#game` itself

SCUMM's native output is 320x200 (8:5 = 1.6:1). If `test-page/index.html`'s
`#game` container isn't *also* exactly that shape, you'll see real black
bars baked into the canvas's own rendered pixels -- not a CSS-level letterbox
sitting around a correctly-sized canvas, but bars actually drawn into the
canvas's pixel buffer by RetroArch's own GL renderer, which faithfully
preserves the core's true aspect ratio inside whatever shape it's given.
Confirmed directly (not by eyeballing screenshots, which repeatedly gave
contradictory-looking results across different window sizes -- see the
debugging-technique note below): querying `canvas.width`/`height` against
`canvas.getBoundingClientRect()` showed the two matching exactly (e.g.
980x503 and 980x503), meaning the canvas was displayed at 1:1 with no CSS
scaling, and the container's own natural shape (~1.95:1) simply didn't
match SCUMM's real 1.6:1 -- the bars were the *correct* result of asking a
correctly-aspect-preserving renderer to fit 1.6:1 content into a
1.95:1-shaped box.

**The fix is not on `#game` itself.** EmulatorJS's own JS resizes `#game`
directly at runtime, overriding any `width`/`height`/`aspect-ratio` you put
in its own inline style or a class rule (confirmed by testing: setting
`aspect-ratio:8/5` directly on `#game` had zero effect on its measured
`getBoundingClientRect()` after load). EmulatorJS does, however, resize
`#game` to fill its *immediate parent* -- so wrap it:

```html
<div id="game-wrapper" style="width:100%;aspect-ratio:8/5;">
<div id="game" style="width:100%;height:100%;background:#000;"></div>
</div>
```

Giving the wrapper the correct ratio means `#game` inherits a
correctly-shaped box, and RetroArch's renderer has nothing left to pad.
Confirmed fixed: `canvas.getBoundingClientRect()` measured 838x523.75
afterward -- 838/523.75 = 1.6002, matching 8:5 to four significant figures,
with zero visible bars.

**Two follow-up corrections, both found by testing a second game (Zak
McKracken's FM-TOWNS CD release) rather than just the one already-working
title:**

1. **The ratio isn't a project-wide constant.** 8:5 (1.6) happens to be
   what most SCUMM titles report, but it's not universal -- different
   games/platforms report different values (confirmed: the FM-TOWNS
   release does not report 1.6 the same way at every point during
   startup -- see the next point). Hardcoding `aspect-ratio:8/5` on the
   wrapper is only correct for *some* games. Read the actual value from
   the core instead, via EmulatorJS's own
   `this.gameManager.getVideoDimensions("aspect")`, and apply it to the
   wrapper's `style.aspectRatio` at runtime.

2. **A single read isn't enough, either.** Reading
   `getVideoDimensions("aspect")` once at `EJS_onGameStart` can catch a
   value that hasn't settled yet -- for the FM-TOWNS release specifically,
   the value returned right at game start differed from what it settled
   on a moment later, once the engine's own video-mode setup finished
   running. Poll for several seconds after start (e.g. every 500ms for
   10s) and keep re-applying whenever the reported value changes, rather
   than trusting the first read.

3. **`width:100%` on the wrapper, never a fixed pixel value.** An early
   version of this fix used `width:960px;max-width:100%` -- this shrinks
   correctly on narrower windows (via `max-width`) but **never grows past
   960px** on wider ones, since nothing tells it to. The symptom looks
   exactly like a resize/timing bug ("shrinking the window makes the game
   smaller, but expanding it stops scaling at one point") and is easy to
   misdiagnose as a continuation of the aspect-ratio investigation above
   -- it's actually a completely unrelated, much simpler CSS mistake.
   Always use `width:100%` (or otherwise genuinely responsive sizing) on
   the wrapper, with the aspect ratio as the only shape constraint.

See `test-page/index.html`'s `EJS_onGameStart` for the current
implementation of both the dynamic-ratio polling and the responsive
wrapper width together.

**If you're chasing a similar layout bug in this project again:** don't
trust visual comparison of screenshots taken at different points across a
debugging session -- window size, canvas size, and letterbox/pillarbox
orientation all vary together, and it's very easy to misread two
differently-sized screenshots as "before/after" when they're actually just
two different container shapes that both happen to show *some* bars. Get
exact numbers instead: `canvas.width`/`height` (the actual render buffer),
`canvas.getBoundingClientRect()` (the CSS-rendered display box), and the
container's own `getBoundingClientRect()`, compared directly. This is the
same lesson as the save-state section's debugging note, applied to layout
instead of application state.

**A dead end worth naming, so it isn't re-investigated:** early in this
investigation it looked like RetroArch's canvas-size-sync
(`library_platform_emscripten.js`'s `ResizeObserver` on the WASM canvas)
was failing to fire reliably, requiring repeated manual window
resizes to "converge" on a correct size -- a plausible-sounding
resize-timing bug. Testing this in an automated browser-automation tab
produced a real, reproducible-looking failure (a freshly attached
`ResizeObserver` never fired for confirmed box-size changes), but this
was very likely an artifact of that tab being backgrounded/non-visible
from Chrome's own perspective (corroborated by an unrelated
`NotAllowedError: ... WakeLock: The requesting page is not visible`
console error appearing in the same session) -- Chrome throttles various
visibility-gated behavior for backgrounded tabs. Dispatching synthetic
`resize` events as a workaround had no effect in either the automated tab
or a real, focused, visible browser tab, which in hindsight was the
signal that the actual bug wasn't about resize timing at all. The real
issue (container shape, above) has nothing to do with `ResizeObserver`
or resize-event timing.

**This fix stops working once `USE_HIGHRES=1` is baked into the core, and
that's expected, not a regression to chase.** The dynamic-ratio read this
section relies on (`getVideoDimensions("aspect")`) reports whatever the
*core* claims its resolution is -- with `USE_HIGHRES=1` that's always the
padded 1280x720 overlay, not the game's real content size, so the wrapper
ends up correctly shaped around the wrong (padded) rectangle and the actual
game still renders smaller with real bars baked into the pixel buffer. This
is the different, deeper pillarboxing described in the `USE_HIGHRES`
section above -- a compile-time engine-gate tradeoff, not a CSS bug. Don't
re-investigate this section's fix for it; it was never meant to solve
that problem.

## Mouse input and pointer lock

The libretro "mouse" input device already sends relative
`movementX`/`movementY`-style deltas per frame -- this is the same model
original DOS mouse drivers used, and it's why the in-game cursor's
direction and movement worked correctly from the very first successful
boot, with no code changes needed. What's *not* automatic is hiding the
OS cursor: without engaging the browser's Pointer Lock API, the real OS
cursor stays visible and moves independently of the in-game cursor,
which looks broken even though the actual input pipeline is fine.

Fix: `test-page/index.html` sets
`EJS_defaultOptions = { lockMouse: "enabled" }`. This is EmulatorJS's own
documented mechanism for defaulting its settings-menu options
(`loader.js` maps `window.EJS_defaultOptions` directly to
`this.config.defaultOptions`, consumed at startup by
`changeSettingOption`) -- not a custom patch. It engages pointer lock on
the first canvas click, which also happens to be the same click needed
to satisfy the browser's audio-autoplay gate, so in practice this all
resolves with a single click after load.

When deploying this core into ROMM specifically, there's no
`EJS_defaultOptions` to set -- ROMM's own `Player.vue` never sets
`lockMouse` and has no equivalent of the test-page's
`EJS_defaultOptions` global. The equivalent fix there is a `config.yml`
addition instead of a code change: `emulatorjs.settings.scummvm.lockMouse:
enabled`. This is ROMM's own per-core EmulatorJS option override
mechanism (see `backend/config/config_manager.py`, which reads
`emulatorjs.settings.<core>.<option>` out of `config.yml`), not anything
specific to this integration.

## Debugging technique notes

- **Read the browser console directly and unfiltered**, via a real
  browser-automation console-reading tool if you have one, rather than
  relying on a page-injected patch (e.g. overriding `window.Worker`) or
  waiting for someone to manually paste console output. A real,
  build-blocking error (`Module.setValue is not a function`) was missed
  for an entire debugging pass specifically because an `onlyErrors`-style
  filtered query returned only one (different) result, and the second
  error was sitting in the unfiltered output the whole time.
- **Uncaught errors inside a spawned pthread worker are real signal, not
  noise** -- don't assume a generic `worker.onerror`-tagged `ErrorEvent`
  with no visible message is benign background noise just because it
  reproduces on every run. It might be (EmulatorJS's own zip-decompression
  worker throws one unrelated to gameplay, confirmed present even before
  any of this project's own code ran), but the only way to know is to
  actually capture the error's real `.message`, not just its `type`.
- **Don't probe unexported `Module.*` internals from outside the page**
  (e.g. `Module.PThread`) just to inspect runtime state -- Emscripten
  sets up warning-getter traps on well-known-but-unexported symbol names
  that call `abort()` the moment they're touched, immediately killing the
  entire running instance you were trying to inspect. If you need runtime
  visibility that isn't already exported, wrap a *known-safe*, standard
  browser API from the outside instead (this project did this
  successfully by wrapping `window.requestAnimationFrame` to log frame
  timing, with zero risk to the running instance) or add the export at
  build time and verify it landed before relying on it.
