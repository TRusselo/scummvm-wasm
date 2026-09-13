# RC-B validation checklist

The re-validation half of RELEASE-PLAN §6, against the from-scratch RC build.
Same 30-title set as the 2026-09-06 rebase pass, with six files updated to the
library's current names. Fill the four result columns per title; a row is done
only when all four have a value.

Per title (RELEASE-PLAN 6.2 to 6.5):

- **Boot**: reaches gameplay, not just the launcher.
- **Audio**: sound actually heard; a screenshot is not evidence.
- **Save/load**: save in game, return to launcher, relaunch, load. Booting is
  not enough (the `tentacle-1` finding, issue #8).
- **Unzip**: whether the ENOTDIR extraction crash occurred, stated even when it
  did not.

Core under test: fill in the md5 from `docker/scummvm-core/scummvm-thread-wasm.data`
and the image tag before starting, and note them in every log filename.

| core md5 | image | started | finished |
|---|---|---|---|
| | `romm-scummvm:ejs-rc` | | |

## A. Twenty titles that only work because of a fix in this project

| # | File in `roms/` | Fix it proves | Boot | Audio | Save/load | Unzip |
|---|---|---|---|---|---|---|
| 1 | `Griffon Legend.zip` | FreeType autofit signature; save-state guard (`afdcbd2`) | | | | |
| 2 | `Zork.zip` — confirm it is Zork I (`glk`) before use; the original `Zork I.zip` is gone | FreeType autofit, glk | | | | |
| 3 | `Dungeon Master.zip` | Level 9 detector fix (now upstream) + dm engine sync + FreeType | | | | |
| 4 | `Tony Tough and the Night of the Roasted Moths (CD Windows).zip` | FreeType autofit + scan-root | | | | |
| 5 | `The Neverhood (CD, Windows).zip` | FreeType autofit | | | | |
| 6 | `Beavis and Butt-head in Virtual Stupidity (CD Windows).zip` | Indeo 3/4/5 + AVI `loadStream` double free | | | | |
| 7 | `Full Pipe (CD, Windows).zip` | Indeo (IV50) + AVI double free | | | | |
| 8 | `Gnap (CD Windows).zip` | Indeo + AVI double free | | | | |
| 9 | `Mutation of J.B. (German).zip` | Indeo + AVI double free | | | | |
| 10 | *dropped* — Chamber of the Sci-Mutant Priestess is every-entry `ADGF_TESTING`, out of scope (issue #3 closed). Its render-mode option is exercised by nothing else; note that. | | | | | |
| 11 | `Zak McKracken and the Alien Mindbenders (Talkie) (FM Towns).zip` | `USE_FMTOWNS_PC98_AUDIO` link fix | | | | |
| 12 | `Indiana Jones and the Fate of Atlantis (Talkie) (CD FM Towns).zip` | FM-TOWNS audio link | | | | |
| 13 | `Loom (CD FM Towns).zip` (was `Loom (Talkie) (CD FM Towns).zip`) | FM-TOWNS audio link | | | | |
| 14 | *dropped* — `The Secret of Monkey Island (FM Towns).zip` is a known incomplete dump (ROM-QUEUE); covered by 11 and 12 | | | | | |
| 15 | `Toonstruck (CD Windows).zip` | engine-data embed (`toon.dat`) | | | | |
| 16 | `Ultima VIII - Pagan.zip` | engine-data embed (`ultima8.dat`) + scan-root | | | | |
| 17 | `The Journeyman Project 2- Buried in Time.zip` | engine-data embed (`fonts.dat`) | | | | |
| 18 | `Nancy Drew - Secrets Can Kill.zip` | engine-data embed (`nancy.dat`); heaviest upstream churn | | | | |
| 19 | `Hopkins FBI (CD Windows).zip` | scan-root fix, 12 directoryGlobs unflattened | | | | |
| 20 | `Muppet Treasure Island.zip` | scan-root fix + runtime `.exe` scan | | | | |

## B. Ten regression canaries

| # | File in `roms/` | Why | Boot | Audio | Save/load | Unzip |
|---|---|---|---|---|---|---|
| 1 | `Day Of The Tentacle (CD Dos)2.zip` (was `(CD Dos).zip`) | SCUMM, the original target | | | | |
| 2 | `The Curse Of Monkey Island (CD Windows).zip` | SCUMM v7/8 | | | | |
| 3 | `Eye of the Beholder (CD DOS).zip` | KYRA/EOB | | | | |
| 4 | `The Legend of Kyrandia 2 The Hand of Fate (CD DOS).zip` | KYRA | | | | |
| 5 | `King's Quest 1 - Quest for the Crown (Floppy DOS).zip` | AGI | | | | |
| 6 | `Sanitarium.zip` | ASYLUM | | | | |
| 7 | `Orion Burger (CD DOS).zip` (the old `Orion Burger.zip` is in `duplicates/`) | M4, runtime `.HAG` loading | | | | |
| 8 | `Discworld (CD DOS).zip` | TINSEL, detection entry added on the fork | | | | |
| 9 | `Broken Sword 2 The Smoking Mirror (CD Windows).zip` | SWORD2 | | | | |
| 10 | `Blade Runner.zip` | BLADERUNNER, largest single title | | | | |

## C. New since the last pass, one each

| # | File in `roms/` | Why | Boot | Audio | Save/load | Unzip |
|---|---|---|---|---|---|---|
| 1 | any `macs2` title, if one is sourced | first core with `macs2` built; every entry is `ADGF_TESTING`, so boot only | | | | |
| 2 | `[test url] Dreamweb (Floppy DOS).zip` | unknown-variant report in console, Report game button opens a tab | | | | |

## Exit criterion

Every A and B row has all four columns filled, no regressions against the
README's ✅ rows, and the unzip column says "no" everywhere. Then cut RC-B:
tag the repo, publish both `.data` files plus `scummvm.json` and their md5s,
and copy the README's Known limitations section into the release notes.
