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
| access | `[test] Amazon Guardians of Eden.zip` | archive.org `000044-AmazonGuardiansOfEden` | Floppy image, hash-verified |
| alg | `[test] Crime Patrol.zip` | archive.org `msdos_Crime_Patrol_1994` | Extracted from installer ISO, hash-verified |
| avalanche | `[test] Lord Avalot dArgent.zip` | archive.org `LordAvalotDArgent_1020` | Freeware, hash-verified |
| bagel | `[test] Hodj n Podj.zip` | archive.org `Nova_HodjnPodj_USA` | Used instead of Space Bar (too large), hash-verified |
| bbvs | `[test] Beavis and Butt-Head in Virtual Stupidity.zip` | archive.org `CA-WINDOWS-Beavis-and-Butt-Head-in-Virtual-Stupidity` | Hash-verified |
| chamber | `[test] Chamber of the Sci-Mutant Priestess.zip` | archive.org `msdos_Chamber_of_the_Sci-Fi_Mutant_Priestess_1989` | Hash-verified |
| bladerunner | `[test] Blade Runner.zip` | archive.org `blasde-runner-1997-all-scummvm-files` | 1.947GB, only-title exception; STARTUP.MIX hash-verified |
| mm | `[test] Might and Magic - World of Xeen.zip` | archive.org `msdos_Might_and_Magic_45_-_World_of_Xeen_1994` | Both xeen.cc/dark.cc hash-verified exactly |
| tsage | `[test] Return to Ringworld.zip` | archive.org `msdos_Return_to_Ringworld_1994` (its bundled `scummvm/` folder) | R2RW.RLB hash-verified exactly |
| plumbers | `[test] Plumbers Dont Wear Ties.zip` | archive.org `Plumbers_Dont_Wear_Ties_PC_Version` | GAME.BIN hash-verified exactly |
| private | `[test] Private Eye.zip` | archive.org `private-eye` | pvteye.z hash-verified (EN_GRB variant) |

## Deferred (not sourceable within size/effort budget)

| Engine | Reason |
|---|---|
| agds | Both titles (Black Mirror, NiBiRu) are large CD/installer-based FMV games; neither fits under 1GB without extraction effort unlikely to pay off. See ENGINE-TEST-PLAN.md for detail. |
| cryomni3d | Versailles 1685 needs an actual InstallShield installer run to produce the real game files; no unshield/innoextract/DOSBox available. Tried both an installer package and raw ISO discs. |
| dragons | Blazing Dragons is PS1-only (no DOS port exists); no archive.org copy of the disc image found, only longplay videos. Other ROM sites are outside this project's sourcing convention. |

## Confirmed this round (moved out of the table above once reported)

(none yet)
