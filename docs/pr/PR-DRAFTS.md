# Upstream PR drafts

Bodies below are **exactly what goes in the PR** — nothing else. Strip every
`Co-Authored-By` / `Claude-Session` trailer from the commits first.

Our own notes are in "Internal" at the bottom, deliberately out of the bodies.

---

# scummvm/scummvm

## PR 1 — `VIDEO: Fix double free of the stream on AVIDecoder::loadStream failure`
`cac3a252862` · +5

```
loadStream() assigns _fileStream = stream, then calls close() on its two late
failure paths. close() deletes _fileStream, but the caller still owns the
stream: VideoDecoder::loadFile() deletes it when loadStream() returns false.

The second delete runs a virtual destructor through a freed vtable pointer -- a
silent double free natively, a call_indirect trap on WebAssembly.

Detach the stream before close() on both paths.
```

## PR 2 — `TINSEL: Add two uncatalogued Discworld 1 English CD variants`
`3f09158c8a9` · +43

```
One .gra release differing only in english.txt, and one .scn release. Both play.
```

## PR 3 — `CHAMBER: take the Hercules blit path only when Hercules was requested`
`a607b761ebe`

```
blitToScreen() guards its 320x200 path with _renderMode == kRenderCGA and
otherwise falls through to a 720x348 Hercules canvas blitted at a fixed +40/+74
offset. Those offsets are only valid when init() took its isCustomHerc branch,
which is driven by _videoMode, not _renderMode.

With no render_mode set the two differ: _renderMode stays kRenderDefault while
the constructor sets _videoMode to kRenderCGA. init() then sizes the screen
320x200, but blitToScreen copies 200 rows to destY 74 and trips the bounds
assertion in copyRectToSurface (74 + 200 > 200).

Explicitly selecting a render mode avoids it, which is why it survives normal
launcher use.

This fixes the assertion only; the engine's hangs and EGA background corruption
are separate and reported at bugs.scummvm.org.
```

## PR 4 — `GRIFFON: Check for quit before the attack/pause early return`
split from `b591d4d34fc` · +13/−3

```
checkInputs() returns early while _attacking || (_forcePause && !_itemSelOn),
and that return sat above the EVENT_QUIT check, so a quit arriving in either
state was discarded and the engine never left its main loop.

Unnoticed on desktop, where the window manager closes the window regardless.
On a frontend that waits for the engine to acknowledge the quit, it hangs
shutdown.
```

## PR 5 — `SCUMM: Override getSaveStateName() to match makeSavegameName()`
split from `955aef0429e` · +15

```
ScummEngine never overrode Engine::getSaveStateName(), so it returned
"target.990" while saveState() writes to makeSavegameName() -- "target.s990".
A caller using the generic name to locate a save SCUMM had just written would
miss the file.
```

## PR 6 — `ENGINES: Add Engine::isSaveOrLoadPending()`
split from `955aef0429e` · +14

```
Engines that defer their save/load I/O rather than performing it in
saveGameState()/loadGameState() -- SCUMM sets _saveLoadSlot and acts on it
later in its own main loop -- give callers no way to tell whether the request
has completed or merely been accepted.
```

---

# libretro/scummvm

## PR 7 — `LIBRETRO: Keep warning() in release builds`
`8ad2b918334` · +5/−1

```
Drop -DDISABLE_TEXT_CONSOLE from the non-DEBUG defines. It compiled every
warning() call out of the binary, so release builds gave no diagnostics for
failures that only warn. RELEASE_BUILD stays.
```

## PR 8 — `LIBRETRO: exclude WebMIDI plugin`
`48dea85dc88` · +13/−4

```
backends/midi/webmidi.cpp is compiled in for any EMSCRIPTEN build, but its
EM_JS glue needs a midiOutputMap global and a Module.setValue export that only
ScummVM's own standalone shell (dists/emscripten/custom_shell-pre.js) provides.
Under RetroArch/EmulatorJS neither exists, so device enumeration throws during
engine startup.

Removes midi/webmidi.o from backends/module.mk and LINK_PLUGIN(WEBMIDI) from
base/plugins.cpp -- both are needed, the registration table being independent
of the object list. Other music drivers are unaffected.
```

## PR 9 — `LIBRETRO: implement save-state support`
split from `955aef0429e` · ~+214

```
ScummVM has no API to serialize a running engine into a memory buffer;
Engine::saveGameState()/loadGameState() only read and write named slots. So
retro_serialize()/retro_unserialize() drive a real engine save/load into a
reserved slot (200 -- must fit in ScummEngine::_saveLoadSlot, a byte) and copy
that slot's bytes to and from the frontend's buffer.

The work runs on the emu thread: retro_serialize() sets a pending flag and
drives the thread forward, and pollEvent() performs it, since g_engine belongs
to that thread.

Requires <PR 5> and <PR 6>.
```

## PR 10 — `LIBRETRO: Stop an unacknowledged quit from hanging the frontend`
split from `b591d4d34fc` · +25

```
close_emu_thread() pushes an EVENT_QUIT and hands the emulator thread a
timeslice, looping until the engine observes it and returns from
scummvm_main(). An engine that keeps yielding but never observes the quit spins
there forever, and as this runs on the frontend's thread it hangs with no
diagnostic.

Bound the loop, warn, and tear down anyway. A leaked engine thread on a core
being unloaded costs less than a hung frontend, and the save-state bridge in
this file already uses the same pattern.
```

## PR 11 — `LIBRETRO: scan the virtual-FS root on Emscripten`
`4b6607e97d3` · +20 · **body rewritten, see Internal**

```
Detection scans from FSNode(game->path).getParent(). Under EmulatorJS the ROM's
whole extracted tree is unpacked under "/", and game->path is whichever file
its fileNames[0] heuristic picked, so the scan root depends on an arbitrary
choice and misses content whenever the anchor is not at the top level.

Scan from "/" instead, which always contains the full tree. Guarded to
EMSCRIPTEN -- on a native build "/" is the real OS root.
```

---

# Internal — not for the PRs

**Splits.** `b591d4d34fc` → PR 4 + PR 10. `955aef0429e` → PR 5 + PR 6 + PR 9.
Neither can be submitted whole; each touches `engines/` and
`backends/platform/libretro/`.

**PR 11's original message was wrong** and must not be reused. It claimed the
VFS root holds only the ROM and "nothing else is ever mounted there". EJS
creates `/data` and mounts IDBFS on `/data/saves`; emscripten and RetroArch add
`/home`, `/tmp`, `/dev`, `/proc`, `/shader`; we embed `/engine-data`. The
rewrite above argues "the root contains the whole tree", which is true.

**PR 6 is the weakest.** A new public API wants a visible consumer, and ours is
in another repo. Consider holding it until PR 9 is up so they can reference
each other.

**Hold** `f09251ff1d1` (assumes the engine-data embed, still an open question
with EmulatorJS). **Never submit** `84f2bd11f5a` (fork-only CI change).

**Issue #1 blocks nothing here.** Its evidence says plain Exit works, so the
quit-hang fix is unrelated.

**Order.** scummvm: 1, 2, 3, 4, 5 (6 held). libretro: 7, 8, 10, 11, then 9
after 5 and 6 land.
