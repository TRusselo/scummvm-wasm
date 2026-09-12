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
`955aef0429e` + `afdcbd2fffe` · ~+240

```
ScummVM has no API to serialize a running engine into a memory buffer;
Engine::saveGameState()/loadGameState() only read and write named slots. So
retro_serialize()/retro_unserialize() drive a real engine save/load into a
reserved slot (200 -- must fit in ScummEngine::_saveLoadSlot, a byte) and copy
that slot's bytes to and from the frontend's buffer.

The work runs on the emu thread: retro_serialize() sets a pending flag and
drives the thread forward, and pollEvent() performs it, since g_engine belongs
to that thread.

Both canSaveGameStateCurrently() and canLoadGameStateCurrently() are honoured
before either branch does any work, so a refused load leaves no half-written
slot file. Engines refuse outside the states where saving is meaningful, and
the frontend offers its save-state buttons whenever a core is running: asked to
save before it has loaded anything, an engine walks into its own uninitialised
state. A refusal is reported through retro_osd_notification() and returns false
from the serialize rather than failing silently.

Requires <PR 5> and <PR 6>.
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

**Splits.** `955aef0429e` → PR 5 + PR 6 + PR 9; it cannot be submitted whole
because it touches both `engines/` and `backends/platform/libretro/`.

`b591d4d34fc` split the same way, into a griffon half and a libretro half.
Both were dropped on 2026-09-09 -- see below. Nothing from that commit is
being submitted.

**PR 11's original message was wrong** and must not be reused. It claimed the
VFS root holds only the ROM and "nothing else is ever mounted there". EJS
creates `/data` and mounts IDBFS on `/data/saves`; emscripten and RetroArch add
`/home`, `/tmp`, `/dev`, `/proc`, `/shader`; we embed `/engine-data`. The
rewrite above argues "the root contains the whole tree", which is true.

**PR 6 is the weakest,** though less so than it was. A new public API wants a
visible consumer, and ours is in another repo. It now at least sits beside two
guards a caller must already consult -- canSaveGameStateCurrently() and
canLoadGameStateCurrently() -- which makes "there is no way to ask whether the
request actually finished" a more natural gap to point at. Still hold it until
PR 9 is up so the two can reference each other.

**PR 9 was blocked and is not any more.** As first drafted it drove
saveGameState() without consulting the engine's own guards, which is the crash
in issue #1: griffon's canSaveGameStateCurrently() is false outside
kGameModePlay, and saving anyway at its title screen reaches drawView() with no
map loaded. `afdcbd2fffe` adds the guards, so the PR is now two commits.

Verified in both directions on a build confirmed by core md5 against the
running container:

| case | guard | result |
|---|---|---|
| Day of the Tentacle, gameplay | allows | saves normally |
| griffon, gameplay | allows | saves normally |
| griffon, menu | refuses | "FAILED TO SAVE STATE", no crash |

The third row is the case that used to fault inside drawView(). It now returns
false from the serialize and the frontend reports it.

**Hold** `f09251ff1d1` (assumes the engine-data embed, still an open question
with EmulatorJS). **Never submit** `84f2bd11f5a` (fork-only CI change).

**Dropped 2026-09-09 -- both halves of `b591d4d34fc`.**
PR 4 reordered griffon's `EVENT_QUIT` check above `checkInputs()`'s
`_attacking`/`_forcePause` early return, on the theory that the early return
was eating quits. Instrumented builds disproved it: `checkInputs()` only runs
in `kGameModePlay`, and every observed hang was in another game mode, so that
path never executed. PR 10 bounded `close_emu_thread()`'s previously unbounded
spin -- sound in principle, but its only evidence is griffon, and it does not
fix the symptom: griffon still never returns to the frontend after the bound
fires. Keep the bound in our fork, where it is what turned a silent hang into
a log line; do not put it to a maintainer without a reproducible case.

**Issue #1 is griffon-only** and gates nothing in this file.

**Order.** scummvm: 1, 2, 3, 5 (6 held). libretro: 7, 8, 11, then 9 after 5
and 6 land.
