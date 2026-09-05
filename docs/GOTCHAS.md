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

These cost the most wall-clock time in this project, not because they
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

### `libdetect.a`/`libdeps.a` don't get rebuilt when `lite_engines.list` changes

Rebuilding with a larger `lite_engines.list` (55 to 103, then 103 to 123
engines, same `scummvm-core` checkout each time) silently kept the *old*
engine set's detection plugins linked in. Confirmed as an undefined-symbol
link failure (`g_SCUMM_DETECTION_type`) rather than a silent no-op only
because the newly-added engine (SCUMM's own `he`/`scumm_7_8` subengines)
happened to trigger `engines/detection_table.h`'s
`LINK_PLUGIN(SCUMM_DETECTION)` for the first time in a way the stale
archive didn't satisfy -- a smaller change might have linked "successfully"
while silently missing detection for the new engines instead of failing
loud.

Root cause: `backends/platform/libretro/libdetect.a` and `libdeps.a` are
top-level merged archives (`emar -M < script.mri`, see the final link line)
that `make` did not reliably decide needed regenerating just because
`lite_engines.list` changed -- the exact same class of bug as the
`module.mk` case above, different files. Confirmed by comparing mtimes:
per-engine archives (`engines/scumm/libscumm.a`) matched the current
build's timestamp; `libdetect.a`/`libdeps.a` were dated from an earlier
build in the same checkout, hours/builds prior.

**Fix:** delete both before rebuilding whenever `lite_engines.list`
changes:

```bash
rm -f scummvm-core/backends/platform/libretro/libdetect.a \
      scummvm-core/backends/platform/libretro/libdeps.a
```

**Verify:** `ls -la` both files after the rebuild and confirm the mtime is
current and (for `libdetect.a` specifically) the size actually changed --
identical size after adding engines is a sign it wasn't really rebuilt.

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

### ROMM doesn't require the `.scm` extension -- plain `.zip` works fine

This project's own docs and the ROMM integration work both settled on
renaming packaged zips to `<name>.scm` before dropping them in ROMM's
library folder. Confirmed unnecessary: a file left with a plain `.zip`
extension (`loom copy.zip`) scanned and played correctly with no
difference in behavior. Checked ROMM's own backend source for a `.scm`
special-case (`grep -rn ".scm" backend/`) and found none -- there's no
ScummVM-specific extension whitelist being enforced. `.scm` was a
convention adopted early in this project, not a real ROMM requirement.
Either extension works; use whichever is more convenient (`.zip` avoids
an extra rename step when repackaging).

### Some engines hardcode relative subpaths in their own C++ source -- for those, keep the directory structure, don't flatten

Most engines (SCUMM included) scan their game folder without caring about
directory layout, which is why flattening to zero subdirectories is the
default-safe move (see above). `griffon` is a counterexample:
`engines/griffon/sound.cpp`, `dialogs.cpp`, and `resources.cpp` all pass
literal relative-path strings straight to the file-open calls --
`"music/boss.ogg"`, `"sfx/door.ogg"`, `"art/window.bmp"`, etc. Flattening
this zip would silently break every one of those lookups. The official
`griffon-1.0.zip` from `scummvm.org`'s freeware page already ships with
the correct `data/`, `mapdb/`, `music/`, `sfx/`, `art/` sibling
subdirectories intact and no filename collisions between them -- for this
engine, leave the structure as-is rather than flattening. If it hits the
intermittent EmulatorJS extraction crash described below, that's the
known flakiness, not a reason to flatten and break the engine's own path
lookups.

### Companion `.dat` files can collide by name with a file the original game already ships

Like `drascula.dat`/`lure.dat`/`queen.tbl` before it, `teenagent` needs
its own ScummVM-authored companion file from
`scummvm-core/dists/engine-data/teenagent.dat` (403,315 bytes, a
versioned resource/translation table -- see
`engines/teenagent/resources.cpp`'s `TEENAGENT_DAT_VERSION` check). The
twist: the original 1996 DOS game *also* ships its own file literally
named `teenagent.dat` (70,047 bytes, an internal resource index used by
the original executable, functionally unrelated to ScummVM's file of the
same name). Since ScummVM's `teenagent` engine never reads the original
executable's data at all, the fix is to **delete the game's original
`teenagent.dat` from the zip and replace it with ScummVM's own** (not
just append -- a straight append leaves the original in place and
ScummVM reads that one, failing with "The 'teenagent.dat' engine data
file is corrupt." since it doesn't match the expected versioned format).
Check any newly-added engine's `resources.cpp`/`detection.cpp` for a
`_DAT_VERSION` constant before assuming an engine-data companion file can
just be appended -- if the game's own archive already contains a file by
that exact name, it needs replacing, not adding to.

Same pattern hit a third time on `kyra` (Legend of Kyrandia): the game's
own install package ships a 353,834-byte `kyra.dat` (unrelated internal
data), while ScummVM's own companion file at
`scummvm-core/dists/engine-data/kyra.dat` is 2,023,908 bytes. Naively
appending it with `zipfile.ZipFile(path, 'a', ...)` produces a zip with
*two* entries both named `kyra.dat` -- Python's `zipfile` even prints a
`UserWarning: Duplicate name` when writing it, easy to miss in a longer
script's output, and which entry actually gets read back is ambiguous
rather than reliably "the last one." The reliable fix is always the same
now: open the zip for reading, copy every entry *except* the colliding
name into a new zip, then add the correct engine-data file once. Three
for three so far (`teenagent`, `kyra`, and this pattern should be
expected for any engine with a `_DAT_VERSION`-style versioned companion
file) -- treat a same-named collision as the default assumption for these
files, not the exception.

### Clearing EmulatorJS's IndexedDB caches: `await indexedDB.deleteDatabase()` does not actually wait

`IDBOpenDBRequest` is not a native `Promise` -- awaiting it directly
resolves immediately with the request object, before the deletion
actually completes (before its `onsuccess`/`onblocked` event fires). A
retest immediately after this bare `await` can still see the old cached
ROM, making a genuine fix look like it didn't work. Wrap it properly:

```js
function delDb(name) {
  return new Promise((resolve, reject) => {
    const req = indexedDB.deleteDatabase(name);
    req.onsuccess = () => resolve();
    req.onblocked = () => resolve(); // still completes once the blocking connection closes
    req.onerror = () => reject(req.error);
  });
}
await Promise.all([delDb("EmulatorJS-core"), delDb("EmulatorJS-roms")]);
```

Follow with a hard reload (`ctrl+shift+r`) before retesting, same as the
intermittent-extraction-crash workaround below.

### `bchunk -s` swaps audio byte order -- don't use it on a normal little-endian rip, or CD music becomes static

`bchunk` splits a `.bin`/`.cue` CD image into separate track files, and
handles `MODE1/2352` (data) and `AUDIO` tracks differently -- audio
tracks come out as raw headerless PCM (`.cdr`), which `ffmpeg -f s16le
-ar 44100 -ac 2` can decode directly into a normal format. `bchunk`'s
`-s` flag is documented as "swabaudio: swap byte order in audio tracks"
-- it exists for target systems that need big-endian samples. Passing it
unconditionally (out of habit, or copying a command that included it) on
a normal rip byte-swaps every 16-bit sample, and the result decodes as
pure static: the game still boots and detects fine, plays back the
"track" without any error, and it's still nominally valid audio data (no
codec failure) -- the corruption is only audible, never visible in a
screenshot or log. Confirmed the fix by re-running plain `bchunk
image.bin image.cue out` (no `-s`) and comparing: same file size, same
duration, but real music instead of noise. **A screenshot proving a
CD-audio game boots and looks correct is not enough verification if the
game has music -- someone needs to actually listen.**

Also relevant here: ScummVM's generic ripped-CD-audio detection
(`Engine::existExtractedCDAudioFiles()`, called with no argument from
most engines' init code) defaults to checking for **track 1**
specifically (`track1.*`/`track01.*`/etc, see
`backends/audiocd/default/default-audiocd.cpp`'s
`fillPotentialTrackNames`), regardless of which physical CD track number
the actual audio content came from. Gobliiins' music is physically CD
track 2 (track 1 is the data track), but the "you're missing ripped CD
audio" warning dialog only goes away once `track01.ogg` exists --
whether the *game* internally requests track 1 or track 2 when it
actually plays music is a separate question the engine's own script
data decides, so the safe fix when there's only one music track is to
provide both `track01.<ext>` and `track02.<ext>` (same file, two names)
rather than guess which number is load-bearing.

### Packaging full multi-CD retail games: raw `.mdf` images need manual sector-stripping, and each disc's same-named cluster files need renaming, not merging

Archive.org's copies of full retail games (as opposed to freeware/demo
releases) are usually raw CD-ROM rips in Alcohol 120% `.mdf`/`.mds`
format, not plain data files. `7z` cannot read a `.mdf` directly. These
are raw sector dumps, and the fix is a small manual conversion script,
run once per disc:

```python
sector_size = 2352
sync_header = 16   # Mode 1: sync(12) + header(4)
# sync_header = 24 # Mode 2 Form 1: sync(12) + header(4) + subheader(8)
data_size = 2048
with open('DISC.mdf', 'rb') as fin, open('DISC.iso', 'wb') as fout:
    while True:
        sector = fin.read(sector_size)
        if len(sector) < sector_size:
            break
        fout.write(sector[sync_header:sync_header + data_size])
```

Check the sector mode before picking the offset: the 4th byte of the
first sector (byte offset 15) is the CD mode -- `01` for Mode 1, `02` for
Mode 2. **Different discs of the same game can use different modes**:
confirmed on Broken Sword II, where CD1 was Mode 2 Form 1 (offset 24) and
CD2 was plain Mode 1 (offset 16). Don't assume the second disc matches
the first; check each one. A correct offset produces a file `7z l`
recognizes as `Type = Iso` with a real volume name; a wrong offset (or
treating an `.mdf` as a plain `.iso`) fails with "Cannot open the file as
archive."

Once each disc converts to a normal ISO9660 image, `7z x` extracts it
like any other archive.

**The second problem, specific to multi-CD games**: both discs ship a
file with the *same name* but *different content* -- e.g. Broken Sword
1's `SPEECH.CLU` (dialogue for the Paris chapters on CD1, a completely
different 339 MB file for Ireland/Scotland/Spain/Syria on CD2) or Broken
Sword 2's `Music.clu`/`speech.clu` (same pattern, both files). Naively
merging both discs' extracted trees into one zip silently drops half the
content -- Python's `zipfile` even warns `Duplicate name` when this
happens, easy to miss in a long build script's output. The fix isn't
flattening or renaming arbitrarily: **check the engine source for its own
multi-disc naming convention** before guessing. For `sword1`, see
`sword1.cpp`'s warning message directly: "copy the SPEECH.CLU files from
both CDs and rename them to SPEECH1.CLU and SPEECH2.CLU". For `sword2`,
`music.cpp`'s `getAudioStream(fh, base, cd, ...)` builds the filename as
`sprintf("%s%d.%s", base, cd, ext)` -- so `music1.clu`/`music2.clu` and
`speech1.clu`/`speech2.clu`. Both files can live inside the same
`Clusters`/`CLUSTERS` folder as everything else; both engines already
register that folder as a matching search subdirectory.

**Not every same-named file needs this treatment.** Some files that
appear on both discs (Broken Sword 1: several `MUSIC/*.WAV` tracks and
`SMACKSHI/GRAVE.SMK`; Broken Sword 2: `Clusters/Credits.clu`,
`Font.clu`, `vielogo.tga`, `credits.bmp`) are genuinely
byte-identical shared resources, confirmed via `md5sum` before
deduplicating -- keep one copy, don't rename these. Conversely, don't
assume a same-named file is a duplicate without checking: also verify
each disc's unique-per-disc files (different filenames entirely, like
Broken Sword 1's CD2-only `MUSIC/6M*.WAV`/`7M*.WAV`/`8M*.WAV` tracks and
`SMACKSHI/IRELAND.SMK` etc.) actually get included -- an early merge
attempt here only walked CD1's `MUSIC`/`SMACKSHI` folders and silently
dropped 86 CD2-only tracks and 14 CD2-only cutscenes before this was
caught by comparing directory listings (`comm -13`) between the two
discs.

### Zips with subdirectories but no file at the true root silently fail to detect any game (root cause fixed 2026-09-02, kept for historical/hook-file context)

**Update:** the underlying cause described in this section --
`retro_load_game()` deriving the detection scan root from whichever file
EmulatorJS's `fileNames[0]` happened to select -- is now fixed
permanently at the core level for this WASM build. See "Subdirectory-
structured engines: anchor placement no longer matters" further down for
the fix and its direct verification (a zip with *zero* root-level files
at all -- every entry nested under `ACT1/`/`ACT2/`/`BURST/`/`MISC/` --
detected and booted correctly with no repackaging). **You no longer need
to ensure a root-level file exists, or control which file is first, for
detection/autodetect purposes.** The `fileNames[0]` mechanism explained
below is still real and still matters for one remaining thing: the
`.scummvm` hook file (see further down) still only activates if it's
literally `fileNames[0]`, since that check is on `game->path` itself, not
on the derived scan root. Kept below for that reason and as historical
context for how this was originally traced.

For engines that need their directory structure preserved (see the
griffon entry above), there's a second, distinct requirement beyond
"don't flatten": **at least one file must sit at the zip's true root
level**, not nested inside any subdirectory. `sword1`'s official Broken
Sword demo hit this: a first packaging attempt kept only the needed
subdirectories (`CLUSTERS/`, `MUSIC/`, `SMACKSHI/`, `SMACKSLO/`,
`SPEECH/`) and dropped every loose root-level file as "installer
cruft." Symptom: no crash, no error -- ScummVM's own launcher loaded
fine, but its game list was simply empty, as if the ROM contained
nothing at all. Confirmed via direct filesystem inspection
(`Module.FS.readdir()`, see below) that every file *had* extracted
correctly -- this is not the extraction-crash bug described next.

Root cause, traced fully through both sides now:

**ScummVM side** (`backends/platform/libretro/src/libretro-core.cpp`'s
`retro_load_game()`): the frontend hands the core a single file path as
"the" content reference for a multi-file zip. The core calls
`Common::FSNode(game->path).getParent()` and passes *that directory* to
`testGame()` for autodetection. If the picked file lives inside
`CLUSTERS/`, the effective scan root becomes `/CLUSTERS`, not the true
zip root -- so a detection entry needing files from two sibling
directories (`clusters/scripts.clu` *and* `smackshi/intro.smk`, both
relative to the same root) can never match, because from `/CLUSTERS`'s
own perspective, `smackshi/` doesn't exist as a child.

**EmulatorJS side -- the actual selection rule, traced through
`test-page/ejs/data/src/emulator.js`'s `downloadRom()` (~lines 777-870),
and this is fully deterministic, not probabilistic:** each extracted zip
entry gets pushed onto a `fileNames` array in the order the
decompression worker emits them -- that's the zip's own central
directory order (whatever order the archive's creator wrote entries in,
via `zipfile.write()`/`zf.writestr()` calls or equivalent), **not**
alphabetical, and **not** any "prefer the root" logic. After extraction:

```js
if (supportedFile !== null) {
    this.fileName = supportedFile;
} else {
    this.fileName = fileNames[0];
}
```

`supportedFile` is the first-in-order file whose extension appears in
`this.extensions` -- but `this.extensions` only gets populated from a
core's own `core.json` (`this.extensions = core.extensions`), and **this
project's `package-core.sh` never generates a `core.json`.** So for this
core, `this.extensions` stays empty for the entire session,
`supportedFile` stays `null` forever, and selection falls through
unconditionally to `fileNames[0]` -- **literally whichever file was
written first into the zip, every time, no exceptions.**

This is also an acknowledged, unfixed upstream EmulatorJS limitation, not
something specific to this project: [EmulatorJS issue
#884](https://github.com/EmulatorJS/EmulatorJS/issues/884) ("Download
functions to retain directory structure," open, no fix) describes the
identical behavior verbatim: *"there is no way to know which one to send
to the core... EmulatorJS will just send the first one it finds."*

For every previously-working flat game (no subdirectories at all), this
never surfaces: whatever file happens to be first is necessarily a
sibling of every other file, so its parent *is* the correct root by
construction. It only becomes visible for directory-structured games.

**Superseded 2026-09-02 -- do NOT repackage ROMs for this any more.** The
core now scans the virtual-FS root directly on Emscripten builds (see
"Subdirectory-structured engines: anchor placement no longer matters"
below), so entry order is irrelevant to detection. The paragraph below
describes the old packaging workaround, kept because the same entry-order
mechanism still governs which file `game->path` points at, which matters
for `.scummvm` hook files.

**The old workaround, deterministic instead of "keep some root file and
hope": write the intended anchor file as the literal first entry added to
the zip, before any subdirectory files, regardless of its name or
extension.** An earlier version of this note suggested any root-level
file would do, and separately that a fabricated dummy file didn't
reliably work -- both observations are now fully explained: a "kept"
original root file only helped when it happened to already be earlier in
the source archive's own internal ordering than the subdirectory files;
a fabricated dummy appended at zip-build time (after the subdirectories
had already been written) simply wasn't first in the resulting zip's
entry order, so it was never picked. **Entry order is the entire
mechanism.** When packaging, add root-level files to the zip archive
*first*, then subdirectories -- with Python's `zipfile`, that just means
calling `zf.write()`/`zf.writestr()` for the intended anchor file before
looping over the subdirectory contents.

**Diagnostic technique used to rule out the extraction-crash bug**: from
the browser console, inspect the emulator's actual in-memory filesystem
directly rather than guessing from symptoms alone:

```js
const mod = window.EJS_emulator?.gameManager?.Module || window.Module;
function walk(path, depth) {
  let out = [];
  for (const e of mod.FS.readdir(path)) {
    if (e === '.' || e === '..') continue;
    const full = path.replace(/\/$/, '') + '/' + e;
    out.push(full);
    if (depth > 0) {
      const st = mod.FS.stat(full);
      if (mod.FS.isDir(st.mode)) out = out.concat(walk(full, depth - 1));
    }
  }
  return out;
}
walk('/', 3);
```

This confirms or rules out "did the zip actually extract" independent of
whatever ScummVM's own UI shows, separating a packaging/extraction
problem from a detection-logic problem.

### An exact byte-size match to a detection-table entry doesn't guarantee detection succeeds -- it's necessary, not sufficient

This session established a working assumption -- confirmed repeatedly --
that a file matching a detection entry's declared *size* exactly, even
with a mismatched MD5, is usually a legitimately complete dump just
missing from ScummVM's hash table, and boots fine. `hopkins`'s "Win95
UK" English variant broke that pattern: `RES_VAN.RES` from a
MyAbandonware-packaged installer matched the table's declared English
Windows size (38296346 bytes) exactly, the zip had a proper root-level
anchor file, and a full IndexedDB/localStorage clear ruled out stale
cache -- yet ScummVM's launcher still came up with an empty game list on
every attempt. Root cause not identified in the time available (possibly
a companion file silently missing or altered by the installer's own
7z/NSIS repacking, possibly something ScummVM's hash check is stricter
about for this specific engine). Reverted to a different disc (the
official Linux port) that detects and plays correctly, accepting its
known caveat (French voice audio despite an `EN_ANY` table tag) rather
than sink more time chasing the second file.

Takeaway: treat "exact size match" as a good sign worth trying, not a
guarantee -- if it still fails, use the `Module.FS.readdir()` walk
technique from the previous section to confirm the file actually
extracted where expected before assuming the file itself is bad.

### ScummVM's detection MD5 only hashes the first 5000 bytes of a file -- computing a full-file MD5 to "verify" a dump produces false negatives

Several "exact size match, MD5 mismatch" cases across this sweep (this
section's `hopkins` case, `icb`'s El Dorado, and this session's initial
read on `groovie`/`lastexpress`) were diagnosed using a full-file MD5.
That's the wrong check: `AdvancedMetaEngineDetection::AdvancedMetaEngineDetection()`
sets `_md5Bytes = 5000` (`engines/advancedDetector.cpp:960`), and
ScummVM's detector hashes only the first 5000 bytes of each file listed
in an `AD_ENTRY`/`AD_ENTRY2s` tuple -- for any file over 5000 bytes, a
full-file MD5 will not match the table even when the file is a byte-for-
byte-correct, fully-detectable dump.

Concretely: `groovie`'s 11th Hour Interactive Demo (`demo.grv`, 15991
bytes; `dvmod1a.gjd`, 8068568 bytes) and `lastexpress`'s demo
(`Demo.HPF`, 58191872 bytes) were both initially written off as
hash-mismatched based on `md5sum` over the whole file. Recomputing with
`head -c 5000 <file> | md5sum` matched the detection table exactly in
both cases -- these were correct, working dumps the whole time. Verify
against ScummVM's actual algorithm before concluding a dump doesn't
hash-match: `head -c 5000 <file> | md5sum`, not `md5sum <file>`.

This likely also affects some already-deferred results from earlier in
this sweep (`hopkins`'s Win95 UK case above, `icb`'s El Dorado) that were
diagnosed with full-file hashes and never re-checked against the 5000-
byte rule -- worth a second look before assuming those dumps are
genuinely bad.

### A `.scummvm` hook file only works if it's the literal first entry in the zip -- and even then, it only bypasses the launcher's ID lookup, not the engine's own hash-based startup detection

`icb`'s "The Road to El Dorado" (game ID `eldorado`) hit this end to end.
The archive.org dump's `g/speech.clu` (1927072 bytes) and `g/g` (17704
bytes) matched the English Windows detection entry's declared *sizes*
exactly but neither's MD5 matched -- nor did either match any of icb's
other 9 known-hash variants (Spanish/Italian/Polish/Brazilian
Portuguese/English demo/4 PS1 regions). Plain autodetection came up with
an empty launcher, the same symptom as a missing root anchor.

Tried the `.scummvm` hook file (documented in the README) to skip
autodetection and launch by game ID directly instead. First attempt
appended `eldorado.scummvm` to the *end* of the zip -- no effect,
launcher still empty. Root cause, traced through
`retro_load_game()` in `libretro-core.cpp`: the hook-file branch only
activates if `game->path` *itself* ends in `.scummvm` --
```cpp
const char *target_file_ext = ".scummvm";
int target_file_ext_pos = strlen(game->path) - strlen(target_file_ext);
if (!(target_file_ext_pos < 0) && strstr(game->path + target_file_ext_pos, target_file_ext) != NULL) {
    // hook-file branch
}
```
and `game->path` is set by EmulatorJS to whichever file was written
*first* into the zip (the same deterministic `fileNames[0]` rule as the
root-anchor issue -- see the "Zips with subdirectories" section above).
An appended-last hook file is never `fileNames[0]`, so this branch never
triggers and the code falls straight through to normal autodetection
with zero error or warning. Rebuilding the zip with `eldorado.scummvm`
written *first* fixed this part: the game ID lookup succeeded (confirmed
via a new, different, more specific error appearing).

**But that only gets past `testGame()`'s ID lookup, not the actual
engine startup.** Traced through `OSystem_libretro::testGame()` in
`libretro-os-utils.cpp`: the non-autodetect path calls
`EngineMan.findGamesMatching(engine_id, game_id)`, a lookup against the
static `PlainGameDescriptor` table -- purely a name match, no file
hashing involved, so it succeeds regardless of which specific dump you
have. But the actual launch (`-p "<dir>" eldorado`) still goes through
ScummVM's normal engine startup, which calls each engine's
`MetaEngine::createInstance(OSystem*, Engine**, const XxxGameDescription
*gd)` -- and `gd` has to come from somewhere. For `icb` (and most
AdvancedMetaEngine-based engines), that descriptor can only be produced
by the *same* hash-based `AdvancedDetector` scan the hook file was
meant to skip. If no detection-table entry's hash matches the actual
files on disk, that internal scan fails, `gd` never gets built, and
ScummVM reports the generic `Common::kNoGameDataFoundError`
("Game data not found") -- a different, more specific error than the
empty-launcher symptom, but still ultimately caused by the same
underlying problem: **this specific dump doesn't match any release
ScummVM has ever catalogued.** The `.scummvm` hook file only helps when
the underlying data would have autodetected fine anyway and you just
want to skip the (slow, or ambiguous) directory scan -- it is not a way
to force an engine to accept an unrecognized dump.

Conclusion for this specific case: not a packaging bug at all (the
anchor-file and hook-file mechanics both work correctly once you know
the zip-entry-order rule) -- it's a sourcing problem. The archive.org
copy found is a real, complete game, just not one of the specific
releases ScummVM's `icb` engine has hash signatures for. Fixing it means
finding a different dump, not repackaging this one further.

### Some engines do their own additional file lookup after detection succeeds -- `mtropolis` needs a `.exe` present even though it isn't part of the hash check

`mtropolis` (Muppet Treasure Island, game ID `mti`) passed initial
`AdvancedDetector` hash-based detection fine with just `MTI1.MPL` +
`MTI2.MPX` present (the two files the detection table actually checks) --
but then threw `ERROR: No executable files were found!` from inside its
own debugger console at boot. Traced to
`engines/mtropolis/boot.cpp`'s `findWindowsPlayer()`:

```cpp
fs.listMatchingMembers(executableFiles, "*.exe", true);
if (executableFiles.size() == 0)
    error("No executable files were found");
```

This runs *after* detection, during the engine's own boot sequence, to
find a `.exe` containing a `"mTropolis Windows Player"` signature string
-- used to determine which player/boot configuration (`MTBOOT_*`) to
use. It's a completely separate check from the detection table's file
list, so a zip built to satisfy detection alone isn't necessarily enough
to actually boot. Fix: include the actual player executable
(`MTPLAY32.EXE` for Windows -- 840192 bytes here, matching the size
noted in a commented-out detection-table reference even though that
file isn't part of the active hash check) alongside the detection files.
Takeaway that generalizes beyond this one engine: passing detection is
necessary but not always sufficient -- some engines validate additional
files at boot time that never show up in `detection_tables.h` at all, so
a "No X found" error after a clean detection is worth grepping the
engine's own source for, not just re-checking the detection table.

### Multiple sibling subdirectories in a zip crash EmulatorJS's own extraction worker -- and the crash is intermittent

Found live-debugging user reports of specific SCUMM titles failing:
zips whose files were split across two or more subdirectories at the same
level (e.g. Full Throttle's `DATA/` + `VIDEO/`, The Dig's `VIDEO/` next to
root files, Curse of Monkey Island's `RESOURCE/` next to root files) threw
`Uncaught ErrnoError {errno: 20}` (`ENOTDIR`) from `mkdir`/`mknod`, deep in
EmulatorJS's bundled decompression Worker (`_extract`/`asm._extract` in
`emulator.min.js`'s compression module) -- before ScummVM's own code ever
ran. Titles with all files at one directory level (flat at the zip root,
*or* everything under one single wrapper folder) don't hit it. Fix:
repackage so every file sits at one directory level, whichever level that
is -- collapse multiple sibling subdirectories into one (a single wrapper
folder is fine; flat-at-root is fine; multiple siblings is not). This is
a property of the zip file itself, unrelated to which ScummVM engine the
game uses.

**This crash (and a separate bogus "engine not compiled in" failure on a
provably-correct core) turned out to be intermittent, not deterministic,
on the *same* zip file with *no* changes to it or the deployed core in
between.** Confirmed exhaustively: the same "fixed" Full Throttle zip
crashed with `ENOTDIR` on one load and loaded correctly on the very next
one, with the served core file verified byte-identical (`sha256sum`) both
times, and the core binary itself verified via `strings` to genuinely
contain the fix (`ScummEngine_v7`/`ScummEngine_v8` symbols present,
`"...not compiled in"` string literals absent). Browser HTTP cache,
EmulatorJS's own `EmulatorJS-core`/`EmulatorJS-roms` IndexedDB caches, and
service workers were all ruled out individually (cleared/deleted directly
via `indexedDB.deleteDatabase()` and confirmed gone, hard-reload with
`ctrl+shift+r`, and a plain `fetch()`/`XMLHttpRequest` from the same page
context reliably returned the correct bytes even when EmulatorJS's own
load produced the wrong result moments later). The likely culprit is a
race in EmulatorJS's own decompression Worker around heap growth during
extraction (`Warning: Enlarging memory arrays, this is not fast!` fires
multiple times for these large files, each one a `ALLOW_MEMORY_GROWTH`
reallocation that could invalidate an in-flight buffer reference) -- but
this lives in EmulatorJS's own vendored code, not this project's source,
so it hasn't been fixed at the root, only worked around.

**Practical takeaway: if a fix that should have worked appears not to
have, retry before concluding it didn't.** A single failure after a real
fix is not strong evidence the fix was wrong -- confirm with a second
attempt (ideally after clearing the two IndexedDB databases above) before
spending time re-diagnosing something that was already correct.

### A DOS "installer" folder in an archive.org dump can be a pre-install seed, not the actual installed game -- check for a bundled CD image if key files are missing

Hit twice: `gob` (Gobliiins) and `tucker` (Bud Tucker) both shipped as
zips with a top-level `.../cd/` folder (a raw CD image, easy to
dismiss as "just a bonus copy") sitting next to what looked like the
real DOS floppy install. In both cases, the floppy-looking folder was
actually **source files for `INSTALL.EXE` to consume**, not an
already-installed game -- Gobliiins' `INTRO.STK` was present but its
MD5 didn't match any known hash (it's the pre-install compressed/stub
version), and Tucker's folder was flat-out missing `infobar.txt`
entirely, not just misplaced. Both times, the *actual* usable game data
was inside the `cd/` image instead (an ISO or `.bin` that needed
extraction) -- confirmed by checking there.

**Practical check:** if a detection-required file is missing or its
hash doesn't match any table entry despite an exact size match, don't
assume the archive is simply incomplete -- check whether a `cd/`
subfolder (or similarly named "bonus" image) contains a complete,
already-installed copy before concluding the source needs to be
abandoned.

**A narrower, more common cousin of this:** a size-exact/MD5-mismatched
detection file does *not* always mean the copy is bad or incomplete --
it happened three more times in one batch (`mohawk`/Myst,
`made`/Rodney's Funscreen, `dgds`/Heart of China) with copies that were
otherwise clearly legitimate, complete, already-installed games (not
installer seeds) -- just an untabulated dump/release revision. ScummVM's
`AdvancedMetaEngineDetection` generally still detects and runs these
fine; a mismatched hash on an otherwise-plausible, correctly-sized file
is not by itself a reason to keep searching for a "better" copy -- try
it before assuming it's broken.

### A ScummVM detection-table entry can exist purely to say "not supported" -- check `ADGF_UNSUPPORTED`/`GAME_NOT_IMPLEMENTED` before sourcing a ROM for it

Picked Logical Journey of the Zoombinis as the `mohawk` engine's test
candidate (it's the engine's best-known non-Myst/Riven title), before
noticing that *every single* `zoombini` entry in
`engines/mohawk/detection_tables.h` -- DOS release, demo, German
release, all of them -- is flagged both
`MetaEngineDetection::GAME_NOT_IMPLEMENTED` and `ADGF_UNSUPPORTED`.
ScummVM ships these entries so it can recognize the game and print a
"this game is known but not implemented" message in the launcher --
not so it can actually run it. No amount of correct packaging would
have made it playable; the engine code simply doesn't support this
game's data format.

**Practical check:** before spending time sourcing/downloading a
candidate ROM for an engine, `grep` that engine's
`detection_tables.h` (or equivalent) for the target game's id and
confirm its entry doesn't carry `ADGF_UNSUPPORTED`. Pivoted to Myst
itself instead (the engine's actual flagship, fully implemented) once
this was caught.

### An in-game dialog (e.g. a missing-companion-file warning) can silently ignore clicks until the canvas has been clicked once for focus

Hit testing `saga` (I Have No Mouth, and I Must Scream): a non-fatal
"Could not find AdLib instrument definition files..." warning appeared,
and clicking its OK button -- repeatedly, at the visually-correct
coordinates, even with an Enter keypress -- did nothing. The in-game
mouse cursor rendered by ScummVM's own GUI was visibly not tracking
click positions at all, staying frozen in one spot regardless of where
the click landed.

Root cause: the canvas/game hadn't received browser input focus yet.
Nothing before this had required a real click landing purely on empty
game canvas (previous dialogs happened to get incidental focus from
whatever click sequence led up to them) -- so this hadn't surfaced
before. Fix: click once on a neutral part of the canvas (not a button or
dialog) first, *then* click the actual target -- the second click then
registers correctly, cursor tracking included. Worth doing this as a
matter of course before the *first* interaction on any freshly-loaded
ROM, not just when a click visibly fails to do anything.

### "Could not fetch core report JSON! Core caching will be disabled!" is expected, not a bug

This warning (`emulator.min.js`, from a 404 on
`ejs/data/cores/reports/scummvm.json`) appears on every load and is
harmless -- there's no real report JSON shipped for this core (see the
`-legacy` section above), so EmulatorJS falls back to not caching core
metadata client-side the way it would for an official, catalog-listed
core. It does not affect whether the actual `.data` file download is
cached (that's the separate `EmulatorJS-core` IndexedDB database,
unaffected by this warning) -- only some secondary metadata convenience.
Safe to ignore.

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

## ROMs no longer need to bundle their own ScummVM engine-data file (fixed 2026-09-02)

Many engines need one of ScummVM's own auxiliary "engine-data" files --
`fonts.dat`, `toon.dat`, `nancy.dat`, `ultima8.dat`, `tony.dat`,
`neverhood.dat`, `cryo.dat`, etc. -- containing resources the engine's
reimplementation needs (fonts, string/version tables, translations) that
aren't part of the original game's own files. This is a standard
ScummVM requirement on every platform, not something specific to this
project; on a desktop install, ScummVM's own installer drops its whole
`dists/engine-data/` directory into a shared location once, and
ScummVM's file-search system finds it automatically for every game,
forever.

Previously, this project's WASM/EmulatorJS deployment had no shared,
persistent location the core could see across different ROM launches --
each ROM's zip is the only thing the core can see -- so every engine
that hit this needed its `.dat` file manually discovered (usually via a
runtime crash) and bundled inside that specific ROM's own zip, every
time.

**This is now fixed at the core level, permanently, for every engine.**
The full spec, architecture, and implementation are in
`docs/superpowers/specs/2026-09-02-wasm-engine-data-embed-design.md` and
`docs/superpowers/plans/2026-09-02-wasm-engine-data-embed.md`. Summary:
ScummVM's entire `dists/engine-data/` directory (minus a few dev-only
files) is now baked directly into the compiled WASM core itself via
Emscripten's `--embed-file` (see `build/build-retroarch-core.sh`), and
`OSystem_libretro::addSysArchivesToSearchSet()`
(`libretro-os-utils.cpp`) registers that embedded path in ScummVM's
search set so the engine's own unmodified `common/engine_data.cpp`
lookup finds it automatically -- **no ROM needs to carry its own copy of
any of these files anymore.** Verified end-to-end: `ultima8.dat`,
`toon.dat`, and `fonts.dat` were stripped from already-confirmed ROMs
(Ultima VIII, Toonstruck, Buried in Time) and all three still booted and
played correctly.

This does **not** fix the separate `fonts.dat`-rendering WASM crash
below, and does **not** fix cases where a game needs an *original game
file* that ScummVM's detector doesn't check (e.g. `groovie`'s
`icons.ph`/`sample.AD`/`sample.OPL`) -- those still must be packaged
into the ROM itself.

## Suspected shared bug: rendering text via `fonts.dat` crashes the WASM core (`RuntimeError: memory access out of bounds`)

Four unrelated engines -- `griffon` (a real-time action RPG), `glk`
(text-adventure interpreter, tested via Zork I), `dm` (Dungeon Master),
and `tony` (Tony Tough, a point-and-click adventure) -- all crash with the
byte-for-byte **identical** stack trace, once each had its missing
`fonts.dat` companion file supplied (see the companion-file-collision
entry above for why that file is needed at all). `tony` is notable
because its own source has no static reference to `"fonts.dat"` at all --
it hit the crash purely through the generic engine-data loader, confirming
the "any engine could hit it at runtime even without a source grep match"
warning below wasn't just theoretical:

```
RuntimeError: memory access out of bounds
    at wasm-function[15670]:0xf50294
    at wasm-function[2124]:0x1cf60c
    at wasm-function[75474]:0x4bd58df
    at wasm-function[39904]:0x2dace62
    ... (MainLoop_runner)
```

Identical function indices *and* identical byte offsets across two
engines with no shared game-specific code is strong evidence this is a
single bug in ScummVM's **common** font-loading/rendering path that
`fonts.dat` feeds (`common/engine_data.cpp`'s generic engine-data loader
is what emits the "Could not locate engine data %s" message both engines
hit before the fix; the crash itself is presumably in whatever consumes
that data to actually draw glyphs -- `graphics/fonts/` or `gui/`).
`sci` was a false lead here: it references `classicmacfonts.dat`, a
*different* file loaded by a separate codepath (`sci/graphics/macfont.cpp`),
not `fonts.dat` -- so KQ5 working normally doesn't contradict this.

**Practical implication:** any other untested engine whose ScummVM
detector reports "Could not locate the 'fonts.dat' engine data file"
should be treated as high-risk for this same crash once the file is
supplied -- expect it to hang at the ScummVM logo splash and then crash,
not actually become playable. Confirmed source references to the literal
string `"fonts.dat"`: `engines/glk/screen.cpp`,
`engines/zvision/zvision.cpp`, `graphics/fonts/ttf.cpp` -- but the
generic loader means any engine could hit it at runtime even without a
static string match, so the reliable signal is the in-app error message
itself, not a source grep. This is a genuine engine/graphics-layer bug in
this WASM build, not a packaging issue -- fixing it would need building
with debug symbols and stepping through the font-rendering code that
consumes `fonts.dat`. Deferred by user decision; engines that hit it get
marked **blocked** (not "deferred" or "needs different packaging") in
`docs/ENGINE-TEST-PLAN.md`.

**Update -- needing `fonts.dat` does NOT guarantee this crash:** `buried`
(The Journeyman Project 2) also needs `fonts.dat`
(`GraphicsManager::createArialFont()` in `engines/buried/graphics.cpp`
falls through to `Graphics::loadTTFFontFromArchive("LiberationSans-Regular.ttf",
...)` when the game's own `arial.ttf`/`arialbd.ttf` aren't present) but
does **not** hit the WASM crash -- it throws a clean, catchable
`error("Failed to load Arial font")` (dropping into ScummVM's own
in-browser debug console) when `fonts.dat` is missing, and once supplied,
renders text and boots into real gameplay with no crash at all. So the
"high-risk" warning above should be read as "if the game's screen goes
blank/hangs after the ScummVM splash," not "any engine that touches
`fonts.dat` is doomed" -- `buried` is proof the same companion file can be
consumed safely by a different code path (direct TTF font rendering via
`graphics/fonts/ttf.cpp`) without tripping the underlying bug that
`griffon`/`glk`/`dm`/`tony`/`neverhood` hit.

**Update -- confirmed independent of file delivery mechanism (2026-09-02):**
once ScummVM's engine-data was embedded directly into the WASM core (see
`docs/superpowers/specs/2026-09-02-wasm-engine-data-embed-design.md`),
all five of `griffon`/`glk`/`dm`/`tony`/`neverhood` were retested with
their bundled `fonts.dat` copy stripped out entirely, relying solely on
the embedded one -- all five still hung on the splash with the identical
out-of-bounds crash. This rules out a corrupted or mismatched bundled
copy as an alternate explanation and confirms it's a deterministic bug in
the font-rendering code itself, not something a different `fonts.dat`
source could ever fix.

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

This project originally built with `USE_HIGHRES=0`, on the assumption
that SCUMM's real 320x200 output would otherwise get padded into a fixed
1280x720 overlay with permanent black bars baked into the canvas's own
framebuffer. **That assumption was wrong, confirmed by live testing after
switching to `USE_HIGHRES=1`: no pillarboxing on any title, lowres or
highres, including while resizing the browser window.** `RES_W_OVERLAY`/
`RES_H_OVERLAY` only seed the *pre-game-load* state (`gui_width`/
`gui_height`, used solely by ScummVM's own generic launcher screen, which
ROMM/EJS titles never actually show since games auto-launch). Once any
game actually loads, `libretro-core.cpp`'s `retro_set_size()` overwrites
`base_width`/`base_height` -- the values `retro_get_system_av_info()`
actually reports to the frontend -- with the game's *real* resolution,
completely independent of these compile-time constants. See the section
below for the distinct, already-fixed *container-shape* pillarboxing
problem, which this isn't either.

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

**Decision for this project: single binary, `USE_HIGHRES=1`.** No
tradeoff turned out to be needed -- one core handles every engine's
resolution correctly, confirmed by actually playing lowres (SCUMM) and
highres (Grim-class) titles side by side with no visible padding on
either. (An earlier version of this doc proposed splitting into two
binaries by resolution profile specifically to avoid pillarboxing; that
was based on the incorrect assumption above and isn't needed.)

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

This maps onto ROMM/EJS as a second named core under the same "ScummVM"
platform, not a separate platform -- ROMM's `_EJS_CORES_MAP` already
takes an array per platform (`scummvm: ["scummvm", "scummvm-hi"]`), the
same mechanism used when one console has multiple valid cores (e.g. NES's
fceumm vs. nestopia). The one real friction: there's no automatic per-ROM
engine detection at the ROMM/EJS layer, since a Grim Fandango zip and a
Monkey Island zip look identical to ROMM (same extension, same platform)
-- the user picks the right core manually per game via EJS's own
core-selector UI, same as any other multi-core EJS platform.

**Whether TinyGL's software rendering actually performs acceptably under
Emscripten/WASM for a real 3D game is a separate, still-open question.**
Compiling proves nothing about runtime behavior -- see the WebMIDI and
save-state sections above for two prior cases where a clean compile hid a
real runtime bug. TinyGL is CPU-only real-time 3D rendering for games
(Grim Fandango, Myst III) that assumed a real GPU on their original
hardware; whether that's fast enough in a browser is unverified.

## `LITE=1` engine lists must name subengines explicitly -- "build-by-default: yes" doesn't cascade

Discovered live-debugging a production report: SCUMM v7/v8 titles (Full
Throttle, The Dig, Curse of Monkey Island) failed with ScummVM's own error
`SCUMM v7-8 support is not compiled in`, despite `scumm` being enabled and
`scumm_7_8` declaring `build-by-default: yes` in `engines/scumm/
configure.engine`. Traced to `configure`'s actual engine-enable mechanism:

- `engine_disable_all()` (called unconditionally whenever `LITE!=0`) sets
  `_engine_<name>_build=no` for *every* registered engine, subengines
  included -- there's no separate "leave subengines alone" case.
- Under `LITE=1`, only names literally present in `lite_engines.list` get
  re-enabled, one `engine_enable()` call per line.
- `engine_enable()` (`configure` line 790) enables exactly the one name
  it's given. It never walks a parent's `subengines` field to also enable
  children -- that cascade only happens in the *non-LITE* desktop build's
  `engine_enable_all()`, a different function entirely.

Net effect: a subengine's own "build-by-default: yes" is meaningless under
`LITE=1` unless that exact subengine name also appears in
`lite_engines.list`, no matter how obviously "on by default" it looks in
`configure.engine`. This affects every engine list in this project built
so far (`all-engines.list`, `gl-core.list`), not just SCUMM -- 23
build-by-default subengines project-wide are never their own top-level
`engines/*/` directory and so never got picked up by scanning directory
names: `scumm_7_8`/`he` (SCUMM), `agos2` (AGOS), `eob`/`lol` (Kyra),
`ihnm` (SAGA), `sci32` (SCI), `ultima4`/`ultima6`/`ultima8` (Ultima),
`mm1`/`xeen` (MM), `myst`/`mystme`/`riven` (Mohawk), `groovie2` (Groovie),
`blueforce`/`ringworld`/`ringworld2` (TSAGE), `versailles` (CryOmni3D),
`foxtail`/`herocraft`/`wme3d` (Wintermute). Fixed by adding all 23
explicitly to the appropriate list (the last 3, Wintermute's, went to
`gl-core.list` alongside their parent).

**Symptom shape worth recognizing**: this fails *late and specifically* --
past packaging, past extraction, past ScummVM's own game-ID detection
(which succeeds, since detection only needs the parent engine's detection
table, not the subengine's runtime code) -- and only at actual launch, with
an engine-specific "X support is not compiled in" message. Don't mistake
this for a packaging or detection bug just because it shows up after both
of those appear to have gone fine.

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

**This fix keeps working fine under `USE_HIGHRES=1`, confirmed by live
testing.** An earlier version of this doc claimed otherwise, reasoning
that `getVideoDimensions("aspect")` would always report the padded
1280x720 overlay under `USE_HIGHRES=1` rather than the game's real
content size. That reasoning was wrong -- see the `USE_HIGHRES` section
above: `retro_set_size()` overwrites the reported resolution with the
actual game's real dimensions once it loads, regardless of
`USE_HIGHRES`, so this section's dynamic-ratio wrapper continues to size
correctly either way.

## Full keyboard input (typing, arrow-key movement) for parser-driven games

Text-parser games (`agi`, `sci`, `hugo`, and any other engine where the
player types commands or moves with raw arrow keys rather than pure
point-and-click) need more than EmulatorJS's default input handling
provides out of the box -- by default EJS maps a fixed retropad-style
button set, not full keyboard passthrough.

The core already supports it: `backends/platform/libretro/src/libretro-core.cpp`
registers a real `retro_keyboard_callback`
(`RETRO_DEVICE_KEYBOARD` is fully wired), and RetroArch's own
`input/drivers/emulatorjs_input.c` forwards raw browser keydown/keyup
events straight to it -- but only when gated on, via
`ejs_set_keyboard_enabled()`. EmulatorJS exposes this as a real,
already-built settings menu item: **Settings (gear icon) → Input Options
→ "Direct Keyboard Input" → Enabled**. No rebuild, no redeploy -- it's a
per-session player-facing toggle, off by default, that a player can flip
on before a parser-driven game and off again afterward.

**Why this isn't set as a default for the whole core:** the setting is
inherently per-*core*, not per-game -- ScummVM is one shared EJS core
across every title, so there's no ROMM/EJS mechanism to default this to
"on" only for `agi`/`sci`/`hugo` while leaving it "off" for
point-and-click games (`config.yml`'s `emulatorjs.settings.scummvm.*`
per-core override, the same mechanism already used for `lockMouse`, would
apply to the whole core). Whether raw keyboard passthrough is actually
harmless for point-and-click games (Monkey Island, Broken Sword, etc.) --
inert extra key events vs. double-firing against ScummVM's own existing
keyboard shortcuts (Esc to skip, F5 for the in-game menu) -- hasn't been
tested. Decided to leave it as a manual per-session toggle rather than a
core-wide default until/unless that's actually verified safe.

There's also a related "Forward Alt key" toggle (`altKeyboardInput`,
also off by default) for games that need Alt as a real modifier rather
than EJS's own hotkey use of it.

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

## Subdirectory-structured engines: anchor placement no longer matters (fixed 2026-09-02)

**Measured impact (2026-09-04).** Re-checked against the 435 zips of the
official ScummVM collection by replaying EmulatorJS's own selection rule
(first entry whose extension matches the core's declared extensions, else
entry zero -- and no real ScummVM zip contains a `.scummvm` file, so it is
always entry zero). 22 of the 435 (5%) pick a file inside a subdirectory
and would therefore have failed detection before this fix, including
stock dumps of Full Throttle, Gabriel Knight, Toonstruck, Beavis CD
Windows, Maniac Mansion NES and four Living Books titles. So this was a
real defect affecting ordinary unmodified ROMs, not an artifact of any
locally repackaged archive. Note also that 13 of those 22 *do* have
root-level files and still failed, because a subdirectory sorted ahead of
them -- which is why "keep a root-level file" never worked reliably.

For engines that need their original subdirectory structure preserved
(`griffon`, `toon`, `ultima8`, etc. -- see "Zips with subdirectories but
no file at the true root" above for the general rule), there used to be a
second, narrower trap specific to *multi-subdirectory* detection entries:
whichever file EmulatorJS's `fileNames[0]` heuristic happened to pick as
the anchor determined which single directory ScummVM's autodetect scan
actually looked in -- not the zip's top level.

Traced end to end while packaging `ultima8` (Ultima VIII: Pagan): a GOG
repack's `usecode/eusecode.flx` hash-matched the "Gold Edition" detection
entry in `engines/ultima/detection_tables.h` exactly, but that entry also
requires `static/eintro.skf` -- a sibling directory. Packaging with
`usecode/eusecode.flx` as the anchor (first zip entry) produced an empty
ScummVM launcher with no error at all, not a "file not found" message.
The cause was in `backends/platform/libretro/src/libretro-core.cpp`'s
`retro_load_game()`:

```cpp
Common::FSNode detect_target = Common::FSNode(game->path);
Common::FSNode parent_dir = detect_target.getParent();
...
test_game_status = LIBRETRO_G_SYSTEM->testGame(parent_dir.getPath().toString().c_str(), true);
```

`game->path` is EmulatorJS's chosen anchor file (`fileNames[0]`, per the
zip-entry-order rule documented elsewhere in this file). `testGame()`
then calls `dir.getChildren(files, ...)` on `parent_dir` -- the anchor
file's *own* folder, not the archive root. With the anchor nested inside
`usecode/`, ScummVM's scan never saw anything in `static/`, so the
two-file entry could never match, silently. (`toon` and `griffon` didn't
hit this in their originally-tested packaging because their required
companion files happened to live in the same folder as their anchor --
but see below, this was luck, not a property of those engines: `toon`'s
own German retail release genuinely needs three sibling directories and
hit the identical failure once actually tested against it.)

**This is now fixed permanently at the core level, not a packaging
workaround.** `retro_load_game()` was traced against EmulatorJS's actual
`downloadRom()` (`test-page/ejs/data/src/emulator.js`), which extracts
every file in a ROM's zip preserving its full relative path, always
writing to the virtual filesystem's true root (`/`) -- confirmed by
reading the extraction code directly
(`this.gameManager.FS.writeFile(`/${fileName}`, fileData)`), not assumed.
This means `/` in this WASM deployment is *always* exactly and only the
current ROM's fully-extracted content tree, regardless of which
arbitrary file `fileNames[0]` happened to select -- unlike a real
desktop/native libretro deployment, where content from many unrelated
games might legitimately share one filesystem and restricting the scan
to "near the specific file you were told to load" is necessary and
correct.

The fix, guarded to this WASM build only (using the `EMSCRIPTEN` define
this Makefile already sets -- see `overrides.mk`'s own comment on why
it's `EMSCRIPTEN` and not `__EMSCRIPTEN__`), forces `parent_dir` to
always be the virtual-FS root instead of deriving it from `game->path`:

```cpp
#ifdef EMSCRIPTEN
	Common::FSNode parent_dir = Common::FSNode(Common::Path("/"));
#else
	Common::FSNode parent_dir = detect_target.getParent();
#endif
```

Native/desktop builds of this same shared source are completely
unaffected -- the `#else` branch is untouched. Verified against the
*original, completely unmodified* German Toonstruck retail dump (needing
`misc/local.pak` + `act1/arcaddbl/arcaddbl.svl` + `act2/study/study.svl`
-- three sibling top-level directories, with `toon`'s own
`directoryGlobs`/`_maxScanDepth=3` already declaring all of them), no
anchor repackaging at all -- this specific zip has **zero** root-level
files at all, every entry nested under one of four sibling top-level
directories -- booted straight into the real intro FMV with live audio.
**No ROM ever needs a carefully-placed (or even present) root-level
anchor file for detection/autodetect purposes again**, single-directory
or multi-directory. The only remaining case where `fileNames[0]` still
matters is the `.scummvm` hook file (see further down), since that
specific check is on `game->path` itself, not on the scan root this fix
changes.

## Packaging by hand-picking only the detection-matching files is risky -- package the complete game data instead

ScummVM's detection only checks 2-3 fingerprint files (an
`AD_ENTRY`/`AD_ENTRY2s` tuple) to *identify* a game -- it says nothing
about every file the engine's actual runtime code will read once the
game is running. Two confirmed cases this sweep hit this exact class of
bug from hand-picking a "minimal" file set based on what detection
needs, rather than packaging the complete original game data:

- **`groovie`**: a minimal zip containing only the two hashed files
  passed detection cleanly, then crashed at runtime on missing
  `icons.ph`/`sample.AD`/`sample.OPL` -- present on the original disc,
  absent from detection's checklist.
- **`alg`** (Crime Patrol): packaging hand-picked the 6 files matching
  the detection entry from the installer ISO, explicitly skipping
  `CPSS.LIB` and a dozen small `.8B`/`.ANI`/`.VGA` resource files as "not
  part of the detection entry." Detection passed, the game launched, then
  crashed to ScummVM's debug console on `_sceneInfo->loadScnFile("cp.scn")`
  (`engines/alg/logic/game_crimepatrol.cpp:79`) -- `CP.SCN`, a plain
  hardcoded filename the engine reads directly, was never included.

**Default to packaging the complete original game directory/disc/ISO
contents** (everything, minus obviously-irrelevant installer-only
cruft like setup wizards or an unrelated bundled demo folder), not a
subset curated around what the detection table happens to name. Given
this project's current ~1GB size budget, most games have plenty of room
to include everything -- there's rarely a real reason to hand-pick.
Reserve trimming for genuinely oversized cases (e.g. a full-game CD-audio
soundtrack when only enough to boot is needed), and when you do trim,
treat every excluded file as a real risk until the game is confirmed
booting into actual gameplay, not just past the ScummVM detection
screen.

## Exact size AND 5000-byte-prefix hash match still doesn't guarantee an intact file

`pink` (The Pink Panther: Passport to Peril) found a failure mode beyond
the ones above: `PPTP.ORB` matched the English detection entry's declared
size (618203600 bytes) *and* its 5000-byte-prefix MD5 exactly, yet
ScummVM's own engine-startup detection (`AdvancedMetaEngineDetection::
createInstance()`) still failed with `Common::kNoGameDataFoundError`
("Game data not found"). Direct WASM-filesystem inspection confirmed the
file was genuinely present, correctly sized, with an intact zip CRC --
not a packaging problem. A `.scummvm` hook file targeting the exact
gameId directly (`pink:peril`) produced the identical error, ruling out
an autodetect-path issue too.

Root cause, found by sourcing an entirely different dump (a `.bin`/`.cue`
CD image from [MyAbandonware](https://www.myabandonware.com/game/the-pink-panther-passport-to-peril-e79),
converted to ISO, extracted, DirectX redistributable files removed): the
new `PPTP.ORB` has the **identical** size and 5000-byte-prefix hash as
the original broken dump, but plays correctly. This proves the original
file was corrupted or incomplete somewhere in the ~618MB *beyond* the
first 5000 bytes checked by ScummVM's own detection, and beyond the
whole-file byte count checked by this project's sizing verification --
neither check this project relies on can catch that class of corruption.
Likely cause: a botched original CD-to-file extraction (e.g. a sector-
alignment error) that happens to preserve both the file's start and its
total length while scrambling data further in.

**Takeaway:** if a game fails at ScummVM's own engine-startup detection
despite the anchor file matching both the declared size and the 5000-byte
prefix hash exactly -- and the WASM filesystem inspection confirms the
file is genuinely present with no zip-level corruption -- suspect a bad
rip/extraction of the *specific dump*, not a packaging or core bug.
Sourcing a completely different dump (different site, different
extraction method) is a legitimate, sometimes necessary troubleshooting
step even when every automated check this project runs says the file
looks correct.

## The "flaky" ENOTDIR extraction error: zips carrying explicit directory entries (root cause found 2026-09-04)

The intermittent `Uncaught ErrnoError {name: 'ErrnoError', errno: 20}`
during EmulatorJS's ROM extraction is neither flaky nor random. errno 20
is ENOTDIR, and the trigger is a property of the zip file alone.

**Mechanism.** EmulatorJS's `decompressFile` callback creates each parent
directory while walking a file's path (`FS.analyzePath(i).exists ||
FS.mkdir(i)`), and then separately calls `FS.mkdir(t)` for any entry whose
name ends in `/`. Most zip writers store only file paths and let the
extractor infer folders. Some also store standalone directory entries
(`data/`, `art/`, ...). When a zip has both, the folder is created by the
path walk and then created again from the standalone entry, and the second
call throws.

**Measured correlation** across the 12 ROMs tested that day:

| ROM | explicit dir entries | ErrnoErrors in console |
|---|---|---|
| Griffon Legend | 5 | 5 |
| the other 11 | 0 | 0 |

Griffon's zip stores `data/`, `mapdb/`, `music/`, `sfx/` and `art/`, and
produced exactly five errors in each of four separate test sessions.

**Consequence.** Benign in this case -- the directory already exists, so
the throw is swallowed at the worker boundary and the game plays. It is
worth knowing about because it is the same error that has previously been
blamed for extraction failures, and because it is a property of the
archive rather than of the game or the core. Nothing to fix on our side;
it is EmulatorJS's extractor.

**Detection gotcha that cost real time:** the console prints
`ErrnoError {errno: 20}`, never the string "ENOTDIR". Grepping a saved log
for "ENOTDIR" always returns zero and looks like a clean run. Grep for
`ErrnoError` instead.

## Quitting can hang the browser tab if an engine drops EVENT_QUIT (fixed 2026-09-04)

Exiting Griffon Legend froze the tab with nothing logged at all.

`close_emu_thread()` in libretro-core.cpp looped without a bound: each pass
pushes an `EVENT_QUIT` and hands the emulator thread a timeslice, waiting
for the engine to observe it and return from `scummvm_main()`. An engine
that keeps yielding but never observes the quit spins there forever, and
because the loop runs on the frontend's own thread the tab locks up with no
diagnostic whatsoever. Now bounded, with a warning, tearing down regardless.

Griffon triggers it: `GriffonEngine::checkInputs()` returns early while
`_attacking` or `_forcePause` is set, and that early return sat *above* the
`EVENT_QUIT` check, so a quit arriving in either state was discarded
outright. Upstream ScummVM has the same ordering -- harmless on desktop,
where the window manager closes the window regardless of what the engine
thinks, and fatal here, where the frontend waits for acknowledgement.

If another engine ever hangs on exit, look for the same shape: an early
return in the engine's event handler placed ahead of its quit check.
