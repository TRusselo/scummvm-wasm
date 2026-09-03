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

## Deferred (not sourceable within size/effort budget)

| Engine | Reason |
|---|---|
| agds | Both titles (Black Mirror, NiBiRu) are large CD/installer-based FMV games; neither fits under 1GB without extraction effort unlikely to pay off. See ENGINE-TEST-PLAN.md for detail. |

## Confirmed this round (moved out of the table above once reported)

(none yet)
