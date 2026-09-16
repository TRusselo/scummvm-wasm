# Upstream PRs

First batch submitted 2026-09-12 03:50; the three scummvm/scummvm PRs were
closed within the hour and resubmitted clean the same evening. Status as of
2026-09-12 evening is in the table below. Bodies further down are the PR text
itself — nothing else.

## Read this before submitting anything else upstream

Maintainer `mduggan` closed PRs 1, 3 and 5 within 106 seconds of each other,
each with one line: *"Please read AI-GUIDELINES.md."* PR 1 then drew two
technical comments as well (see its row).
`scummvm/scummvm` **and** `libretro/scummvm` carry an identical
`AI-GUIDELINES.md` with two hard rules:

- *"AI agents must never have (Co-) authorship of your code."* A
  `Co-Authored-By: Claude ...` or `Claude-Session:` trailer is an instant
  reject. PRs 1 and 3 carried both.
- *"AI assistance MUST be disclosed in the commit message"* — as
  `Assisted-by: Claude:claude-opus-5`. PR 5 carried no disclosure at all, the
  opposite failure.

The claim that trailers were stripped from every submitted commit, which this
file used to make, was simply false. Check each upstream repo for
`AI-GUIDELINES.md` / `CONTRIBUTING.md` before the first commit; it overrides
our own repo's commit convention. `libretro/libretro-deps` has no such policy.

| PR | where | files touched | reach | status |
|---|---|---|---|---|
| 1 | scummvm/scummvm#7925 → #7944 | `video/avi_decoder.cpp` | all platforms, any AVI | #7925 **closed** — AI co-authorship, then `bluegr`: unnecessary, and `lephilousophe`: **superseded by #7935** (his general fix, all decoders). #7944 was resubmitted before those two comments were read and **withdrawn** 2026-09-12 citing #7935 |
| 2 | scummvm/scummvm#7926 | `engines/tinsel/detection_tables.h` | detection only | **withdrawn** — booted, not played through |
| 3 | scummvm/scummvm#7928 → #7946 | `engines/chamber/cga.cpp` | all platforms, chamber only | #7928 closed — AI co-authorship; **#7946 open**, quiet since 2026-09-13 |
| 5 | scummvm/scummvm#7927 → #7945 | `engines/scumm/scumm.h` | all platforms, SCUMM only | #7927 closed — no AI disclosure, and comment far too long; **#7945 MERGED** 2026-09-14 into `master` |
| 6 | — | `engines/engine.h`, `engines/scumm/scumm.h` | new base-class virtual | **on hold with 9** — see "Save states: asked before submitting" below |
| 7 | libretro/scummvm#110 | `backends/platform/libretro/Makefile.common` | libretro core, all targets | **merged** 2026-09-12 into `staging_master` (not `master` yet); `spleen1981` asked for the code comment to go, and it did. Reached `master`; **dropped from the fork 2026-09-15** |
| 8 | libretro/scummvm#111 → scummvm/scummvm#7947 | `base/plugins.cpp` | EMSCRIPTEN builds only | **FIXED UPSTREAM, both closed.** #111: `spleen1981`, belongs upstream. #7947 approved by `chkuendig` 08:37:18Z, then `lephilousophe` committed the same fix to master as `de8c01b` 32 s later; closed as superseded 2026-09-13. **Fork's `48dea85` and `f3c5255` both dropped 2026-09-15** — upstream guards the whole platform-MIDI block on `__LIBRETRO__` rather than the plugin line |
| 9 | — | `backends/platform/libretro/src/libretro-core.cpp` + header | libretro core | **on hold** — issue opened asking whether it is wanted at all, 2026-09-15 |
| 11 | libretro/scummvm#112 | `backends/platform/libretro/src/libretro-core.cpp` | EMSCRIPTEN-guarded | **CLOSED** 2026-09-14 by `spleen1981`: "let's avoid platform specific workarounds to support an unsupported use case". Stays in our fork as permanent divergence |
| 13 | libretro/scummvm#113 | `libretro-os-utils.cpp` | libretro core, all targets | **MERGED** into `staging_master`; patch-present in `libretro/master`; **dropped from the fork 2026-09-15** |
| 14 | libretro/scummvm#114 | `libretro-os.h`, `libretro-os-utils.cpp` | EMSCRIPTEN-guarded | **MERGED** 2026-09-15 by `spleen1981`. He asked about `LIBCO=0` and withdrew the question himself; a review comment asked `hasFeature()` to move to `libretro-os-base.cpp`, done — `openUrl()` stayed, that file defines `FORBIDDEN_SYMBOL_ALLOW_ALL` and without it `forbidden.h`'s `FILE` macro breaks `<emscripten.h>`. **Both commits dropped from the fork 2026-09-15** |
| 20 | — | `data/emulator.css`, `data/src/{emulator,GameManager,netplay}.js` | every core, every embedder | **drafted 2026-09-15, not opened.** Branch `msg-severity` pushed nowhere yet; clean against #1267/#1268/#1269 |
| 21 | — | `libretro-core.cpp`, `libretro-os-utils.cpp`, `include/libretro-core.h` | libretro core, all targets | **drafted 2026-09-15, not opened.** Upstream's own uninitialised `retro_message_ext`, unchanged since 2023 |
| 22 | rommapp/romm#4539 | `docker/Dockerfile` | RomM image only | **CLOSED** 2026-09-16 by `zurdi15`: *"I'm not gonna merge a messy patch for something that emujs will release at some point. Lets wait for them to release 4.3.0"*. Correct call — the fix is in `v4.3.0-pre` — and it costs us nothing, our fork had already dropped this backport in `6bb3cdf6e`. See "RomM's EmulatorJS version" below |
| 23 | — | `data/src/emulator.js` | every core, every embedder | **drafted 2026-09-16, not opened.** Split out of patch 02; the only piece of it that stands alone upstream. Branch `fix-decompress-progress` |
| — | libretro/libretro-deps#15 | FreeType `autofit` | pinned by `dependencies.mk` | **open, the release gate.** Reframed 2026-09-15: upstream FreeType already made this exact change, and the vendored copy here is 2.7.0 against upstream's 2.14.3. Our explanatory comment was removed so the files match upstream character for character |

Two of the three closures disputed only the trailers; PR 1's also disputed the
approach, and that was missed for eight hours because the thread was not
re-read before resubmitting. **Re-read every comment on a closed PR before
opening its replacement.** Resubmitting means rewriting the commit with
`Assisted-by:` and no co-author — the policy warns repeat undisclosed use can
bring a permanent ban.

**Read the "files touched" column before submitting anything.** A line count
says nothing about blast radius; the path does. `engines/<name>/` is engine code
on every platform, `backends/platform/libretro/` is this core only, and an
`EMSCRIPTEN` guard narrows it further. Every correction made to this batch after
submission -- PR 8's unstated scope, PR 2's overclaim, PR 3's missing
before/after table -- was a reviewer's first question about reach, answerable
from this column.

**`libretro/scummvm` is not a downstream fork of the port.** The libretro
backend lives in official ScummVM sources -- `backends/platform/libretro/` sits
in `scummvm/scummvm` alongside `3ds`, `android`, `sdl` and the rest, and
docs.libretro.com credits the core to the ScummVM Team. `libretro/scummvm` is
the staging repo where backend work lands first and flows upstream in batches:
as of 2026-09-15 it is **28 commits ahead of `scummvm/scummvm` and 0 behind**.

Two consequences. ScummVM's `AI-GUIDELINES.md` governs every commit to the
libretro backend, not just the ones sent to `scummvm/scummvm`. And a change
spanning `engines/` and `backends/platform/libretro/` is one feature in one
codebase, not two PRs gated on each other -- an earlier note in this file
claiming the opposite was wrong.

Branches: engine fixes are cut from `scummvm/scummvm` master and pushed to
`TRusselo/scummvm-scummvm`; libretro fixes are cut from `libretro/scummvm`
master and pushed to the same fork — `TRusselo/scummvm` was renamed to
`TRusselo/scummvm-scummvm`, so the two names are one repository. Note `TRusselo/scummvm-scummvm` sits
in the existing fork network with `libretro/scummvm` as its parent, so branches
must be based on `upstream/master` explicitly or the diff is enormous.

Our own notes are in "Internal" at the bottom, deliberately out of the bodies.

---

# scummvm/scummvm

## PR 1 — `VIDEO: Fix double free of the stream on AVIDecoder::loadStream failure` — SUPERSEDED
`cac3a252862` · +5 · #7925 closed, #7944 withdrawn

Superseded by scummvm/scummvm#7935 (`lephilousophe`), which makes every
decoder's `loadStream()` free the stream on failure and removes the
caller-side delete in `VideoDecoder::loadFile()` — the opposite direction from
ours. Keep `cac3a25` on the fork until #7935 merges, then drop it on rebase.

```
loadStream() assigns _fileStream = stream, then calls close() on its two late
failure paths. close() deletes _fileStream, but the caller still owns the
stream: VideoDecoder::loadFile() deletes it when loadStream() returns false.

The second delete runs a virtual destructor through a freed vtable pointer -- a
silent double free natively, a call_indirect trap on WebAssembly.

Detach the stream before close() on both paths.
```

## PR 2 — `TINSEL: Add two uncatalogued Discworld 1 English CD variants` — WITHDRAWN
`3f09158c8a9` · +43 · opened as scummvm/scummvm#7926, closed the same day

Body as submitted said "Both play." That is an overclaim: the two releases were
verified only as far as detecting and booting into gameplay, neither was played
through, and this project's testing does not overrule ScummVM's own. Submitting
a detection entry asserts a release is supported, which is a compatibility claim
we have not earned.

Adding detection entries by PR **is** an accepted route -- 60 merged PRs with
"detection" in the title, several within the last month -- so the mechanism was
not the problem; the claim was. Resubmit only if a release is played to
completion, or reported through the unknown-variant route instead, which asks
for the MD5s without asserting support.

For reference, the entries were `EN_ANY` / `kPlatformDOS` / `GID_DW1`:

```
dw.gra        c8808ccd988d603dd35dff42013ae7fd   781656
english.txt   6a371099c0bd0777fa32e8d442cad204   228542

dw.scn        70955425870c7720d6eebed903b2ef41   776188
english.txt   7526cfc3a64e00f223795de476b4e2c9   228878
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

**Smaller since #7945 merged.** That commit carried the SCUMM
`getSaveStateName()` override as well; upstream has it now, and the
2026-09-15 rebase resolved the `scumm.h` conflict in upstream's favour. What
is left to offer is the base-class virtual plus SCUMM's one-line override of
it, nothing else.

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

## PR 8 — `LIBRETRO: exclude WebMIDI plugin` — FIXED UPSTREAM, CLOSED
`48dea85dc88` · +7/−4 · #111 closed: not a libretro change

> **Do not resolve this conflict by keeping our version.** Upstream fixed
> the same bug independently in `de8c01b` ("EMSCRIPTEN: Don't build WebMIDI
> with libretro"), authored 2026-09-13T08:35:22Z -- 32 seconds after
> `chkuendig` approved #7947. #7947 was closed as superseded the same day.
>
> The two fixes edit the same region different ways and **will conflict on
> every merge from upstream**:
>
> - ours (`f3c5255`): adds a condition, `#if defined(EMSCRIPTEN) && !defined(__LIBRETRO__)`
> - theirs (`de8c01b`): moves `LINK_PLUGIN(WEBMIDI)` inside the existing
>   `#if defined(__LIBRETRO__) ... #else ... #endif` block, where it is
>   excluded by construction and needs no extra condition
>
> **Take theirs, drop ours.** Behaviour is identical -- both exclude WebMIDI
> from libretro builds -- so the deployed core does not change. Theirs is
> cleaner and is what master will keep carrying.

Now scummvm/scummvm#7947, `BACKENDS: Do not link WebMIDI in libretro
Emscripten builds`: one line in `base/plugins.cpp`,
`#if defined(EMSCRIPTEN) && !defined(__LIBRETRO__)`. `module.mk` untouched.
The fork carries the same change as `f3c5255`. Body as originally submitted:

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

## PR 13 — `LIBRETRO: Log the unknown-game report when autodetection finds nothing` — OPEN as libretro/scummvm#113
`9ebc6940b1c` (PR head `31ebc43` on `staging_master`) · +2 · `backends/platform/libretro/src/libretro-os-utils.cpp` · issue #6 item 1

Platform-agnostic. Uses the backend's existing `logMessage()` and ScummVM's own
`generateUnknownGameReport()`, the same call `--detect` makes in
`base/commandLine.cpp`. Reaches the browser console only with EmulatorJS debug
mode on (RetroArch passes `-v` only then), which is the prerequisite the issue
records.

```
testGame() runs detection before --auto-detect ever does, so when nothing
matches, ScummVM's unknown-game report is never produced: the user gets an
empty launcher and no clue which files did not match. Log the report the
Add Game dialog would have shown.
```

## PR 14 — `LIBRETRO: Implement kFeatureOpenUrl on Emscripten` — OPEN as libretro/scummvm#114
`cdeaa23430d` (PR head `65d7f53` on `staging_master`) · +26 · `libretro-os.h`, `libretro-os-utils.cpp` · issue #6 item 2 · EMSCRIPTEN-guarded

Verified live: EMI's md5-check dialog ("Could not open the file voice.lab")
shows Open URL and the click opens the wiki in a new tab; Chrome did not block
it. Needed a rebuild of every backend object first -- see GOTCHAS, "Header
edits under backends/platform/libretro/".

Expect the same question `spleen1981` asked on #112: why an EMSCRIPTEN branch in
the shared core. Answer is the same: native libretro has no URL API; the guard
keeps every other target at `hasFeature() == false`, which is today's behaviour.

```
MessageDialogWithURL shows its button regardless of kFeatureOpenUrl and gates
only the click, so on the libretro core the button appeared and did nothing.
Declare the feature on Emscripten and open the link from the main thread,
since the engine runs on a worker where window.open() does not exist.
```

---

# EmulatorJS/EmulatorJS — four fixes, ready to open

Prepared 2026-09-15. All four are built and verified as **vanilla EmulatorJS at
`0b1c5e9` plus exactly one patch**, each with a regression check on a second
core, using `build/emulatorjs/standalone.sh --patch=<file>`.

**Their rules, re-read 2026-09-15 before drafting.** `CONTRIBUTING.md` in
`EmulatorJS/EmulatorJS`; nothing in `EmulatorJS/emulatorjs.org` beyond setup
instructions. Neither repo has a PR template, and **neither has an AI policy** —
unlike `scummvm/scummvm`. Our own `Assisted-by: Claude:<model-id>` trailer still
applies.

What their CI and docs actually demand:

- **Do not let an editor reformat anything.** CONTRIBUTING.md asks contributors
  to disable the VS Code formatter before submitting, and suggests
  `diffEditor.ignoreTrimWhitespace: false`. Keep diffs to the changed lines.
- **Every non-binary file must end with a newline** — enforced by
  `.github/workflows/newlines.yml` on every PR.
- **ESLint runs** (`eslint.config.js`): `no-var`, `prefer-const`,
  `prefer-arrow-callback`, all warnings, ES2020 modules. All four changes
  comply. Note the config does not extend `eslint:recommended`, so `no-undef`
  is off and `TextDecoder` not being in their `globals` list is not a failure.
- Base branch `main`. One topic per PR.

**No comments in any of these diffs.** Checked line by line.

**All four opened 2026-09-15.** Branches are cut from each repo's current
`main`. The three code PRs sit at `mergeable_state: blocked` with no checks
reported -- that is branch protection plus GitHub holding workflow runs for a
first-time contributor, not a fault. emulatorjs.org#78's Netlify preview built
clean.

## Save states: asked before submitting

PRs 6 and 9 are **on hold by choice**, not blocked. An issue was opened on
`libretro/scummvm` 2026-09-15 asking whether save-state support is wanted at
all, because the case against is real: ScummVM is not a machine emulator, its
own save system already works on every platform including this core, and our
`retro_serialize()` is a wrapper around `saveGameState()` rather than a new
capability. A desktop RetroArch user gains nothing. The motivation is
frontend-shaped -- ROMM's launcher and sync are built around save states -- and
that is divergence, not a general fix.

Upstream's `retro_serialize_size()` returns 0 today, so the core reports no
save-state support at all.

If the answer is yes, the general mechanism goes and one piece stays ours: the
`/savestate_error.txt` channel, which exists only because RetroArch's OSD is
invisible under EmulatorJS -- exactly the platform-specific kind of thing that
closed PR 11.

---

## PR 15 — `Restore mouse input on devices that report a touchscreen` — OPEN as EmulatorJS/EmulatorJS#1268

`build/emulatorjs/patches/03b-canvas-pointer-supports-mouse.patch` · +2 ·
`data/src/emulator.js`

```
The canvas is given ejs-canvas-no-pointer at construction whenever the device
reports a touchscreen, so the virtual gamepad overlay can receive touches. The
overlay is only displayed once a real touch happens. On a touchscreen laptop
neither is true: no overlay is shown, and the canvas still ignores the mouse,
so nothing receives pointer input.

Restore pointer events when the overlay is not up and the core declares
supportsMouse in its core.json, leaving every other core exactly as it is.
```

Verified on a touchscreen laptop, patched build: ScummVM (`supportsMouse: true`)
gets `pointerEvents: auto` and the mouse works; `fceumm` (`options: {}`) keeps
`ejs-canvas-no-pointer`, `pointerEvents: none`, and plays normally. A
keyboard-driven game (King's Quest 1, AGI parser) still takes typed input and
arrow keys, so restoring pointer events costs nothing on that side.

## PR 16 — `Decode the core report so its options are honoured` — OPEN as EmulatorJS/EmulatorJS#1269

`build/emulatorjs/patches/06-parse-core-report.patch` · +18/-3 ·
`data/src/emulator.js`

```
downloadFile() resolves the core report to { data, headers } where data is an
EJS_CacheItem holding the raw bytes in files[0].bytes. The handler assigns
rep = rep.data, so rep becomes the cache item -- no buildStart, no options --
and the JSON is never decoded. Every core is then fetched under its -legacy
filename regardless of what its report says, and the warning about caching
being disabled fires on every launch.

Decode the bytes and parse them.
```

Verified with a core whose report sets `defaultWebGL2: true`: before the patch
it is fetched as `scummvm-thread-legacy-wasm.data`, after it as
`scummvm-thread-wasm.data`. `fceumm`, whose report carries an empty `options`,
still gets `-legacy` and still plays — only cores that declare the option
change behaviour.

## PR 17 — `Set this.debug in EJS_Download` — OPEN as EmulatorJS/EmulatorJS#1267

Branch `TRusselo/EmulatorJS:fix-download-debug-logging`, **pushed 2026-09-13,
never opened** · +1 · `data/src/cache.js`

```
EJS_Download's constructor never assigned this.debug, so its three
"Using cached version of" statements could not run and a cache hit was
indistinguishable from a miss without the Network panel.
```

Verified in a browser: the line appears on a cache hit after the change and
never before it.

## PR 18 — `docs: build RetroArch from v1.22.2, not next` — OPEN as EmulatorJS/emulatorjs.org#78

`EmulatorJS/emulatorjs.org` · `content/2.docs4devs/4.buildingRAW.md`

```
The instructions clone the RetroArch fork with --branch next. That branch was
last updated 2026-05-16; v1.22.2 is the repository default and current to
2026-08-07. Anyone following the page builds cores against a stale branch.
```

Different repo from the other three. Documentation only.

---

# EmulatorJS/RetroArch

## PR 19 — `scummvm in requiresThreads` — DRAFTED, NOT OPENED, same gate as PR 12

`build/emulatorjs/patches/07-scummvm-requires-threads.patch` · +1 ·
`EmulatorJS/EmulatorJS` `data/src/consts.js`

`core.json`'s `requireThreads` is declarative only -- their own `cores.json`
sets it for `ppsspp`, `dosbox_pure` and `azahar`, but the string appears nowhere
in `data/src/` or the bundle. Enforcement is the hardcoded array:

```js
export const requiresThreads = ["ppsspp", "dosbox_pure", "azahar"];
```

Without an entry there, an embedder who forgets `EJS_threads` gets a generic
"Error for site owner" instead of `This core requires threads, but EJS_threads
is not set!` (`emulator.js:611`), and the user-facing Threads toggle stays
visible (`emulator.js:5348`) for a core with no non-threaded build.

Verified vanilla-plus-this-patch-only: omitting `EJS_threads` names the cause,
and a normal load still fetches the core and its engine-data and runs.

**Same gate as PR 12**: meaningless until `cores.json` has a `scummvm` entry,
since it is an entry for a core they do not have. Keep `requireThreads: true`
in our `core.json` regardless -- it matches what every threaded core declares.

## PR 20 — `Show errors in red and stop styling every message as one` — DRAFTED, NOT OPENED

`EmulatorJS/EmulatorJS` branch `msg-severity` · `data/emulator.css`,
`data/src/emulator.js`, `data/src/GameManager.js`, `data/src/netplay.js`

```
.ejs_message is styled `color: red` for every message, so "SAVED STATE TO
SLOT 1" reads as a failure. displayMessage() takes an optional severity that
colours the element, and the save-state and netplay call sites pass it.
```

Reach: every core, every embedder. No behaviour change beyond colour; a caller
that passes no severity gets the element it always got, minus the red.

Independent of #1267, #1268 and #1269 — `git merge-tree` is clean against all
three, and only #1268/#1269 touch `emulator.js` at all.

This also retires the one place we were writing RomM's own class names into
EmulatorJS. Patch 04 added `msg-error`/`mdi-alert` from inside `showFailure()`
because RomM hid every unclassed `.ejs_message` (D1); rommapp/romm#4520 fixed
that, so `showFailure()` is now one line and the class names are gone.

Not verified in a browser yet — see the test list on issue #12 §3.

---

# libretro/scummvm

## PR 23 — `Show decompression progress instead of a frozen download percentage` — DRAFTED, NOT OPENED

`EmulatorJS/EmulatorJS` branch `fix-decompress-progress` · +16/−7 ·
`data/src/emulator.js`

```
cache.js reports "decompressing" ticks and the Decompress Game * strings are
already translated, but the progress wrapper only passed "downloading"
through, so the loading text held the last download value for the whole
unpack. The decompressor sends percentage with no total or loaded, so
percentage is now honoured on its own.
```

Reach: every core, every embedder, any archive big enough for the unpack to be
visible. Split out of patch 02, which is otherwise ours to keep.

**The evidence is in their own tree**, which is what makes this worth sending:

- `cache.js:236` and `:242` already call `onProgress("decompressing", …)`
- `cache.js:100`'s docstring says the callback "returns status(downloading or
  decompressing)"
- `Decompress Game Core` / `Data` / `BIOS` / `Parent` / `Patch` are translated in
  **22 localization files**
- and `emulator.js`'s wrapper drops every one of those ticks with
  `if (status === "downloading")`

So the feature was built end to end and the consumer throws it away. Five
localized strings that nothing can ever display is the symptom.

Two call sites are relabelled, Core and Data — the only two with both a
`+ progress` readout and an existing translated string. `Download Game State`
is left alone: a `.state` file is not an archive, and there is no
`Decompress Game State` string. `Download Game BIOS` / `Parent` / `Patch` appear
nowhere in `data/src/` at all, so those translations were already orphaned
before this and are out of scope.

The `percentage` handling is the non-obvious half: the wasm extractor reports
percentage with `total` and `loaded` both zero, so the old `total ? … : …`
ternary would have shown `0.00MB` for the whole decompression.

Verified: `npx eslint data/src/emulator.js` output byte-identical before and
after, trailing newline intact (their `newlines.yml` checks every non-binary
file). No PR template, and their AI restriction is scoped to *bug reports*
(`.github/ISSUE_TEMPLATE/bug.md`), not pull requests -- same basis as #1267,
#1268 and #1269.

### Not drafted: `ejsUserMessage`

The other candidate from patch 02 was letting a download error carry its own
user-facing reason instead of collapsing to "Network Error". **It is not
submittable.** The only thing that ever sets `ejsUserMessage` is patch 01's
streaming extractor (`01-cache-streaming.patch:89`). Upstream has no producer,
so the change would add a mechanism nothing triggers. It stays coupled to 01.

## PR 21 — `LIBRETRO: Give OSD notifications a severity` — DRAFTED, NOT OPENED

`260af0f0ad8` · +13/−10 · `backends/platform/libretro/src/libretro-core.cpp`,
`libretro-os-utils.cpp`, `include/libretro-core.h`

```
retro_osd_notification() fills four fields of retro_message_ext and leaves
priority, level and progress at whatever was on the stack. Zero-initialise it
and take a level, so a frontend that ranks or filters messages gets a real
value.
```

Reach: **libretro core, all targets, not Emscripten-specific.** The function is
`3590bb387cf` (Giovanni Cascione, 2023-05-10); the missing fields have been
there since. This is their bug, not ours, which is what makes it worth sending.

Eleven call sites classified: `RETRO_LOG_ERROR` for "Game not found" and
"Failed to set up HW rendering", `RETRO_LOG_WARN` for the folder-missing and
save-refusal messages, default `RETRO_LOG_INFO` for the rest.

Keep it terse — #110, #113 and #114 all went in as a few lines of body, and
`spleen1981` asked for a code comment to be removed on #110.

## PR 12 — `EMULATORJS: add scummvm to the large-stack, large-heap and async core lists` — DRAFTED, NOT OPENED
`5323840b21` on local branch `ejs-build-scummvm-arrays` (worktree in the session
scratchpad), based on `origin/v1.22.2` · +3/−3 · `emulatorjs/build-emulatorjs.sh`

Their rules, read 2026-09-12 before drafting (`.github/PULL_REQUEST_TEMPLATE.md`,
`CONTRIBUTING.md`; no AI policy anywhere in EmulatorJS or its RetroArch fork,
nor an org-level `.github`): rebase first, one topic per PR, squash to a single
commit, base on `v1.22.2` (their default; #45 and #38 merged there), fill the
template's Description / Related Issues / Related Pull Requests / Reviewers.

**Gate: this PR is part of the "submit core" process, not a standalone fix.**
The arrays are keyed by core name, and their link script only sees a
`scummvm` `.bc` if `cores.json` has a `scummvm` entry, which needs an
`EmulatorJS/scummvm` fork to clone. So it hinges on EmulatorJS accepting the
core at all (the #1263 conversation), then forking, and it is opened together
with the `cores.json` entry in `EmulatorJS/build` — either one alone breaks
their build of the core. Opened earlier it is entries for a core they do not
have. Open with:

```
git -C retroarch push fork ejs-build-scummvm-arrays
gh pr create -R EmulatorJS/RetroArch --base v1.22.2 --head TRusselo:ejs-build-scummvm-arrays
```

Body (their template, filled):

```
## Description

Adds `scummvm` to `largeStack`, `largeHeap` and `needsAsync` in
`emulatorjs/build-emulatorjs.sh`.

The ScummVM libretro core embeds its engine-data files, so its static data
exceeds the 128 MB default at link time (`wasm-ld: error: initial memory too
small, 186199984 bytes needed`), and it runs on real pthreads with Asyncify
like `dosbox_pure`.

## Related Issues

EmulatorJS/EmulatorJS#1263

## Related Pull Requests

A `cores.json` entry in EmulatorJS/build, to follow once the core repository
is forked.
```

---

# Internal — not for the PRs

**Two things caught by reading the PRs after opening them, both worth repeating
before the next batch.**

*Scope, stated up front.* PR 8 removed WebMIDI and the body never said what else
that touched. Both edits sit inside existing `EMSCRIPTEN` guards, no other
platform is affected, and the core still reaches MIDI through the frontend's
`RETRO_ENVIRONMENT_GET_MIDI_INTERFACE` -- all true, none of it written down. It
also left the removed lines commented out rather than deleted, which upstreams
generally reject; git history is the record. Revised to `+7/-4` and the body now
answers the scope question before a reviewer has to ask it.

*Claims, kept to what was verified.* PR 2 said "Both play." Booting into
gameplay is not playing through, and a detection entry asserts a release is
supported. Withdrawn rather than softened. The rule this violates is the
project's own: our testing does not overrule ScummVM's, and a title booting once
says nothing about completability. PR 3's body is the shape to copy -- it claims
an assertion fixed and explicitly disclaims the engine's remaining hangs.

*Build hygiene.* `backends/platform/libretro/lite_engines.list` is always dirty
in this tree -- `build-core.sh` writes it. `git commit -a` swept 96 unrelated
lines into PR 5's commit; caught before pushing. Stage files explicitly.


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

---

## RomM's EmulatorJS version

rommapp/romm#4539 was the duplicate-mkdir backport: two `sed` calls against the
vendored EmulatorJS 4.2.3 in RomM's Dockerfile, each guarded by a `grep -q` so a
future version fails the build loudly. `zurdi15` closed it 2026-09-16 --
"a messy patch for something that emujs will release at some point" -- and he is
right about the shape. We reached the same conclusion independently: `6bb3cdf6e`
deleted that exact patch from our fork when we moved to a pinned `main` checkout,
for the same reason.

**He is waiting for a real thing.** 4.3.0 is in pre-release testing:
`v4.3.0-pre`, published 2026-05-17 with a `4.3.0-pre.7z` asset, and `9a12941`
-- the duplicate-mkdir fix -- is in it, which our own `c073a5297` said at the
time. Waiting for that to go stable rather than `sed`-patching 4.2.3 is the
right call, and this file briefly claimed otherwise off a misread of
`package.json`'s unbumped `4.2.4` dev version.

What is worth recording is the timeline, not a complaint about it:

| | |
|---|---|
| last **stable** release | `v4.2.3`, 2025-07-05 |
| 4.3.0 pre-release | `v4.3.0-pre`, 2026-05-17, still prerelease |
| commits on `main`, last 90 days | 15, most recent 2026-08-07 |
| our pinned `EJS_COMMIT` `0b1c5e9` | `v4.3.0-pre` + 20 commits |

RomM's Dockerfile pins 4.2.3 today and moves when 4.3.0 goes stable, which is
not imminent at that cadence.

Two consequences:

1. The only untested target is **4.2.3**, which is what RomM ships today. Our
   pinned `0b1c5e9` is `v4.3.0-pre` plus 20 commits, so the vanilla test
   (GOTCHAS, 2026-09-14) already covers the prerelease. When 4.3.0 goes stable
   RomM lands on a tree we have effectively validated against.
2. It bounds `6bb3cdf6e`. Our pin is 20 commits past `v4.3.0-pre`, and the
   reasons for it -- duplicate-mkdir, Core Options v2 -- are in the prerelease
   or on main ahead of it. The pin is a bridge to 4.3.0, not a permanent
   divergence; drop it once 4.3.0 is stable.

Second downstream in a row to say the fix belongs upstream rather than in their
tree -- `spleen1981` on libretro/scummvm#111, now `zurdi15` here. Offer the fix
where it lives, not where it hurts.

# Downstream issue drafts (ROMM / EmulatorJS), 2026-09-13

Found while making a save-state refusal visible. None are ScummVM or libretro
issues; all three are in the layers below us, and all three affect every core in
a deployment, not just ours. Not filed yet.

| # | where | one line | status |
|---|---|---|---|
| D1 | rommapp/romm#4504 | `.ejs_message` is `visibility: hidden`, so EmulatorJS's own messages never appear | **filed** 2026-09-13, with the AI disclosure CONTRIBUTING.md requires |
| D2 | EmulatorJS/EmulatorJS | `EJS_Download` never sets `this.debug`, so three log statements are dead | **will not be filed by an agent** -- see note |
| D3 | rommapp/romm | core variant is unpinned, so the same core caches twice | **blocked** — see note |

**D2 must be filed by a human, or not at all.** EmulatorJS's bug template
(`.github/ISSUE_TEMPLATE/bug.md`) carries two checkboxes we cannot honestly
tick:

> - [ ] I am not an LLM/Ai. Bug reports filed by ai will be closed. Just type
>       out the issue yourself it's not that hard
> - [ ] I have not made any changes to the EmulatorJS instance I am running
>       into this bug on.

The first is an explicit prohibition; the second fails anyway, since this
deployment runs four local patches. Do not file it from here. The finding stays
recorded below in case a human wants to report it from an unpatched instance.

**D3 is not filable as-is.** Pinning `EJS_webgl2Enabled` is a workaround for a
report-fetch flake; the real path is our core being a normal EmulatorJS core
whose `reports/scummvm.json` is served the way every other core's is. That
depends on issue #4 (release blockers). Raise it with EmulatorJS as part of that
conversation rather than as a ROMM bug.

## D1 — ROMM hides every message EmulatorJS raises for itself

`frontend/src/views/Player/EmulatorJS/Player.vue`:

```css
#game .ejs_message            { visibility: hidden; }
#game .ejs_message.msg-info    { visibility: visible; }
#game .ejs_message.msg-error   { visibility: visible; }
#game .ejs_message.msg-success { visibility: visible; }
```

ROMM adds one of those classes from its own `displayMessage` wrapper, so
messages ROMM sends are visible. But `.ejs_message` is the element
EmulatorJS's own `displayMessage()` writes to, and it adds no class -- so
**every message EmulatorJS raises for itself is invisible**: `FAILED TO SAVE
STATE`, `SAVED STATE TO SLOT`, core download errors, and anything a core
surfaces through it. This affects all cores.

Reproduce: in a running game, `EJS_emulator.displayMessage("test")`. The
element gets the text (`EJS_emulator.msgElem.textContent`) and never appears.

Suggested fix: make the base class visible and let ROMM's classes control
colour only, or have the wrapper add a default class. Either way the default
should not hide an element ROMM does not exclusively own.

**FIXED UPSTREAM.** Filed as rommapp/romm#4504, fixed by rommapp/romm#4520
(`8c7b2c64f`, `gantoine`) taking the first of those two options, and picked up
in our 2026-09-15 rebase. Patch 04's `msg-error`/`mdi-alert` workaround existed
only for this and has been removed — see PR 20.

## D2 — `EJS_Download` never assigns `this.debug`

`data/src/cache.js`:

```js
constructor(storageCache = null, EJS = null) {
    this.storageCache = storageCache;
    this.EJS = EJS;
}
```

No `this.debug`, so the three `if (this.debug) console.log("Using cached
version of", url)` statements (lines ~141, ~153, ~158) can never fire. The
`this.debug = debug` at line ~400 belongs to `EJS_Cache`, a different class.

Consequence: there is no way to tell a cache hit from a miss in the console.
Diagnosing one currently needs the Network panel. `EJS_emulator.downloader.debug
= true` before starting a game is a usable workaround and confirms the
statements are otherwise correct.

## D3 — core variant depends on a report fetch, so the same core can cache twice

`data/src/emulator.js`:

```js
if (this.webgl2Enabled === null) {
    this.webgl2Enabled = rep.options ? rep.options.defaultWebGL2 : false;
}
let legacy = (this.supportsWebgl2 && this.webgl2Enabled ? "" : "-legacy");
let filename = this.getCore() + (threads ? "-thread" : "") + legacy + "-wasm.data";
```

When `reports/<core>.json` fails to fetch, `defaultWebGL2` is unknown and the
`-legacy` filename is chosen instead. Those are two different cache keys, so an
intermittent report fetch means the same core is downloaded and cached twice.
For a ~1 MB core that is unremarkable; for ours it is 198 MB per copy once
extracted.

Also note the warning text is wrong: on that path `buildStart` is set to
`Math.random() * 100` under a message saying "Core caching will be disabled",
but `buildStart` is never read anywhere in this version.

**Do not file this at ROMM.** See the note above.

