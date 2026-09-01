# Engine Test Plan

Phase 1 (this document): compile a prioritized list of ScummVM engines to
test, one representative popular game each, plus a smaller/easier
candidate ROM for the actual test. Phase 2 (testing) is now underway.

## Confirmed working so far (32 of 102, + agos2 subengine bonus)

`agi`, `sci`, `sky`, `agos` (base + `agos2` subengine), `adl`, `cge`,
`cge2`, `parallaction`, `drascula`, `lure`, `queen`, `wage`, `dreamweb`,
`got`, `teenagent`, `awe`, `sword1`, `sword2`, `ags`, `kyra`, `gob`,
`cine`, `sherlock`, `hugo`, `touche`, `cruise`, `sword25`, `saga`,
`toltecs`, `tucker`, `mohawk`, `made`. Marked **Confirmed working** in their table row below — search this file for that phrase to
jump to them.

`sludge` was tested successfully (The Interview, freeware) but then
removed and skipped per user caution (unsigned/unverified `.exe`, low
value anyway since ScummVM itself marks SLUDGE unstable/WIP).

`griffon`, `glk`, and `dm` **blocked** on the same shared bug, not a
packaging problem: all three needed their `fonts.dat` companion file
(found and fixed), but all three then crash with the **identical**
`RuntimeError: memory access out of bounds` stack trace once that file
is supplied (same wasm function indices and byte offsets — see
GOTCHAS.md's "Suspected shared bug" section). This looks like a bug in
ScummVM's common font-rendering codepath in this WASM build, not
something fixable by repackaging. Any other untested engine that reports
"Could not locate the 'fonts.dat' engine data file" should be treated as
high-risk for this same crash. Deferred by user decision rather than
investigated further tonight.

All three ROMs are correctly packaged (fonts.dat fix already applied)
and kept — not deleted — in
`/mnt/unraid/emulation/scummvm/non-running/` (`Griffon Legend.zip`,
`Zork I.zip`, `Dungeon Master.zip`), for easy retesting once the
underlying WASM bug is fixed. `non-running/` is the convention going
forward for any ROM that's packaged correctly but blocked by an
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
| ultima | Ultima VIII: Pagan (via `ultima8` subengine — newest/most advanced of the ultima4/6/8 trio; base `ultima` has no standalone game) | Same (only title on this subengine) | Yes | archive.org Origin Systems / Ultima collections |
| twine | Little Big Adventure | Same | Unclear | Deferred — only accessible archive.org copy found is a 500 MiB CD `.bin`/`.cue` image (French "Adeline" branding, English uncertain); needs CD-image mounting rather than a plain data zip, skipped for now |
| mohawk | Myst | **Confirmed working** — correction: the tracker's original candidate (Logical Journey of the Zoombinis) turned out to be entirely `ADGF_UNSUPPORTED`/`GAME_NOT_IMPLEMENTED` in ScummVM's own detection table (every zoombini entry, DOS and demo alike) — it's detected only to show a "not supported" message, never playable. Pivoted to Myst itself instead. The archive.org CD image (`cdrom-myst-1.2`) is a single Mode1/2352 track, no CD audio; stripped to a 640MB ISO9660 with a Python sector-strip script, then 7z-extracted. The disc root is itself an **installer disc** (installer subfolders `MYST32`/`MYST16` present) but, unlike the Gobliiins/Tucker pattern, the actual game's Mohawk `.DAT` archives (`MYST.DAT`, `STONE.DAT`, etc.) and its `QTW/` QuickTime-movie subdirectory sit right at the disc root alongside the installer folders — no CD-image-within-an-image needed, just excluding the installer/setup clutter. `MYST.DAT`'s size matched a known detection-table entry exactly but its MD5 didn't (yet another size-match/hash-mismatch case, harmless here since Mohawk detection didn't require an exact table hit) — detected and booted straight to the intro cinematic and into the in-game dock scene, screenshot-confirmed navigable | Yes | archive.org (`cdrom-myst-1.2`), raw Mode1/2352 CD `.bin`/`.cue` converted to ISO9660 by hand, ~573 MiB after excluding installer folders |
| mediastation | Muppet Treasure Island | Unclear if a smaller Media Station title exists | Yes | archive.org, "Muppet Treasure Island PC CD-ROM" |
| nancy | Nancy Drew: Secrets Can Kill | Secrets Can Kill (shortest/oldest in series) | Yes | archive.org early Nancy Drew CD-ROM titles |
| groovie | The 7th Guest | Same (only realistic option; large CD-ROM) | Yes | archive.org CD-ROM preservation collections |
| sky | Beneath a Steel Sky | **Confirmed working** — officially freeware | Yes | Already tested |
| adl | Mystery House | **Confirmed working** — bundled ScummVM freeware game | Yes | Already tested |
| lastexpress | The Last Express | Same (only title, CD-ROM) | Yes | archive.org, "The Last Express 1997 CD-ROM" |
| ags | (actively used indie engine — Blackwell, Unavowed, etc.) | **Confirmed working** via 5 Days a Stranger (Chzo Mythos) — a bare freeware `.exe`, no companion files, no subdirectories | Yes | archive.org (`5_Days_a_Stranger`), already tested |
| toon | Toonstruck | Same | Yes | archive.org Virgin Interactive collections |
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
| darkseed | Dark Seed | Same | Yes | archive.org Cyberdreams collections |
| dgds | Rise of the Dragon | Heart of China (smaller/shorter) | Yes | archive.org Dynamix/Sierra back-catalog |
| director | (varies — CD-ROM Director-based titles) | Small Director-based demo/shareware title | Likely yes | archive.org "Macromedia Director games" |
| dragons | Blazing Dragons | Same | Yes | archive.org PS1/DOS collections |
| drascula | Drascula: The Vampire Strikes Back | **Confirmed working** — needed `drascula.dat` companion file | Yes | Already tested |
| dreamweb | DreamWeb | **Confirmed working** — legally freeware since 2011 | Yes | Already tested |
| griffon | The Griffon Legend | **Blocked** — official freeware zip from scummvm.org works fine as packaged (its `data/`/`mapdb/`/`music/`/`sfx/`/`art/` sibling subdirectories must NOT be flattened, unlike most engines — see GOTCHAS.md); needed `fonts.dat` companion file (now fixed), but the compiled WASM core crashes with a `RuntimeError: memory access out of bounds` inside the engine's own code once gameplay starts. Genuine engine bug, not a packaging issue — needs debug-build investigation, deferred by user decision | Yes | scummvm.org freeware games page (`griffon-1.0.zip`) |
| hopkins | Hopkins FBI | Same | Yes (has English translation) | archive.org French-adventure collections |
| hugo | Hugo's House of Horrors | **Confirmed working** — needed `hugo.dat` companion file (straight append, no collision this time) | Yes | archive.org (`msdos_Hugos_House_of_Horrors_1990`), already tested |
| icb | In Cold Blood | Same | Yes | archive.org, "In Cold Blood PC game" |
| immortal | The Immortal | Same (small floppy-era game) | Yes | archive.org EA classics |
| lab | Labyrinth: The Computer Game | Same | Yes | Deferred — couldn't find a clean DOS/Windows package on archive.org (only Apple II/C64 floppy images turned up, platforms `lab` doesn't support); worth another search pass later |
| macventure | Shadowgate | Same | Yes | Deferred — correction: ScummVM's `macventure` engine only supports the **Macintosh** and **Apple IIgs** releases (`detection.cpp`'s `MACGAME`/`IIGSGAME` macros hard-code `kPlatformMacintosh`/`kPlatformApple2GS`), not the MS-DOS version; a packaged DOS copy failed to detect for exactly this reason. Sourcing a Mac release means extracting from a `.moof`/HFS floppy disk image — same disk-image-tooling complexity class as `startrek`/`twine`, deferred alongside them |
| made | Return to Zork | **Confirmed working** — tested the lighter Rodney's Funscreen instead, per this row's own recommendation. Tiny (~2.3 MiB), flat file layout, no subdirectories. `RODNEYS.DAT` size matched the detection table's entry (92990 bytes) but its MD5 didn't (yet another size-match/hash-mismatch case, harmless — same as `mohawk`/Myst this batch) — detected and ran straight into the interactive main menu (kids' edutainment minigame hub) | Yes | archive.org (`msdos_Rodneys_Funscreen_1992`), already tested |
| mads | Rex Nebular and the Cosmic Gender Bender | Same | Yes | Deferred — only accessible copy found is 9 raw floppy `.img` disk images, same disk-image tooling complexity class as `lab`/`startrek`/`twine`; not attempted this pass |
| mtropolis | Obsidian | Same (no smaller mTropolis title known) | Yes | archive.org, note multi-CD |
| neverhood | The Neverhood | Same; check for an official demo | Yes | archive.org DOS CD release |
| parallaction | The Big Red Adventure | **Confirmed working** (via Nippon Safes Inc., official freeware, English language-select confirmed) | Yes | Already tested |
| pegasus | The Journeyman Project: Pegasus Prime | Same (only Pegasus-engine title) | Yes | archive.org CD release |
| buried | The Journeyman Project 2: Buried in Time | Same | Yes | archive.org Presto Studios collections |
| plumbers | Plumbers Don't Wear Ties | Same (already tiny, mostly static slides) | Yes | archive.org FMV/CD-ROM collections |
| private | Private Eye | Same (compact, short FMV mystery) | Yes | archive.org CD-ROM FMV collections |
| saga | I Have No Mouth, and I Must Scream | **Confirmed working** — tested the flagship title directly rather than the lighter alternative, ~461 MiB after excluding a redundant CD-bonus subfolder. Shows a non-fatal "missing SAMPLE.AD/SAMPLE.OPL" AdLib warning (cosmetic — different synth used, not a functional issue); the OK dialog needed a canvas-focus click first (see GOTCHAS.md) | Yes | archive.org (`msdos_I_Have_No_Mouth_and_I_Must_Scream_1995`), already tested |
| sludge | Out of Order | **Tested and worked** (via The Interview, official freeware) but removed and skipped per user caution — unsigned/unverified `.exe`, low priority anyway (ScummVM marks SLUDGE unstable/WIP) | Yes | Skipped, not kept |
| titanic | Starship Titanic | Same | Yes | archive.org, multi-CD, larger download |
| tony | Tony Tough and the Night of the Roasted Moths | Same | Yes | archive.org DOS/Win collections |
| touche | Touché: The Adventures of the Fifth Musketeer | **Confirmed working** — real game data was in a bundled CD-variant subfolder (already-extracted plain files, not a raw disc image this time), ~385 MiB total | Yes | archive.org (`msdos_Touche_-_The_Adventures_of_the_Fifth_Musketeer_1995`), already tested |
| voyeur | Voyeur | Same (note: mature content) | Yes | archive.org CD-i/DOS FMV collections |
| zvision | Zork: Grand Inquisitor | Zork Nemesis (only other title on this engine, similar size) | Yes | archive.org Activision/Zork collections |
| asylum | Sanitarium | Same (only title) | Yes | archive.org abandonware collections |
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
