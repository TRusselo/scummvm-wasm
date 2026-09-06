# scummvm-wasm

TEST STATUS : 81 of 111 engines confirmed load into game.

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
plays, not just compiles. **81 of 111 confirmed working as of this
writing** — see the status table near the end of this file, or
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

**You never need to bundle a ScummVM engine-data file** (`fonts.dat`,
`toon.dat`, `nancy.dat`, `ultima8.dat`, etc.) into a ROM's zip. As of
2026-09-02 the entire set is compiled directly into the core itself --
see `docs/GOTCHAS.md`'s "ROMs no longer need to bundle their own ScummVM
engine-data file" section if you're curious why this was ever necessary.
If an engine reports "Could not locate engine data X," that means the
game itself is genuinely missing a required *original* game file, not
that you need to add one of ScummVM's own `.dat` files.

### 1. Already have a working ScummVM install of the game?

If you already have a game folder that ScummVM itself can detect and
launch (from an existing ScummVM install, or a romset built for another
ScummVM-based frontend), it almost certainly already satisfies the rules
below -- ScummVM's own auto-detection has always required this same
one-directory-level layout, independent of this project. Zip that folder
as-is (see the packaging rule in step 2) and try it before rebuilding
anything from scratch.

### 2. Packaging from raw game files

The packaging rule, in order of how often you'll need each part:

1. **All files must sit at one directory level: flat-at-root, or a
   single wrapper folder.** `cd` into the game's data folder and zip its
   *contents*, not the folder itself, so nothing has a parent path
   inside the zip:

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
   ```

   (A plain `zip` binary wasn't available in the environment this was
   developed in -- Python's `zipfile` module works identically and is
   always available.)

2. **Never split files across multiple sibling subdirectories in the
   same zip** (e.g. a `DATA/` folder next to a `VIDEO/` folder) --
   confirmed to intermittently crash EmulatorJS's own bundled
   decompression worker (`Uncaught ErrnoError {errno: 20}`, `ENOTDIR`)
   before ScummVM's code ever runs. This is a real bug in EmulatorJS's
   own vendored code, not something this project introduced or can fix
   -- collapsing to one directory level is the only known workaround.
   See [docs/GOTCHAS.md](docs/GOTCHAS.md)'s "Multiple sibling
   subdirectories" section for the full investigation.

3. **Exception: some engines need their subdirectory structure
   preserved, not flattened.** `griffon` is the known example -- its own
   source hardcodes relative paths like `"music/boss.ogg"`, so
   flattening its zip breaks every one of those lookups. Check an
   engine's source for hardcoded relative paths before assuming flat is
   always correct.

4. **Zip entry order no longer matters for detection.** Earlier versions
   of this guide told you to write a root-level "anchor" file into the
   zip first, because the core scanned only the directory containing
   whichever file EmulatorJS happened to hand it. Since 2026-09-02 the
   core scans the virtual filesystem root directly on Emscripten builds,
   so a game is detected wherever its files sit in the archive. **Do not
   repackage anything for this.** Measured against the 435 zips of the
   official ScummVM collection, 22 would have failed detection under the
   old behaviour, including stock dumps of Full Throttle, Gabriel Knight
   and Toonstruck; all of them work untouched now.

   Entry order still decides which file EmulatorJS passes as the content
   path, which matters only for `.scummvm` hook files (see below). That
   selection is deterministic -- always the first entry written -- as
   traced through EmulatorJS's `downloadRom()` and corroborated by
   [EmulatorJS issue
   #884](https://github.com/EmulatorJS/EmulatorJS/issues/884).

5. **Multi-disc games: merge all discs into one zip, not one zip per
   disc.** When both discs ship a file with the *same name* but
   *different content* (common for CD-era games -- e.g. dialogue/music
   archives that differ per disc), check that specific engine's own
   source for its multi-disc naming convention rather than guessing --
   e.g. `sword1` expects each disc's `SPEECH.CLU` renamed to
   `SPEECH1.CLU`/`SPEECH2.CLU`; `sword2` expects
   `music1.clu`/`music2.clu` and `speech1.clu`/`speech2.clu`. Verify
   with `md5sum` before assuming a same-named file across discs is a
   duplicate you can drop -- some genuinely are identical shared
   resources, but not all. See GOTCHAS.md's "Packaging full multi-CD
   retail games" section for the full walkthrough, including converting
   raw `.mdf`/`.bin` disc images to ISO9660 first if that's what you're
   starting from.

Older SCUMM games (Maniac Mansion, Zak McKracken, Loom, Indiana Jones and
the Last Crusade) use numbered `NN.LFL` files. Newer ones (Indiana Jones
and the Fate of Atlantis, Day of the Tentacle) use a `<NAME>.000` /
`<NAME>.001` / `MONSTER.SOU` container format -- both are handled
transparently by the same ScummVM SCUMM engine and the same packaging
rules above.

**Maniac Mansion note:** the original Day of the Tentacle CD release
bundles a complete, separately-playable copy of Maniac Mansion as an
in-game easter egg (found on the original disk under a `MANIAC/`
subfolder). If you don't have a standalone Maniac Mansion copy, that one
works identically -- it's the real, complete game, not a demo.

### 3. Deploying the packaged zip

Two options:

- **Local test-page** (fastest for testing one game in isolation): drop
  the zip in `test-page/` and point `EJS_gameUrl` at it in
  `test-page/index.html` (the `.scm` extension is just this project's
  own early convention, not a requirement -- see GOTCHAS.md, plain
  `.zip` works identically). Game files here are gitignored; this repo
  ships no copyrighted game data.
- **A hosted ROMM instance** (the actual method used for the 102-engine
  sweep, and the more realistic real-world deployment target): run
  `build/deploy-to-romm.sh <path-to-romm-checkout>` to stage the built
  core into a ROMM fork, then drop the packaged zip into that instance's
  ScummVM platform ROM folder and let ROMM scan and serve it. See the
  "Known limitations" section below for what's confirmed working this
  way (including save states).

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

**A hook file must be the literal first entry written into the zip, not
merely present somewhere in it** -- this is the one case where zip entry
order still matters. ScummVM's own
`retro_load_game()` only takes the hook-file branch if the specific path
EmulatorJS hands it as `game->path` itself ends in `.scummvm` -- and per
the traced rule, that path is always whichever file was written first
into the zip. A `.scummvm` file added anywhere else in write order is
silently ignored with no error, falling through to normal (and possibly
failing) autodetection instead. Confirmed by direct test: appending the
hook file last did nothing; writing it first made ScummVM's own launcher
correctly recognize the game ID. Note this only gets you past the
launcher-level ID lookup -- the engine's actual startup still runs
ScummVM's normal hash-based detection internally to build the
game-specific descriptor most engines' `createInstance()` requires, so a
dump that doesn't match any of an engine's known hash-verified releases
will still fail at that later stage with a generic "Game data not
found," even with a correctly-placed hook file.

## Known limitations

- **Game size ceiling: two limits, both in EmulatorJS rather than in this
  core.** (1) The packaged `.zip` must be under **2 GiB** — EmulatorJS buffers
  the whole download into a single JS `ArrayBuffer`, hitting V8's maximum
  typed-array length; over the line the tab pauses in `downloadFile` before the
  core exists. (2) **zip + unpacked** must be under **4 GiB** — EmulatorJS
  decompresses in a Worker running its own separate wasm32 module
  (`asm._extract`) that holds the compressed input *and* the decompressed output
  in one linear memory; over the line it hangs at "decompressing game data" with
  no progress shown. Measured: Phantasmagoria (1.79 + 2.14 = 3.93 GiB) plays;
  The Feeble Files 4CD (1.996 + 2.07 = 4.07 GiB) clears the first limit by
  3.7 MB then hangs on the second; Riven, Zork: Grand Inquisitor and Gabriel
  Knight 2 all exceed 2 GiB zipped and never start. Unpacked size alone predicts
  nothing — Zork GI unpacks smaller than Phantasmagoria and still fails. Our own
  wasm32 heap has never been the constraint. See
  [issue #5](https://github.com/TRusselo/scummvm-wasm/issues/5).

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
- **Minimum browser versions: Chrome 92, Firefox 79, Safari 15.2** (all
  2020-2021). This is the same constraint as the HTTPS requirement above,
  expressed as version numbers: the core is built with real pthreads
  (`HAVE_THREADS=1`), which need `SharedArrayBuffer`, which browsers only expose
  to cross-origin-isolated pages -- re-enabled behind COOP/COEP in Chrome 92
  (Jul 2021), Firefox 79 (Jul 2020) and Safari 15.2 (Dec 2021). The core also
  links `MIN_WEBGL_VERSION=2` (WebGL2: Chrome 56, Firefox 51, Safari 15), so on
  Safari the two requirements land within a few months of each other. Older
  browsers cannot run this core at all, regardless of how it is served.

  Worth knowing for the size work in
  [issue #5](https://github.com/TRusselo/scummvm-wasm/issues/5): the proposed
  streaming loader would need `DecompressionStream("deflate-raw")` -- Chrome 103
  (Jun 2022), Firefox 113 (May 2023), Safari 16.4 (Mar 2023). On Chrome and
  Firefox that is *below* the bar this core already sets, so it costs nothing.
  On Safari it is slightly above (16.4 vs 15.2), meaning a Safari 15.2-16.3 user
  could run the core today but could not use a streaming loader for oversized
  games. That gap is the reason the proposal is gated and feature-detected
  rather than a straight replacement.
- **14 engines are not compiled into this core, and a game on one of them
  fails silently.** `alcachofa`, `foxtail`, `freescape`, `grim`, `herocraft`,
  `hpl1`, `myst3`, `stark`, `tetraedge`, `tinsel`, `twp`, `watchmaker`,
  `wintermute` and `wme3d` need an OpenGL-capable core that has not been built
  yet (`build/engine-lists/gl-core.list`). Launching one of their games does not
  produce an error -- with no engine present, detection simply matches nothing
  and you land in an empty ScummVM launcher. Discworld (`tinsel`) is the easy
  way to see this. Worth knowing before debugging a "detection failure" that is
  really a missing engine.
- **Music is AdLib-only, which makes some games depend on files their dump may
  omit.** `SharedArrayBuffer`-era browsers give us no MIDI hardware (the WebMIDI
  plugin is excluded -- see `docs/GOTCHAS.md`), FluidSynth is compiled in but
  ships no soundfont so ScummVM never offers it, and MT-32 emulation needs
  Roland ROMs that cannot be redistributed. `MidiDriver::detectDevice()`
  therefore always resolves to AdLib. For the four engines that use the Miles
  AdLib driver (`toltecs`, `made`, `saga2`, `eem`) this is not merely a
  fidelity question: they call `MidiDriver_Miles_AdLib_create("SAMPLE.AD",
  "SAMPLE.OPL")` and hard-`error()` if the game's own timbre banks are absent.
  A desktop user with a soundfont configured never sees this, because
  `MDT_PREFER_GM` routes them past the Miles path entirely -- which is how an
  incomplete dump can sit in a collection folder marked "Working" and still fail
  here. Tracked in
  [issue #4](https://github.com/TRusselo/scummvm-wasm/issues/4).
- EmulatorJS's own "Save State"/"Load State" buttons work (bridged to
  ScummVM's save/load system -- see docs/GOTCHAS.md for the three
  separate bugs, two in ScummVM and one in RetroArch/EmulatorJS, that
  had to be fixed to make this work), and so does ScummVM's own in-game
  save-anywhere/load-anywhere menu. Both write to the same underlying
  save slot mechanism. **Confirmed working end-to-end through a real
  hosted ROMM instance** (`build/deploy-to-romm.sh`), not just the local
  test-page -- ROMM's own EmulatorJS integration already implements
  server-backed save/state persistence for any core, so once this
  project's `retro_serialize()`/`retro_unserialize()` fix landed, saving
  and loading through ROMM's UI worked with no extra wiring needed on
  this project's side.
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

## Engine Status

Legend: ✅ confirmed working (a real game boots and plays) · 🚫 blocked
(packaged correctly, blocked by an engine/core bug) · ⏸️ deferred
(sourcing/tooling blocker, not yet worked around) · 🔒 blocked on a
separate OpenGL core build that doesn't exist yet · ❓ engine not
confidently identified · ⬜ not yet attempted · ⚠️ worked, excluded on
purpose

**81 of 111 confirmed** (plus the `agos2` subengine). 1 blocked
(`chamber`, see [issue #3](https://github.com/TRusselo/scummvm-wasm/issues/3)),
14 deferred on sourcing/tooling, 15 waiting on a GL-core build that hasn't
happened yet, 3 unidentified, the rest untested.

All confirmed engines were re-validated on 2026-09-06 against a core rebased
onto current upstream ScummVM — 30 titles: 20 chosen because they only work due
to a code fix in this project, 10 as regression canaries. No regressions.

That rebase also brought 10 engines that did not exist when this project
started: `bolt`, `eem`, `fool`, `gamos`, `harvester`, `macs2`, `pelrock`,
`phoenixvr`, `waynesworld`, plus `colony` (deferred to the GL core — it declares
a `3d` dependency). The nine 2D ones are now in `all-engines.list` but **are not
in the currently deployed core**, which was built before they were added: they
need a rebuild and none has been tested. Four (`fool`, `harvester`, `macs2`,
`waynesworld`) are not built by default upstream, so expect some to be as
immature as `chamber`. Full
narrative detail (what game, what source, what broke, how it was fixed)
lives in [docs/ENGINE-TEST-PLAN.md](docs/ENGINE-TEST-PLAN.md) — this
table is the at-a-glance summary, kept in sync with it.

<details>
<summary><strong>Widely Known</strong> (20 engines)</summary>

| Engine | Status | Notes |
|---|---|---|
| agi | ✅ | King's Quest I; also Leisure Suit Larry 1-3, Space Quest I-III |
| glk | ✅ | Zork I confirmed. Was long mislabelled as a `fonts.dat` crash; the real cause was two FreeType autofit function-pointer signature mismatches, fixed 2026-09-04 |
| awe | ✅ | Another World |
| dm | ✅ | Dungeon Master (DOS v3.4). Needed the `dm` engine synced from upstream ScummVM for DOS support, plus a fix to the GLK Level 9 detector that was misclaiming its save file |
| sword1 | ✅ | Broken Sword — full game, both CDs merged |
| sword2 | ✅ | Broken Sword II — full game, both CDs merged |
| sci | ✅ | King's Quest V |
| bladerunner | ✅ | Only title on this engine, under the 2GB single-title exception (1.947GB) |
| ultima | ✅ | Ultima VIII: Pagan via `ultima8` |
| twine | ⏸️ | Only accessible copy is a French CD image, needs disk-image tooling |
| mohawk | ✅ | Via Myst (original candidate, Zoombinis, is `ADGF_UNSUPPORTED`) |
| mediastation | ✅ | Via Beatrix Potter (size-limit swap for Muppet Treasure Island); not kept in the live library by user preference |
| nancy | ✅ | Nancy Drew: Secrets Can Kill |
| groovie | ✅ | Via The 11th Hour Interactive Demo (7th Guest dumps failed MD5 despite matching size) |
| sky | ✅ | Beneath a Steel Sky, official freeware |
| adl | ✅ | Mystery House, bundled ScummVM freeware |
| lastexpress | ✅ | Via official Interactive Demo (full retail is 3 CDs, over size limit) |
| ags | ✅ | Via 5 Days a Stranger (Chzo Mythos), freeware |
| toon | ✅ | Toonstruck CD1 only (2-CD Sold Out budget release; full retail exceeds size limit) |
| startrek | ⏸️ | Only raw floppy disk images found, needs disk-image tooling |

</details>

<details>
<summary><strong>Genre-Notable</strong> (43 engines)</summary>

| Engine | Status | Notes |
|---|---|---|
| kyra | ✅ | Legend of Kyrandia: Book One |
| mm | ✅ | World of Xeen via `xeen` subengine |
| tsage | ✅ | Return to Ringworld via `ringworld2` subengine |
| sherlock | ✅ | The Case of the Serrated Scalpel |
| queen | ✅ | Flight of the Amazon Queen, official freeware |
| lure | ✅ | Lure of the Temptress, freed by Revolution Software |
| gob | ✅ | Gobliiins, with music |
| cine | ✅ | Future Wars |
| cruise | ✅ | Cruise for a Corpse |
| cryo | ✅ | Lost Eden (English DOS) |
| cryomni3d | ⏸️ | Versailles 1685 needs an InstallShield installer run; no unshield/innoextract/DOSBox available |
| darkseed | ✅ | Dark Seed |
| dgds | ✅ | Via Heart of China |
| director | ✅ | The Journeyman Project — plays normally past the `ADGF_UNSTABLE` "Start anyway?" warning dialog |
| dragons | ⏸️ | Blazing Dragons is PS1-only; no archive.org disc image found |
| drascula | ✅ | Drascula: The Vampire Strikes Back |
| dreamweb | ✅ | DreamWeb, freeware since 2011 |
| griffon | ✅ | The Griffon Legend plays. Saving currently freezes the tab — tracked separately |
| hopkins | ✅ | Hopkins FBI (freeware Linux port; audio is French despite `EN_ANY` tag) |
| hugo | ✅ | Hugo's House of Horrors |
| icb | ⏸️ | Tried El Dorado (also on this engine); dump doesn't match any known hash signature, not a packaging issue |
| immortal | ⏸️ | Apple IIgs-only engine, no clean disk dump found |
| lab | ⏸️ | No usable DOS/Windows package found |
| macventure | ⏸️ | Mac/Apple IIgs-only engine, needs HFS disk-image tooling |
| made | ✅ | Via Rodney's Funscreen |
| mads | ⏸️ | Only raw floppy disk images found |
| mtropolis | ✅ | Via Muppet Treasure Island (Obsidian, original candidate, is multi-CD, no smaller cut) |
| neverhood | ✅ | The Neverhood |
| parallaction | ✅ | The Big Red Adventure, official freeware |
| pegasus | ✅ | The Journeyman Project 3: Pegasus Prime (official ScummVM-team demo) |
| buried | ✅ | The Journeyman Project 2: Buried in Time demo |
| plumbers | ✅ | Plumbers Don't Wear Ties |
| private | ✅ | Private Eye (EN_GRB variant) |
| saga | ✅ | I Have No Mouth, and I Must Scream |
| sludge | ⚠️ | Worked (The Interview) but excluded — unsigned `.exe`, engine marked unstable/WIP by ScummVM itself |
| titanic | ⏸️ | Starship Titanic — GOG version hash-matches exactly, but `Assets/` alone is 1.19GiB (over size limit); single-game engine, no alt title |
| tony | ✅ | Tony Tough and the Night of the Roasted Moths |
| touche | ✅ | Touché: The Adventures of the Fifth Musketeer |
| voyeur | ✅ | Perfect hash match to full-game detection entry, no ambiguity |
| zvision | ⏸️ | Full retail (3 CDs) exceeds 1GB; only lighter alt found fails detection |
| asylum | ✅ | Sanitarium CD1 only (full retail's 3 CDs exceed size limit; demo installer couldn't be unpacked) |
| sword25 | ✅ | Broken Sword 2.5, official freeware fan game |
| agos | ✅ | Simon the Sorcerer (base + `agos2` subengine via Simon 2) |

</details>

<details>
<summary><strong>Niche/Obscure</strong> (36 engines)</summary>

| Engine | Status | Notes |
|---|---|---|
| access | ✅ | Amazon: Guardians of Eden |
| agds | ⏸️ | Both titles (Black Mirror, NiBiRu) too large for size budget |
| alg | ✅ | Crime Patrol (was missing `CP.SCN` + resource files skipped during initial packaging, fixed) |
| avalanche | ✅ | Lord Avalot d'Argent, freeware |
| bagel | ✅ | Hodj 'n' Podj (used instead of The Space Bar, too large) |
| bbvs | ✅ | Beavis and Butt-Head in Virtual Stupidity. Needed Indeo 3 enabled plus a double-free fix in the AVI loader |
| cge | ✅ | Soltys, bundled ScummVM freeware |
| cge2 | ✅ | Sfinx, official English release |
| chamber | 🚫 | Reaches title screen then hangs; likely genuine engine immaturity (not built by default upstream, no compatibility wiki entry) |
| chewy | ✅ | English DOS release exists, corrects old "German-only" note |
| composer | ✅ | Magic Tales: Baba Yaga and the Magic Geese |
| draci | ✅ | Dragon History, English fan translation |
| efh | ✅ | Escape from Hell |
| gnap | ✅ | U.F.O.s / Gnap |
| hadesch | ⏸️ | Hades Challenge — confirmed `ol.pod` dump mismatch, not fixable by repackaging |
| hdb | ✅ | Hyperspace Delivery Boy!, official freeware |
| hypno | ✅ | Wetlands (US) |
| illusions | ✅ | Duckman: The Graphic Adventures of a Private Dick |
| kingdom | ✅ | Kingdom: The Far Reaches |
| lilliput | ✅ | The Adventures of Robin Hood |
| m4 | ✅ | Orion Burger (was missing all 9 SECTION*.HAG per-chapter archives, fixed) |
| mortevielle | ✅ | Mortville Manor, French data presents in English via `mort.dat` overlay |
| mutationofjb | ✅ | Mutation of J.B. (German-only, no English release exists) |
| ngi | ✅ | Full Pipe. Needed Indeo 5 enabled |
| petka | ✅ | Red Comrades 2, Russian-only, testing purposes |
| pink | ✅ | Pink Panther: Passport to Peril — original dump was corrupted beyond the first 5000 bytes, fixed by resourcing from MyAbandonware |
| prince | ⬜ | Polish-only, fan patch unverified |
| qdengine | ⬜ | Russian-origin |
| saga2 | ✅ | Faery Tale Adventure II (was missing SAMPLE.AD/SAMPLE.OPL, fixed) |
| supernova | ✅ | Mission Supernova, official EN_ANY entry shares the German hash |
| teenagent | ✅ | TeenAgent, official freeware |
| toltecs | ✅ | 3 Skulls of the Toltecs |
| got | ✅ | God of Thunder, official freeware |
| trecision | ⏸️ | Nightlong — predicted 3-CD-file caveat confirmed, only 2 of 3 exist in the accessible release |
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
<summary><strong>New — added by the 2026-09-06 upstream rebase</strong> (9 engines)</summary>

Present in `all-engines.list` but **not in the currently deployed core**, which
was built before they existed. They need a rebuild before any can be tested.
"default" is upstream's own `add_engine` build-by-default flag — the four marked
`no` are ones upstream does not ship by default, the same status `chamber` had
until this rebase.

| Engine | Upstream description | Upstream default | Status |
|---|---|---|---|
| bolt | Bolt | yes | ⬜ needs rebuild |
| eem | Eagle Eye Mysteries | yes | ⬜ needs rebuild |
| gamos | Gamos | yes | ⬜ needs rebuild |
| pelrock | Alfred Pelrock | yes | ⬜ needs rebuild |
| phoenixvr | Phoenix VR | yes | ⬜ needs rebuild |
| fool | The Fool's Errand | no | ⬜ needs rebuild |
| harvester | Harvester | no | ⬜ needs rebuild |
| macs2 | Macs2 | no | ⬜ needs rebuild |
| waynesworld | Wayne's World | no | ⬜ needs rebuild |

</details>

<details>
<summary><strong>Deferred — needs the separate GL-core build</strong> (15 engines)</summary>

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
| foxtail | FoxTail |
| herocraft | (HeroCraft titles) |
| wme3d | Wintermute 3D titles |
| colony | The Colony (added by the 2026-09-06 rebase; declares a `3d` dependency) |

</details>

## Contributing

Read [docs/GOTCHAS.md](docs/GOTCHAS.md) before touching the build scripts
-- several things in there look like they could be simplified or removed
and are load-bearing. [docs/ADDING-ENGINES.md](docs/ADDING-ENGINES.md) is
a head start if you want to extend this beyond the SCUMM engine to other
engines ScummVM supports.
