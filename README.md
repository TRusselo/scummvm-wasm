# scummvm-wasm

A WebAssembly build of [ScummVM](https://www.scummvm.org/)'s SCUMM engine,
packaged as an [EmulatorJS](https://emulatorjs.org/) libretro core, so
LucasArts SCUMM adventure games can be played directly in a browser.

**Status: work in progress, but functional.** All six original target
games boot and play (video, audio, mouse, and gamepad input all
confirmed working):

- Maniac Mansion
- Zak McKracken and the Alien Mindbenders
- Loom
- Indiana Jones and the Last Crusade
- Indiana Jones and the Fate of Atlantis (including the CD/talkie version,
  with full voice acting)
- Day of the Tentacle (including the CD/talkie version)

This is not an official ScummVM or EmulatorJS project. It's a from-scratch
wiring-together of two existing, independently-working projects
([libretro/scummvm](https://github.com/libretro/scummvm) and
[EmulatorJS/RetroArch](https://github.com/EmulatorJS/RetroArch)) that had
never actually been built for this specific combination (SCUMM engine +
Emscripten + real pthreads + EmulatorJS's packaging conventions) before.
Most of the value here isn't the code -- it's the accumulated knowledge of
*why* each build flag exists and what breaks without it. See
[docs/GOTCHAS.md](docs/GOTCHAS.md) if you're extending this project;
almost everything non-obvious in the build scripts is explained there,
not just asserted.

## Quickstart

```bash
git clone --recurse-submodules https://github.com/TRusselo/scummvm-wasm.git
cd scummvm-wasm

# One-time toolchain setup (installs the Emscripten SDK under toolchain/emsdk)
bash build/setup-emsdk.sh

# Build the ScummVM core, link it into RetroArch, package it for EmulatorJS
bash build/build-core.sh
bash build/build-retroarch-core.sh
bash build/package-core.sh

# Fetch the EmulatorJS frontend (pinned to v4.2.3, matches what this was
# tested against)
bash test-page/download-emulatorjs.sh

# Serve the test page (plain http.server won't work -- see why below)
python3 test-page/serve-coop-coep.py
```

Then add a game: zip a directory of `.LFL`/`.000`/`.001`/`.SOU` files
**flat, with no parent folder inside the zip** (see
[Adding a game](#adding-a-game) below), rename it to `<name>.scm`, drop it
in `test-page/`, and point `EJS_gameUrl` in `test-page/index.html` at it.
Open `http://localhost:8934/index.html`, click into the canvas once (the
browser won't allow audio or pointer lock before a user gesture), and the
game should boot straight to its title screen.

## Why a custom server script?

Emscripten's real-pthread support (`HAVE_THREADS=1`, required -- see
[docs/GOTCHAS.md](docs/GOTCHAS.md)) needs `SharedArrayBuffer`, which
browsers only expose on cross-origin-isolated pages. That requires two
response headers (`Cross-Origin-Opener-Policy: same-origin` and
`Cross-Origin-Embedder-Policy: require-corp`) that plain
`python3 -m http.server` doesn't send. `test-page/serve-coop-coep.py` is a
tiny `http.server` subclass that adds them, plus a `Cache-Control:
no-store` header so a browser reload during development can't silently
serve a stale core after a rebuild.

## Architecture

```
scummvm-wasm/
├── scummvm-core/     git submodule -> a fork of libretro/scummvm
│                     (see below for why it's a fork, not upstream)
├── retroarch/        git submodule -> EmulatorJS/RetroArch (branch "next")
├── build/            build scripts, run in order: build-core.sh ->
│                     build-retroarch-core.sh -> package-core.sh
├── test-page/        a minimal EmulatorJS embed page for local testing;
│                     ejs/ (the actual EmulatorJS frontend) is downloaded
│                     by download-emulatorjs.sh, not committed
├── toolchain/        emsdk, installed by setup-emsdk.sh, not committed
└── docs/
    ├── GOTCHAS.md            <- read this first if something breaks
    ├── BUILD.md              <- what each build script actually does, and why
    ├── ADDING-ENGINES.md     <- extending beyond SCUMM to other ScummVM engines
    └── superpowers/          detailed session-by-session investigation
                              history (specs, plans, diagnostic notes) --
                              useful for archaeology, not a starting point
```

The build produces one thing: a libretro core (`scummvm_libretro.js` /
`.wasm`) built from ScummVM's own `backends/platform/libretro` port,
linked using RetroArch's `Makefile.emulatorjs` (which knows how to produce
the specific `.data`/`.js`/`.wasm` triple and naming convention EmulatorJS's
loader expects), then packaged into that naming convention by
`package-core.sh`.

### Why `scummvm-core` points at a fork, not upstream

One real source patch was needed to make ScummVM's SCUMM engine boot
correctly in this specific build (excluding a plugin whose JS glue only
works in ScummVM's own standalone-Emscripten shell -- see
[docs/GOTCHAS.md](docs/GOTCHAS.md)'s WebMIDI section for the full story).
Since there's no push access to `libretro/scummvm` upstream, that one
commit lives on a dedicated `emulatorjs-wasm-fixes` branch on
[TRusselo/scummvm](https://github.com/TRusselo/scummvm), and
`.gitmodules` points there instead of upstream. If you fork this whole
project, you may want to fork `scummvm-core` too and repoint
`.gitmodules` at your own fork, or open a PR against the
`emulatorjs-wasm-fixes` branch above.

## Adding a game

ScummVM's file-based auto-detection expects a game's data files sitting
directly in one directory (no subfolder). EmulatorJS's generic
zip-extraction writes every zip entry to the filesystem root by basename,
regardless of the path recorded inside the zip -- so the safest approach,
proven across all six target games, is to **zip the contents of the
game's data folder directly (`cd` into it first), never the folder
itself**:

```bash
cd "/path/to/Game Folder"
python3 -c "
import zipfile, sys
from pathlib import Path
src = Path('.')
with zipfile.ZipFile('/tmp/game.zip', 'w', zipfile.ZIP_DEFLATED) as zf:
    for f in sorted(src.iterdir()):
        if f.is_file():
            zf.write(f, arcname=f.name)
"
mv /tmp/game.zip path/to/scummvm-wasm/test-page/game.scm
```

(A plain `zip` binary wasn't available in the environment this was
developed in -- Python's `zipfile` module works identically and is always
available. Either works; the flat-structure requirement is what matters,
not the tool.)

Older SCUMM games (Maniac Mansion, Zak McKracken, Loom, Indiana Jones and
the Last Crusade) use numbered `NN.LFL` files. Newer ones (Indiana Jones
and the Fate of Atlantis, Day of the Tentacle) use a `<NAME>.000` /
`<NAME>.001` / `MONSTER.SOU` container format -- both are handled
transparently by the same ScummVM SCUMM engine and the same zip-flat
convention.

**Maniac Mansion note:** the original Day of the Tentacle CD release
bundles a complete, separately-playable copy of Maniac Mansion as an
in-game easter egg (found on the original disk under a `MANIAC/`
subfolder). If you don't have a standalone Maniac Mansion copy, that one
works identically -- it's the real, complete game, not a demo.

Game files (`test-page/*.scm`) are gitignored; this repo ships no
copyrighted game data.

## Known limitations

- EmulatorJS's generic save-state UI (its own "Save State" menu entry,
  independent of ScummVM's built-in save/load) doesn't work -- the SCUMM
  libretro core's `_save_state_info` doesn't return what EmulatorJS's
  `GameManager.getState()` expects. This was an intentional scope
  decision, not an oversight: ScummVM's own in-game save-anywhere/
  load-anywhere system works fine and was always the intended save
  mechanism for this project. See docs/GOTCHAS.md if you want to fix the
  generic path anyway.
- Only manually tested via a real browser (Chrome), not covered by any
  automated test suite.
- The Emscripten SDK version is not pinned (`setup-emsdk.sh` installs
  `latest`) -- this build was verified against whatever "latest" resolved
  to in August 2026. If a future emsdk release breaks something, that's
  the first thing to check.

## Contributing

Read [docs/GOTCHAS.md](docs/GOTCHAS.md) before touching the build scripts
-- several things in there look like they could be simplified or removed
and are load-bearing. [docs/ADDING-ENGINES.md](docs/ADDING-ENGINES.md) is
a head start if you want to extend this beyond the SCUMM engine to other
engines ScummVM supports.
