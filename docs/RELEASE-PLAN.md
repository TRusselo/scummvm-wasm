# Plan: toward a Pre-Release Candidate binary

Written 2026-09-08. Scope: what stands between today's working core and a
public Pre-Release Candidate distributed through EmulatorJS.

**Nothing here is a code change.** It is a sequencing plan with exit criteria.

---

## 0. What "Pre-Release Candidate" has to mean here

Worth fixing the definition first, because it determines how much of the list
below is actually blocking.

Per issue #4, **EmulatorJS never receives our binaries.** Their
`build-emulatorjs.sh` globs `*_emscripten.bc`, runs the same
`Makefile.emulatorjs` link, and 7z's the result itself. So "release" means
*their build produces our core from source* — not that we hand them a `.data`.

That gives two candidate definitions, and they imply very different work:

- **RC-A — "EmulatorJS can build it"**: the real target. Gated on upstream
  merges and on EmulatorJS accepting build-system changes. Mostly *not* in our
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
| **ours** | **~93 MB** |
| fbneo (their largest) | 7.9 MB |
| typical | ~1 MB |

We are ~11x their largest and ~80x typical, almost entirely from 74 MB of
embedded engine-data.

This is a **policy** question, not a technical one, and its answer reshapes
item 3 below. If they would rather fetch engine-data separately than bake it
into the wasm, our build changes shape — so polishing an 89–93 MB core before
asking risks discarding the work.

**Action:** one short message on EJS issue
[#1263](https://github.com/EmulatorJS/EmulatorJS/issues/1263) (already open,
ours) covering: the size, why (engine-data), the three options (bake / fetch
separately / split core+data), and asking which they want.

**Exit criterion:** a stated preference from EmulatorJS, or an explicit
"no objection to the baked form".

*Cost: ~1 hour. Blocks: item 3, and the shape of RC-A.*

---

## 2. Upstream merges — the hard gates

### 2.1 `libretro/libretro-deps#15` — FreeType autofit signature fix (OPEN)

**The one true hard gate.** Their build starts from libretro-deps master.
Without this, the build traps on the first glyph with a real outline — fatal.
Our `dependencies.mk` pin to `TRusselo/libretro-deps` exists solely for this
and reverts to two upstream lines once it lands.

**Action:** nothing to write; it needs review attention. Periodic, polite
follow-up only.

**Exit criterion:** merged, pin reverted, core rebuilt and re-validated.

*Blocks RC-A absolutely. Does not block RC-B (we carry the fork pin).*

### 2.2 Engine fixes → `scummvm/scummvm`

Ours, upstreamable, independent of each other:

| commit | change | issue |
|---|---|---|
| `cac3a252862` | VIDEO: AVIDecoder::loadStream double free | — |
| `a607b761ebe` | CHAMBER: Hercules blit path guard | #3 |
| `b591d4d34fc` | Dropped quit event hangs the tab on exit | #1 |
| `3f09158c8a9` | TINSEL: two uncatalogued Discworld 1 variants | — |

Precedent is good: #7902 (Level 9 detector) was accepted and applied as
`05f236adb`, and digitall explicitly invited more.

**Note:** `4dc59596241` (our Level 9 commit) is now redundant — it will drop
out on the next rebase. Expect it to vanish; that is correct, not lost work.

**Action:** one PR per fix, terse messages scaled to the diff (see
`feedback_terse_upstream_commit_messages`). Detection entries and the AVI fix
are the easiest sells; chamber should reference issue #3's evidence.

*Cost: ~1 day total. Does not block RC-B.*

### 2.3 Port integration → `libretro/scummvm`

Inherently ours, and must land there for RC-A:

- `955aef0429e` real save-state support (`retro_serialize`/`retro_unserialize`)
- `4b6607e97d3` scan the virtual-FS root on Emscripten
- `f09251ff1d1` register embedded `/engine-data` in the search set
- `48dea85dc88` exclude the WebMIDI plugin
- `8ad2b918334` keep `warning()` in release builds
- `8690c2d4e6d` render-mode core option
- issue #6's two items (unknown-variant reporting, `kFeatureOpenUrl`)

`84f2bd11f5a` (CI arm64 removal) is fork-only and must **never** be submitted.

*Larger and more entangled than 2.2; sequence after it.*

---

## 3. EmulatorJS build-system gaps

All three are in `build-emulatorjs.sh` and none can be resolved unilaterally.
**Sequence after item 1**, since the answer there may change 3.2 entirely.

**3.1 Memory settings.** `scummvm` appears in neither `largeStack` nor
`largeHeap`. Their build would fail exactly as our rebase did:
`wasm-ld: error: initial memory too small, 186199984 bytes needed`. Adding
`scummvm` to both yields 128 MB stack / 512 MB heap — more than we need but
functional. Small, self-contained PR.

**3.2 Engine-data embed — the real gap.** We pass
`--embed-file ../build/embed-staging/engine-data@/engine-data`. **Nothing in
their script does anything like this, for any core.** Needs a design decision
with them, not a patch from us.

**3.3 Drop `--pre-js midi-stub-pre.js`.** Likely droppable once the WebMIDI
exclusion (2.3) is upstream — nothing reads `midiOutputMap` any more. Removes
one more non-standard build input. Verify by building without it.

---

## 4. Known defects — fix, forward, or document

Each needs a decision; not all need a fix before RC.

| issue | disposition |
|---|---|
| **#1** Griffon save freezes the tab | Have a fix (`b591d4d34fc`). **Verify it actually resolves #1**, then close or upstream. |
| **#2** Options dialog "null function" over an unclosed dialog | Reproducible, no fix. Decide: RC blocker or documented limitation. Leaning *document* — it needs a specific user action. |
| **#3** Chamber hangs in every render mode | Upstream engine immaturity; every entry is `ADGF_TESTING`. **Forward to bugs.scummvm.org** and close ours. Not an RC blocker — out of scope by the no-unstable-engines rule. |
| **#6** Silent unknown-variant failures + `kFeatureOpenUrl` | Quality-of-life, upstreamable. Not an RC blocker but high value: silent failure was the single biggest time sink in testing. |
| **#5** Size ceilings | See item 5. |
| **#7** RetroArch rebase | Note-to-self; no action until a bump is wanted. |

**Newly found, not yet filed** — two from 2026-09-08 worth issues before they
are forgotten:

- **Save invisibility across a re-add.** Launching via the `.scummvm` hook
  registers target `tentacle`; adding the same game again in the launcher
  yields `tentacle-1` (`EngineManager::generateUniqueDomain`), and savegame
  names key off the active domain, so prior saves become unreachable. Stock
  ScummVM behaviour, surfaced by our launch creating an invisible first
  target. Compounded by `scummvm.ini` living in MEMFS and dying each launch.
- **`gl-core.list` has no effect.** `colony`/`watchmaker` are upstream
  `default=no` so were never built; `hpl1`/`twp` are `default=yes` and are
  compiled into the main core *despite* being listed as excluded. Either make
  the exclusion real or delete the list.

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

**6.4 Save/load round-trip per confirmed title.** New requirement after the
`tentacle-1` finding: save, return to launcher, relaunch, load. Booting is not
enough.

**6.5 Flaky-unzip status stated per batch**, even when clean.

**6.6 Honest counts in the README before publishing.** Currently overstated:
six engines are marked ✅ that ScummVM itself classifies as broken or
unsupported (`avalanche`, `cryo`, `dm`, `lilliput`, `mediastation`,
`mutationofjb`) and that are no longer in the build. An RC must not claim
them. Recount against the *enabled* set, not the list.

---

## 7. Suggested order

1. **Ask EmulatorJS about size** (item 1) — cheap, unblocks the rest, may
   reshape item 3
2. **File the two unfiled findings** (item 4) while fresh
3. **README truthfulness pass** (6.6) — required before anything is published
4. **Engine-fix PRs to scummvm/scummvm** (2.2) — independent, good precedent
5. **Clean rebuild + full re-validation** (item 6) — produces the RC-B candidate
6. **Cut RC-B**: versioned `.data` + report JSON + documented limitations
7. Then RC-A work: libretro/scummvm integration (2.3), EJS build gaps (3),
   gated on `libretro-deps#15` (2.1)

---

## 8. Explicit non-goals for this RC

Stating these so they do not creep in:

- **GL core** — 4 engines (`colony`, `hpl1`, `twp`, `watchmaker`) plus 3D
  Wintermute. All large commercial titles still on sale. Deferred until
  requested.
- **Unpack at the door** — real work, own conversation, post-RC.
- **Unstable/testing engines** — ScummVM does not ship them and neither do we.
- **wme3d TinyGL renderer** — unfinished upstream, disabled by its own author.
