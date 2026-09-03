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

No per-ROM `.dat`-file bundling or careful anchor placement needed
anymore (see `docs/GOTCHAS.md`'s engine-data-embed and scan-root-fix
sections) — repackaging is now only needed to *create* a ROM that doesn't
already exist as a usable zip (e.g. converting a raw CD image), not to
route around packaging quirks.

## Awaiting test

| Engine | ROM filename | Source | Notes |
|---|---|---|---|
| chewy | `[test] Chewy - Esc from F5.zip` | archive.org `msdos_Chewy_-_ESC_from_F5_1997` | English DOS release, hash-verified |
| composer | `[test] Magic Tales - Baba Yaga.zip` | archive.org `babayagawin` | Hash-verified |
| draci | `[test] Dragon History.zip` | archive.org `msdos_Dragon_History_1995` | English fan translation, hash-verified |
| efh | `[test] Escape from Hell.zip` | archive.org `msdos_Escape_from_Hell_1990` | Hash-verified |
| gnap | `[test] U.F.O.s (Gnap).zip` | archive.org `gnap_20230710` | Confirmed English release, hash-verified |
| hadesch | `[test] Hades Challenge.zip` | archive.org `hadeschallenge` | 2 of 3 detection files hash-match exactly, 3rd size-matches only |
| hdb | `[test] Hyperspace Delivery Boy.zip` | archive.org `hdb-linux` | Official freeware Linux release, hash-verified |
| hypno | `[test] Wetlands.zip` | archive.org `msdos_Wetlands_1995` | Hash-verified via CD image (installed copy was missing MISSIONS.LIB) |
| illusions | `[test] Duckman.zip` | archive.org `duckman-game-cd` | Hash-verified; corrects an earlier wrong candidate note ("Simon the Sorcerer's Puzzle Pack") |
| kingdom | `[test] Kingdom - The Far Reaches.zip` | archive.org `msdos_Kingdom_I_-_The_Far_Reaches_1995` | Hash-verified |
| lilliput | `[test] The Adventures of Robin Hood.zip` | archive.org `msdos_Adventures_of_Robin_Hood_The_1992` | Hash-verified, tiny (1.1MB) |
| m4 | `[test] Orion Burger.zip` | archive.org `msdos_Orion_Burger_1996` | Hash-verified |
| mortevielle | `[test] Mortville Manor.zip` | archive.org `mortevielle` | MENUFR.MOR hash-verified; presents in English via mort.dat translation overlay despite French data files |
| mutationofjb | `[test] Mutation of J.B. (German).zip` | archive.org `mutation-of-jb` | Hash-verified; German-only, no English release exists (corrects a prior contradictory note) |
| ngi | `[test] Full Pipe.zip` | archive.org `Full-Pipe_CSF` | Official English Steam release, hash-verified exactly; corrects an old "Russian-primary" note |
| petka | `[test] Red Comrades 2.zip` | archive.org `petka/petka/petka2.7z` | Hash-verified (5000-byte-prefix); genuinely Russian-only, no translation exists |
| pink | `[test] Pink Panther - Passport to Peril.zip` | archive.org `ThePinkPantherPassportToPerilUSA` | English (USA), hash-verified exactly; corrects an old "unclear" note |
| saga2 | `[test] Faery Tale Adventure II.zip` | archive.org `msdos_Halls_of_the_Dead_-_Faery_Tale_Adventure_II_1997` | All 7 required files hash/size-verified |
| supernova | `[test] Mission Supernova.zip` | archive.org `bhv-playware_msn-disk` | Hash-verified exactly; corrects an old "unverified translation" note — official EN_ANY entry shares the German hash |
| trecision | `[test] Nightlong - Union City Conspiracy.zip` | archive.org `DreamCatcher_Nightlong_Win95_1998_Eng` | **Caveat**: detection needs 3 CD-animation files, only 2 exist in this release; `data.nl` hash-verified but detection may fail on the missing `nlanim.cd3` |

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

## Blocked (user-tested, failed — tagged in `non-running/`)

| Engine | Game | Symptom | Notes |
|---|---|---|---|
| alg | Crime Patrol (used instead of Mad Dog McCree) | Drops to ScummVM debug console, `exit` freezes | Leading suspect: `CPSS.LIB` was skipped during packaging (not part of the hash-detection fingerprint) but may be needed at runtime — retry with it included |
| bbvs | Beavis and Butt-Head in Virtual Stupidity | "mem access OOB" | Same signature as the shared `fonts.dat` WASM crash (griffon/glk/dm/tony/neverhood) — 6th engine confirmed hitting this core-level bug, not a packaging issue |
| chamber | Chamber of the Sci-Mutant Priestess | Freezes the browser tab entirely | Different symptom from the other two; root cause not yet identified |

## Deferred (not sourceable within size/effort budget)

| Engine | Reason |
|---|---|
| agds | Both titles (Black Mirror, NiBiRu) are large CD/installer-based FMV games; neither fits under 1GB without extraction effort unlikely to pay off. See ENGINE-TEST-PLAN.md for detail. |
| cryomni3d | Versailles 1685 needs an actual InstallShield installer run to produce the real game files; no unshield/innoextract/DOSBox available. Tried both an installer package and raw ISO discs. |
| dragons | Blazing Dragons is PS1-only (no DOS port exists); no archive.org copy of the disc image found, only longplay videos. Other ROM sites are outside this project's sourcing convention. |
| prince | Confirmed a real official English "w/translation" detection entry exists (just needs the original Polish/German `databank.ptc` + ScummVM's own now-embedded `prince_translation.dat`) — but no accessible dump of the original Polish/German release found on archive.org after real search effort. |
| qdengine | Confirmed genuinely Russian-only (hardcoded in the detection macros). Identified two small candidates (`nupogodi3`, `karliknos`) but archive.org searches only turned up unrelated cartoon media under the same titles, not the game. |
