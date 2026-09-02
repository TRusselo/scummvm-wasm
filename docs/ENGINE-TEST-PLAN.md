# Engine Test Plan

Phase 1 (this document): compile a prioritized list of ScummVM engines to
test, one representative popular game each, plus a smaller/easier
candidate ROM for the actual test. Phase 2 (testing) is now underway.

## Confirmed working so far (46 of 102, + agos2 subengine bonus)

`agi`, `sci`, `sky`, `agos` (base + `agos2` subengine), `adl`, `cge`,
`cge2`, `parallaction`, `drascula`, `lure`, `queen`, `wage`, `dreamweb`,
`got`, `teenagent`, `awe`, `sword1`, `sword2`, `ags`, `kyra`, `gob`,
`cine`, `sherlock`, `hugo`, `touche`, `cruise`, `sword25`, `saga`,
`toltecs`, `tucker`, `mohawk`, `made`, `dgds`, `darkseed`, `nancy`,
`hopkins`, `mediastation`, `mtropolis`, `groovie`, `lastexpress`, `toon`,
`ultima` (via `ultima8`), `director`, `voyeur`, `asylum`, `buried`. Marked **Confirmed working** in their table row below — search this file for that phrase to
jump to them.

`sludge` was tested successfully (The Interview, freeware) but then
removed and skipped per user caution (unsigned/unverified `.exe`, low
value anyway since ScummVM itself marks SLUDGE unstable/WIP).

`griffon`, `glk`, `dm`, `tony`, and now `neverhood` **blocked** on the
same shared bug, not a packaging problem: all five needed their
`fonts.dat` companion file (found and fixed), but all five then crash
with the **identical** `RuntimeError: memory access out of bounds` stack
trace once that file is supplied (same wasm function indices and byte
offsets — see GOTCHAS.md's "Suspected shared bug" section). This looks
like a bug in ScummVM's common font-rendering codepath in this WASM
build, not something fixable by repackaging. Any other untested engine
that reports "Could not locate the 'fonts.dat' engine data file" should
be treated as high-risk for this same crash. Deferred by user decision
rather than investigated further tonight.

All five ROMs are correctly packaged (fonts.dat fix already applied)
and kept — not deleted — in
`/mnt/unraid/emulation/scummvm/non-running/` (`Griffon Legend.zip`,
`Zork I.zip`, `Dungeon Master.zip`, `Tony Tough.zip`, `Neverhood.zip`),
for easy retesting once the underlying WASM bug is fixed. `non-running/`
is the convention going forward for any ROM that's packaged correctly
but blocked by an
engine/core bug rather than
abandoned — as opposed to a bad packaging attempt, which just gets fixed
in place or discarded.

## Scope

- **102 top-level engines** below: every engine in
  `build/engine-lists/all-engines.list` except `scumm` (base SCUMM is
  already extensively validated — MI1/2, Loom, Sam & Max, Full Throttle,
  Curse of Monkey Island, The Dig all confirmed working). Subengines
  (`scumm_7_8`, `he`, `sci32`, `eob`/`lol`, etc.) are grouped under their
  parent, not tested separately, per your call.
- **11 deferred GL-core engines** in their own section at the end —
  researched for completeness, but not testable until that separate core
  gets built.
- `agos` (Simon the Sorcerer) is included below but flagged
  already-confirmed — it booted successfully during tonight's bug-fixing
  session, so it's effectively done, just not called out as excluded
  since that wasn't part of what you asked to skip.

## How to read this

Ordered by rough popularity tier (Widely Known → Genre-Notable →
Niche/Obscure → Unclear/Needs Verification), most popular first per your
request. Within a tier, order is a rough judgment call, not precise.
**"Candidate Test ROM" is chosen for ease of testing, not necessarily the
same as "Most Popular Game"** — a small freeware/shareware title from the
same engine is preferred when the flagship is large or hard to source,
since the goal is proving the engine works, not playing its biggest game
first.

**Confidence note:** most of this was compiled from general knowledge by
parallel research agents, with light web verification on some batches.
Anything marked **unclear** below is a genuine gap, not a guess — verify
those directly against [ScummVM's own supported games
wiki](https://wiki.scummvm.org/index.php/Category:Supported_Games) before
sourcing a ROM for them. One cross-engine mixup was caught and corrected:
an earlier draft suggested *5 Days a Stranger* as a Wintermute test
candidate — it's actually an AGS-engine game (confirmed correctly listed
under `ags` below), so Wintermute's candidate is flagged for
re-verification instead of asserting a possibly-wrong title.

**One special case, not a normal row:**
- **`agos`** — see above, already confirmed working tonight.

**Parent engines with no standalone game of their own** (`mm`, `tsage`,
`ultima`): each is grouped with several subengines, but the parent
itself has no playable title — only the subengines do. Resolved by
picking each parent's newest/most feature-rich subengine and testing a
game from that instead: `mm` → `xeen` (World of Xeen, 1992-93 — a real
technical leap over `mm1`'s 1986 original), `tsage` → `ringworld2`
(Return to Ringworld, 1994, sequel to 1993's Ringworld), `ultima` →
`ultima8` (Ultima VIII: Pagan, 1994 — SVGA graphics, the most advanced of
the `ultima4`/`ultima6`/`ultima8` trio). These appear below under their
parent engine name with the chosen subengine noted.

**Easiest-possible starting points**, regardless of tier (officially
freeware, often hosted directly by ScummVM or the original developer, no
sourcing effort required): `adl` (Mystery House — bundled ScummVM
freeware game), `cge` (Soltys — bundled ScummVM freeware game),
`mutationofjb` (Mutation of J.B. — freeware, made for ScummVM),
`queen` (Flight of the Amazon Queen — official freeware), `sky` (Beneath
a Steel Sky — official freeware), `lure` (Lure of the Temptress — made
freeware by Revolution), `dreamweb` (DreamWeb — legally freeware since
2011), `sword1` (Broken Sword — official free demo available). Worth
doing several of these first regardless of where they fall in the
popularity ordering below, purely because they remove all sourcing
friction.

---

## Widely Known

| Engine | Most Popular Game | Candidate Test ROM | English Available | Source Note |
|---|---|---|---|---|
| agi | King's Quest I | **Confirmed working** (Leisure Suit Larry 1-3 and Space Quest I-III both play) | Yes | Already tested |
| glk | Zork I | **Blocked** — same shared engine-level bug as `griffon` (see GOTCHAS.md): needs `fonts.dat` companion file (confirmed, now fixed), but crashes with the identical `RuntimeError: memory access out of bounds` stack trace once that file is supplied. Genuine cross-engine WASM bug, not fixable by repackaging | Yes, legally free | Already tested (archive.org `zork1` item, official Infocom DOS release, MD5-matched to detection table entry `88-840726`) |
| awe | Another World / Out of This World | **Confirmed working** — English DOS release, flat zip (no subdirectories, no fonts.dat needed) | Yes | archive.org (`another_world_dos`), already tested |
| dm | Dungeon Master | **Blocked** — same shared `fonts.dat` engine bug as `griffon`/`glk` (third confirmation of the identical crash signature, see GOTCHAS.md) | Yes | archive.org (`msdos_Dungeon_Master_1989`), already tested |
| sword1 | Broken Sword: The Shadow of the Templars | **Confirmed working — full game**, not just the demo. Merged both CD's unique content (English speech, music, cutscenes) into one ~1080 MiB zip, following user's "prefer full game over demo unless it's over the size limit" preference (explicit override granted for this one, since even after deduplicating identical files across discs it landed just over 1 GB). Needed each disc's own `SPEECH.CLU` renamed to `SPEECH1.CLU`/`SPEECH2.CLU` (see GOTCHAS.md's multi-CD section); demo's root-anchor-file lesson still applied | Yes | archive.org (`Broken_Sword_The_Shadow_of_the_Templars_Europe`), raw `.mdf` CD images converted to ISO9660 by hand (see GOTCHAS.md) |
| sword2 | Broken Sword II: The Smoking Mirror | **Confirmed working — full game**, not just the demo. Same merge approach as `sword1`: both CDs' unique `Clusters`/`Smacks` content combined into one ~1056 MiB zip (explicit size-limit override granted), each disc's `Music.clu`/`speech.clu` renamed to `Music1/2.clu`/`speech1/2.clu` | Yes | archive.org (`Broken_Sword_II_The_Smoking_Mirror_Europe`), raw `.mdf` CD images (Mode 2 Form 1 on CD1, Mode 1 on CD2 — mixed sector modes across discs of the same game) converted to ISO9660 by hand |
| sci | King's Quest V | **Confirmed working** (King's Quest V plays) | Yes | Already tested |
| bladerunner | Blade Runner | Only title (CD-ROM, FMV-heavy, no smaller alt) | Yes | archive.org Westwood/abandonware collections |
| ultima | Ultima VIII: Pagan (via `ultima8` subengine) | **Confirmed working** — and found a genuinely new packaging gotcha along the way (see GOTCHAS.md's "Subdirectory-structured engines: the anchor file's own directory is scanned, not the zip root" section). First attempt used a GOG repack (`msdos_Ultima_VIII_-_Pagan_1994`, archive.org) whose `usecode/eusecode.flx` hash-matched the "Gold Edition" detection entry exactly, but that entry also requires `static/eintro.skf` — a different subdirectory — and ScummVM's libretro backend's autodetect only scans the **anchor file's own parent directory** (`libretro-core.cpp`'s `retro_load_game()` → `parent_dir = FSNode(game->path).getParent()`), not the zip root; with `usecode/eusecode.flx` as the anchor, `static/` was never visible, producing an empty ScummVM launcher (no crash, just nothing detected). Separately, `ultima8`'s own `_directoryGlobs` only lists `"usecode"` (`engines/ultima/detection.cpp`), so even a root-anchored scan can never see into `static/` for entries that need both — that specific Gold Edition 2-file entry is undetectable via directory autodetect no matter how it's packaged. Switched to a different archive.org dump (`Ultima-VIII-Pagan`/`pagan-ultima-viii.zip`) whose `eusecode.flx` hash-matches the simpler single-file "Ultima VIII - CD" entry instead (no `static/` dependency), packaged with the true root-level `u8.exe` as the first zip entry (anchor). Needed ScummVM's own `ultima8.dat` companion file (from `scummvm-core/dists/engine-data/`) added to the zip. Booted straight into the real rendered title/story sequence ("Your two worlds will be crushed... Britannia first, then Earth!"); audio confirmed live via engine state (`started:true`, `muted:false`). Menu/gameplay mouse interactivity not separately verified — same pointer-lock automation limitation noted on `toon` this batch | Yes | archive.org (`Ultima-VIII-Pagan` item) |
| twine | Little Big Adventure | Same | Unclear | Deferred — only accessible archive.org copy found is a 500 MiB CD `.bin`/`.cue` image (French "Adeline" branding, English uncertain); needs CD-image mounting rather than a plain data zip, skipped for now |
| mohawk | Myst | **Confirmed working** — correction: the tracker's original candidate (Logical Journey of the Zoombinis) turned out to be entirely `ADGF_UNSUPPORTED`/`GAME_NOT_IMPLEMENTED` in ScummVM's own detection table (every zoombini entry, DOS and demo alike) — it's detected only to show a "not supported" message, never playable. Pivoted to Myst itself instead. The archive.org CD image (`cdrom-myst-1.2`) is a single Mode1/2352 track, no CD audio; stripped to a 640MB ISO9660 with a Python sector-strip script, then 7z-extracted. The disc root is itself an **installer disc** (installer subfolders `MYST32`/`MYST16` present) but, unlike the Gobliiins/Tucker pattern, the actual game's Mohawk `.DAT` archives (`MYST.DAT`, `STONE.DAT`, etc.) and its `QTW/` QuickTime-movie subdirectory sit right at the disc root alongside the installer folders — no CD-image-within-an-image needed, just excluding the installer/setup clutter. `MYST.DAT`'s size matched a known detection-table entry exactly but its MD5 didn't (yet another size-match/hash-mismatch case, harmless here since Mohawk detection didn't require an exact table hit) — detected and booted straight to the intro cinematic and into the in-game dock scene, screenshot-confirmed navigable | Yes | archive.org (`cdrom-myst-1.2`), raw Mode1/2352 CD `.bin`/`.cue` converted to ISO9660 by hand, ~573 MiB after excluding installer folders |
| mediastation | Muppet Treasure Island | **Confirmed working** — tested Beatrix Potter instead, per the size-limit swap rule (Muppet Treasure Island's only found copy is a 3-disc release well over 1GB). Booted and played correctly, proving the engine works. Not kept in the live library — removed at the user's discretion (didn't like the game itself, unrelated to the test result) | Yes | archive.org, already tested |
| nancy | Nancy Drew: Secrets Can Kill | **Confirmed working** — single-disc CD-ROM release (archive.org item's disc 2 was unneeded, disc 1 alone has the full game). Disc was a raw Mode 2 Form 1 `.iso` (2352-byte sectors, `.iso` extension despite not being a plain ISO9660 image already) needing the same sector-strip treatment as `.mdf` images (offset 24). Needed ScummVM's own `nancy.dat` companion file (straight append, no collision). The engine's `directoryGlobs` registers `game`/`cdsound`/`cdvideo`/`hdvideo` as matching subdirectories, so the disc's original folder structure could be kept as-is inside the zip rather than flattened — just excluded installer-only clutter (`Redist/`, `SETUP.EXE`, etc.). `CifTree.dat` was another size-match/hash-mismatch case, harmless. Booted straight into the actual game menu and intro letter, screenshot-confirmed | Yes | archive.org (`nancy-drew-secrets-can-kill-disc-1`), already tested |
| groovie | The 7th Guest | **Confirmed working** — swapped to The 11th Hour (Interactive Demo) after two independent 7th Guest DOS/Windows dumps both matched detection's file sizes exactly but failed MD5 (see GOTCHAS.md's "5000-byte detection hash" note — these may actually be valid dumps, not re-checked). The 11th Hour's official Interactive Demo (cited directly in `groovie/detection.cpp`'s own source comment as sourced from `archive.org/details/11th_Hour_demo`) matched exactly once verified correctly. Needed `icons.ph` (cursor resource) and `sample.AD`/`sample.OPL` (AdLib timbre files) from the disc's `SYSTEM/` folder alongside the `GROOVIE/`+`MEDIA/` game files — none of these are part of the detection entry's two hashed files, so their absence produces a runtime crash-to-debugger (`Couldn't open icons.ph or icons.bin`, then `MILES-ADLIB: could not open timbre file`) rather than a detection failure. Booted into the real FMV brightness-calibration screen; engine state checked directly (`started:true`, `muted:false`, `volume:0.5`, no errors) to confirm audio pipeline is live, not just the visual | Yes | archive.org (`11th_Hour_demo`), ISO extracted with `7z` |
| sky | Beneath a Steel Sky | **Confirmed working** — officially freeware | Yes | Already tested |
| adl | Mystery House | **Confirmed working** — bundled ScummVM freeware game | Yes | Already tested |
| lastexpress | The Last Express | **Confirmed working** — full retail is 3 CDs (~3.8GB), way over the size limit with no lighter cut, so used the official English Interactive Demo instead. Initially misdiagnosed as hash-mismatched (full-file MD5 on `Demo.HPF` didn't match); re-checked with the correct 5000-byte-prefix hash (see GOTCHAS.md) and it matched exactly. The demo is a single self-contained `DEMO.HPF` archive — `lastexpress/data/archive.cpp` opens exactly that one filename for demo builds, no companion files needed. Booted straight to the real title/map screen (Fabergé-egg clock, Europe route line, Volume/Brightness/Quit menu) | Yes | archive.org (`LASTEXPR`/`Last_Express_demo`, byte-identical mirrors), already tested |
| ags | (actively used indie engine — Blackwell, Unavowed, etc.) | **Confirmed working** via 5 Days a Stranger (Chzo Mythos) — a bare freeware `.exe`, no companion files, no subdirectories | Yes | archive.org (`5_Days_a_Stranger`), already tested |
| toon | Toonstruck | **Confirmed working** — full retail is 2 CDs (~1.2GB combined 7z downloads, over the size limit), and the only demo dump found (`toonstruck-subspace-demo`, archive.org) has a `local.pak` that's 1KB off the demo detection entry's size (different revision, doesn't hash-match, not pursued further). Instead used just **CD1** of the English "2-CD Sold Out re-release" (`toonstruck` item, `TOONCD1.7z`) — this budget re-release's detection entry only requires `local.pak`+`generic.svl` (not the four-file `arcaddbl.svl`/`study.svl` set the original release needs), and both files matched the entry's size and 5000-byte hash exactly. CD1 alone (Act 1 + Misc, ~530MB) is under 1GB and self-contained detection-wise. Needed ScummVM's own `toon.dat` companion file (from `scummvm-core/dists/engine-data/`, not present in the game data) added to the zip — without it, get "Unable to locate the 'toon.dat' engine data file". Subdirectory structure (`MISC/`, `ACT1/...`) must be preserved per the engine's `directoryGlobs`; `MISC/LOCAL.PAK` kept as the first zip entry. Booted straight into the real animated title screen (spinning-propeller-hat clown, confirmed live via repeated screenshots) with audio confirmed live via engine state (`started:true`, `muted:false`). Menu-button clicks couldn't be verified in this session — `requestPointerLock()` threw `WrongDocumentError` in the browser-automation tab, leaving the in-game software cursor frozen; this reads as an automation-environment limitation (relative-mouse-without-lock), not a packaging or engine defect — see GOTCHAS.md's "Mouse input and pointer lock" section | Yes | archive.org (`toonstruck` item, CD1 only), 7z+bchunk extracted |
| startrek | Star Trek: 25th Anniversary | Same | Yes | Deferred — archive.org only has raw floppy disk images (`.7z` of `.img` files) for the DOS release, needing disk-image extraction rather than a plain data zip; skipped for now |

## Genre-Notable

| Engine | Most Popular Game | Candidate Test ROM | English Available | Source Note |
|---|---|---|---|---|
| kyra | The Legend of Kyrandia: Book One | **Confirmed working** — needed `kyra.dat` companion file swap (same collision pattern as `teenagent` — see GOTCHAS.md) | Yes | archive.org (`msdos_Legend_of_Kyrandia_Book_1_1992`) — excluded a bundled CD-variant bonus subfolder (500MB+ of unneeded assets), floppy game data alone is ~32 MiB |
| mm | World of Xeen (via `xeen` subengine — newest/most feature-rich of mm1/xeen; base `mm` has no standalone game) | Might and Magic IV: Clouds of Xeen alone (lighter than the combined World of Xeen release) | Yes | archive.org Might and Magic / New World Computing collections |
| tsage | Return to Ringworld (via `ringworld2` subengine — sequel, newest of the tsage-based titles; base `tsage` has no standalone game; based on Larry Niven's Hugo/Nebula-winning novel) | Same (only title on this subengine) | Yes | archive.org, "Return to Ringworld DOS" |
| sherlock | The Lost Files of Sherlock Holmes: The Case of the Serrated Scalpel | **Confirmed working** — correction: "Sherlock Holmes: Consulting Detective" (an earlier draft's candidate) is a different, FMV/laserdisc-based series not supported by ScummVM's `sherlock` engine at all; the correct title is this one | Yes | archive.org (`msdos_Sherlock_Holmes_-_The_Case_of_the_Serrated_Scalpel_1992`), already tested |
| queen | Flight of the Amazon Queen | **Confirmed working** — officially freeware; needed `queen.tbl` companion file | Yes | Already tested |
| lure | Lure of the Temptress | **Confirmed working** — freed by Revolution Software; needed `lure.dat` companion file | Yes | Already tested |
| gob | Gobliiins | **Confirmed working, with music** — packaged from the CD version's data track (extracted via `bchunk`; a floppy-install source folder found first turned out to be pre-install stub files, not the real game). This specific dump's `INTRO.STK` doesn't match any known hash in ScummVM's detection table despite matching size exactly, but it detected and ran fine anyway. Music required converting the CD audio track to Ogg Vorbis and naming it `track01.ogg`/`track02.ogg` (see GOTCHAS.md — first attempt used `bchunk -s`, which produced pure static; re-ripped without that flag) | Yes | archive.org (`msdos_Gobliiins_1_1991`), CD image (`.bin`/`.cue`) inside the package |
| cine | Future Wars | **Confirmed working** — a bundled CD-variant install already had pre-ripped `track1.mp3` etc. in ScummVM's exact naming convention, no manual audio work needed | Yes | archive.org (`msdos_Future_Wars_1989`), already tested |
| cruise | Cruise for a Corpse | **Confirmed working** — flat single-wrapper-folder zip, no companion files needed | Yes | archive.org (`msdos_Cruise_for_a_Corpse_1991`), already tested |
| cryo | Dracula: The Resurrection | Same | Yes | archive.org Cryo Interactive collections |
| cryomni3d | Atlantis: The Second Age | Versailles 1685 (smaller scope) | Yes | archive.org Cryo back-catalog |
| darkseed | Dark Seed | **Confirmed working** — the archive.org floppy-disk dump (`000834-Darkseed`) was a genuine installer-seed case needing raw-floppy tooling; instead sourced an already-installed CD release whose root also contained clutter (a nested `cd/DARKSEED/` install-disc-plus-clutter layout), extracted just the `cd/DARKSEED/` subtree (~28 MiB, includes ART/PICTURE/ROOM/SOUND/SPEECH). `TOS.EXE` matched the CD English entry's exact size (168480 bytes) but not its MD5 — detected and ran anyway | Yes | archive.org (`msdos_Dark_Seed_1992`), already tested |
| dgds | Rise of the Dragon | **Confirmed working** — tested Heart of China instead, per this row's own recommendation. The raw floppy-disk archive.org dump (`heart-of-china-1991`, `.IMG`/`.IMA` FAT12 images) is a genuine **installer-seed** case (third time this batch's family of gotchas showed up, though not yet documented as its own GOTCHAS.md entry): the floppies only contain `VOLUME.000`-`006` chunks plus `INSTALL.COM`, not the installed `VOLUME.RMF` the engine's detection requires. Found an already-installed copy instead (`msdos_Heart_of_China_1991`, archive.org's standard pre-installed MS-DOS-collection format) with `VOLUME.RMF` + `VOLUME.001`-`007` sitting flat, ~8.3 MiB total. `VOLUME.RMF`'s size matched a known detection-table entry exactly but its MD5 didn't (same harmless pattern as `mohawk`/`made` this batch) — booted through the Dynamix splash and end credits straight into a real playable scene with an interactive dialogue menu | Yes | archive.org (`msdos_Heart_of_China_1991`), already-installed copy (avoided a separate raw-floppy dump that only contained the DOS installer, not the installed game) |
| director | The Journeyman Project | **Confirmed working** — sourced the DOS/Windows retail release (archive.org `the-journeyman-project-pc-1.0`, ISO, 454MB extracted, under the size limit), root-level `JMAN.EXE` size- and 5000-byte-hash-matched the `WINGAME1("jman", ...)` entry in `engines/director/detection_tables.h` exactly. Packaged flat with `JMAN.EXE` as the first zip entry; ScummVM correctly identified it and presented its real `ADGF_UNSTABLE` "not yet fully supported... Start anyway?" warning dialog. The dialog click initially produced zero network requests due to a transient ROMM dev-server instability (stale/mismatched JS chunk hashes across page loads) — not a ScummVM or packaging issue. User confirmed the game plays normally once "Start anyway" is actually clicked through | Yes | archive.org (`the-journeyman-project-pc-1.0`) |
| dragons | Blazing Dragons | Same | Yes | archive.org PS1/DOS collections |
| drascula | Drascula: The Vampire Strikes Back | **Confirmed working** — needed `drascula.dat` companion file | Yes | Already tested |
| dreamweb | DreamWeb | **Confirmed working** — legally freeware since 2011 | Yes | Already tested |
| griffon | The Griffon Legend | **Blocked** — official freeware zip from scummvm.org works fine as packaged (its `data/`/`mapdb/`/`music/`/`sfx/`/`art/` sibling subdirectories must NOT be flattened, unlike most engines — see GOTCHAS.md); needed `fonts.dat` companion file (now fixed), but the compiled WASM core crashes with a `RuntimeError: memory access out of bounds` inside the engine's own code once gameplay starts. Genuine engine bug, not a packaging issue — needs debug-build investigation, deferred by user decision | Yes | scummvm.org freeware games page (`griffon-1.0.zip`) |
| hopkins | Hopkins FBI | Same | Yes (has English translation) | **Confirmed working** — officially freeware since 2007, ScummVM-provided open-source Linux port (`RES_VAN.RES`, exact size match to the table's declared Linux English entry, MD5 mismatch harmless as usual for this session). Engine's `directoryGlobs` covers all the disc's original subdirectories (`SYSTEM`/`LINK`/`BUFFER`/`ANIM`/`ANM`/`MUSIC`/`SEQ`/`SAVE`/`SOUND`/`SVGA`/`VOICE`/`TSVGA`), so no flattening needed. Booted straight into the publisher intro cinematic and a real in-engine cutscene. **Caveat:** despite this build's `EN_ANY` classification in ScummVM's own detection table (presumably referring to on-screen text/subtitles), the voice audio is actually French — confirmed by ear. A separate "Hopkins FBI Win95 UK" release exists in ScummVM's table with a different exact-size match, sourced from a MyAbandonware-packaged installer, but repackaging it hit a *second* detection failure (empty launcher, even after fixing the root-anchor-file issue and a full IndexedDB/localStorage clear) that wasn't resolved in the time available — reverted to the working Linux disc rather than leave the engine unconfirmed. Worth revisiting with more time if English audio matters | Yes | archive.org (`HopkinsFbi-AdventureGamelinuxVersion`), already tested |
| hugo | Hugo's House of Horrors | **Confirmed working** — needed `hugo.dat` companion file (straight append, no collision this time) | Yes | archive.org (`msdos_Hugos_House_of_Horrors_1990`), already tested |
| icb | In Cold Blood | Same | Yes | Deferred — tried "The Road to El Dorado" (`eldorado`, also on this engine) instead first: the only archive.org copy found matches the English Windows detection entry's declared file *sizes* exactly but not the MD5, nor any of icb's other 9 known-hash variants (Spanish/Italian/Polish/Portuguese/4 PS1 regions) — genuinely not a release ScummVM has hash signatures for, not a packaging problem (see GOTCHAS.md's `.scummvm` hook-file section for the full trace). Needs either a different El Dorado dump or an attempt at In Cold Blood itself instead |
| immortal | The Immortal | Same (small floppy-era game) | Yes | Deferred — this engine only supports the **Apple IIgs** release (single `IMMORTAL.dsk`, 819200 bytes, `kPlatformApple2GS`); every archive.org copy found is either a `.woz` raw-flux dump (needs specialized flux-to-sector conversion tooling) or a `.po` ProDOS-order image whose exact-size-match (819200) still failed real detection (unlike this session's other "size matches, hash doesn't" cases, this one is a genuine wrong/mismatched disk, confirmed by ScummVM's launcher list staying empty) — same disk-image-tooling complexity class as `lab`/`startrek`/`twine`/`macventure`/`mads` |
| lab | Labyrinth: The Computer Game | Same | Yes | Deferred — couldn't find a clean DOS/Windows package on archive.org (only Apple II/C64 floppy images turned up, platforms `lab` doesn't support); worth another search pass later |
| macventure | Shadowgate | Same | Yes | Deferred — correction: ScummVM's `macventure` engine only supports the **Macintosh** and **Apple IIgs** releases (`detection.cpp`'s `MACGAME`/`IIGSGAME` macros hard-code `kPlatformMacintosh`/`kPlatformApple2GS`), not the MS-DOS version; a packaged DOS copy failed to detect for exactly this reason. Sourcing a Mac release means extracting from a `.moof`/HFS floppy disk image — same disk-image-tooling complexity class as `startrek`/`twine`, deferred alongside them |
| made | Return to Zork | **Confirmed working** — tested the lighter Rodney's Funscreen instead, per this row's own recommendation. Tiny (~2.3 MiB), flat file layout, no subdirectories. `RODNEYS.DAT` size matched the detection table's entry (92990 bytes) but its MD5 didn't (yet another size-match/hash-mismatch case, harmless — same as `mohawk`/Myst this batch) — detected and ran straight into the interactive main menu (kids' edutainment minigame hub) | Yes | archive.org (`msdos_Rodneys_Funscreen_1992`), already tested |
| mads | Rex Nebular and the Cosmic Gender Bender | Same | Yes | Deferred — only accessible copy found is 9 raw floppy `.img` disk images, same disk-image tooling complexity class as `lab`/`startrek`/`twine`; not attempted this pass |
| mtropolis | Obsidian | **Confirmed working** — tested Muppet Treasure Island instead (also on this engine, `mti` game ID, `ADGF_NO_FLAGS` fully implemented), per the size-limit swap rule since Obsidian is multi-CD with no smaller cut. Needed `MTI1.MPL` (anchor file, first in zip write order) + `MTI2.MPX` (bulk data) + `MTPLAY32.EXE` (mTropolis Windows Player executable — the engine's own `boot.cpp` scans `*.exe` files for a "mTropolis Windows Player" signature to determine boot configuration, separately from the initial hash-based detection; omitting it throws "No executable files were found" even after detection succeeds). `MTI1.MPL`/`MTI2.MPX` matched the Windows Retail entry's declared sizes exactly but not the MD5 (yet another size-match/hash-mismatch case that still worked, unlike `icb`) | Yes | archive.org (`mti-1_202606`, 3-disc CD set), disc 1 only sufficient (~461 MiB) |
| neverhood | The Neverhood | **Blocked** — same shared `fonts.dat` engine bug as `griffon`/`glk`/`dm`/`tony` (fifth confirmation of the identical `RuntimeError: memory access out of bounds` crash signature, see GOTCHAS.md). Packaging itself succeeded: `hd.blb`/`a.blb`/`c.blb`/`i.blb`/`m.blb`/`s.blb`/`t.blb` flat at root from a converted raw `.bin`/`.cue` CD image (Mode 1), plus ScummVM's own `neverhood.dat` companion file; `hd.blb` matched the English detection entry's declared size exactly but not its MD5 (worked anyway). Detection and companion-file loading succeeded fine — crash only hits once `fonts.dat` is added, same as the other four. Moved to `non-running/` | Yes | archive.org (`TheNeverhoodUSA`), raw `.bin`/`.cue` converted to ISO9660 by hand, ~638 MiB |
| parallaction | The Big Red Adventure | **Confirmed working** (via Nippon Safes Inc., official freeware, English language-select confirmed) | Yes | Already tested |
| pegasus | The Journeyman Project: Pegasus Prime | Same (only Pegasus-engine title) | Yes | archive.org CD release |
| buried | The Journeyman Project 2: Buried in Time | **Confirmed working** — used the official US Gold (UK) English Windows demo instead of full retail (a 3-CD set), since `buried`'s detection table has dedicated demo entries needing only `BIT816.EXE` (8BPP) or `BIT2416.EXE` (24BPP) alone — no companion DLL required, unlike the full retail's `AD_ENTRY2s` entries. Sourced the demo installer from archive.org (`BuriedInTimeDemo`, a self-extracting `.exe`), extracted with `7z` to reveal `Data/bitdata/` containing `BIT816.EXE`+`BIT2416.EXE` alongside `CASTLE`/`COMMON`/`MISC` asset subdirectories (~124MB total, well under the size limit). Both EXEs' 5000-byte-prefix MD5s matched the "US Gold (UK)" demo entries exactly. Packaged the whole `bitdata` folder flat with `BIT816.EXE` as the first zip entry (anchor); no `directoryGlobs` subdirectory requirement applies since detection only needs the root-level EXE, and the asset subdirectories are read directly by the exe at runtime, not via ScummVM's own directory scan. Initially missed ScummVM's own `fonts.dat` companion file (not part of the game's own data, needed separately like `toon.dat`/`ultima8.dat`) — without it, the interactive main menu displayed fine, but clicking "Interactive Demo" crashed with `error("Failed to load Arial font")` (`engines/buried/graphics.cpp:128`, `GraphicsManager::createArialFont()` falling through to `loadTTFFontFromArchive("LiberationSans-Regular.ttf", ...)` which needs `fonts.dat` to resolve). Adding `fonts.dat` from `scummvm-core/dists/engine-data/` fixed it — booted through the real Presto Studios intro, into the interactive main menu, and confirmed the actual "Interactive Demo" gameplay screen (rendered 3D barn/farm scene, working Biochip Display/Navigation UI, inventory items). Engine state confirmed live (`started:true`, `muted:false`), no Arial/exit errors after the fix | Yes | archive.org (`BuriedInTimeDemo`), self-extracting `.exe` extracted with `7z` |
| plumbers | Plumbers Don't Wear Ties | Same (already tiny, mostly static slides) | Yes | archive.org FMV/CD-ROM collections |
| private | Private Eye | Same (compact, short FMV mystery) | Yes | archive.org CD-ROM FMV collections |
| saga | I Have No Mouth, and I Must Scream | **Confirmed working** — tested the flagship title directly rather than the lighter alternative, ~461 MiB after excluding a redundant CD-bonus subfolder. Shows a non-fatal "missing SAMPLE.AD/SAMPLE.OPL" AdLib warning (cosmetic — different synth used, not a functional issue); the OK dialog needed a canvas-focus click first (see GOTCHAS.md) | Yes | archive.org (`msdos_I_Have_No_Mouth_and_I_Must_Scream_1995`), already tested |
| sludge | Out of Order | **Tested and worked** (via The Interview, official freeware) but removed and skipped per user caution — unsigned/unverified `.exe`, low priority anyway (ScummVM marks SLUDGE unstable/WIP) | Yes | Skipped, not kept |
| titanic | Starship Titanic | **Deferred — over size limit, no alt title (single-game engine)**. The retail 3-CD version (archive.org `stcd-1`, disc 1 alone, 674MB) doesn't even contain `newgame.st` at all — its `Assets/` folder uses differently-named `a.st`/`z.st` containers instead, an entirely different asset layout from what ScummVM's detection table expects, and discs 2/3 weren't pursued once the GOG version below hash-matched cleanly. The GOG release (archive.org `starshiptitanicgog`, InnoSetup installer, extracted with a portable `innoextract` binary since neither `innoextract` nor `unshield` were preinstalled and there was no sudo access) DOES produce an exact match: `app/newgame.st` is 87227 bytes with a 5000-byte-prefix MD5 of `c276f2661f0d0a547445a65db78b2292`, identical to the English detection entry. But `app/Assets/` (hundreds of `.avi` FMV clips) alone is 1.19 GiB uncompressed — AVI video doesn't compress further under deflate, so the deployable zip would land around the same size — over this project's ~1GB limit. `titanic` is a single-game engine (only English/German entries for the same one title), so there's no smaller alternate game to swap to per the size-limit rule, and no official demo was found. Left untested; would need either a size-limit exception or a way to split/stream the Assets folder to proceed | Yes (GOG version hash-confirmed correct, but too large) | archive.org (`starshiptitanicgog`), extracted with `innoextract` (GitHub release binary, no install needed) |
| tony | Tony Tough and the Night of the Roasted Moths | **Blocked** — same shared `fonts.dat` engine bug as `griffon`/`glk`/`dm` (fourth confirmation of the identical crash signature, see GOTCHAS.md). Packaging itself succeeded: sourced a raw `.bin`/`.cue` CD image, converted via `bchunk`, needed a root-level anchor file kept alongside the `Roasted`/`Voices` directoryGlobs subfolders (all files matched the English detection entry's exact sizes but not its MD5s) plus `tony.dat`; detection then succeeded but the WASM crash hits once `fonts.dat` is added. Moved to `non-running/` | Yes | archive.org (`tony-tough-and-the-night-of-roasted-moths-usa`), already tested |
| touche | Touché: The Adventures of the Fifth Musketeer | **Confirmed working** — real game data was in a bundled CD-variant subfolder (already-extracted plain files, not a raw disc image this time), ~385 MiB total | Yes | archive.org (`msdos_Touche_-_The_Adventures_of_the_Fifth_Musketeer_1995`), already tested |
| voyeur | Voyeur | **Confirmed working** — a clean, perfect hash match on the first try: archive.org `voyeur_202307`'s "Voyeur (English DOS CD)" folder has `BVOY.BLT` at exactly 13036269 bytes with a 5000-byte-prefix MD5 of `12e9e10654171501cf8be3a7aa7198e1`, identical to the detection table's full-game entry — no size-match/hash-mismatch ambiguity at all this time. Flat directory (139 files, ~358MB total, well under the size limit), no subdirectories, no companion `.dat` file needed. Packaged with `BVOY.BLT` as the first zip entry. Booted straight into the real publisher intro screen ("Conversion By... Entertainment Software Partners"); engine state confirmed live (`started:true`, `muted:false`) | Yes | archive.org (`voyeur_202307`), already tested |
| zvision | Zork: Grand Inquisitor | Zork Nemesis (only other title on this engine, similar size) | Yes | Deferred — Zork Nemesis's full retail release is 3 CDs, and discs 1+2 alone already total ~1.1 GiB (each disc has its own distinct `ZASSETS` folder, not overlapping/duplicate content, so this isn't a case of dedupable shared files) — over the 1 GB limit before even adding disc 3. The one alternative found, an archive.org "Limited Edition Interactive Preview" ISO (volume label `ZNPREVUE`), is NOT the same build ScummVM's detection table expects: its `SCRIPTS.ZFS` is ~1 MB vs the table's declared 380 KB, a real size mismatch rather than just a hash mismatch. Tested live anyway — ScummVM's launcher came up with an empty game list, confirming detection genuinely fails on this build. Zork: Grand Inquisitor (this engine's only other title) is likely similarly CD-heavy; not attempted this pass |
| asylum | Sanitarium | **Confirmed working** — full retail is 3 CDs (archive.org `sanitarium-3cd`, ~1.84GB combined), over the size limit, and the official demo (archive.org `sandemo`) is an InstallShield `DATA1.CAB` installer that couldn't be unpacked (`cabextract` explicitly detects it as InstallShield-specific and refuses; `unshield` wasn't preinstalled and there was no sudo access to add it). Used **CD1 only** of the 3-CD retail set instead (`SANITARIUM1.iso`, 524MB) — its `Data/` folder (SNTRM.DAT/RES.*/SCN.*/Vids/Music, ~479MB total) matches the "CD Unpatched"/"CD Patched" detection entries' file sizes exactly (SNTRM.DAT 8930 bytes, RES.000 272057 bytes, SCN.006 2918330 bytes) but not their 5000-byte-prefix MD5s — yet another size-match/hash-mismatch case, harmless as usual this session: ScummVM still detected and booted it. Packaged flat with SNTRM.DAT as the first zip entry, `Vids/` subdirectory preserved per the engine's own `directoryGlobs` (`Music/` also kept, though not glob-registered, just in case). Booted through the real ASC Games publisher intro video into an actual in-game/cutscene frame (confirmed via a second screenshot after the intro), engine state confirmed live (`started:true`, `muted:false`) | Yes | archive.org (`sanitarium-3cd`, disc 1 only), already tested |
| sword25 | Broken Sword 2.5: The Return of the Templars | **Confirmed working** — official freeware fan game, only needed `data.b25c` at the zip root (~827 MiB, under the 1 GB threshold) | Yes | scummvm.org freeware games page (`sword25-v1.0.zip`), already tested |
| agos | Simon the Sorcerer | **Confirmed working** (base `agos`, tonight; `agos2` subengine also confirmed via Simon 2) | Yes | Already in `/mnt/unraid/emulation/scummvm/roms/` |

## Niche/Obscure

| Engine | Most Popular Game | Candidate Test ROM | English Available | Source Note |
|---|---|---|---|---|
| access | Amazon: Guardians of Eden | Martian Memorandum (shorter prequel) | Yes | archive.org, "Martian Memorandum DOS" |
| agds | Black Mirror / NiBiRu: Age of Secrets | NiBiRu: Age of Secrets (likely lighter) | Yes | archive.org, "Black Mirror 2004 adventure game" |
| alg | Mad Dog McCree | Consider Space Pirates if size matters (Mad Dog is FMV-heavy) | Yes | archive.org, "Mad Dog McCree DOS ISO" |
| avalanche | Lord Avalot d'Argent | Same (only title, small) | Yes | archive.org old British PC archives |
| bagel | Spaceship Warlock / Hodj 'n' Podj | Hodj 'n' Podj may be lighter — verify which is smaller | Yes | archive.org Boffo/HyperCard-era collections |
| bbvs | Beavis and Butt-Head in Virtual Stupidity | Same (only title) | Yes | archive.org abandonware collections |
| cge | Soltys | **Confirmed working** — bundled ScummVM freeware game | Yes | Already tested |
| cge2 | Sfinx | **Confirmed working** — official English release (`sfinx-en-v1.1.zip`) | Yes | Already tested |
| chamber | Chamber of the Sci-Mutant Priestess | Same (only title) | Yes | archive.org abandonware DOS collections |
| chewy | Chewy: Esc from F5 | Same | Fan translation only, no official English | archive.org German adventure collections |
| composer | (low confidence — likely Byron Preiss edutainment title) | Same | Yes (US kids' edutainment) | archive.org "Byron Preiss Multimedia" collections |
| draci | Draci Historie (Dragon History) | Same | Community English translation exists | archive.org Czech adventure collections |
| efh | Escape from Hell | Same | Yes | archive.org Horrorsoft/AdventureSoft collections |
| gnap | (low confidence title) | Same (only title) | Unclear | search "Gnap adventure game" on archive.org |
| hadesch | (low confidence — likely Russian/Eastern European) | Unclear | Unclear | Verify via ScummVM wiki first |
| hdb | Hyperspace Delivery Boy! | Same — freeware, small | Yes | archive.org / old freeware mirrors |
| hypno | (low confidence — likely niche FMV/rail-shooter) | Unclear | Unclear | Verify via ScummVM wiki first |
| illusions | Simon the Sorcerer's Puzzle Pack | Same | Yes | archive.org, "Simon the Sorcerer's Puzzle Pack" |
| kingdom | Kingdom: The Far Reaches | Same | Likely yes | archive.org classic CD-ROM collections |
| lilliput | The Adventures of Robin Hood | Same | Yes | archive.org, "Adventures of Robin Hood Firstlight" |
| m4 | Orion Burger | Same (ScummVM team calls it fully completable) | Yes | archive.org, "Orion Burger Sanctuary Woods" |
| mortevielle | Mortville Manor (Le Manoir de Mortevielle) | Same | Unclear — verify English/fan translation | archive.org French DOS abandonware |
| mutationofjb | Mutation of J.B. | Same | **No** — correction: not actually freeware (earlier draft was wrong). It's a commercial 1996 Slovak game with only Slovak/German releases; no legitimate free English source found. Abandonware-only, testing-only if sourced at all | Not on scummvm.org's freeware page; abandonware sites host ISOs in a legal gray area |
| ngi | Fullpipe (Pilot Pirks) | Same | Likely Russian-primary — testing-only, verify | ScummVM team has requested other-language copies; may be hard to source |
| petka | Red Comrades Save the Galaxy | Same | No — Russian-only, unverified fan translations | archive.org Russian abandonware collections |
| pink | Pink Panther: Hokus Pokus Pink | Same | Unclear | search "Hokus Pokus Pink" on Russian game collections |
| prince | The Prince and the Coward | Same | No — Polish-only, unverified fan patch | Polish abandonware sites mirrored on archive.org |
| qdengine | (low confidence — Burut Creative Team titles) | Unclear — verify exact ScummVM-supported game list | No — Russian-origin | search Burut Creative Team titles on archive.org |
| saga2 | Faery Tale Adventure II: Halls of the Dead | Same (only SAGA2 title) | Yes | archive.org DOS/Win9x collections |
| supernova | Mission Supernova | Same | No — German-origin, unverified translation | German abandonware archives on archive.org |
| teenagent | TeenAgent | Same — freeware | Yes | archive.org freeware collections |
| teenagent | TeenAgent | **Confirmed working** — officially freeware; needed ScummVM's own `teenagent.dat` companion file swapped in (the original game ships a same-named but unrelated internal file — see GOTCHAS.md) | Yes | Already tested (freeware DOS zip via archive.org `msdos_TeenAgent_1995`) |
| toltecs | 3 Skulls of the Toltecs | **Confirmed working** — needed `SAMPLE.AD`/`SAMPLE.OPL` AdLib timbre files (this engine treats their absence as fatal, unlike `saga`'s cosmetic-only warning for the same missing files — both were sitting right in the source archive, easy to miss) | Yes | archive.org (`msdos_3_Skulls_of_the_Toltecs_1996`), already tested |
| got | God of Thunder | **Confirmed working** — officially freeware, hosted directly by scummvm.org | Yes | Already tested (`gotfree.zip`, ~1 MiB) |
| trecision | Nightlong: Union City Conspiracy | Same | Yes | archive.org DreamCatcher/Trecision uploads |
| tucker | Bud Tucker in Double Trouble | **Confirmed working** — the archive's DOS installer-seed folder was missing `infobar.txt` entirely (genuinely absent from the archive, not just misplaced); the real installed game (with speech, full audio) was inside a bundled `BUD.iso` CD image instead, ~622 MiB | Yes | archive.org (`msdos_Bud_Tucker_in_Double_Trouble_1996`), already tested |
| wage | Resolved: official ScummVM WAGE Collection is a multi-game bundle, not one title — **Confirmed working** via "Magic Rings" (1988, picked for its clean filename, avoiding punycode-mangled entries elsewhere in the bundle) | Same | Yes | scummvm.org freeware games page (`wage-games-master-1.0.zip`), already tested |

## Unclear — Needs Verification (check ScummVM's wiki before sourcing)

| Engine | Notes |
|---|---|
| crab | Could not confidently identify — possibly a newer/indie addition |
| tot | Could not confidently identify ("ToT") |
| vcruise | Could not confidently identify |

---

## Deferred — Blocked on GL-core Build

These 11 engines need `build/engine-lists/gl-core.list`'s separate core
(with `FORCE_OPENGLES2=1`) actually built before any of them are
testable. Researched now for completeness; some are very well-known.

| Engine | Most Popular Game | Popularity | Candidate Test ROM | English Available | Source Note |
|---|---|---|---|---|---|
| grim | Grim Fandango | Widely known | Same (large CD-size, no smaller alt) | Yes | archive.org LucasArts collections |
| myst3 | Myst III: Exile | Widely known | Same (only title, full CD-size) | Yes | archive.org Myst franchise collections |
| stark | The Longest Journey | Widely known | Same (only title, multi-CD) | Yes | archive.org Funcom back-catalog |
| twp | Thimbleweed Park | Widely known (adventure-press) | Same | Yes | archive.org or GOG-derived files |
| tinsel | Discworld | Genre-notable to widely known | Same; check for a demo | Yes | archive.org Psygnosis/Perfect Entertainment collections |
| freescape | Driller | Genre-notable (historically significant) | Same — small file | Yes | archive.org Incentive Software collections |
| tetraedge | Syberia (franchise) | Genre-notable | Syberia 3 or Amerzone remake | Yes | archive.org/GOG-derived Microids back-catalog |
| hpl1 | Penumbra: Overture | Genre-notable (horror cult favorite) | Standalone tech demo if it exists, else full game | Yes | archive.org/itch.io Frictional Games back-catalog |
| alcachofa | Yesterday | Genre-notable | Same (only title this engine supports) | Yes | archive.org modern-adventure collections |
| watchmaker | The Watchmaker | Niche/obscure | Same (only title, heavy on video) | Yes | archive.org FMV-adventure/CD-ROM collections |
| wintermute | Helga Deep In Trouble | Genre-notable | Same — **resolved**: officially freeware, hosted directly by scummvm.org (`helga_deep_in_trouble.zip`, ~169 MiB — check against the 1 GB go-ahead threshold when this engine's core is ready, but well under it). Earlier candidate (5 Days a Stranger) was wrong-engine (that's AGS) | Yes (English and Czech) | scummvm.org freeware games page |

---

## Next steps (Phase 2, not started)

1. Review this list — flag anything wrong, reprioritize, or add/remove
   engines.
2. Resolve the 8 "Unclear" entries via ScummVM's own wiki before sourcing
   ROMs for them.
3. Start testing from the top of Widely Known (or the freeware
   easiest-starting-points list above), repackaging per
   `docs/GOTCHAS.md`'s zip-packaging rules as needed, documenting any
   new per-engine packaging quirks as they're found.
4. Leave working, English ROMs in `/mnt/unraid/emulation/scummvm/roms/`;
   non-English ROMs used for testing-only should not be left there.
   Correctly-packaged ROMs blocked by an engine/core bug (not a
   packaging problem) go in
   `/mnt/unraid/emulation/scummvm/non-running/` instead of being
   deleted, for easy access when retesting later.
5. **Do not download/test any candidate ROM over 1 GB without checking
   with the user first.** Several Widely Known-tier engines are
   CD-ROM-era games that can run large (`bladerunner`, `sword1`/`sword2`
   full CD releases, `mohawk`, `groovie`, `lastexpress`, `titanic`,
   `mtropolis`, etc.) — check the file size before pulling one down and
   flag/defer instead of proceeding if it's near or over that threshold.
6. Also on the user's wishlist, separate from engine testing: full game
   collections for King's Quest, Space Quest, and Leisure Suit Larry
   (played KQ5 and LSL1 as a kid) — to source and package once the
   engine-testing pass is further along. Also the rest of the Chzo
   Mythos series beyond `5 Days a Stranger` (7 Days a Skeptic, Trilby's
   Notes, 6 Days a Sacrifice, The Countdown — all free, same
   creator/engine).
7. **Prefer the full retail game over a demo when both exist**, even if
   sourcing the full game is more work (e.g. raw CD `.mdf` images needing
   manual conversion — see GOTCHAS.md). The 1 GB threshold above still
   applies to the final packaged ROM; ask before keeping anything over
   it rather than assuming an override carries over between games (each
   of `sword1`/`sword2`'s full-game overrides were granted individually,
   not as a blanket rule).
