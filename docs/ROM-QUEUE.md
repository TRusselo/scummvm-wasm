# ROM Test Queue

Workflow as of 2026-09-02: Claude sources and packages ROMs, prefixes the
filename with `[test]`, and drops them into
`/mnt/unraid/emulation/scummvm/roms/`. User tests in the browser
themselves (faster than round-tripping through a fork), then renames the
file (dropping the `[test]` prefix) if it works, or moves it to
`non-running/` if it doesn't. Claude finalizes `docs/ENGINE-TEST-PLAN.md`/
`README.md` once the user reports the result.

Sizing rule: prefer non-demo, English, under ~1GB. If the only realistic
candidate exceeds 1GB, look for a smaller/different title on the same
engine first. Exception: if a game is the *only* title on its engine and
its size is under ~2GB, it's fine to use as-is rather than deferring the
whole engine.

**Hard ceiling (measured 2026-09-06) — two limits, both inside EmulatorJS:**

1. **zip < 2 GiB.** EJS buffers the download into one JS `ArrayBuffer`; over
   V8's max typed-array length the tab dies in `downloadFile` before the core
   starts.
2. **zip + unpacked < 4 GiB.** EJS decompresses in a Worker running its own
   wasm32 module (`asm._extract`) holding compressed input and decompressed
   output together; over 4 GiB it hangs at "decompressing game data" with no
   percentage.

| ROM | zip | unpacked | sum | result |
|---|---|---|---|---|
| Phantasmagoria | 1.787G | 2.144G | 3.931G | plays |
| Feeble Files (2CD Amiga) | 1.034G | 1.083G | 2.117G | plays |
| Feeble Files (4CD Windows) | 1.996G | 2.071G | 4.067G | hangs decompressing |
| Riven (CD) | 2.036G | 2.674G | 4.711G | fails downloading |
| Zork: Grand Inquisitor | 2.091G | 2.359G | 4.450G | fails downloading |
| Gabriel Knight 2 | 2.618G | 3.343G | 5.961G | fails downloading |

Phantasmagoria clears limit 2 by only 74 MB, so it is close to the largest game
this architecture can run at all. Unpacked size alone predicts nothing. Full
analysis in issue #5.

## Awaiting test

| Engine | ROM filename | Source | Notes |
|---|---|---|---|
| hadesch | `[test] Hades Challenge.zip` | archive.org `hadeschallenge` | **Blocked, dump issue confirmed**: all files present exactly where expected, but `ol.pod`'s MD5 doesn't match any of ScummVM's ~3 cataloged variants at that byte size — a genuine dump-sourcing problem, not fixable by repackaging |
| trecision | `[test] Nightlong - Union City Conspiracy.zip` | archive.org `DreamCatcher_Nightlong_Win95_1998_Eng` | **Blocked, predicted caveat confirmed**: only 2 of 3 required CD-animation files exist in this release; needs a genuine 3-CD dump or the demo entry instead |
| toltecs | `3 Skulls of the Toltecs (CD DOS).zip` | needs re-sourcing | **Incomplete dump — needs replacement.** Contains only `WESTERN`; missing `SAMPLE.AD`/`SAMPLE.OPL`, the Miles AdLib timbre banks `engines/toltecs/music.cpp:39` opens unconditionally when the device is AdLib. Fails with `ERROR: MILES-ADLIB: could not open timbre file`. Came from the collection's `Working/` folder — a desktop validator with a soundfont configured never hits this, because `MDT_PREFER_GM` routes them past the Miles path (see issue #4's MIDI/FluidSynth section). A complete copy exists at `duplicates/3 Skulls of the Toltecs.zip` if a re-source proves hard |
| scumm | `The Secret of Monkey Island (FM Towns).zip` | needs re-sourcing | **Incomplete dump — needs replacement.** Contains only `MONKEY.000`/`MONKEY.001`. The `monkey` FM-TOWNS detection entry carries `GF_AUDIOTRACKS` (`engines/scumm/detection_tables.h:204`), so ScummVM warns that CD audio must be ripped. Needs a `Track*.fla` set alongside the data files, matching how Zak (21 tracks), Loom (16) and Last Crusade (14) are packaged in this library. Note Fate of Atlantis and Monkey 2 FM-TOWNS legitimately have none — those entries lack `GF_AUDIOTRACKS` and use the internal FM-TOWNS synth |
| mohawk (`riven`) | `Riven (CD Windows).zip`, `Riven (DVD Windows).zip` | — | **Permanently blocked at current EJS architecture.** 2.04/2.17 GB zips, 2.67/2.74 GB unpacked — over the 2 GiB zip limit (2.036/2.17 GiB). Brave pauses with "Paused before potential out-of-memory crash" inside EmulatorJS's `downloadFile` on `t = r.response`, before the core starts; our core only ever logs its own init. Engines are compiled in (`mohawk`/`myst`/`mystme`/`riven`), so this is not an engine gap and not a regression. Would need EmulatorJS to stream the download and decompress per zip entry rather than buffering the whole archive — see issue #5 |
| sci (`gk2`) | `Gabriel Knight 2 The Beast Within (CD, DOS).zip` | — | **Blocked, over limit 1.** 2.618 GiB zip (3.343 GiB unpacked). Fails in EJS's `downloadFile` before the core starts. Largest non-GL title in the library |
| zvision | `Zork - Grand Inquisitor (DVD Windows).zip` | — | **Blocked, over limit 1.** 2.091 GiB zip. Note it unpacks *smaller* than Phantasmagoria (2.359 vs 2.144 GiB) yet still fails — the zip size is what binds |
| agos (`feeble`) | `The Feeble Files (4CD Windows).zip` | — | **Blocked, over limit 2.** 1.996 GiB zip clears limit 1 by 3.7 MB, but zip+unpacked = 4.067 GiB exceeds the extractor Worker's 4 GiB wasm32 memory — hangs at "decompressing game data" with no percentage. **The 2CD Amiga edition plays** and is the working copy for this engine |
| tinsel | `Discworld (CD DOS).zip`, `Discworld (CD DOS v2).zip`, `Discworld 2 (CD DOS).zip` | needs re-sourcing | **All three are unrecognised releases** — engine is fine. `tinsel` builds into this core as of 2026-09-06 (moved out of gl-core.list; it declares no `3d` dep and its TinyGL use is guarded by `if (getGameID() == GID_NOIR)`), and all three dumps still land in an empty launcher. Two match their *anchor* exactly and fail on the second required file: CD DOS has `DW.GRA` 781656 (known) but `ENGLISH.TXT` 228542 where the entry wants **237774**; Discworld 2 has `DW2.SCN` 103593 (the only known size) but `ENGLISH1.TXT` 233295 where the entry wants **274444**; CD DOS v2's `DW.SCN` 776188 matches nothing (known: 776396, 776524, 1272686). Same class as `icb`/El Dorado — a real release ScummVM has no signature for, not fixable by repackaging. **What to look for:** a dump with `english.txt` at 237774, or any multilingual Euro release carrying `french/german/italian/spanish.txt` — those entries accept any size for the language file and would detect on `DW.GRA` 781656 alone |

## Confirmed working (user-tested, `[pass]` tag)

| Engine | Game | Notes |
|---|---|---|
| access | Amazon: Guardians of Eden | |
| avalanche | Lord Avalot d'Argent | |
| bagel | Hodj 'n' Podj | used instead of The Space Bar (too large) |
| bladerunner | Blade Runner | 1.947GB, only-title exception |
| mm | World of Xeen (via `xeen`) | |
| tsage | Return to Ringworld (via `ringworld2`) | |
| plumbers | Plumbers Don't Wear Ties | |
| private | Private Eye | EN_GRB variant |
| chewy | Chewy: Esc from F5 | |
| composer | Magic Tales: Baba Yaga and the Magic Geese | |
| draci | Dragon History | English fan translation |
| efh | Escape from Hell | |
| hdb | Hyperspace Delivery Boy! | official freeware |
| hypno | Wetlands (US) | needed CD image's copy of `MISSIONS.LIB` |
| illusions | Duckman: The Graphic Adventures of a Private Dick | |
| kingdom | Kingdom: The Far Reaches | |
| lilliput | The Adventures of Robin Hood | |
| mortevielle | Mortville Manor | French data, presents in English via `mort.dat` overlay |
| petka | Red Comrades 2: For the Great Justice | Russian-only, testing purposes |
| supernova | Mission Supernova, Part 1 | official EN_ANY entry shares the German hash |
| alg | Crime Patrol | fixed — was missing `CP.SCN` + a dozen resource files |
| saga2 | Faery Tale Adventure II: Halls of the Dead | fixed — was missing `SAMPLE.AD`/`SAMPLE.OPL` |
| m4 | Orion Burger | fixed — was missing all 9 `SECTION*.HAG` per-chapter archives |
| pink | The Pink Panther: Passport to Peril | fixed — original dump corrupted beyond the first 5000 bytes despite matching size+prefix hash; resourced from MyAbandonware |

## Blocked (user-tested, failed — tagged in `non-running/`)

> **Fixed and removed from this list 2026-09-04:** `bbvs` (Beavis and
> Butt-Head), `gnap` (U.F.O.s), `mutationofjb` (Mutation of J.B.) and
> `ngi` (Full Pipe) were all listed here as a shared `fonts.dat` WASM
> crash. That diagnosis was wrong and all four now play. The real causes
> were two FreeType autofit function-pointer signature mismatches, and
> for `bbvs`/`ngi` a missing Indeo codec plus a double free in
> `AVIDecoder::loadStream()`. `griffon`, `dm`, `glk`, `tony` and
> `neverhood` were fixed by the same work. See the corrected summary in
> ENGINE-TEST-PLAN.md.

| Engine | Game | Symptom | Notes |
|---|---|---|---|
| chamber | Chamber of the Sci-Mutant Priestess | Reaches title screen (past `ADGF_UNSTABLE` warning), then hangs | Likely genuine engine immaturity, not a dump issue -- not built by default upstream, no compatibility wiki entry, TODO-riddled source. Two prior dumps also failed differently (browser freeze, before that) |

## Deferred (not sourceable within size/effort budget)

| Engine | Reason |
|---|---|
| agds | Both titles (Black Mirror, NiBiRu) are large CD/installer-based FMV games; neither fits under 1GB without extraction effort unlikely to pay off. See ENGINE-TEST-PLAN.md for detail. |
| cryomni3d | Versailles 1685 needs an actual InstallShield installer run to produce the real game files; no unshield/innoextract/DOSBox available. Tried both an installer package and raw ISO discs. |
| dragons | Blazing Dragons is PS1-only (no DOS port exists); no archive.org copy of the disc image found, only longplay videos. Other ROM sites are outside this project's sourcing convention. |
| prince | Confirmed a real official English "w/translation" detection entry exists (just needs the original Polish/German `databank.ptc` + ScummVM's own now-embedded `prince_translation.dat`) — but no accessible dump of the original Polish/German release found on archive.org after real search effort. |
| qdengine | Confirmed genuinely Russian-only (hardcoded in the detection macros). Identified two small candidates (`nupogodi3`, `karliknos`) but archive.org searches only turned up unrelated cartoon media under the same titles, not the game. |
