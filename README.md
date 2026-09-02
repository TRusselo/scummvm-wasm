# scummvm-wasm

A WebAssembly build of [ScummVM](https://www.scummvm.org/) — all 102
non-OpenGL engines it supports, not just SCUMM — packaged as an
[EmulatorJS](https://emulatorjs.org/) libretro core, so ScummVM-supported
adventure games can be played directly in a browser.

**Status: work in progress, but functional.** The project started as a
SCUMM-only build; that scope is now the most thoroughly validated part of
it. All six original target games boot and play (video, audio, mouse, and
gamepad input all confirmed working):

- Maniac Mansion
- Zak McKracken and the Alien Mindbenders (EGA and FM TOWNS VGA)
- Loom
- Indiana Jones and the Last Crusade
- Indiana Jones and the Fate of Atlantis (including the CD/talkie version,
  with full voice acting)
- Day of the Tentacle (including the CD/talkie version)

Since then the build itself was widened to include every other ScummVM
engine that doesn't require OpenGL (103 engines total, SCUMM plus 102
more — see `build/engine-lists/all-engines.list`), and a systematic sweep
is underway to source a real game and confirm each one actually boots and
plays, not just compiles. **34 of 102 confirmed working as of this
writing** — see the full status table below, or
[docs/ENGINE-TEST-PLAN.md](docs/ENGINE-TEST-PLAN.md) for the complete
per-engine sourcing notes and packaging quirks behind each result.

<img width="1890" height="1180" alt="image" src="https://github.com/user-attachments/assets/860f20a3-a6f2-4d12-8f6b-e7d2b9f532ce" />

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

## Engine Status

Legend: ✅ confirmed working (a real game boots and plays) · 🚫 blocked
(packaged correctly, blocked by an engine/core bug) · ⏸️ deferred
(sourcing/tooling blocker, not yet worked around) · 🔒 blocked on a
separate OpenGL core build that doesn't exist yet · ❓ engine not
confidently identified · ⬜ not yet attempted · ⚠️ worked, excluded on
purpose

**34 of 102 confirmed** (plus the `agos2` subengine). 4 blocked on a
shared crash, 6 deferred on sourcing/tooling, 11 waiting on a GL-core
build that hasn't happened yet, 3 unidentified, the rest untested. Full
narrative detail (what game, what source, what broke, how it was fixed)
lives in [docs/ENGINE-TEST-PLAN.md](docs/ENGINE-TEST-PLAN.md) — this
table is the at-a-glance summary, kept in sync with it.

<details>
<summary><strong>Widely Known</strong> (20 engines)</summary>

| Engine | Status | Notes |
|---|---|---|
| agi | ✅ | King's Quest I; also Leisure Suit Larry 1-3, Space Quest I-III |
| glk | 🚫 | `fonts.dat`-related WASM crash, shared with `griffon`/`dm`/`tony` |
| awe | ✅ | Another World |
| dm | 🚫 | Same shared `fonts.dat` WASM crash |
| sword1 | ✅ | Broken Sword — full game, both CDs merged |
| sword2 | ✅ | Broken Sword II — full game, both CDs merged |
| sci | ✅ | King's Quest V |
| bladerunner | ⬜ | Only realistic candidate is CD-heavy, no smaller alt |
| ultima | ⬜ | Via `ultima8` subengine (Ultima VIII) |
| twine | ⏸️ | Only accessible copy is a French CD image, needs disk-image tooling |
| mohawk | ✅ | Via Myst (original candidate, Zoombinis, is `ADGF_UNSUPPORTED`) |
| mediastation | ⬜ | |
| nancy | ⬜ | |
| groovie | ⬜ | |
| sky | ✅ | Beneath a Steel Sky, official freeware |
| adl | ✅ | Mystery House, bundled ScummVM freeware |
| lastexpress | ⬜ | |
| ags | ✅ | Via 5 Days a Stranger (Chzo Mythos), freeware |
| toon | ⬜ | |
| startrek | ⏸️ | Only raw floppy disk images found, needs disk-image tooling |

</details>

<details>
<summary><strong>Genre-Notable</strong> (43 engines)</summary>

| Engine | Status | Notes |
|---|---|---|
| kyra | ✅ | Legend of Kyrandia: Book One |
| mm | ⬜ | Parent engine, no standalone game of its own (see `xeen`) |
| tsage | ⬜ | Parent engine, no standalone game of its own (see `ringworld2`) |
| sherlock | ✅ | The Case of the Serrated Scalpel |
| queen | ✅ | Flight of the Amazon Queen, official freeware |
| lure | ✅ | Lure of the Temptress, freed by Revolution Software |
| gob | ✅ | Gobliiins, with music |
| cine | ✅ | Future Wars |
| cruise | ✅ | Cruise for a Corpse |
| cryo | ⬜ | |
| cryomni3d | ⬜ | |
| darkseed | ✅ | Dark Seed |
| dgds | ✅ | Via Heart of China |
| director | ⬜ | |
| dragons | ⬜ | |
| drascula | ✅ | Drascula: The Vampire Strikes Back |
| dreamweb | ✅ | DreamWeb, freeware since 2011 |
| griffon | 🚫 | Same shared `fonts.dat` WASM crash |
| hopkins | ⬜ | |
| hugo | ✅ | Hugo's House of Horrors |
| icb | ⬜ | |
| immortal | ⏸️ | Apple IIgs-only engine, no clean disk dump found |
| lab | ⏸️ | No usable DOS/Windows package found |
| macventure | ⏸️ | Mac/Apple IIgs-only engine, needs HFS disk-image tooling |
| made | ✅ | Via Rodney's Funscreen |
| mads | ⏸️ | Only raw floppy disk images found |
| mtropolis | ⬜ | |
| neverhood | ⬜ | |
| parallaction | ✅ | The Big Red Adventure, official freeware |
| pegasus | ⬜ | |
| buried | ⬜ | |
| plumbers | ⬜ | |
| private | ⬜ | |
| saga | ✅ | I Have No Mouth, and I Must Scream |
| sludge | ⚠️ | Worked (The Interview) but excluded — unsigned `.exe`, engine marked unstable/WIP by ScummVM itself |
| titanic | ⬜ | |
| tony | 🚫 | Same shared `fonts.dat` WASM crash |
| touche | ✅ | Touché: The Adventures of the Fifth Musketeer |
| voyeur | ⬜ | |
| zvision | ⬜ | |
| asylum | ⬜ | |
| sword25 | ✅ | Broken Sword 2.5, official freeware fan game |
| agos | ✅ | Simon the Sorcerer (base + `agos2` subengine via Simon 2) |

</details>

<details>
<summary><strong>Niche/Obscure</strong> (36 engines)</summary>

| Engine | Status | Notes |
|---|---|---|
| access | ⬜ | |
| agds | ⬜ | |
| alg | ⬜ | |
| avalanche | ⬜ | |
| bagel | ⬜ | |
| bbvs | ⬜ | |
| cge | ✅ | Soltys, bundled ScummVM freeware |
| cge2 | ✅ | Sfinx, official English release |
| chamber | ⬜ | |
| chewy | ⬜ | No official English release |
| composer | ⬜ | |
| draci | ⬜ | Community English translation exists |
| efh | ⬜ | |
| gnap | ⬜ | Low confidence on title identification |
| hadesch | ⬜ | Low confidence on title identification |
| hdb | ⬜ | |
| hypno | ⬜ | Low confidence on title identification |
| illusions | ⬜ | |
| kingdom | ⬜ | |
| lilliput | ⬜ | |
| m4 | ⬜ | |
| mortevielle | ⬜ | French-origin, English availability unclear |
| mutationofjb | ⬜ | Commercial Slovak/German-only release, no legitimate free English source |
| ngi | ⬜ | Russian-primary |
| petka | ⬜ | Russian-only |
| pink | ⬜ | English availability unclear |
| prince | ⬜ | Polish-only, fan patch unverified |
| qdengine | ⬜ | Russian-origin |
| saga2 | ⬜ | |
| supernova | ⬜ | German-origin, translation unverified |
| teenagent | ✅ | TeenAgent, official freeware |
| toltecs | ✅ | 3 Skulls of the Toltecs |
| got | ✅ | God of Thunder, official freeware |
| trecision | ⬜ | |
| tucker | ✅ | Bud Tucker in Double Trouble |
| wage | ✅ | Via "Magic Rings" (WAGE Collection freeware bundle) |

</details>

<details>
<summary><strong>Unclear / Unidentified</strong> (3 engines)</summary>

| Engine | Status | Notes |
|---|---|---|
| crab | ❓ | Could not confidently identify |
| tot | ❓ | Could not confidently identify ("ToT") |
| vcruise | ❓ | Could not confidently identify |

</details>

<details>
<summary><strong>Deferred — needs the separate GL-core build</strong> (11 engines)</summary>

These need `build/engine-lists/gl-core.list`'s dedicated OpenGL-enabled
core (`FORCE_OPENGLES2=1`), which hasn't been built yet — none are
testable until it exists.

| Engine | Most Popular Game |
|---|---|
| grim | Grim Fandango |
| myst3 | Myst III: Exile |
| stark | The Longest Journey |
| twp | Thimbleweed Park |
| tinsel | Discworld |
| freescape | Driller |
| tetraedge | Syberia (franchise) |
| hpl1 | Penumbra: Overture |
| alcachofa | Yesterday |
| watchmaker | The Watchmaker |
| wintermute | Helga Deep In Trouble (freeware, ready to test once the core exists) |

</details>

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

For the six original SCUMM target games, flat packaging is enough:
**zip the contents of the game's data folder directly (`cd` into it
first), never the folder itself**, so every file sits at the zip's root
with no subdirectory:

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
available.)

**The 102-engine sweep surfaced a fuller picture than "always flatten,"
though.** The real constraint, and three things that follow from it:

- **All files need to sit at one directory level -- flat-at-root or a
  single wrapper folder both work.** What actually breaks is *multiple
  sibling subdirectories* in the same zip (e.g. a `DATA/` folder next to
  a `VIDEO/` folder): this intermittently crashes EmulatorJS's own
  bundled decompression worker (`Uncaught ErrnoError {errno: 20}`,
  `ENOTDIR`) before ScummVM's code ever runs. This is a real, confirmed
  bug in EmulatorJS's own vendored code (likely a race during heap
  growth mid-extraction), not something this project introduced or has
  fixed -- collapsing to one directory level is a packaging workaround,
  not a fix. See [docs/GOTCHAS.md](docs/GOTCHAS.md)'s "Multiple sibling
  subdirectories" section for the full investigation.
- **Some engines need their subdirectory structure preserved, not
  flattened.** `griffon` is the known example -- its own source hardcodes
  relative paths like `"music/boss.ogg"`, so flattening its zip breaks
  every one of those lookups. Check an engine's source for hardcoded
  relative paths before assuming flat is always correct.
- **A zip that keeps subdirectory structure still needs at least one
  file at the true root level**, or ScummVM's own auto-detection can
  silently produce an empty game list (a different failure than the
  crash above -- no error, just nothing detected). See GOTCHAS.md's
  "Zips with subdirectories but no file at the true root" section.

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

### Skipping autodetection with a `.scummvm` hook file

If a zip contains a `<name>.scummvm` text file alongside the game's data
files, ScummVM's libretro backend uses it to skip full-directory
autodetection entirely and launch directly -- this is stock upstream
ScummVM behavior (see `scummvm-core/backends/platform/libretro/src/libretro-os-utils.cpp`'s
built-in help text), not something specific to this project, and it works
through this project's zip-flat convention unchanged. The hook file's
content is either:

- a ScummVM **game ID** (e.g. `zak`, `maniac`, `tentacle`, `atlantis`) --
  works even if the game was never added via the ScummVM GUI; ScummVM
  launches it directly from the hook file's own folder with default
  options, or
- a **target** name matching an entry already in `scummvm.ini` -- only
  useful if that config file is already populated, which isn't the normal
  path for this project's zip-per-game setup.

The game ID form is the useful one here. Confirmed working end-to-end:
zipping Zak McKracken's files flat plus a `zak.scummvm` file containing
just `zak` launches straight into the game, skipping the ~60-line
per-file detection scan (see GOTCHAS.md's debugging-technique note) that
a plain autodetected zip goes through. Not required -- plain autodetection
(no hook file) already works for every game this project ships -- but
useful if you want faster, more precise startup for a specific game.

## Known limitations

- **⚠️ Requires HTTPS (or `localhost`) wherever you actually deploy it --
  a bare LAN IP or hostname over plain HTTP will not work, no matter how
  correctly everything else is configured.** This core uses real pthreads
  (`HAVE_THREADS=1`), which need `SharedArrayBuffer`, which browsers only
  grant on a secure context -- HTTPS, or the special-cased `localhost`.
  Serving over plain HTTP to any other origin makes the browser silently
  *ignore* the required `Cross-Origin-Opener-Policy`/
  `Cross-Origin-Embedder-Policy` headers rather than erroring on them, and
  the resulting failure (`SharedArrayBuffer function is not exposed`)
  looks unrelated to HTTPS at first glance. The local `test-page/` harness
  sidesteps this by using `localhost`; any other deployment (e.g. behind a
  reverse proxy, on a LAN IP, etc.) needs a real TLS certificate in front
  of it. See docs/GOTCHAS.md's "`HAVE_THREADS=1` requires cross-origin
  isolation at serve time" section for the full explanation.
- EmulatorJS's own "Save State"/"Load State" buttons work (bridged to
  ScummVM's save/load system -- see docs/GOTCHAS.md for the three
  separate bugs, two in ScummVM and one in RetroArch/EmulatorJS, that
  had to be fixed to make this work), and so does ScummVM's own in-game
  save-anywhere/load-anywhere menu. Both write to the same underlying
  save slot mechanism.
- What's *not* implemented is server-backed persistence -- EmulatorJS's
  own documented hooks for this (`EJS_onSaveState`, `EJS_onLoadState`,
  `EJS_loadStateURL`, and the equivalent save-file hooks) aren't wired up
  anywhere in `test-page/`, since this is a local static-file test
  harness with no backend to persist to. Hosting this core somewhere
  with real save-state persistence (e.g. RomM) means wiring those hooks
  up to that host's own backend -- a deployment-specific integration
  step, not something this project's test page needs to do itself.
- The exit-confirmation dialog only offers "Exit"/"Cancel" in the
  EmulatorJS release this project is pinned to (v4.2.3) -- no separate
  "Exit & Save" button. Confirmed by reading `emulator.min.js`'s dialog
  construction directly: it unconditionally creates exactly two buttons.
  If a newer EmulatorJS release adds one, or a host's own wrapper UI
  does, that's independent of the save-state fix above.
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
