# Engine Test Plan

Phase 1 (this document): compile a prioritized list of ScummVM engines to
test, one representative popular game each, plus a smaller/easier
candidate ROM for the actual test. **No testing, downloading, or
packaging has happened yet** — this is the research pass only. Phase 2
(testing) starts after this list is reviewed.

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
| agi | King's Quest I | King's Quest I (small, iconic, well preserved) | Yes | archive.org Sierra AGI collections |
| glk | Zork I | Zork I | Yes, legally free | archive.org Infocom collections; also GOG's free Zork Anthology files |
| awe | Another World / Out of This World | Another World (fit on ~2 floppies originally) | Yes | archive.org DOS releases |
| dm | Dungeon Master | Dungeon Master (Amiga/Atari ST releases are small) | Yes | archive.org FTL Games / Amiga-ST collections |
| sword1 | Broken Sword: The Shadow of the Templars | Official free demo (much smaller than full CD game) | Yes | archive.org has both full game and demo |
| sword2 | Broken Sword II: The Smoking Mirror | Official free demo if available, else full game | Yes | archive.org Broken Sword collections |
| sci | King's Quest V | Jones in the Fast Lane (small, compact SCI0 title) | Yes | archive.org Sierra SCI collections |
| bladerunner | Blade Runner | Only title (CD-ROM, FMV-heavy, no smaller alt) | Yes | archive.org Westwood/abandonware collections |
| ultima | Ultima VIII: Pagan (via `ultima8` subengine — newest/most advanced of the ultima4/6/8 trio; base `ultima` has no standalone game) | Same (only title on this subengine) | Yes | archive.org Origin Systems / Ultima collections |
| twine | Little Big Adventure | Same, or its floppy release if smaller | Yes | archive.org Adeline Software/LBA collections |
| mohawk | Where in Time is Carmen Sandiego? | Logical Journey of the Zoombinis (smaller, well preserved) | Yes | archive.org Carmen Sandiego / Zoombinis releases |
| mediastation | Muppet Treasure Island | Unclear if a smaller Media Station title exists | Yes | archive.org, "Muppet Treasure Island PC CD-ROM" |
| nancy | Nancy Drew: Secrets Can Kill | Secrets Can Kill (shortest/oldest in series) | Yes | archive.org early Nancy Drew CD-ROM titles |
| groovie | The 7th Guest | Same (only realistic option; large CD-ROM) | Yes | archive.org CD-ROM preservation collections |
| sky | Beneath a Steel Sky | Same — **officially freeware** | Yes | archive.org direct, or GOG (free) |
| adl | Mystery House | Same — **bundled ScummVM freeware game** | Yes | scummvm.org freeware games page |
| lastexpress | The Last Express | Same (only title, CD-ROM) | Yes | archive.org, "The Last Express 1997 CD-ROM" |
| ags | (actively used indie engine — Blackwell, Unavowed, etc.) | 5 Days a Stranger (Chzo Mythos) — freeware, short | Yes | Freeware, creator's site or archive.org AGS collections |
| toon | Toonstruck | Same | Yes | archive.org Virgin Interactive collections |
| startrek | Star Trek: 25th Anniversary | Same (DOS floppy version smaller than CD "Judgment Rites") | Yes | archive.org DOS collections |

## Genre-Notable

| Engine | Most Popular Game | Candidate Test ROM | English Available | Source Note |
|---|---|---|---|---|
| kyra | The Legend of Kyrandia: Book One | Same (smallest of trilogy) | Yes | archive.org, "Legend of Kyrandia DOS" |
| mm | World of Xeen (via `xeen` subengine — newest/most feature-rich of mm1/xeen; base `mm` has no standalone game) | Might and Magic IV: Clouds of Xeen alone (lighter than the combined World of Xeen release) | Yes | archive.org Might and Magic / New World Computing collections |
| tsage | Return to Ringworld (via `ringworld2` subengine — sequel, newest of the tsage-based titles; base `tsage` has no standalone game; based on Larry Niven's Hugo/Nebula-winning novel) | Same (only title on this subengine) | Yes | archive.org, "Return to Ringworld DOS" |
| sherlock | Sherlock Holmes: Consulting Detective | The Case of the Serrated Scalpel | Yes | archive.org DOS adventure collections |
| queen | Flight of the Amazon Queen | Same — **officially freeware** | Yes | archive.org direct |
| lure | Lure of the Temptress | Same — freed by Revolution Software | Yes | archive.org DOS floppy version |
| gob | Gobliiins | Same (original, smallest in trilogy) | Yes | archive.org, "Gobliiins DOS" |
| cine | Future Wars | Same | Yes | archive.org Delphine Software collections |
| cruise | Cruise for a Corpse | Same | Yes | archive.org Delphine Software collections |
| cryo | Dracula: The Resurrection | Same | Yes | archive.org Cryo Interactive collections |
| cryomni3d | Atlantis: The Second Age | Versailles 1685 (smaller scope) | Yes | archive.org Cryo back-catalog |
| darkseed | Dark Seed | Same | Yes | archive.org Cyberdreams collections |
| dgds | Rise of the Dragon | Heart of China (smaller/shorter) | Yes | archive.org Dynamix/Sierra back-catalog |
| director | (varies — CD-ROM Director-based titles) | Small Director-based demo/shareware title | Likely yes | archive.org "Macromedia Director games" |
| dragons | Blazing Dragons | Same | Yes | archive.org PS1/DOS collections |
| drascula | Drascula: The Vampire Strikes Back | Same | Yes | archive.org; also ScummVM's own community translation |
| dreamweb | DreamWeb | Same — **legally freeware since 2011** | Yes | Official free release; also archive.org |
| griffon | The Griffon Legend | Same — freeware | Yes | archive.org or itch.io mirrors |
| hopkins | Hopkins FBI | Same | Yes (has English translation) | archive.org French-adventure collections |
| hugo | Hugo's House of Horrors | Same (first, smallest, shareware) | Yes | archive.org, "Hugo's House of Horrors DOS" |
| icb | In Cold Blood | Same | Yes | archive.org, "In Cold Blood PC game" |
| immortal | The Immortal | Same (small floppy-era game) | Yes | archive.org EA classics |
| lab | Labyrinth: The Computer Game | Same | Yes | archive.org Lucasfilm games |
| macventure | Shadowgate | Same (small classic Mac/DOS title) | Yes | archive.org Mac/DOS collections |
| made | Return to Zork | Rodney's Funscreen (much smaller kids' title) | Yes | archive.org; prefer Funscreen over multi-disc Return to Zork |
| mads | Rex Nebular and the Cosmic Gender Bender | Same | Yes | archive.org, "Rex Nebular Cosmic Gender Bender" |
| mtropolis | Obsidian | Same (no smaller mTropolis title known) | Yes | archive.org, note multi-CD |
| neverhood | The Neverhood | Same; check for an official demo | Yes | archive.org DOS CD release |
| parallaction | The Big Red Adventure | Same | Yes | archive.org, "Big Red Adventure DOS" |
| pegasus | The Journeyman Project: Pegasus Prime | Same (only Pegasus-engine title) | Yes | archive.org CD release |
| buried | The Journeyman Project 2: Buried in Time | Same | Yes | archive.org Presto Studios collections |
| plumbers | Plumbers Don't Wear Ties | Same (already tiny, mostly static slides) | Yes | archive.org FMV/CD-ROM collections |
| private | Private Eye | Same (compact, short FMV mystery) | Yes | archive.org CD-ROM FMV collections |
| saga | I Have No Mouth, and I Must Scream | Inherit the Earth: Quest for the Orb (lighter download) | Yes | archive.org has both |
| sludge | Out of Order | Same — freeware indie title | Yes | archive.org indie/freeware collections |
| titanic | Starship Titanic | Same | Yes | archive.org, multi-CD, larger download |
| tony | Tony Tough and the Night of the Roasted Moths | Same | Yes | archive.org DOS/Win collections |
| touche | Touché: The Adventures of the Fifth Musketeer | Same | Yes | archive.org DOS collections |
| voyeur | Voyeur | Same (note: mature content) | Yes | archive.org CD-i/DOS FMV collections |
| zvision | Zork: Grand Inquisitor | Zork Nemesis (only other title on this engine, similar size) | Yes | archive.org Activision/Zork collections |
| asylum | Sanitarium | Same (only title) | Yes | archive.org abandonware collections |
| sword25 | Broken Sword 2.5: The Return of the Templars | Same — free fan game | Yes | bs25.org / archive.org fan-game mirrors |
| agos | Simon the Sorcerer | **Already confirmed working tonight** | Yes | Already in `/mnt/unraid/emulation/scummvm/roms/` |

## Niche/Obscure

| Engine | Most Popular Game | Candidate Test ROM | English Available | Source Note |
|---|---|---|---|---|
| access | Amazon: Guardians of Eden | Martian Memorandum (shorter prequel) | Yes | archive.org, "Martian Memorandum DOS" |
| agds | Black Mirror / NiBiRu: Age of Secrets | NiBiRu: Age of Secrets (likely lighter) | Yes | archive.org, "Black Mirror 2004 adventure game" |
| alg | Mad Dog McCree | Consider Space Pirates if size matters (Mad Dog is FMV-heavy) | Yes | archive.org, "Mad Dog McCree DOS ISO" |
| avalanche | Lord Avalot d'Argent | Same (only title, small) | Yes | archive.org old British PC archives |
| bagel | Spaceship Warlock / Hodj 'n' Podj | Hodj 'n' Podj may be lighter — verify which is smaller | Yes | archive.org Boffo/HyperCard-era collections |
| bbvs | Beavis and Butt-Head in Virtual Stupidity | Same (only title) | Yes | archive.org abandonware collections |
| cge | Soltys | Same — **bundled ScummVM freeware game** | Yes | ScummVM's own SourceForge freeware releases |
| cge2 | Sfinx | Same (same developer as Soltys) | Needs verification | ScummVM freeware games page/wiki |
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
| mutationofjb | Mutation of J.B. | Same — **freeware, made for ScummVM** | Yes | Distributed via ScummVM's own site/wiki |
| ngi | Fullpipe (Pilot Pirks) | Same | Likely Russian-primary — testing-only, verify | ScummVM team has requested other-language copies; may be hard to source |
| petka | Red Comrades Save the Galaxy | Same | No — Russian-only, unverified fan translations | archive.org Russian abandonware collections |
| pink | Pink Panther: Hokus Pokus Pink | Same | Unclear | search "Hokus Pokus Pink" on Russian game collections |
| prince | The Prince and the Coward | Same | No — Polish-only, unverified fan patch | Polish abandonware sites mirrored on archive.org |
| qdengine | (low confidence — Burut Creative Team titles) | Unclear — verify exact ScummVM-supported game list | No — Russian-origin | search Burut Creative Team titles on archive.org |
| saga2 | Faery Tale Adventure II: Halls of the Dead | Same (only SAGA2 title) | Yes | archive.org DOS/Win9x collections |
| supernova | Mission Supernova | Same | No — German-origin, unverified translation | German abandonware archives on archive.org |
| teenagent | TeenAgent | Same — freeware | Yes | archive.org freeware collections |
| toltecs | 3 Skulls of the Toltecs | Same | Yes | archive.org DOS/Win ISO collections |
| trecision | Nightlong: Union City Conspiracy | Same | Yes | archive.org DreamCatcher/Trecision uploads |
| tucker | Bud Tucker in Double Trouble | Same | Yes | archive.org DOS collections |

## Unclear — Needs Verification (check ScummVM's wiki before sourcing)

| Engine | Notes |
|---|---|
| crab | Could not confidently identify — possibly a newer/indie addition |
| got | Could not confidently identify |
| tot | Could not confidently identify ("ToT") |
| vcruise | Could not confidently identify |
| wage | Engine itself is an obscure vintage classic-Mac adventure-creation tool; specific bundled title unconfirmed |

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
| wintermute | (needs re-verification — see confidence note above) | Genre-notable | **Flagged for re-check**: prior candidate (5 Days a Stranger) was wrong-engine (that's AGS). Need an actual small Wintermute freeware title — candidates to check: Ghost in the Sheet, or a Book of Unwritten Tales demo | Unclear until re-verified | Check itch.io Wintermute-engine freeware collections directly |

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
