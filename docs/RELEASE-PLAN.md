# Plan: toward a Pre-Release Candidate binary

Written 2026-09-08, revised 2026-09-12 after reading EmulatorJS's actual build
scripts (issue #4, third comment). Scope: what stands between today's working
core and a public Pre-Release Candidate distributed through EmulatorJS.

**Nothing here is a code change.** It is a sequencing plan with exit criteria.

---

## 0. What "Pre-Release Candidate" has to mean here

Worth fixing the definition first, because it determines how much of the list
below is actually blocking.

Per issue #4, **EmulatorJS never receives our binaries.** `EmulatorJS/build`'s
`build.sh` reads a `repo` + `branch` per core from `cores.json`, clones it,
runs make, then links with their RetroArch fork's `build-emulatorjs.sh` and
7z's the result. Every one of the 47 repos in `cores.json` is an `EmulatorJS/*`
fork carrying its own commits; there is no patch step. So "release" means
*a branch they fork builds our core* — not that we hand them a `.data`, and
not that every commit is upstream first.

That gives two candidate definitions, and they imply very different work:

- **RC-A — "EmulatorJS can build it"**: the real target. Gated on EmulatorJS
  creating `EmulatorJS/scummvm` (404 today), taking our branch onto it, and
  accepting three array entries in `build-emulatorjs.sh`. Mostly *not* in our
  control.
- **RC-B — "a binary we would stand behind, built by us"**: a versioned,
  reproducible `.data` + report JSON, published with honest documented limits.
  Entirely in our control.

**Recommendation: aim RC-B first**, and treat RC-A as the release after it.
RC-B is achievable on our own schedule, gives something testable to point
EmulatorJS at, and every task it needs is also needed for RC-A.

The rest of this plan is ordered on that basis.

---

## 1. Do this before anything else: ask EmulatorJS about size

**Issue #4 already flags this and it is still unasked.** Measured against
their own 189-core distribution:

| core | `.data` |
|---|---|
| **ours** | **90 MB** (94,089,362 bytes, 130 engine entries) |
| fbneo (their largest) | 7.9 MB |
| typical | ~1 MB |

We are ~11x their largest and ~80x typical, almost entirely from 74 MB of
embedded engine-data (`fonts-cjk.dat` alone is 38 MB). Per engine it is
~0.69 MB, under a typical whole core.

This is a **policy** question, not a technical one, and its answer reshapes
item 3 below. libretro's own makefile already has a `datafiles` target that
bundles engine-data into `scummvm.zip` for a system directory; if they would
rather fetch that separately than bake it into the wasm, the `.data` drops to
roughly 16 MB and item 3.2 disappears — so polishing a 90 MB core before
asking risks discarding the work.

**Action:** one short message on EJS issue
[#1263](https://github.com/EmulatorJS/EmulatorJS/issues/1263) (already open,
ours) covering: the size, why (engine-data), the three options (bake / fetch
separately / split core+data), and asking which they want.

**Exit criterion:** a stated preference from EmulatorJS, or an explicit
"no objection to the baked form".

*Cost: ~1 hour. Blocks: item 3, and the shape of RC-A.*

---

## 2. Upstream merges — maintenance, not gates

Since EmulatorJS builds whatever branch its fork carries, nothing here blocks
RC-A on its own. Each merge is one less commit for `EmulatorJS/scummvm` to
carry, and a fork that depends on a personal fork (2.1) is a fair objection
for them to raise. Track in `docs/pr/PR-DRAFTS.md`.

### 2.1 `libretro/libretro-deps#15` — FreeType autofit signature fix (OPEN)

Without this fix the core traps on the first glyph with a real outline. Our
`dependencies.mk` pins `TRusselo/libretro-deps@7e18f86`, and the libretro
build clones exactly that URL and commit, so a build of our branch works
today. What the merge buys is removing the personal-fork dependency; the pin
then reverts to two upstream lines.

**Action:** nothing to write; it needs review attention. Periodic, polite
follow-up only. Open since 2026-09-06, no comment.

**Exit criterion:** merged, pin reverted, core rebuilt and re-validated.

### 2.2 Engine fixes → `scummvm/scummvm`

Ours, upstreamable, independent of each other:

| commit | change | status (2026-09-12) |
|---|---|---|
| `cac3a252862` | VIDEO: AVIDecoder::loadStream double free | superseded by scummvm#7935 (maintainer's general fix); our #7944 withdrawn. Keep locally until #7935 merges |
| `a607b761ebe` | CHAMBER: Hercules blit path guard | open as scummvm#7946 |
| `955aef0429e` (part) | SCUMM: getSaveStateName() override | open as scummvm#7945 |
| `f3c52552c73` | BACKENDS: WebMIDI guard on `__LIBRETRO__` | open as scummvm#7947 |
| `3f09158c8a9` | TINSEL: two uncatalogued Discworld 1 variants | withdrawn (#7926): booted, not played through |
| `b591d4d34fc` | Dropped quit event hangs the tab on exit | dropped 2026-09-09, theory disproved; not submitted |

Precedent: #7902 (Level 9 detector) was closed and the fix applied as digitall's
own commit `05f236adb`, with an invitation to file more. The commit message was
called out as far too long; see `docs/pr/PR-DRAFTS.md` for the rules learned.

**Note:** `4dc59596241` (our Level 9 commit) is now redundant — it will drop
out on the next rebase. Expect it to vanish; that is correct, not lost work.

**Action:** three are open (#7945, #7946, #7947) and clean; wait for review.
Nothing further to submit from this set. Rules learned are in
`docs/pr/PR-DRAFTS.md`: re-read every comment on a closed PR before opening
its replacement.

*Does not block RC-B or RC-A.*

### 2.3 Port integration → `libretro/scummvm`

Inherently ours. Either lands there or is carried by `EmulatorJS/scummvm`:

- `955aef0429e` real save-state support (`retro_serialize`/`retro_unserialize`)
- `4b6607e97d3` scan the virtual-FS root on Emscripten — open as libretro#112
- `f09251ff1d1` register embedded `/engine-data` in the search set — held
- `8ad2b918334` keep `warning()` in release builds — **merged** as libretro#110
  into `staging_master`; carry it until that reaches `master`
- (the WebMIDI change belongs to scummvm/scummvm, not here — see 2.2)
- `8690c2d4e6d` render-mode core option
- issue #6's two items (unknown-variant reporting, `kFeatureOpenUrl`)

`84f2bd11f5a` (CI arm64 removal) is fork-only and must **never** be submitted.

*Larger and more entangled than 2.2; sequence after it.*

---

## 3. EmulatorJS build-system gaps

Two scripts are involved and they have different option surfaces. The core
compile (`EmulatorJS/build` `build.sh`) passes `INITIAL_HEAP=268435456
AUTO_MEMORY_GROWTH=1` by default and takes per-core `makeoptions.arguments`.
The RetroArch link (`build-emulatorjs.sh` in `EmulatorJS/RetroArch`) takes no
per-core options and keys hardcoded arrays on the `.bc` name. **Sequence 3.2
after item 1**, since the answer there may remove it entirely.

**3.1 Link-time arrays — three entries in `build-emulatorjs.sh`.** `scummvm`
is in none of `largeStack`, `largeHeap`, `needsAsync` (verified on `v1.22.2`,
2026-09-12). Without `largeHeap` the link fails as our rebase did,
`wasm-ld: error: initial memory too small, 186199984 bytes needed` — that is
static data plus stack at link time, which `ALLOW_MEMORY_GROWTH` cannot help.
Without `needsAsync` the core is built with no Asyncify. The entries give
128 MB stack / 512 MB heap / `ASYNC=1`. One three-line PR to their RetroArch
fork.

**3.2 Engine-data embed — has a precedent and an alternative.** We pass
`--embed-file ../build/embed-staging/engine-data@/engine-data` via
`EMCC_CFLAGS`. `cores.json` supports `custom: true` with `build_command` and
`build_retroarch_command`; `ppsspp` uses it to build ffmpeg and copy it into
`RetroArch/` before linking, so our flag fits an existing shape. The
alternative is item 1's `datafiles` route: ship `scummvm.zip` as a fetched
asset and mount it, which every other libretro frontend already does. Needs a
design decision with them; the custom command is the fallback.

**3.3 Drop `--pre-js midi-stub-pre.js`.** WebMIDI is now a one-line
`__LIBRETRO__` guard (`f3c5255`, scummvm#7947), so nothing reads
`midiOutputMap`. `build-retroarch-core.sh` still passes the stub. Verify by
building without it; then it is one less non-standard input.

**3.4 The engine set may need no configuration.** libretro's defaults are
`LITE=0 NO_WIP=1`, which enables ScummVM's build-by-default set and drops
engines whose dependencies the platform lacks (real OpenGL is unavailable for
emscripten). That is `all-engines.list`'s policy by construction; we use
`LITE=1` plus a copied `lite_engines.list` only to pin it explicitly.
**Untested:** build once with no `LITE` and diff `config.mk.engines` against
the list. If identical, the `cores.json` entry needs no `arguments` and the
fork need not carry a list.

**3.5 The `cores.json` entry**, for when 3.1 lands:

```json
{ "name": "scummvm", "repo": "https://github.com/EmulatorJS/scummvm", "branch": "<theirs>",
  "license": "COPYING",
  "makeoptions": { "buildpath": "./backends/platform/libretro", "makescript": "Makefile", "arguments": [] },
  "options": { "requireThreads": true } }
```

`requireThreads: true` because the core runs on real pthreads (`USE_LIBCO=0`),
like `dosbox_pure`; there is no libco build to fall back to.

---

## 4. Known defects — fix, forward, or document

Each needs a decision; not all need a fix before RC.

| issue | disposition |
|---|---|
| **#1** `[broken game]` Griffon: unacknowledged quit | Save half **fixed** (`afdcbd2`, verified). Quit half open, unconfirmed, griffon-only; `b591d4d34fc` bounds the hang but does not fix it. Not a blocker. |
| **#2** Options dialog "null function" over an unclosed dialog | **Closed 2026-09-12**, documented limitation: needs a specific user action. |
| **#3** Chamber hangs in every render mode | **Closed 2026-09-12**, out of scope: every entry is `ADGF_TESTING`. Assertion fix is scummvm#7946; the hang is upstream's. |
| **#6** Silent unknown-variant failures + `kFeatureOpenUrl` | **Next.** Quality-of-life, upstreamable. Not an RC blocker but high value: silent failure was the single biggest time sink in testing. |
| **#5** Size ceilings | See item 5. |
| **#7** RetroArch rebase | **Closed 2026-09-12**: merged to `v1.22.2` clean, canvas-size fix on top. |

**Newly found, not yet filed** — one from 2026-09-08 worth an issue before it
is forgotten:

- **Save invisibility across a re-add.** Launching via the `.scummvm` hook
  registers target `tentacle`; adding the same game again in the launcher
  yields `tentacle-1` (`EngineManager::generateUniqueDomain`), and savegame
  names key off the active domain, so prior saves become unreachable. Stock
  ScummVM behaviour, surfaced by our launch creating an invisible first
  target. Compounded by `scummvm.ini` living in MEMFS and dying each launch.

*(A second finding recorded here on 2026-09-08, that `gl-core.list` had no
effect, was retracted on 2026-09-10: all four listed engines have no
`ENABLE_` entry in `config.mk.engines`. See GOTCHAS.)*

---

## 5. Size ceilings (#5) — scope decision, not an RC blocker

Two measured EmulatorJS limits, neither ours: **~2 GB zip** (V8 `ArrayBuffer`
in the buffered download) and **~4 GB zip+unpacked** (extractor wasm32).

Confirmed unchanged in 4.3.0-pre: `data/compression/` is byte-identical
between the tags, and the download path still materialises one `ArrayBuffer`.

The fix is **unpack at the door** — parse and inflate during download, writing
each entry straight to the FS. Note `DecompressionStream` handles
gzip/deflate/deflate-raw only, so the loader must walk the zip's local file
headers itself.

**Recommendation: not an RC blocker.** It affects specific large titles
(Riven, Zork GI, Myst III, The Longest Journey, 4-CD Feeble Files), not the
core. Ship RC-B with the limit documented, pursue unpack-at-the-door as its
own EmulatorJS conversation afterwards.

---

## 6. Verification before any RC is cut

This is the part most at risk of being skipped, and the part that most
determines whether the RC is honest.

**6.1 Rebuild from a clean tree and confirm reproducibility.** The build has
accumulated hand-fixes. At minimum: `rm base/plugins.o` (engine-list changes
do not rebuild the plugin registry — silent, and the dangerous direction is
*adding* engines), then a full build, then verify the enabled engine set
matches `all-engines.list`.

**6.2 Re-validate the confirmed set against the final binary.** Precedent
exists: 30 titles were re-validated after the 2026-09-06 rebase. Do the same
here — 20 chosen because they only work due to a fix in this project, 10 as
regression canaries.

**6.3 Audio, not just boot.** Standing rule, and it caught a real
misdiagnosis this week. Every confirmation must state that sound was heard.
The RetroArch `v1.22.2` merge (2026-09-10) switched the audio driver default
to rwebaudio; every core since is linked with it. **Verified by ear
2026-09-12** on the staged core (md5 `d941d2be…`).

**6.4 Save/load round-trip per confirmed title.** New requirement after the
`tentacle-1` finding: save, return to launcher, relaunch, load. Booting is not
enough.

**6.5 Flaky-unzip status stated per batch**, even when clean.

**6.6 Honest counts in the README before publishing.** Done 2026-09-10/11:
the six engines no longer in the build are ⚠️, counts are 89 of 107 top-level
against the enabled set, and `build/check-engines.py` now diffs the lists and
README against `upstream/master` after every build. Keep it that way.

---

## 7. Suggested order

1. **Ask EmulatorJS about size** (item 1) — cheap, unblocks the rest, may
   reshape item 3. Still unasked.
2. **Issue #6** (unknown-variant reporting, `kFeatureOpenUrl`) — next code work
3. **File the `tentacle-1` finding** (item 4) while fresh
4. ~~README truthfulness pass (6.6)~~ done
5. ~~Engine-fix PRs (2.2)~~ submitted, three open
6. **Test 3.4** (default engine set) and **3.3** (drop the MIDI stub) — one
   build each, both simplify the EmulatorJS ask
7. **Clean rebuild + full re-validation** (item 6) — produces the RC-B candidate
8. **Cut RC-B**: versioned `.data` + report JSON + documented limitations
9. Then RC-A: the three-entry PR to `EmulatorJS/RetroArch` (3.1), the
   engine-data decision (3.2), and asking for `EmulatorJS/scummvm` to exist

---

## 8. Explicit non-goals for this RC

Stating these so they do not creep in:

- **GL core** — 4 engines (`colony`, `hpl1`, `twp`, `watchmaker`) plus 3D
  Wintermute. All large commercial titles still on sale. Deferred until
  requested.
- **Unpack at the door** — real work, own conversation, post-RC.
- **Unstable/testing engines** — ScummVM does not ship them and neither do we.
- **wme3d TinyGL renderer** — unfinished upstream, disabled by its own author.
