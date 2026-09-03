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
route around packaging quirks. **New lesson this round**: detection only
checks 2-3 fingerprint files, not everything the engine reads at
runtime — hand-picking files based on the detection entry alone risks
dropping something needed later (`alg`'s `cp.scn`, `saga2`'s
`SAMPLE.AD`/`SAMPLE.OPL`, `m4`'s `SECTION*.HAG`, all found and fixed this
round). Default to packaging complete original game data; see
GOTCHAS.md's "Packaging by hand-picking only the detection-matching
files is risky" section.

## Awaiting test

| Engine | ROM filename | Source | Notes |
|---|---|---|---|
| pink | `[test] Pink Panther - Passport to Peril.zip` | archive.org `ThePinkPantherPassportToPerilUSA` | **Blocked, not yet fixed**: user reported "missing game data, then scumm loader" — root cause not yet investigated |
| hadesch | `[test] Hades Challenge.zip` | archive.org `hadeschallenge` | **Blocked, not yet fixed**: empty ScummVM launcher; leading suspect is `ol.pod`'s hash mismatch (2 of 3 detection files matched exactly) |
| trecision | `[test] Nightlong - Union City Conspiracy.zip` | archive.org `DreamCatcher_Nightlong_Win95_1998_Eng` | **Blocked, predicted caveat confirmed**: only 2 of 3 required CD-animation files exist in this release; needs a genuine 3-CD dump or the demo entry instead |

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

## Blocked (user-tested, failed — tagged in `non-running/`)

| Engine | Game | Symptom | Notes |
|---|---|---|---|
| chamber | Chamber of the Sci-Mutant Priestess | Freezes the browser tab entirely | Root cause not yet identified |
| bbvs | Beavis and Butt-Head in Virtual Stupidity | "mem access OOB" | Shared `fonts.dat` WASM crash, 6th confirmation |
| gnap | U.F.O.s | "mem OOB" | Shared `fonts.dat` WASM crash, 7th confirmation |
| mutationofjb | Mutation of J.B. (German) | "mem OOB" | Shared `fonts.dat` WASM crash, 8th confirmation |
| ngi | Full Pipe | "mem OOB after SCUMM splash" | Shared `fonts.dat` WASM crash, 9th confirmation |

## Deferred (not sourceable within size/effort budget)

| Engine | Reason |
|---|---|
| agds | Both titles (Black Mirror, NiBiRu) are large CD/installer-based FMV games; neither fits under 1GB without extraction effort unlikely to pay off. See ENGINE-TEST-PLAN.md for detail. |
| cryomni3d | Versailles 1685 needs an actual InstallShield installer run to produce the real game files; no unshield/innoextract/DOSBox available. Tried both an installer package and raw ISO discs. |
| dragons | Blazing Dragons is PS1-only (no DOS port exists); no archive.org copy of the disc image found, only longplay videos. Other ROM sites are outside this project's sourcing convention. |
| prince | Confirmed a real official English "w/translation" detection entry exists (just needs the original Polish/German `databank.ptc` + ScummVM's own now-embedded `prince_translation.dat`) — but no accessible dump of the original Polish/German release found on archive.org after real search effort. |
| qdengine | Confirmed genuinely Russian-only (hardcoded in the detection macros). Identified two small candidates (`nupogodi3`, `karliknos`) but archive.org searches only turned up unrelated cartoon media under the same titles, not the game. |
