# Build Pipeline

This walks through what each script under `build/` (and
`test-page/download-emulatorjs.sh`) actually does, in the order you run
them, and why each step exists. For *why specific flags are needed* (as
opposed to *what the scripts do*), see [GOTCHAS.md](GOTCHAS.md) -- this
doc cross-references it rather than repeating it.

Run order:

```
setup-emsdk.sh  ->  build-core.sh  ->  build-retroarch-core.sh  ->  package-core.sh
                                                                     (+ download-emulatorjs.sh, any time)
```

## `build/setup-emsdk.sh`

One-time toolchain install. Clones
[emscripten-core/emsdk](https://github.com/emscripten-core/emsdk) into
`toolchain/emsdk` (skipped if it already exists), then runs
`./emsdk install latest && ./emsdk activate latest`.

`toolchain/` is gitignored -- every other script in this pipeline
`source`s `toolchain/emsdk/emsdk_env.sh` to put `emcc`/`em++`/`emmake` on
`PATH` for that script's process only, so re-running this once per clone
is enough; you don't need to activate it in your interactive shell.

The emsdk version is intentionally **not pinned** to a specific release
tag -- this project always builds against whatever `latest` currently
resolves to. See the "Known limitations" note in the README: if a future
emsdk release changes behavior, this is the first thing to check via
`git log` on the emsdk repo or by pinning to the version this was last
verified against.

## `build/build-core.sh`

Compiles ScummVM itself (not yet linked into a libretro core) via its own
`backends/platform/libretro/Makefile`, targeting `platform=emscripten`.
Produces `scummvm-core/backends/platform/libretro/scummvm_libretro_emscripten.bc`
-- an LLVM bitcode archive, not yet a `.wasm` -- which the next script
consumes.

Two things happen before the actual `emmake make` call:

1. **`echo "scumm" > scummvm-core/backends/platform/libretro/lite_engines.list`**
   scopes the entire build to the SCUMM engine only. ScummVM's libretro
   port supports building a subset of its ~25 engines via this file (one
   engine name per line) instead of compiling all of them, which would
   both bloat the `.wasm` and multiply the maintenance/testing surface far
   beyond this project's actual target games. See
   [ADDING-ENGINES.md](ADDING-ENGINES.md) if you want to add another
   engine here.
2. **`source toolchain/emsdk/emsdk_env.sh`** activates the toolchain for
   this script's process.

The actual build:

```bash
cd scummvm-core/backends/platform/libretro
EMCC_CFLAGS="-pthread -sSHARED_MEMORY" emmake make platform=emscripten LITE=1 -j"$(nproc)"
```

- `platform=emscripten` selects the Makefile's Emscripten-specific block
  (compiler, linker, and source-file selection all change here --
  e.g. it's what pulls in `fs/emscripten/*.cpp` from
  `backends/module.mk`).
- `LITE=1` is this Makefile's own flag for "build only the engines listed
  in `lite_engines.list`", paired with step 1 above.
- `EMCC_CFLAGS="-pthread -sSHARED_MEMORY"` (environment variable, not a
  make command-line override) adds real-pthread compile support. This
  **must** use the `EMCC_CFLAGS` env var, not `make CXXFLAGS=...` --
  see GOTCHAS.md's "Passing extra compiler flags" entry for exactly why
  the command-line-override form silently breaks the build with no error.

Output: `scummvm_libretro_emscripten.bc`, listed via `ls -la` at the end
so a successful run is visually confirmed (size is typically in the tens
of MB; a suspiciously small file, or a `.bc` from hours before your
source edit, means something silently didn't rebuild -- see GOTCHAS.md's
stale-archive section).

## `build/build-retroarch-core.sh`

Links the `.bc` from the previous step into an actual libretro core using
RetroArch's own `Makefile.emulatorjs` (a make target EmulatorJS's
maintainers added to RetroArch specifically for producing
Emscripten/EmulatorJS-compatible cores -- this is not a generic RetroArch
build target).

```bash
cp -f scummvm-core/backends/platform/libretro/scummvm_libretro_emscripten.bc \
      retroarch/libretro_emscripten.a
```

`Makefile.emulatorjs` expects the core's compiled object code as
`libretro_emscripten.a` inside the `retroarch/` tree -- this copy (really
a rename; a `.bc` LLVM bitcode file works fine passed to `ar`/`wasm-ld` as
if it were a `.a`) is how the two independent build systems (ScummVM's
own Makefile, and RetroArch's) hand off to each other. There's no shared
build system between the two submodules; this file copy *is* the
integration point.

```bash
cd retroarch
EMCC_CFLAGS="--pre-js ../build/midi-stub-pre.js" emmake make -f Makefile.emulatorjs \
  LD=em++ \
  HAVE_7ZIP=1 HAVE_CHD=1 \
  HAVE_THREADS=1 PTHREAD_POOL_SIZE=4 \
  ASYNC=1 HAVE_OPENGLES3=1 \
  STACK_SIZE=16777216 INITIAL_HEAP=134217728 \
  TARGET=scummvm_libretro.js \
  -j"$(nproc)"
```

Flag-by-flag (see GOTCHAS.md for the *why* behind each of these where a
real bug was involved):

- `LD=em++` -- required for C++ RTTI/`libc++abi` linking; the default
  `emcc` link driver fails without it.
- `HAVE_7ZIP=1 HAVE_CHD=1` -- enable RetroArch's built-in archive-format
  support (7z/CHD), unrelated to any bug fix; ScummVM game data isn't
  normally shipped in these formats for this project's target games, but
  there's no reason to disable them.
- `HAVE_THREADS=1 PTHREAD_POOL_SIZE=4` -- real-pthread support, must match
  `build-core.sh`'s `-pthread` compile flag or linking fails with a
  `wasm-ld` shared-memory feature mismatch error.
- `ASYNC=1` -- Emscripten Asyncify, needed because ScummVM's engine loop
  makes blocking calls (e.g. waiting on user input) that must yield back
  to the browser's event loop rather than actually blocking the one JS
  thread.
- `HAVE_OPENGLES3=1` -- matches the `-thread` (non-`-legacy`) EmulatorJS
  packaging convention `package-core.sh` uses; see that script and
  GOTCHAS.md's packaging section.
- `STACK_SIZE=16777216` (16MB) -- raised from Emscripten's 4MB default;
  a real, necessary fix for a genuine native stack overflow. See
  GOTCHAS.md -- and don't confuse this with `ASYNCIFY_STACK_SIZE`, a
  separate, much smaller Asyncify-only bookkeeping stack hardcoded
  elsewhere in `Makefile.emulatorjs`.
- `INITIAL_HEAP=134217728` (128MB) -- initial WASM linear memory heap
  size; the CD/talkie games (Fate of Atlantis, Day of the Tentacle) are
  tens to over a hundred MB of game data loaded into the virtual
  filesystem, so the default heap isn't enough headroom.
- `EMCC_CFLAGS="--pre-js ../build/midi-stub-pre.js"` -- injects a stub
  `var midiOutputMap = new Map();` global before the module's own code
  runs. Kept as defense-in-depth even though the WebMIDI plugin that used
  to need it is now fully excluded at the ScummVM-source level (see
  GOTCHAS.md's WebMIDI section) -- nothing currently reads this global,
  but it's harmless to leave in place.
- `TARGET=scummvm_libretro.js` -- names the output files
  (`scummvm_libretro.js` / `.wasm`).

Output: `retroarch/scummvm_libretro.js` and `retroarch/scummvm_libretro.wasm`.

## `build/package-core.sh`

Repackages the two RetroArch output files into the single `.data`
container EmulatorJS's loader expects, under the naming convention it
looks for:

```bash
rm -f test-page/ejs/data/cores/scummvm-wasm.data \
      test-page/ejs/data/cores/scummvm-legacy-wasm.data

7z a -y test-page/ejs/data/cores/scummvm-thread-wasm.data \
  retroarch/scummvm_libretro.wasm retroarch/scummvm_libretro.js
```

The `rm -f` first removes any stale non-thread-suffixed names from
earlier testing (this project always builds with `HAVE_THREADS=1`, so
those names should never exist as real output -- only as leftovers).
`7z a` (add to archive) bundles the `.js`+`.wasm` pair into one `.data`
file named `scummvm-thread-wasm.data`, per the `-thread`/`-legacy` naming
convention EmulatorJS's loader parses to detect a core's capabilities
(see GOTCHAS.md's packaging section for the full naming-convention
explanation and a caveat about also keeping a `-legacy`-suffixed copy in
sync until this project ships a real core-report JSON).

Output: `test-page/ejs/data/cores/scummvm-thread-wasm.data`, the file
`test-page/index.html` (via `EJS_core = "scummvm"`) tells EmulatorJS's
loader to fetch.

## `test-page/download-emulatorjs.sh`

Not part of the core-build pipeline proper -- fetches the EmulatorJS
*frontend* itself (the JS/HTML/CSS that renders the player UI, handles
zip extraction, settings menus, etc.), pinned to release `4.2.3`:

```bash
curl -sL -o ejs.7z "https://github.com/EmulatorJS/EmulatorJS/releases/download/v4.2.3/4.2.3.7z"
mkdir -p ejs
7z x -y ejs.7z -o./ejs
rm ejs.7z
```

Skips the download entirely if `test-page/ejs/data/loader.js` already
exists, so it's safe to re-run. `test-page/ejs/` is gitignored -- run
this once per clone, same as `setup-emsdk.sh`. The version is pinned
(unlike emsdk) because this project's `-thread`/`-legacy` naming-convention
assumptions were verified against this specific EmulatorJS release; a
newer release's loader logic isn't guaranteed to parse core filenames the
same way.

## Serving

None of the above starts a server. `test-page/serve-coop-coep.py` does,
on port 8934, adding the `Cross-Origin-Opener-Policy` /
`Cross-Origin-Embedder-Policy` headers real pthreads require and a
`Cache-Control: no-store` header so repeated rebuilds during development
can't be masked by browser caching. See the README's "Why a custom server
script?" section and GOTCHAS.md for both of these.
