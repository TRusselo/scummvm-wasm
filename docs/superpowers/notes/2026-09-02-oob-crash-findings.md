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

**Resolved in the "Follow-up: buried vs GLK font-loading comparison"
section below.** `buried`'s actual confirmed-working test run used a
non-truecolor detection entry, which takes `kTTFRenderModeMonochrome` and
(traced into FreeType's own dispatch logic) never invokes autofit at all,
while GLK's `Screen::loadFont()` always defaults to `kTTFRenderModeLight`,
which -- unconditionally, for the TrueType driver -- does. `buried`'s
success provides no evidence about the LIGHT/autofit path GLK's crash
actually goes through.

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

### Follow-up (2026-09-03, Task B): logging trimmed, still impractical -- but differently

The leading hypothesis going into this follow-up was that the diagnostic
logging itself, not `SAFE_HEAP=2`, was the practical bottleneck:
`TTFFont::load()`'s two 256-iteration loops fired an unconditional
`printf`+`fflush(stdout)` per character (up to ~512 times per font load),
and under Emscripten pthreads a worker's `fflush` on proxied stdout is a
synchronous cross-thread operation. This was trimmed (see
`scummvm-core`'s `4ddbbfa52fb` commit): the per-iteration lines were
removed entirely, and `fflush(stdout)` was dropped from every diagnostic
call site except the one immediately before the crashing `FT_Load_Glyph()`
call in `cacheGlyph()` -- the only line that must survive as the last
output before a trap.

Rebuilt with the same `DEBUG=1` flags as before
(`bash build/build-core.sh` then `DEBUG=1 bash
build/build-retroarch-core-debug.sh` then `bash build/package-core.sh`).
Artifact sizes came out essentially identical to the first attempt --
`.wasm` 378,733,353 bytes (~379MB, vs. 379MB before) and packaged `.data`
122,011,804 bytes (~117MB, vs. 117MB before). This confirms the
expectation stated when this follow-up was planned: the logging trim was
never expected to change binary size (log call sites are a rounding error
against a whole-program `-O0`/`SAFE_HEAP=2` rebuild) -- the goal was
runtime responsiveness, not size, and size was correctly unaffected either
way.

**Result: still impractical, but the failure mode changed in a
meaningful, informative way.** Four attempts were made this round (across
two browser tabs, with the user directly watching one window while an
automated tab drove the other):
1. Reached "Decompress Game Core" ~76% then appeared to stall -- but the
   tab was separately confirmed to have been closed by user accident, not
   hung. Invalidated as a data point.
2. Reached full core boot successfully -- all 58 expected RetroArch/
   ScummVM startup log lines captured live via `read_console_messages`,
   ending at `[INFO] [Display] Found display driver: "gl".` (GL context
   found, GLSL shaders linked, OpenAL audio driver started). Positive
   control confirmed: real-time main-thread log capture was working for
   this exact run, immediately before the point where output stopped.
   Then appeared to stall for several minutes with no new console output
   and intermittent screenshot failures -- but the user identified this as
   Brave's background-tab throttling (the tab was backgrounded relative to
   the browser window), not a genuine hang. Also invalidated as a
   build-hang data point, though it re-confirms background-tab throttling
   as a real, recurring confound in this harness (consistent with this
   project's standing "close unused tabs" testing guidance).
3. Reached the identical 58-line boot point (through
   `[INFO] [Display] Found display driver: "gl".`) with the tab kept in
   the foreground this time, then **genuinely crashed** -- confirmed
   directly by the user watching the tab, not inferred from tooling
   symptoms.
4. Reloaded and repeated: reached the exact same 58-line boot point again,
   then **crashed again at the same point** -- the user predicted this
   correctly before it happened, based on attempt 3.

No `[fonts-oob-debug]` line, no ScummVM game-detection output, and no
`RuntimeError`/`SAFE_HEAP` diagnostic text was ever captured in this
round -- the build never survived past its own startup sequence far enough
to reach game loading, let alone font loading. The positive control
(real-time capture of the 58 boot lines) was confirmed working on the
exact runs that then went silent, so this is a genuine absence of further
output from the page, not a tooling-capture gap -- though it's worth
stating precisely what this does and doesn't rule out: it confirms
`read_console_messages` sees real-time **main-thread** output up to the
crash; it does not by itself confirm or deny whether pthread-worker
`printf` output would have been visible too, because the crash happened
before ScummVM's own worker-thread code (game detection, then font
loading) ever ran. That half of the C1 hypothesis (from the "Correction"
section above) remains untested by this round as well.

**Comparing the two rounds' failure signatures directly:** the original
attempt's tab became unresponsive to script injection shortly after/around
the decompress step and was eventually lost after 40+ seconds of repeated
injection timeouts -- consistent with an overloaded-but-technically-alive
renderer rather than a hard crash. This round's build, with the logging
trimmed, reliably got measurably further -- through full RetroArch core
initialization, GL context creation, shader linking, and audio driver
startup -- before crashing outright (a real tab crash, user-confirmed
twice in a row at the identical point). So the logging trim did produce a
real, reproducible improvement in how far the build gets before failing;
it did not fix the underlying impracticality, and the new failure mode
(a hard crash immediately after audio/display driver init, before any
game-specific code runs) is if anything a worse place to fail for this
investigation's purposes, since it's further from the decompress step but
still well before the actual diagnostic target (font loading happens after
game detection, which never got a chance to start). The most plausible
explanation, not confirmed: `SAFE_HEAP=2` instruments every single memory
access with bounds/alignment-checking calls, which combined with `-O0`
(no dead-code elimination, no inlining, much larger generated code) most
likely drives real memory/CPU usage high enough, on top of the large heap
growth already visible in this build's own console output (the pasted
manual DevTools log this round showed heap growth to 512MB early in
extraction, before core init even starts), to hit a hard per-tab resource
limit shortly after startup completes -- but this was not directly
diagnosed (no `chrome://crashes` or `about:memory`-equivalent data was
captured for either crash).

**Updated bottom line:** `DEBUG=1`/`SAFE_HEAP=2` remains confirmed
impractical for interactively reaching this specific crash in this test
harness, now across two independent rounds and four more attempts (six
total). The earlier round's "impractical" verdict holds, but for a
refined reason: it is not simply that the tab hangs near the decompress
step (trimming the logging measurably fixed that specific symptom -- the
tab now reliably gets all the way through core boot), it's that the
combination of `-O0` and `SAFE_HEAP=2` on a program this large appears to
exhaust some hard resource limit shortly after boot, before the game/font
code that's actually of interest ever runs. Future attempts should try
the flag-isolation experiment already suggested above (`SAFE_HEAP=1`
alone, or `-O1` without `SAFE_HEAP`, to find out which flag actually
drives the crash) rather than assuming `SAFE_HEAP=2` itself is
categorically unusable -- this round narrowed the failure to "sometime
between audio-driver-init and the game finishing detection," which is a
smaller window than "sometime between page load and the crash" that the
first round left it at.

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

## Follow-up: buried vs GLK font-loading comparison

Resolved. The "Contradiction" section above is settled: `buried`'s success
and GLK's crash are not actually comparable -- they take genuinely
different FreeType code paths, and the difference is real, source-verified,
and load-bearing, not a false lead.

**The render-mode call sites differ:**
- `engines/glk/screen.cpp:132`'s `Screen::loadFont()` calls
  `Graphics::loadTTFFont(f, DisposeAfterUse::YES, (int)size,
  Graphics::kTTFSizeModeCharacter)` -- only 4 explicit arguments. Per
  `graphics/fonts/ttf.h:101`'s declaration, the omitted `renderMode`
  parameter defaults to `kTTFRenderModeLight`.
- `engines/buried/graphics.cpp:116` and `:124`'s
  `GraphicsManager::createArialFont()` explicitly passes
  `_vm->isTrueColor() ? Graphics::kTTFRenderModeLight :
  Graphics::kTTFRenderModeMonochrome`.
- `engines/buried/metaengine.cpp:71`'s `isTrueColor()` returns
  `(_gameDescription->flags & GF_TRUECOLOR) != 0`. This project's own
  `docs/ENGINE-TEST-PLAN.md` (buried row) documents the *actual* ROM used to
  confirm `buried` working: the "US Gold (UK)" `BIT816.EXE` demo (8BPP),
  packaged as the anchor. `engines/buried/detection_tables.h:406-415`'s
  matching detection entry for that exact file
  (`AD_ENTRY1s("BIT816.EXE", "5535fd50e504537ab08066a89df1b6de", 1259040)`)
  has flags `ADGF_DEMO` only -- **no `GF_TRUECOLOR`** (contrast the
  adjacent `BIT2416.EXE` 24BPP demo entry at line 417-426, which does carry
  `GF_TRUECOLOR`). So the confirmed-working `buried` test run had
  `isTrueColor() == false`, meaning its actual, exercised call used
  **`kTTFRenderModeMonochrome`, not `kTTFRenderModeLight`**.

**Tracing both render modes through `ttf.cpp`:** `TTFFont::load()`'s switch
(lines 346-364) maps `kTTFRenderModeLight` -> `_loadFlags =
FT_LOAD_TARGET_LIGHT`, `_renderMode = FT_RENDER_MODE_LIGHT`, and
`kTTFRenderModeMonochrome` -> `_loadFlags = FT_LOAD_TARGET_MONO`,
`_renderMode = FT_RENDER_MODE_MONO`. Neither branch ORs in
`FT_LOAD_FORCE_AUTOHINT` or `FT_LOAD_NO_BITMAP` (the latter is only added
separately for `_fakeItalic`, irrelevant here). So the two paths hand
FreeType genuinely different `FT_RENDER_MODE_*`/`FT_LOAD_TARGET_*` values,
not equivalent ones under different names.

**This is not a coarse guess -- traced into FreeType's actual dispatch
logic** (this project's vendored copy at
`scummvm-core/backends/platform/libretro/deps/libretro-deps/freetype`).
`src/base/ftobjs.c`'s `FT_Load_Glyph()` (~line 604) decides whether to
route a glyph through the autofit module with this exact condition (comment
and code, lines 652-690):

```c
// - Otherwise, auto-hint for LIGHT hinting mode or if there isn't
//   any hinting bytecode in the TrueType/OpenType font.
...
FT_Render_Mode mode = FT_LOAD_TARGET_MODE(load_flags);
if ( ( mode == FT_RENDER_MODE_LIGHT && !FT_DRIVER_HINTS_LIGHTLY(driver) ) ||
     ( FT_IS_SFNT(face) && ttface->num_locations &&
       ttface->max_profile.maxSizeOfInstructions == 0 &&
       ttface->font_program_size == 0 &&
       ttface->cvt_program_size == 0 ) )
    autohint = TRUE;
```

`FT_DRIVER_HINTS_LIGHTLY(driver)` checks a static per-driver module flag
(`FT_MODULE_DRIVER_HINTS_LIGHTLY`, `include/freetype/ftmodapi.h:120`).
Grepping the whole vendored FreeType tree shows only
`src/cff/cffdrivr.c:950` (the CFF/PostScript driver) sets this flag --
`src/truetype/ttdriver.c`'s `tt_driver_class` (the driver used for all
three `.ttf`/`glyf`-format fonts in play here) does **not** set it, and
this is independent of `TT_CONFIG_OPTION_SUBPIXEL_HINTING` or the
`interpreter_version` (checked: `ftoption.h` has subpixel hinting set to
"minimal"/v40, and `ttobjs.c:1295` does default `interpreter_version` to
`TT_INTERPRETER_VERSION_40` accordingly, but that only affects grid-fitting
quality *if* the native hinter runs at all -- it never sets the
`HINTS_LIGHTLY` module flag, which is hardcoded per-driver at
compile time).

**The consequence, for a TrueType driver, is unconditional:**
`FT_DRIVER_HINTS_LIGHTLY(driver)` is always false, so the first half of the
OR (`mode == FT_RENDER_MODE_LIGHT && !HINTS_LIGHTLY`) is true for *every*
`FT_RENDER_MODE_LIGHT` glyph load on a TrueType font, regardless of whether
that font has its own hinting bytecode. **`autohint` is forced `TRUE`
unconditionally for LIGHT mode on this driver** -- FreeType's autofit
module always runs. For `FT_RENDER_MODE_MONO` (and `_NORMAL`), only the
second OR clause applies, which checks whether the font's own
`fpgm`/`prep`/`cvt` tables are empty.

**Checked whether the fonts themselves differ enough to matter (they
don't):** extracted `LiberationSans-Regular.ttf` (buried),
`GoMono-Regular.ttf` and `NotoSerif-Regular.ttf` (GLK) from
`scummvm-core/dists/engine-data/fonts.dat` and inspected their table
directories with `fonttools`/`ttx`. All three are `glyf`-format TrueType
fonts and all three carry non-empty `fpgm`, `prep`, `cvt `, and `gasp`
tables (i.e. all three have real native hinting bytecode) -- so the fonts
are not the discriminator; GLK's fonts are not somehow "unhinted" compared
to buried's. This rules out the font-file angle: the only thing that
actually differs is the render-mode argument each call site passes.

**Conclusion:** this is a real, load-bearing discriminating variable, not
a wash.
- GLK's `Screen::loadFont()` always requests `kTTFRenderModeLight` ->
  `FT_RENDER_MODE_LIGHT`, which -- per FreeType's own dispatch logic on this
  driver -- **always** routes through the autofit module, the exact
  subsystem where the confirmed crash traps.
- `buried`'s actual confirmed-working test run used the non-truecolor demo
  entry, so its exercised call used `kTTFRenderModeMonochrome` ->
  `FT_RENDER_MODE_MONO`, which -- given `LiberationSans-Regular.ttf` has
  non-empty hinting tables -- takes the native TrueType bytecode-hinter
  path and **never invokes autofit at all**.

`buried`'s success therefore provides **no evidence whatsoever** about
whether the LIGHT-mode/autofit path works, because its tested configuration
never exercised that path. The original plan's "probably not
`ttf.cpp`'s direct TTF path, since `buried` uses it successfully" assumption
is now understood to have been comparing two code paths that only share a
source file, not actual runtime behavior. This does not by itself explain
*why* autofit traps -- that remains open -- but it fully resolves the
contradiction: there is no evidence anywhere in this project's own test
history that FreeType's autofit dispatch has ever run successfully in this
WASM build. (Note: `gui/ThemeEngine.cpp`'s `loadScalableFont`, discussed in
the "Open question" section above, *does* use `kTTFRenderModeLight` too and
*has* run successfully across many confirmed-working engines -- that
remains the real, still-unresolved counter-evidence against a
categorically-broken autofit dispatch, not `buried`.)

## BREAKTHROUGH (2026-09-04): deterministic glyph-level repro, captured via automated tooling

A control build (zero extra debug flags -- exactly Task 2's original
recipe, `-O3` + `-g -gsource-map`, no `DEBUG=1`, no `SAFE_HEAP`) was run
against `test-page/griffon.zip` with the printf-based diagnostic logging
from Task 4's fix round still in place. This session initially
misdiagnosed this run twice before getting it right -- both
misdiagnoses and the corrected conclusion are recorded here because the
methodology mistakes are as instructive as the finding itself.

**Misdiagnosis #1**: an automated `read_console_messages` query (narrow
pattern, made well after the run had already produced thousands of lines
of output) found only a late-occurring `RuntimeError: memory access out
of bounds` in `__clock_gettime`/`cpu_features_get_time_usec`/
`runloop_iterate` -- generic RetroArch frame-timing code with no
connection to fonts or FreeType -- and, seeing this in isolation, this
session concluded the *entire* prior FreeType/GLK crash-site
investigation might have been looking at the wrong thing, and that some
pervasive, ROM-independent memory corruption was the real culprit.

**Misdiagnosis #2**: challenged on this, a second automated query for
`"Enlarging memory arrays"` (used to check the leading
`ALLOW_MEMORY_GROWTH=1` + `-pthread` hypothesis) found no matches in the
core module's context, leading to a claim that no heap-growth event
occurred in this run at all.

**Both misdiagnoses stemmed from the same root methodology error**:
`read_console_messages` was queried after the fact with narrow patterns
and default limits, against a run that turned out to have produced
**11,339 lines of console output**. The user was independently watching
this exact run with real DevTools open, saved a complete copy of it
(`desktop/console.log`), and both corrected misdiagnoses were wrong: the
console *did* show heap-growth events (confirming an automated query can
silently miss real evidence buried under enough later output -- the same
class of gap this document's earlier "Correction -- the tooling-gap claim
was wrong" section already describes, recurring in a new form), and,
far more importantly, **the true first anomaly in the complete log was
never queried for at all**, because the automated tool's own narrow,
after-the-fact queries only ever surfaced what was still within its
retention window near the end of an 11k-line run.

**With the complete log in hand, the actual sequence is now fully
resolved and it is exactly what Tasks 3-4 already found -- deterministically
so, this time**, at **line 620 of 11,339**, immediately after the
ScummVM splash and audio/GL driver init:

```
[fonts-oob-debug] TTFFont::load: face=0xb32ec98 num_glyphs=712 mapping=0 loadFlags=0x10000
[fonts-oob-debug] cacheGlyph: chr=0  slot=1 face=0xb32ec98 loadFlags=0x10000 (numGlyphs=712)
[fonts-oob-debug] cacheGlyph: FT_Load_Glyph returned OK for chr=0 slot=1
[fonts-oob-debug] cacheGlyph: chr=13 slot=2 face=0xb32ec98 loadFlags=0x10000 (numGlyphs=712)
[fonts-oob-debug] cacheGlyph: FT_Load_Glyph returned OK for chr=13 slot=2
[fonts-oob-debug] cacheGlyph: chr=32 slot=3 face=0xb32ec98 loadFlags=0x10000 (numGlyphs=712)
[fonts-oob-debug] cacheGlyph: FT_Load_Glyph returned OK for chr=32 slot=3
[fonts-oob-debug] cacheGlyph: chr=33 slot=4 face=0xb32ec98 loadFlags=0x10000 (numGlyphs=712)
worker sent an error! ...: Uncaught RuntimeError: function signature mismatch
    at af_loader_load_glyph
    at af_autofitter_load_glyph
    at FT_Load_Glyph
    at Graphics::TTFFont::cacheGlyph(Graphics::TTFFont::Glyph&, unsigned int) const
    at Graphics::TTFFont::load(...)
    at Graphics::loadTTFFont(...)
    at Glk::Screen::loadFont(Glk::FACES, Common::Archive*, double, double, int)
    at Glk::Screen::loadFonts(Common::Archive*)
    at Glk::Screen::loadFonts()
    at Glk::Screen::initialize()
```

This is the single most concrete result this entire investigation has
produced. It confirms, with a clean automated capture (no manual DevTools
paste needed this time -- the `retro_log_cb`-to-`printf` swap plus
`EJS_DEBUG_XX` really do work together, resolving that open question):

- The crash is **exactly** where Task 3/4 said it was:
  `TTFFont::cacheGlyph` -> `FT_Load_Glyph` -> FreeType's autofit dispatch,
  reached via `Glk::Screen`'s real font-loading chain.
- It is **deterministic at the glyph level**: the first three glyphs
  cached against this specific font (`face=0xb32ec98`, `num_glyphs=712`,
  `loadFlags=0x10000` i.e. `FT_LOAD_TARGET_LIGHT`) succeed cleanly --
  character codes 0, 13 (CR), and 32 (space). The trap fires on the
  **fourth glyph cached, character code 33 (`'!'`), slot 4** -- every
  single time, before its "FT_Load_Glyph returned OK" line ever prints.
  This is not timing-dependent or nondeterministic at this level of
  detail; it is a specific glyph in a specific font.
- Everything that happens **after** this crash in the remaining ~10,700
  lines of the log -- continued `[INFO] Setting real canvas size` spam,
  and eventually the `__clock_gettime`/`platform_emscripten_update_canvas_dimensions_cb`
  traps this session mistakenly promoted to a standalone "major finding"
  -- is downstream fallout of the emulation core's pthread already
  having fatally crashed, with the surrounding RetroArch/EmulatorJS
  harness limping along in a partially-torn-down state for a long time
  afterward before something else in it also eventually faults. **These
  are not independent bugs.** This session's original framing (Tasks 1-4,
  the final review) was right the whole time; the "pervasive memory
  corruption unrelated to fonts" theory floated earlier today was a
  direct product of querying an incomplete log tail without checking
  the beginning first, and should be disregarded as a lead.

**On the memory-growth question specifically** (raised, correctly
double-checked, and only partially resolved during this same
back-and-forth): heap-growth events are confirmed to occur on this run,
but per the user's explicit, repeated caution, growth events are **normal,
expected behavior that also occurs on ROMs/engines that never crash** --
their mere presence is not evidence either for or against them being
related to this crash, and this document should not (and now does not)
assert a direction on that either way without dedicated, timestamped
correlation work that has not been done. Treat it as a genuinely open,
untested variable, not a lead to chase on its own.

**What this means for the actual next step toward a fix**: the problem is
now narrow and concrete enough to actually debug directly, rather than
guessed at via build-flag experiments. The next session should:

1. Find out what is special about character 33 / the 4th glyph in this
   font that the first three (0, 13, 32) don't share -- e.g. examine
   `GoMono-Regular.ttf`'s (or whichever font `face=0xb32ec98` is --
   confirm which of the two GLK fonts this face pointer corresponds to)
   own glyph-33 outline/hinting data directly (a font editor or
   `fonttools`/`ttx` dump), looking for anything unusual about that
   specific glyph (a malformed contour, an edge case in its hinting
   program, an unusually large/complex outline) that could trip a bug in
   FreeType's autofit script/style dispatch when this specific WASM
   build processes it.
2. Since the crash is now 100% deterministic and fast to reach (line 620,
   not line 11,339 -- reachable in well under a minute, not many
   minutes), this is now cheap enough to iterate on directly: add
   logging *inside* FreeType's own `af_autofitter_load_glyph`/
   `af_loader_load_glyph` (this project's vendored copy, under
   `scummvm-core/backends/platform/libretro/deps/libretro-deps/freetype`)
   to see exactly which function-pointer-table lookup or dispatch step
   is producing a mismatched-signature call for this specific glyph --
   this is a much smaller, more tractable place to add targeted
   diagnostics than anything tried so far.
3. Re-run the render-mode/font comparison from the "buried vs GLK"
   follow-up above with this new specificity in mind: check whether
   `gui/ThemeEngine.cpp`'s successfully-used `kTTFRenderModeLight` path
   ever actually caches a glyph for character 33 in the fonts it loads --
   if it does and doesn't crash, the bug is specific to something about
   *this* font's glyph 33, not the render mode/autofit path in general;
   if it never touches character 33 at all, that would be a much more
   direct, complete explanation than anything found so far.

## RESOLVED (2026-09-04, follow-up round): exact dispatch point found, with a concrete candidate root cause

This follow-up picked up directly from the BREAKTHROUGH section above. Three
things were done: (1) identify the exact crashing font and glyph via
`fonttools`, (2) add diagnostic `printf` logging inside this project's
vendored FreeType (`scummvm-core/backends/platform/libretro/deps/libretro-deps/freetype`,
a separate nested git checkout -- see "Build/tooling note" below) at the
autofit dispatch points identified by source analysis, rebuild, and
reproduce; (3) cross-check the ThemeEngine counter-evidence from the "Open
question" section above. All three succeeded and converge on a single,
well-supported, concrete finding.

### Task 1: the crashing font is GoMono-Regular.ttf, and glyph 33 is unremarkable except for being non-empty

`engines/glk/screen.cpp`'s `Screen::loadFonts(Common::Archive*)` calls
`loadFont(MONOR, ...)` first (`MONOR` is index 0 of the `FACES` enum in
`engines/glk/fonts.h:30`), and `Screen::loadFont`'s `FILENAMES[8]` array maps
index 0 to `"GoMono-Regular.ttf"`. Extracting it from `fonts.dat` and
inspecting with `fonttools` confirms `maxp.numGlyphs == 712`, an exact match
to the crash log's `num_glyphs=712` -- this is definitively the crashing
font.

Inspecting the `glyf` table for the four glyphs in play:

| chr | glyph name | numContours | instruction bytes | outcome |
|---|---|---|---|---|
| 0 (NUL) | `uni0000` | 0 (empty) | 0 | succeeds |
| 13 (CR) | `uni000D` | 0 (empty) | 0 | succeeds |
| 32 (space) | `space` | 0 (empty) | 0 | succeeds |
| 33 (`!`) | `exclam` | 2 | 76 | **crashes** |

Character 33 is **not** structurally unusual for an `exclam` glyph (a
vertical bar contour plus a dot contour, 10 points total, normal TrueType
hinting bytecode) -- it is simply the **first glyph in this font-load
sequence with any outline at all**. This directly answers Task 1's item 4
in favor of the second framing offered there: this is not "what's special
about glyph 33," it's "what's broken in autofit's real per-glyph analysis
path in general, first triggered here because it's the first non-trivial
glyph." Confirmed empirically below, not just inferred.

### Task 2: exact trap site found by source analysis, then confirmed live by diagnostic logging

Reading `src/autofit/afloader.c`'s `af_loader_load_g()` (the static helper
that does the real per-glyph work, called from `af_loader_load_glyph()`;
`-O3` inlines it into the latter, matching the crash trace's
`af_loader_load_glyph` frame with no separate `af_loader_load_g` frame)
shows an explicit fast path at line 276: `if ( slot->outline.n_points == 0 )
goto Hint_Metrics;` -- this **skips** the block containing the
`writing_system_class->style_hints_apply(...)` indirect call entirely for
any empty-outline glyph. Every glyph before `'!'` in this font-load sequence
(0, 13, 32) has `n_points == 0` and therefore never reaches that call. `'!'`
is the first one that does.

**The likely defect, found by reading the writing-system class definitions
directly:** every `AF_WritingSystem_ApplyHintsFunc` implementation in this
vendored FreeType tree -- `af_latin_hints_apply` (`aflatin.c:3378`),
`af_cjk_hints_apply` (`afcjk.c:2258`), `af_indic_hints_apply`
(`afindic.c:82`, itself delegating to `af_cjk_hints_apply`), and
`af_dummy_hints_apply` (`afdummy.c:41`) -- is declared returning `FT_Error`,
and every one of them is stored into its writing-system class struct via an
explicit cast to `AF_WritingSystem_ApplyHintsFunc`
(`aftypes.h:224-228`), which is typed as returning **`void`**:

```c
typedef void
(*AF_WritingSystem_ApplyHintsFunc)( FT_UInt          glyph_index,
                                    AF_GlyphHints    hints,
                                    FT_Outline*      outline,
                                    AF_StyleMetrics  metrics );
```

e.g. `aflatin.c:3486`: `(AF_WritingSystem_ApplyHintsFunc) af_latin_hints_apply`.
This return-type mismatch (`void` vs. `FT_Error`/`int`) is silently
tolerated by every conventional native ABI (an unused return value in a
register costs nothing) -- it is textbook C undefined behavior via an
incompatible function pointer cast, but upstream FreeType has shipped this
exact pattern for years without issue on any native target. WASM's
`call_indirect` type-checks the full function type (parameter types *and*
return arity/type) of every indirect call against the table entry's actual
compiled type, and does not tolerate it. This is precisely the mechanism a
"function signature mismatch" trap describes, and it is systemic across
*all four* writing systems in this file, not particular to Latin or to this
font.

By contrast, the other two indirect calls on the same dispatch path --
`style_metrics_scale` (`AF_WritingSystem_ScaleMetricsFunc`, returns `void`,
and every real implementation checked -- `af_latin_metrics_scale` --
actually returns `void` too, no mismatch) and `style_hints_init`
(`AF_WritingSystem_InitHintsFunc`, returns `FT_Error`, and
`af_latin_hints_init` actually returns `FT_Error` -- also no mismatch) --
have no such discrepancy. This predicts, before any live test, that
`style_hints_init`/`style_metrics_scale` should keep succeeding right up to
the crash, and only `style_hints_apply` should trap.

**Diagnostic logging added** (`scummvm-core/backends/platform/libretro/deps/libretro-deps/freetype/src/autofit/afloader.c`,
plain `printf`+`fflush(stdout)` per this investigation's established
convention, no `__LIBRETRO__` guard needed -- see "Build/tooling note"
below for why) at three points: right after `af_face_globals_get_metrics`
resolves each glyph's style/writing-system (logging the writing system,
style, and all three function-pointer values), right after
`style_metrics_scale`/`style_hints_init` return (to confirm they didn't
trap), and immediately before/after the `style_hints_apply` call.

**Live confirmation, from the user's own DevTools capture (`~/Desktop/console2.log`,
saved by the user mid-run, independent of the automated tool -- see
"Build/tooling note" below), reproduced against `test-page/griffon.zip` on a
freshly rebuilt core (same recipe as the BREAKTHROUGH section: `-O3` +
`-g -gsource-map`, no `DEBUG=1`):**

```
[fonts-oob-debug] cacheGlyph: chr=32 slot=3 face=0xb298cb0 loadFlags=0x10000 (numGlyphs=712)
[fonts-oob-debug][autofit] load_glyph: gindex=3 writing_system=1 style=44 style_metrics_scale=0x127f style_hints_init=0x1281 style_hints_apply=0x1282
[fonts-oob-debug][autofit] style_metrics_scale: returned (did not trap) for gindex=3
[fonts-oob-debug][autofit] style_hints_init: returned (did not trap) for gindex=3 error=0
[fonts-oob-debug] cacheGlyph: FT_Load_Glyph returned OK for chr=32 slot=3
[fonts-oob-debug] cacheGlyph: chr=33 slot=4 face=0xb298cb0 loadFlags=0x10000 (numGlyphs=712)
[fonts-oob-debug][autofit] load_glyph: gindex=4 writing_system=1 style=44 style_metrics_scale=0x127f style_hints_init=0x1281 style_hints_apply=0x1282
[fonts-oob-debug][autofit] style_metrics_scale: returned (did not trap) for gindex=4
[fonts-oob-debug][autofit] style_hints_init: returned (did not trap) for gindex=4 error=0
[fonts-oob-debug][autofit] style_hints_apply: about to call writing_system=1 style=44 fn=0x1282 glyph_index=4 n_points=10 hints=0x9016d80 outline=0xb29b4cc metrics=0x7fd3828
worker sent an error! ...: Uncaught RuntimeError: function signature mismatch
    at af_loader_load_glyph
    at af_autofitter_load_glyph
    ...
```

This is as precise a confirmation as this investigation is likely to get:
glyph index 3 (space, empty outline) and glyph index 4 (`!`, real outline)
resolve to the **identical** writing system (1 = `AF_WRITING_SYSTEM_LATIN`),
the **identical** style (44), and the **identical three function pointers**
(`0x127f`/`0x1281`/`0x1282`) -- proving the only thing that differs between
the successful and crashing glyph is `n_points` (0 vs. 10), exactly as
predicted by the `n_points == 0` fast path. `style_metrics_scale` and
`style_hints_init` both return normally (no trap) for both glyphs, exactly
as predicted by the return-type analysis above. The trap fires at, and
only at, the `style_hints_apply` call (`fn=0x1282`, i.e. `af_latin_hints_apply`
for this style/writing-system) -- its own "returned (did not trap)" log
line never printed, and the real `RuntimeError` immediately follows. No
other candidate indirect call in this dispatch chain was left unconfirmed.

Also notable: glyphs 0 (NUL) and 13 (CR) resolve to writing_system=2
(`AF_WRITING_SYSTEM_CJK`), style=59 -- i.e. this build's `AF_STYLE_FALLBACK`
is `AF_STYLE_HANI_DFLT` (`afglobal.h:69`'s `#ifdef AF_CONFIG_OPTION_CJK`
branch), confirming `AF_CONFIG_OPTION_CJK` is enabled in this build. This is
incidental -- `af_cjk_hints_apply` has the identical return-type mismatch,
so it would have failed too had NUL/CR had non-empty outlines -- but it
confirms the fallback-style bookkeeping matches source exactly, reinforcing
confidence in the whole reading.

**This is diagnosis, not a fix, per this investigation's standing rule.**
No FreeType source was changed beyond the diagnostic logging itself (still
in place, uncommitted-to-`Exit` behavior unchanged). A real fix would need
to either correct the four writing systems' function-pointer types (or their
casts) to genuinely return `void` and discard the `FT_Error` (upstream
FreeType itself never actually uses `style_hints_apply`'s return value --
`af_loader_load_g` calls it as a bare statement, ignoring any result, so
correcting the types to be honest about this would very likely be a safe,
minimal upstream-style fix) -- not attempted here.

### Task 3: the ThemeEngine cross-check's premise doesn't hold in this build -- it very likely never exercises this path at all

The "Open question" section above treated `gui/ThemeEngine.cpp`'s
`loadScalableFont` (also `kTTFRenderModeLight`, also TrueType/autofit) as
strong counter-evidence against a universal, always-broken autofit dispatch,
reasoning that dozens of confirmed-working engines render their ScummVM GUI
through it without crashing. Checking this directly this round:

- ScummVM's default UI text genuinely contains `!` constantly (e.g.
  `gui/launcher.cpp`: *"ScummVM could not find any engine capable of running
  the selected game!"*; `gui/massadd.cpp`: *"Scan complete!"*; multiple
  entries in `gui/credits.h`) -- so if this path were genuinely exercised
  with real glyphs, it plausibly would hit `!` or some other non-empty
  Latin glyph sooner or later.
- But `ThemeEngine::loadFont()` (`ThemeEngine.cpp:1803-1811`) only calls
  `loadScalableFont()` when a theme supplies a non-empty `scalableFilename`
  for a given font id. This project's WASM build does **not** bundle any
  external theme `.zip` (`scummmodern.zip`/`scummclassic.zip` exist in
  `scummvm-core/gui/themes/` in source, but are absent from
  `build/embed-staging/engine-data/` and from every build script checked --
  `grep` for `scummmodern|scummclassic|theme.dat` across `build/*.sh` and
  the libretro `.mk` files found nothing). Without a bundled theme,
  `ThemeEngine::loadTheme()` falls back to the hardcoded `"builtin"` theme
  (`ThemeEngine.cpp:2109`'s `warning("Could not find theme '%s' falling
  back to builtin"...)`).
- The builtin theme's font declarations are hardcoded in
  `gui/themes/default.inc` and use **only `.bdf` bitmap fonts**
  (`helvb12.bdf`, `clR6x12.bdf`, `fixed5x8.bdf`) for every font id
  (`text_default`, `text_button`, `text_normal`, `tooltip_normal`,
  `console`) -- no `scalableFilename` is ever configured for any of them.

**This means `ThemeEngine::loadScalableFont`'s `kTTFRenderModeLight`/autofit
path is very likely never exercised at all in this WASM build**, regardless
of how many engines are "confirmed working" -- "confirmed working" only
establishes that the game booted and its BDF-rendered GUI displayed, not
that any TTF/autofit code ran. The earlier round's reasoning ("if the
dispatch table were universally corrupted, GUI font loading would be
expected to crash on every engine") rested on an unverified assumption that
this path was actually being exercised in this specific build; it wasn't
checked against the actual bundled/fallback theme before being used as
counter-evidence. This removes that counter-evidence rather than
confirming it, and leaves the return-type-mismatch defect found in Task 2
as a plausible universal defect rather than something GLK/font-specific --
GLK is simply one of the only code paths in this codebase (see the "9
engines" cluster in this doc's Summary) that unconditionally loads its own
TTF fonts via `kTTFRenderModeLight` regardless of any theme's
availability, since it ships and loads its own embedded `fonts.dat`
directly rather than going through `ThemeEngine`'s theme-driven font
selection at all.

**One other `kTTFRenderModeLight` call site was checked and found
non-comparable, for the same reason `buried` was found non-comparable in
the earlier "Follow-up" section**: `engines/asylum/system/text.cpp:70`
(Sanitarium, confirmed working per `docs/ENGINE-TEST-PLAN.md:190`) loads
`"NotoSansSC-Regular.otf"` with `kTTFRenderModeLight`, but this is
specifically the engine's `_chineseFont` (a Simplified-Chinese OpenType
font, likely CFF-flavored rather than glyf/TrueType, which per the
"Follow-up" section's own already-documented `FT_DRIVER_HINTS_LIGHTLY`
logic would take the CFF driver's own native light-hinting path and never
invoke autofit at all) -- and even setting the font-format question aside,
this path is very unlikely to have been exercised by the confirmed English
test run at all (a Chinese-localization-only font, not the game's normal
text rendering). `engines/neverhood/menumodule.cpp`'s `kTTFRenderModeLight`
call is not independent evidence either way -- Neverhood is already one of
the 9 engines in this bug's own cluster. The only other two source files
using `kTTFRenderModeLight` (`engines/vcruise/runtime.cpp`,
`engines/grim/font.cpp`/`engines/stark/services/fontprovider.cpp`) belong to
engines `docs/ENGINE-TEST-PLAN.md` does not list as confirmed working
(`vcruise`: "Could not confidently identify"; `grim`/`stark`: candidate
info only, no confirmed-working test result recorded) -- not usable as
evidence either way without first actually testing them, which was not
attempted this round (flagged as a reasonable next step, not pursued
further here per this task's own "don't overinvest" guidance).

### Build/tooling note: the vendored FreeType tree is a separate, gitignored nested checkout

`scummvm-core/backends/platform/libretro/deps/libretro-deps` is **not**
tracked by `scummvm-core`'s own git (`backends/platform/libretro/.gitignore`
excludes the whole `deps/` folder) -- it is its own separate git checkout of
`https://github.com/libretro/libretro-deps`, fetched/pinned by
`backends/platform/libretro/dependencies.mk` (`DEPS_COMMIT_libretro-deps`)
via `backends/platform/libretro/scripts/configure_submodules.sh`. That
script **runs on every `make` invocation** and does `git reset --hard` on
this checkout if it's dirty, unless `DEBUG_ALLOW_DIRTY_SUBMODULES=1` is set
(a `?=`-defaulted Makefile variable, so exporting it as a shell environment
variable before invoking `emmake make` -- e.g. before running
`build/build-core.sh` -- is sufficient; no script edits needed). **Any
future round editing files under this `deps/` tree must set
`DEBUG_ALLOW_DIRTY_SUBMODULES=1` in the environment before running
`build/build-core.sh`, or the edits will be silently wiped by the very next
build.** This round's diagnostic edits to `afloader.c` were confirmed to
survive a full `build-core.sh` + `build-retroarch-core-debug.sh` +
`package-core.sh` cycle with this variable set. Because this checkout is
its own nested git repo (with its own `git init`/`remote add` from the
configure script, not a real git submodule), it cannot be committed via
`scummvm-core`'s own git at all -- there is nowhere in this project's normal
git history for these diagnostic changes to live long-term; they exist only
in this checked-out working tree and as this document's transcription of
them (full diff: `git diff` inside
`scummvm-core/backends/platform/libretro/deps/libretro-deps` from this
session's checkout). A prior round's task instructions assumed FreeType
changes would go into `scummvm-core`'s own submodule commit history the
same way `ttf.cpp` changes do -- this is not actually possible for this
particular file, since it lives in a doubly-nested, separately-tracked
dependency checkout outside `scummvm-core`'s own repository.

Also confirmed this round: **the automated `read_console_messages` tool did
not capture this run's crash at all**, even queried with a broad `"."`
pattern and `limit=500` immediately after the crash was known (from the
user's own parallel manual capture) to have happened. The MCP-driven tab
stalled at the ScummVM splash/black-screen stage for the entire run (per
its own screenshots) and never produced the GameID-table/game-detection
output the user's real DevTools session shows starting at its own log line
361 onward -- i.e. this was two genuinely different browser
sessions/contexts running the same build, not a capture-window/retention
gap in the same session as earlier rounds hit. The user's own manually
captured DevTools log (saved directly to `~/Desktop/console2.log`, 605
lines) is what actually contains the deterministic sequence quoted above.
This is consistent with this document's "Known limitations" section's
standing note that this crash reliably needs a human with real, manually
opened DevTools to capture reliably -- worth stating plainly again rather
than re-litigating, since this round hit it again independently.

## FIX CONFIRMED (2026-09-04): root cause found, fixed, and verified live

Following directly from the "BREAKTHROUGH" section above, the exact
function-pointer dispatch was traced to source and fixed:

**Root cause, fully confirmed against source (not inferred):**
`scummvm-core/backends/platform/libretro/deps/libretro-deps/freetype`'s
`src/autofit/aftypes.h` declares:
```c
typedef void
(*AF_WritingSystem_ApplyHintsFunc)( FT_UInt glyph_index, AF_GlyphHints hints,
                                     FT_Outline* outline, AF_StyleMetrics metrics );
```
Every implementation assigned to this pointer -- `af_latin_hints_apply`
(`aflatin.c`), `af_cjk_hints_apply` (`afcjk.c`), `af_indic_hints_apply`
(`afindic.c`), `af_dummy_hints_apply` (`afdummy.c`) -- is declared
`static FT_Error` (a real return value) and force-cast to this mismatched
`void`-returning type at assignment (each `AF_DEFINE_WRITING_SYSTEM_CLASS`
block). **Separately and independently**, `af_dummy_hints_apply` was
missing the typedef's 4th parameter (`metrics`) entirely -- a genuine
arity mismatch, not just a return-type one; `af_latin_hints_apply`/
`af_cjk_hints_apply`/`af_indic_hints_apply` all have the correct 4
parameters (verified directly), so only the dummy/`AF_STYLE_NONE_DFLT`
writing system had this second defect.

Both are the kind of mismatch native ABIs (x86/ARM calling conventions)
silently tolerate -- a caller ignoring an actual return value sitting in
a register, or a callee never reading an extra stack/register argument
the caller passed -- which is exactly why this bug has presumably never
been noticed on any of FreeType's countless native deployments. WASM's
`call_indirect` performs strict type-checking (return type AND full
parameter list) on every indirect call and traps immediately with
`function signature mismatch` the instant either mismatch is actually
exercised. `af_dummy_hints_apply` (the dummy/`AF_STYLE_NONE_DFLT` writing
system) is reached for any glyph FreeType's style classifier doesn't map
to a specific script -- which explains the deterministic chr-33 trigger:
characters 0/13/32 are empty-outline placeholders that never reach the
`style_hints_apply` dispatch at all (an early-exit guard for empty
outlines skips it), and `'!'` (33) is simply the first glyph in the load
sequence with a real outline, making it the first time this exact
indirect call fires for this font.

**Fix applied** (`aftypes.h`'s typedef changed to declare `FT_Error`,
matching every real implementation -- the sole call site in `afloader.c`
already discards the result as a bare statement, so this is a pure
type-correctness fix with zero behavioral change on any platform; and
`af_dummy_hints_apply` given its missing `metrics` parameter, marked
unused like `glyph_index` already is, matching the codebase's own
convention) and **confirmed live**: rebuilt clean, reproduced against
`griffon.zip` again -- **zero `RuntimeError`/`signature mismatch`/`memory
access out of bounds` anywhere in a 3301-line captured console log** (this
time genuinely complete, not truncated -- checked directly, not inferred).
The run now proceeds cleanly through font loading and reaches the
already-documented, already-understood, **non-crashing**
"Level9-debugger-diversion" outcome (`ERROR: Unable to locate valid Level
9 game in file: objectdb.dat!`, dropping into ScummVM's own interactive
debugger) instead. That remaining behavior is a separate, benign,
already-explained issue (this specific ROM gets routed to GLK's Level9
sub-interpreter, whose own internal validation then rejects it) -- not a
crash, and not part of what this investigation was chasing.

**Where the fix lives**: this vendored FreeType is not a real git
submodule of `scummvm-core` (gitignored, pinned via a hardcoded commit SHA
in `backends/platform/libretro/dependencies.mk`, re-synced by
`configure_submodules.sh` on every build). Discovered the hard way: an
uncommitted edit, and even a *committed*-but-not-pinned edit, gets
silently wiped on the next build the moment `git rev-parse HEAD` in that
checkout no longer matches `DEPS_COMMIT_libretro-deps` exactly --
`configure_submodules.sh` treats any mismatch as "wrong checkout" and does
`rm -rf` + a fresh shallow clone of the pinned commit, not a soft reset.
One earlier attempt at this exact fix was lost this way (a diagnostic-
logging commit made by an earlier session's implementer, and this
session's first two fix attempts, were all destroyed by this mechanism
before being understood). The durable fix: forked
`libretro/libretro-deps` to `TRusselo/libretro-deps`, committed the fix on
branch `fix/wasm-autofit-signature-mismatch` (commit `b94bd2d`), pushed
it, and updated `dependencies.mk`'s `DEPS_URL_libretro-deps`/
`DEPS_COMMIT_libretro-deps` to point at that fork+commit -- matching this
project's existing convention for the `scummvm-core` submodule itself
(also forked, also pinned to a specific commit on `TRusselo`'s fork).
**Anyone touching this vendored FreeType (or any other `dependencies.mk`
entry) in the future must fork+pin the same way, or their change will
silently vanish on the next build.**

**What remains, for whoever picks this up next**: this fix (a) needs to
be reported/upstreamed to `libretro-deps` (and ideally to FreeType itself,
if they still vendor an old-enough copy with this bug) as a real, general
WASM-portability defect, not just patched locally forever, and (b) should
be cross-checked against the other 8 originally-listed "affected engines"
(`dm`, `tony`, `neverhood`, `bbvs`, `gnap`, `mutationofjb`, `ngi`, and
`glk` proper) to confirm the same fix resolves their crashes too -- this
round only tested against `griffon.zip`'s GLK-misrouted repro. Given the
crash site and mechanism are entirely generic (any glyph landing on
`AF_STYLE_NONE_DFLT`, or exercising the return-type mismatch on any
writing system, regardless of which ScummVM engine triggers font loading),
there is no reason to expect those other 8 engines behave differently,
but this has not been directly re-tested against each one individually.

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

## SECOND BUG (2026-09-04, later): Beavis and Butt-Head still crashed on the fixed core -- a different cause with the same symptom

After the FreeType fix was deployed to the live ROMM container (image and core
MD5 both verified), the user launched *Beavis and Butt-Head in Virtual
Stupidity* (bbvs engine) and got the familiar
`RuntimeError: function signature mismatch` followed by a cascade of
`memory access out of bounds` (user log: `console4.log`). Their read was "same
bug". It is not, and the way that was established is worth recording because it
needed no rebuild and no reproduction.

### Symbolicating a production (name-stripped) wasm without rebuilding it

The production `.wasm` has no name section. Chrome's trace prints module byte
offsets (`…:0x54c015`). A ~150-line parser
(`~/scummvm-wasm-scratch/beavis-crash-analysis/wasmmap.py`) reads the TYPE /
IMPORT / FUNCTION / ELEM / CODE / DATA sections directly, maps each offset to a
function index + wasm signature, and resolves `i32.const` operands to string
literals in the data segments (passive segments; the start function's
`memory.init` calls give their addresses, segment 0 lives at 1024).
`llvm-objdump -d --start-address/--stop-address` from the emsdk then
disassembles one function at a time (disassembling all 186 MB is impractical).

Two gotchas: (1) V8 reports the *call instruction's own offset* for every frame,
not a return address; (2) binaryen's -O3 `reorder-functions` sorts functions by
call count, so function index says nothing about link order, and a re-link with
`--profiling-funcs` produces a *different* ordering -- the symbol map from a
name-preserving re-link only matched the production binary for the most-called
few hundred functions. Body-shape comparison (identical 202-op sequence, 388
bytes) was what confirmed the name.

### What the trace actually is

| frame | function (by strings / shape) |
|---|---|
| 0x2dacd1c | `dynCall_ii` (pthread entry trampoline) |
| 0x5215a91 | libretro-common `thread_wrap` |
| 0x2dd1dcd | `retro_wrap_emulator` with `scummvm_main` inlined (91 KB) |
| 0x1ab37ea | `runGame` |
| 0x578d806 | `BbvsEngine::run` with `playVideo` inlined (`vid/video%03d.avi`) |
| 0x54c015 | **`Video::VideoDecoder::loadFile`** -- the trap |

`loadFile` decodes to exactly `file = new Common::File(); if (file->open(p))
{ if (loadStream(file)) return true; } delete file; return false;`
(sizeof(File) == 40 = vptr + `_handle` + 32-byte `String`; vtable slot 3 is
`loadStream`, slot 12 is `open`). The trap is the `delete file`: a
`call_indirect` through **vtable slot 1, the deleting destructor**. A real
destructor slot always has the `(i32) -> ()` signature the caller expects, so
this is not a cast bug at all -- the vptr had been overwritten, i.e. the object
was already freed. Same message as the FreeType bug, unrelated mechanism.

### Top-down chain (earliest cause first)

1. **No Indeo codec in this port.** The game's AVIs are Indeo 3 (`IV32`,
   `ffprobe`), Full Pipe's intro is Indeo 5 (`IV50`). `image/module.mk` and
   `image/codecs/codec.cpp` gate Indeo 3/4/5 behind `USE_INDEO3`/`USE_INDEO45`,
   and this fork's `backends/platform/libretro/Makefile.common` never defined
   them. Upstream ScummVM's libretro Makefile.common does (lines 177-181 on
   master); our `libretro/scummvm`-based fork lagged. The other four gated-looking
   codecs (truemotion1, xan, cdtoons, jyv1) compile unconditionally here, so
   Indeo was the only real hole.
2. `createBitmapCodec()` returns null → `AVIVideoTrack::isValid()` false →
   `handleStreamHeader()` returns false → `loadStream()` hits
   "Failed to parse AVI header" → **`close()` deletes the stream it was handed**,
   returns false.
3. `VideoDecoder::loadFile()` deletes the same `Common::File` again → double
   free → allocator metadata over the vptr → trap. Natively this is a silent (or
   glibc-aborting) double free; upstream master still has it.
4. **Why nobody could see any of this:** release builds also passed
   `-DDISABLE_TEXT_CONSOLE`, which turns every `warning()` into an inline no-op.
   The strings "Indeo 3 codec is not compiled", "Failed to parse AVI header",
   "Unable to open video" do not exist in the production binary at all
   (verified by byte search). The user's blank console lines were not a capture
   problem; the messages were compiled out.

### Fix (scummvm-core `9fdbf469a29`, fork branch `debug/fonts-oob-crash-diagnostics`)

- `Makefile.common`: `USE_INDEO3 = 1` / `USE_INDEO45 = 1` + the `-D` defines,
  mirroring upstream.
- `Makefile.common`: drop `DISABLE_TEXT_CONSOLE` from release builds (keep
  `RELEASE_BUILD`), so `warning()` reaches the libretro log and the browser
  console.
- `video/avi_decoder.cpp`: on both post-assignment failure paths in
  `loadStream()`, set `_fileStream = nullptr` before `close()`, so the caller
  keeps ownership on failure, consistent with the early-return paths and with
  `loadFile()`. Direct `loadStream()` callers that relied on deletion-on-failure
  now leak on that error path instead of double-freeing; that is the safer of
  the two behaviours and matches how every other decoder behaves.

Because the `DISABLE_TEXT_CONSOLE` change alters every translation unit that
calls `warning()`, the Unraid rebuild wiped all core objects (kept the
libretro-deps ones) rather than relying on make's header-only dependency
tracking. Clean core compile is ~12 min on that box.

### Bearing on the other "mem OOB" ROMs

- Full Pipe (ngi): `intro.avi` is Indeo 5 → almost certainly the same chain;
  covered by `USE_INDEO45`.
- U.F.O.s / Gnap: `HOFFMAN.AVI` is Cinepak + PCM, both supported → a different
  failure; now diagnosable because warnings are back.
- Mutation of J.B.: no video files at all → different bug.

### On the question "did the first fix do anything, is the PR needed"

Yes and yes. The FreeType fix removed griffon's deterministic glyph-33 crash
(clean 3301-line run). Upstream `libretro/libretro-deps` master (2026-08-01)
still ships FreeType 2.7.0 with both signature bugs, while FreeType upstream
has had the corrected `FT_Error` / 4-parameter signatures for years, so a PR
there is a straight backport. `-sEMULATE_FUNCTION_POINTER_CASTS` (still
supported by emcc 6.0.9 via binaryen `--fpcast-emu`) would have masked the
FreeType class of bug but not this one, and is not worth its cost.

### VERIFIED LIVE (2026-09-04, evening)

Container force-updated to image `4f661a2b9a3f` (core MD5
`f9c2e1a8ff8b7b0f99f06257bd3763b1`, confirmed inside the running container).
Beavis and Butt-Head now plays its intro and runs into the game past the main
menu. The user's full 1490-line `console5.log` has zero RuntimeErrors, zero
ScummVM `WARNING:` lines, and no ENOTDIR extraction crash; the only entries are
ROMM frontend 404/500s, two normal Emscripten heap-growth notices, and the usual
benign fullscreen-permission rejection at the end.
