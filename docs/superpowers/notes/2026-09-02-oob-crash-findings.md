# OOB-crash investigation: findings (2026-09-02 / fix round 2026-09-03)

This document is the tracked, standalone record of the `debug/fonts-oob-crash`
investigation. It supersedes the untracked ledger and per-task reports under
`.superpowers/sdd/2026-09-02-oob-crash-investigation/` (deleted once this file
landed) -- a reader should not need those to understand what was found.

## Summary

The investigation set out to find why 9 ScummVM engines (`griffon`, `glk`,
`dm`, `tony`, `neverhood`, `bbvs`, `gnap`, `mutationofjb`, `ngi`) all crash
with a WASM trap once their `fonts.dat` companion file is supplied, and
whether that pointed at one shared, generic ScummVM-WASM bug.

**What was confirmed, source-verified, across multiple independent
re-reviews:**
- The crash is a real `WebAssembly.RuntimeError: function signature mismatch`
  inside FreeType's autofit-hinting dispatch, reached through genuine,
  unmodified ScummVM GUI/GLK code (not a decompiler/optimizer artifact).
- A debug build using this project's own pre-existing `DEBUG=1` Makefile mode
  was tried for the first time this round (see "Reusable tooling" below), and
  plain `printf` diagnostic logging was substituted for `retro_log_cb` on the
  theory that it would work around a real tooling gap (see "Correction"
  below) -- confirmed true for main-thread output, but **not confirmed**
  for the pthread emulation-worker context specifically (see the
  "Correction" section's retest results).

**What this fix round overturned:** the investigation's central explanatory
theory -- that the `griffon.zip` test ROM (and, by extension, the other 8
affected ROMs) fail their *own* engine's detection and get misdetected into
GLK's `level9v3` sub-interpreter -- turns out to rest on a methodology error.
Redoing the same comparison with ScummVM's *actual* detection algorithm (an
MD5 of the file's first 5000 bytes, not the whole file) shows `griffon.zip`'s
`objectdb.dat` **does** match Griffon's own detection table exactly, as do
the corresponding detection files for all 6 other ROMs checked in this round
(`bbvs`, `ngi`/Full Pipe, `mutationofjb`, `gnap`, `neverhood`, `tony`). See
"CORRECTION" section below -- this is the single most important finding of
this fix round and changes what "9 engines share one bug" most likely means.

**What remains open:**
- Why does the crash trace show real GLK engine code (`Glk::GlkEngine::run()`,
  `Screen::loadFont()`) executing when loading a ROM that ScummVM's own
  Griffon detector should accept? Not resolved this round (see CORRECTION).
- Whether the "function signature mismatch" trap reflects genuine upstream
  memory corruption, or a legitimate/deterministic autofit function-pointer
  dispatch defect specific to this WASM build. Genuinely undecided (see
  "Open question" below).
- Why `buried` (a confirmed-working engine) uses the same `ttf.cpp` TTF-load
  path successfully, contradicting the plan's original assumption. Unresolved
  (see "Contradiction" below).

## Confirmed root cause chain (source-verified)

`Graphics::TTFFont::cacheGlyph()` (`graphics/fonts/ttf.cpp:813`, function
name/line may drift slightly after the printf-logging edit in this round --
see the `[fonts-oob-debug]` comments in that file for the current exact
locations) calls `FT_Load_Glyph()`, which traps inside FreeType's autofit
dispatch with `WebAssembly.RuntimeError: function signature mismatch`. This
is reached via `engines/glk/screen.cpp`'s real `Screen::initialize()` ->
`loadFonts()` -> `loadFont()` chain. This chain was confirmed genuine (not
code-folding) after an earlier report wrongly claimed the `Glk::Screen::*`
frames were an `-O3` identical-code-folding artifact pointing at
`gui/ThemeEngine.cpp`'s `loadScalableFont` instead -- a follow-up review
found `engines/glk/screen.cpp:132`'s real `Screen::loadFont()` has an exact
parameter-signature match to the trace, and the full call chain
(`initialize`->`loadFonts`->`loadFonts(archive)`->`loadFont`) matches
frame-for-frame, while `ThemeEngine::loadScalableFont`'s real signature is
structurally too different to fold with it. The report's original
"verified this two ways" claim was corrected once this was actually checked
against source directly.

## CORRECTION: the ROM-mislabeling theory rests on a methodology error

The investigation's Task 3 established (and multiple later re-reviews
independently re-confirmed) that `test-page/griffon.zip` "fails Griffon's
own detection" because its `objectdb.dat` has the declared size (27754
bytes) but a different MD5 than the one entry in
`engines/griffon/detection.cpp`:

```
AD_ENTRY1s("objectdb.dat", "ec5371da28f01ccf88980b32d9de2232", 27754)
```

Task 3's own check was:

```
$ unzip -p test-page/griffon.zip objectdb.dat | md5sum
d322e95213c120f874fa5816e3800c76  (27754 bytes)
```

**This is a full-file MD5, not what ScummVM's detector actually computes.**
`engines/advancedDetector.cpp` hashes only the file's first `_md5Bytes` bytes
(`_md5Bytes = 5000` by default -- `engines/advancedDetector.cpp:960`, used at
line 668's `Common::computeStreamMD5AsString(*testFile.get(), md5Bytes)`).
This project's own `ENGINE-TEST-PLAN.md` consistently calls this the
"5000-byte-prefix MD5" and uses it correctly everywhere else. Comparing a
full-file MD5 against a 5000-byte-prefix hash will show a mismatch for
essentially any file over 5000 bytes, correct dump or not -- it is not
evidence of a bad dump or a detection failure.

Redone correctly during this fix round:

```
$ unzip -p test-page/griffon.zip objectdb.dat | head -c 5000 | md5sum
ec5371da28f01ccf88980b32d9de2232  -
```

**This matches Griffon's detection table exactly.** `test-page/griffon.zip`
is, per ScummVM's own detection algorithm, a valid, correctly-detectable
Griffon dump. The "griffon.zip fails detection, falls through to a GLK
sub-interpreter" theory that the rest of the investigation built on is
**not supported** by a correct hash comparison.

This does not explain away the actually-observed behavior -- the user's own
manually-opened DevTools session and this project's automated testing both
independently confirmed the ROM genuinely boots into GLK's `level9v3`
sub-interpreter (the "Unable to locate valid Level 9 game" debugger-diversion
screen is real and reproducible). But the *mechanism* is not "Griffon
detection fails, ScummVM falls back to GLK." A plausible alternative,
not yet investigated: GLK's own sub-engine detection
(`engines/glk/detection.cpp:264`'s `detectGames()`) dispatches to ~15
sub-interpreter `MetaEngine`s including `Level9MetaEngine`, several of which
use their own heuristic/file-format sniffing rather than exact
`AD_ENTRY` hash matching -- so it is possible some file in the ROM's set
independently triggers a true (by GLK's own heuristic criteria) Level9 match
*at the same time* Griffon's exact-hash match also succeeds, creating a
multi-engine detection ambiguity that something (engine registration order,
a scoring rule, or a bug in how this harness resolves ambiguous matches)
resolves in GLK's favor. This is speculation, not verified -- flagged as the
next concrete thing to check, not resolved in this round.

### Item 5: do the OTHER 8 affected engines' ROMs also fail their own detection?

Checked using the corrected 5000-byte-prefix method (not Task 3's original
full-file method) against six of the locally-present ROMs:

| Engine | ROM checked | Detection file | Expected MD5 (5000-byte prefix) | Actual MD5 (5000-byte prefix) | Match? |
|---|---|---|---|---|---|
| bbvs | Beavis and Butt-Head in Virtual Stupidity.zip | `VNM/VSPR0001.VNM` (1166628 bytes) | `7ffe9b9e7ca322db1d48e86f5130578e` (EN_ANY entry) | `7ffe9b9e7ca322db1d48e86f5130578e` | **Yes** |
| ngi (fullpipe) | Full Pipe.zip | `4620.sc2` (510 bytes, whole file) | `66ef399644434e88f3951acd882742b6` ("Full Pipe English Steam version" entry) | `66ef399644434e88f3951acd882742b6` | **Yes** |
| mutationofjb | Mutation of J.B. (German).zip | `JB.EX_` (150800 bytes) | `8833f22f1763d05eeb909e8626cdec7b` (DE_DEU entry) | `8833f22f1763d05eeb909e8626cdec7b` | **Yes** |
| gnap | U.F.O.s (Gnap).zip | `STOCK_N.DAT` (12515823 bytes) | `46819043d019a2f36b727cc2bdd6980f` (EN_ANY entry) | `46819043d019a2f36b727cc2bdd6980f` | **Yes** |
| neverhood | Neverhood.zip | `hd.blb` (4279716 bytes) | `22958d968458c9ff221aee38577bb2b2` (primary entry) | `22958d968458c9ff221aee38577bb2b2` | **Yes** |
| tony | Tony Tough.zip | `Roasted/roasted.MPC` (366773 bytes) | `57c4a3860cf899443c357e0078ea6f49` (first English entry) | `57c4a3860cf899443c357e0078ea6f49` | **Yes** |
| griffon (re-check) | test-page/griffon.zip | `objectdb.dat` (27754 bytes) | `ec5371da28f01ccf88980b32d9de2232` | `ec5371da28f01ccf88980b32d9de2232` | **Yes** |

**All 7 ROMs checked match their own claimed engine's detection table
exactly**, once compared correctly. None show the "right size, wrong content"
misdetection pattern the investigation had assumed. This means the "9
engines need `fonts.dat`" grouping most likely **is** a shared, generic
ScummVM-WASM bug in the common font-rendering codepath (the investigation's
very first hypothesis, in `ENGINE-TEST-PLAN.md`), not 9 independent
misdetection incidents. It also means Task 4's "why does GLK code run for a
Griffon ROM" investigation, while a real and reproducible phenomenon, was
answered with the wrong mechanism -- see the CORRECTION above.

**Independent corroboration, found in this project's own pre-existing
documentation** (`docs/ENGINE-TEST-PLAN.md`, written and committed before
this investigation branch existed): every one of these ROMs' rows already
states detection succeeded, explicitly, in each case:
- `neverhood` (line 177): *"Detection and companion-file loading succeeded
  fine -- crash only hits once `fonts.dat` is added"*
- `tony` (line 186): *"detection then succeeded but the WASM crash hits once
  `fonts.dat` is added"*
- `bbvs` (line 203): 5000-byte-prefix MD5 and size *"match the detection
  entry exactly"*
- `gnap` (line 211): 5000-byte-prefix MD5 *"hash-matches the `EN_ANY`/Windows
  entry exactly"*
- `ngi`/Full Pipe (line 221): *"hash-verified exactly against `4620.sc2`'s
  English-Steam detection entry"* -- also clarifies the "mem OOB after SCUMM
  splash" phrase in that ROM's filename was always colloquial for "the
  generic ScummVM boot splash," not a literal SCUMM-engine misdetection.

In other words: the "these ROMs might be misdetecting" question this fix
round was asked to check (Item 5) was **already answered, correctly, in this
project's own records before the investigation even began** -- every
previously-tested row already documented successful detection followed by a
post-detection crash. Nobody cross-checked `ENGINE-TEST-PLAN.md` against the
investigation's own "griffon.zip fails detection" claim while building the
"9 ROMs independently misdetect" theory in Task 3/4/the final review, even
though the two were in direct tension the whole time.

This is a read-only, static-file finding only. Per this project's standing
rule, none of these six non-`griffon` ROMs were touched, repackaged, or
"fixed" -- they remain exactly as found in
`/mnt/unraid/emulation/scummvm/non-running/`. No browser reproduction was
attempted for any of them in this round.

One neighboring, not-yet-fixed timing confound worth disclosing: the
~512-line-per-font-load diagnostic logging added in Task 4 (two 256-iteration
loops in `TTFFont::load()`) was active during the runs that produced the
2-of-3 Level9-debugger-diversion split reported in Task 4 -- a plausible
timing/scheduling confound for that specific observation, not something this
round investigated further or changed.

## Correction -- the tooling-gap claim was wrong

An earlier report claimed the entire pthread-worker's console output is
invisible to automated browser tooling (`read_console_messages`). This is
false: `printf`-based output from the SAME worker thread (e.g. ScummVM's own
game-detection log lines, and the `level9v3` sub-detector match) WAS
captured normally by the automated tool -- `identifyGame()`/`detectGames()`
(`base/main.cpp`/`base/commandLine.cpp`) both run inside `scummvm_main()`,
which the branch's own `stack-trace-1.txt` shows executing inside the same
pthread worker the crash later occurs in, so this is genuinely
worker-thread output, not main-thread output as an earlier draft of this
section called it (corrected here).

The real discriminator is less settled than an earlier draft of this
section claimed. That draft attributed it entirely to the print API:
`retro_log_cb` calls get routed through RetroArch's own `RARCH_LOG`/
verbosity filtering (`retroarch/verbosity.c`), which was believed to
prevent them reaching the console the automated tool reads, while plain
`printf` does not go through that gate. **This explanation is incomplete**:
commit `6a02069` (already on this branch, predating this round's fix)
added `EJS_DEBUG_XX = true` specifically to pass RetroArch's `-v` flag and
open `verbosity_is_enabled()` -- so at the point this round's printf
retest ran, that gate was already open, and `retro_log_cb` output should
no longer have been silently dropped by it either. Whether the original
`retro_log_cb` diagnostic calls (Task 4) would now surface correctly with
that gate open was never re-tested after `6a02069` landed -- the printf
swap happened first, without first confirming whether the original
`retro_log_cb` approach was already fixed by the verbosity change alone.
This is left as an open, untested question rather than resolved.

This round's fix: `scummvm-core/graphics/fonts/ttf.cpp`'s 5 diagnostic call
sites (in `TTFFont::load()`, `TTFFont::cacheGlyph()`, `TTFFont::assureCached()`)
were switched from `retro_log_cb(RETRO_LOG_WARN, ...)` to plain
`printf(...)` followed by `fflush(stdout)`. Since `printf` is portable C, not
libretro-specific, the `#ifdef __LIBRETRO__` guards around these specific
call sites were also removed, along with the now-unneeded
`#include "backends/platform/libretro/include/libretro-core.h"` -- a
libretro-only, cross-layer include that a prior review flagged as unsafe on
this generic, multi-backend file (every `USE_FREETYPE2` backend compiles
`graphics/fonts/ttf.cpp`, not just libretro/Emscripten). Removing the include
entirely (rather than re-guarding it) fixes that portability problem as a
side effect.

**Result of retesting this round: inconclusive, not confirmed either way.**
The printf-swapped core was rebuilt (both as part of the `DEBUG=1`/
`SAFE_HEAP=2` build, and separately as a fast, non-`DEBUG` `-O3` build once
the `SAFE_HEAP=2` build proved impractical to run -- see below) and tested
live against `test-page/griffon.zip` five times in this round. Four of the
five attempts stalled indefinitely at the ScummVM splash screen and never
reached game detection or the crash at all (the tab stayed responsive --
a test click correctly triggered a real `WrongDocumentError` pointer-lock
exception -- but no further `[INFO]`/emulation console output appeared for
over a minute in each case). This session's own `ps aux` showed heavy,
unrelated concurrent CPU load at the time (a `DisplayLinkManager` process at
~160% CPU, several Brave renderer processes at 20-40% CPU each, a compositor
at ~30%) that plausibly starved the pthread-heavy emulation workload of real
CPU time -- a plausible explanation, but a re-review of this round's own diff
surfaced a stronger, previously-unconsidered alternative that should be
ruled out first: **the printf swap itself made the instrumentation far more
expensive.** Before this round, the diagnostic sites were
`#ifdef __LIBRETRO__` + `if (retro_log_cb)` calls (near-zero cost once
disabled, and previously always disabled by the log-level/verbosity gates
anyway); they are now unconditional `printf(...)` followed by an explicit
`fflush(stdout)`, firing up to ~512 times per font load across
`TTFFont::load()`'s two 256-iteration loops alone. Under Emscripten with
pthreads, a worker's stdout is proxied to the main thread, making a forced
flush on every one of those calls a genuinely expensive, synchronous,
cross-thread operation in the exact hot path this round was trying to
observe. This round's stalls may therefore be self-inflicted by the
instrumentation's own new cost, not solely external CPU contention -- not
distinguished from the contention theory by this round's data, and worth
checking first (e.g. buffering the log lines or removing the per-call
`fflush`) before drawing further conclusions from this build variant.

The one attempt that did reach a crash produced a genuine `worker.onerror`
`ErrorEvent` (the same swallowed-detail signature Task 3 already
characterized), but **zero `[fonts-oob-debug]` printf lines appeared in the
automated tool's captured console** for that run, despite the instrumented
`TTFFont::load()` loops being written to fire (and `fflush`) hundreds of
times before any crash could occur on a real font-loading path. Three
explanations remain open, not distinguished by this round's data:
1. That specific crash occurred via a path that never actually called the
   instrumented functions (e.g., a different failure before font loading was
   reached, or the Level9-debugger-diversion path Task 4 previously found).
2. Plain `printf` output genuinely still does not reach the automated
   `read_console_messages` tool for this Worker context, and the C1
   hypothesis (printf succeeds where `retro_log_cb` failed) does not hold.
3. Emscripten's proxied stdout from a worker can be lost if that worker
   terminates abruptly (as a crash does), independent of `fflush` -- the
   flush may complete locally but the proxying to the main thread's console
   sink may not survive the worker's termination.

**This round's honest conclusion: the printf swap is not confirmed to fix
the tooling gap.** The evidence is one ambiguous data point, not a clean
positive or negative. A follow-up round with less system contention and
more attempts (to get a clean run that both reaches the crash AND is
confirmed, independently, to have gone through `TTFFont::load()`) is needed
to actually settle this -- ideally by also checking whether the earlier,
successfully-captured `[INFO] [Aspect Ratio]`/game-detection main-thread
messages (which DO appear reliably, confirming the tool can see plain
`printf`/`console.log`-routed output from at least the main thread) extend
to the pthread emulation-worker context specifically, which remains the
open, untested half of the C1 hypothesis.

## Open question -- is this corruption, or a static/deterministic defect?

The investigation had been treating this as "upstream memory corruption
clobbering a function pointer table" without ever testing that against the
trap's literal meaning. `function signature mismatch` is exactly what a
legitimate, deterministic, mismatched-signature indirect call produces --
which is literally the mechanism FreeType's autofit module uses (dispatching
through per-script/per-writing-system function-pointer tables). This
actually fits the investigation's own strongest cross-engine evidence
(identical `wasm-function[N]` indices across unrelated engines/runs) *better*
than random corruption would, which would be expected to vary run-to-run and
engine-to-engine.

This remains **genuinely open, not resolved either way**. A cheap
discriminator a reviewer proposed: `gui/ThemeEngine.cpp:1751`'s
`loadScalableFont` (used by every engine's GUI, including all the
confirmed-working engines in this project's own `ENGINE-TEST-PLAN.md`) calls
the same `Graphics::loadTTFFont` with `Graphics::kTTFRenderModeLight`
(`FT_LOAD_TARGET_LIGHT` / `FT_RENDER_MODE_LIGHT`, set in `ttf.cpp`'s
`setupFace`-equivalent switch around line 349) -- and `FT_LOAD_TARGET_LIGHT`
still invokes FreeType's autofitter internally. This project's own test
history already provides real evidence here without needing to reprove
anything: dozens of engines in `ENGINE-TEST-PLAN.md` are marked **Confirmed
working**, and every one of them renders its ScummVM GUI (launcher, menus,
dialogs) through `ThemeEngine`, meaning `loadScalableFont`'s
autofit-invoking path has already run successfully, repeatedly, across many
separate engines/binaries in this exact build. That is real evidence
*against* a categorical, always-broken autofit dispatch in this WASM build --
if the dispatch table were universally corrupted or mismatched, GUI font
loading would be expected to crash on every engine, not just this specific
cluster. This points toward something GLK-font-specific (a particular font
file, glyph, or code path only `Screen::loadFont()` exercises) or genuinely
corruption-driven (triggered by something specific to how these engines'
data loads, not a static build defect) rather than a build-wide dispatch
break. Still not proven either way -- this is reasoning from existing
evidence, not a new direct test of the GLK-specific path.

## Contradiction in the original investigation plan

The plan assumed the crash was "probably not `graphics/fonts/ttf.cpp`'s
direct TTF path, since `buried` [a different, confirmed-working engine on
this exact build] uses that exact path successfully." The confirmed crash
**is** in that exact path (`TTFFont::cacheGlyph` -> `FT_Load_Glyph`). This
was never reconciled in any prior report and is not resolved here either.
Either `buried`'s success doesn't actually rule this out (e.g. it uses a
different render mode -- `buried`'s own font loading is worth checking
directly, not yet done -- a different font file, or never triggers the
autofit sub-path at all), or there's a discriminating variable nobody has
identified yet. Stated here plainly as unresolved, not silently dropped.

## What's still needed for a real fix

1. Resolve the CORRECTION's open question above: why does GLK code actually
   run when loading a ROM that Griffon's own detector accepts? Check
   `engines/glk/level9/level9.cpp`'s (or its `MetaEngine`'s) own detection
   heuristic against the exact files in `griffon.zip`/`Griffon Legend.zip`,
   and check how this harness's engine-selection resolves a multi-engine
   detection ambiguity (if that's what's actually happening).
2. Directly check `buried`'s own font-loading render mode/path against
   `Screen::loadFont()`'s, to resolve the plan's own unreconciled
   contradiction above.
3. Confirm whether the `DEBUG=1`/`SAFE_HEAP=2` build (this round's build --
   see "Reusable tooling") can pinpoint the actual faulting write with a
   precise trap location, instead of the downstream "function signature
   mismatch" symptom -- this is the single most promising untried lever per
   `docs/GOTCHAS.md`'s own prior precedent (see below).
4. Once (1)-(3) narrow the mechanism, re-run the ThemeEngine/render-mode
   discriminator concretely (not just by analogy to existing GUI-load
   successes) against the GLK font path specifically.

## Reusable tooling

`build/build-retroarch-core-debug.sh` (confirmed sufficient for
symbolicated stack traces via `-g -gsource-map`) was extended this round to
optionally pass `DEBUG=1` through to `retroarch/Makefile.emulatorjs`'s own
pre-existing debug mode (lines ~299-301: `-O1` CFLAGS, `-O0 -g -gsource-map
-s SAFE_HEAP=2 -s STACK_OVERFLOW_CHECK=2 -s ASSERTIONS=1` LDFLAGS) rather
than reinventing a subset of it. `DEBUG` is a Makefile variable checked with
`ifeq ($(DEBUG), 1)`, so it is now passed as an explicit `make` argument
(`DEBUG_ARG="DEBUG=1"` appended to the `emmake make` invocation), not just
exported into the shell environment, to avoid depending on `emmake`/`make`'s
environment-variable-import behavior. `docs/GOTCHAS.md:114-124` documents
that this exact flag combination previously turned a vague "memory access
out of bounds" into an exact diagnosis (a 4MB-stack overflow, pinpointed to
the precise `SP` value and stack limits) on a prior, unrelated bug. Nobody
had tried it against this investigation's crash before this round.

**Result: the `DEBUG=1`/`SAFE_HEAP=2` build is confirmed impractically heavy
to actually run in this harness, within this round's testing budget.** It
built successfully (~3 minutes, `-O0 -g -gsource-map -s SAFE_HEAP=2 -s
STACK_OVERFLOW_CHECK=2 -s ASSERTIONS=1`), but produced dramatically larger
artifacts than the normal `-g -gsource-map`-only debug build: `.wasm` grew
from 212MB to 379MB, and the packaged/compressed core `.data` archive the
browser downloads grew from 89MB to 117MB. Loading it in the test harness
went past the "Decompress Game Core" progress indicator but then the tab
became fully unresponsive (script injection into the page timed out
repeatedly for 40+ seconds, and the tab was eventually lost/closed).

The user independently ran their own manual test session in parallel and
hit the same practical problem on their first attempt: a hang on a blank
screen that never reached the game or the crash. On a rerun, their real
DevTools console showed (among other things) repeated `Warning: Enlarging
memory arrays, this is not fast!` lines from a `_extract`/`asm._extract`
7z-decompression Worker, and several `Multiple debug symbols for script
were found. Using EmbeddedDWARF` notices. **Correction, checked with the
user directly: the memory-growth warnings are normal, routine Emscripten
heap-growth behavior that appears on most loads in this project, including
runs that work fine -- not a symptom specific to this build or to the
hang.** They are not treated as a finding here. The `EmbeddedDWARF` notices
are plausibly just Chrome DevTools acknowledging the debug build's multiple
debug-info sources (`-g -gsource-map` from Task 2, by design) rather than
anything diagnostic. The blank-screen hang itself remains unexplained --
this session's own independent test of the same `DEBUG=1`/`SAFE_HEAP=2`
build also produced a fully unresponsive tab (script injection timed out
repeatedly for 40+ seconds, tab eventually lost), which is at minimum
consistent with the much larger debug artifacts (`.wasm` 212MB -> 379MB,
packaged `.data` 89MB -> 117MB) being slow to extract/instantiate/run, but
this round did not isolate the hang's exact cause (extraction time vs.
`SAFE_HEAP=2` runtime overhead vs. something else).

**Bottom line for future use of this build mode:** `DEBUG=1`/`SAFE_HEAP=2`
is confirmed impractical to use for interactive testing against this crash
within this round's time budget -- two independent sessions (this one and
the user's) both hit an unresponsive/hung state before reaching the actual
crash site. Future attempts should budget significantly more wall-clock
time past the decompress step before concluding it's hung, and/or try
tuning the flags (e.g. `SAFE_HEAP=1` instead of `2`, or `-O1` without
`SAFE_HEAP`) to isolate which one drives the slowdown -- not attempted this
round.

## Known limitations

Reproducing this crash requires a human with real, manually-opened Chrome
DevTools -- the richest capture in this whole investigation came from the
user pasting their own DevTools console output directly. A `printf`-based
logging approach was tried this round as a possible automated-tooling
workaround; it's confirmed to work for plain main-thread output (game
detection, aspect-ratio logs) but **not confirmed** for the pthread
emulation-worker context where the actual crash lives -- see the
"Correction" section's retest results. `test-page/griffon.zip` (per the
CORRECTION above, a ROM whose actual misdetection mechanism is still
unexplained, not simply "fails Griffon detection") is a nondeterministic
repro -- Task 4 measured roughly 1/3 of runs hitting an earlier
Level9-debugger diversion instead of reaching the crash site; this round's
own retest saw an even higher stall rate (4 of 5 attempts never left the
splash screen at all), plausibly worsened by heavy unrelated CPU load on
the test machine at the time rather than a change in the ROM's own
behavior (see "Correction" section for detail).

## Note for whenever a fix eventually merges

`docs/GOTCHAS.md` (on the `engines-2d-sweep` branch, not touched by this
investigation branch) has stale claims that should be corrected then: it
documents only 4 engines sharing this bug (not the 9 tracked here), refers
to the crash only as "memory access out of bounds" (this investigation found
it also presents as `function signature mismatch`), and its `tony` row's
narrative is undercut by this fix round's finding that `fonts.dat` is
GLK-specific (`engines/glk/screen.cpp`'s own hardcoded `FONTS_FILENAME`, with
`backends/imgui/imgui_fonts.cpp` its only other consumer in the whole
codebase) rather than a ScummVM-wide requirement.
