# OOB-crash investigation follow-up: report (2026-09-03/04)

This is the report for the two follow-up tasks dispatched against the
`debug/fonts-oob-crash` branch's ongoing investigation into the
`Graphics::TTFFont::cacheGlyph()` -> `FT_Load_Glyph()` "function signature
mismatch" WASM trap. Full detail for both tasks is in
`docs/superpowers/notes/2026-09-02-oob-crash-findings.md`, appended in
place (new sections, nothing rewritten or deleted) -- this report
summarizes what was done and found without duplicating that detail.

## Task A: buried vs GLK font-loading path comparison

**Question:** the original investigation plan assumed the crash couldn't
be in `graphics/fonts/ttf.cpp`'s direct TTF-loading path because `buried`
(a confirmed-working engine) uses that exact path successfully. The
confirmed crash IS in that path. Never reconciled.

**Finding: resolved. The paths are genuinely different, not a wash.**

- `engines/glk/screen.cpp:132`'s `Screen::loadFont()` calls
  `Graphics::loadTTFFont(...)` with only 4 explicit arguments, defaulting
  `renderMode` to `kTTFRenderModeLight` (`graphics/fonts/ttf.h:101`).
- `engines/buried/graphics.cpp:116,124`'s `createArialFont()` explicitly
  branches on `_vm->isTrueColor()`. The actual ROM used to confirm
  `buried` working (`docs/ENGINE-TEST-PLAN.md`'s "US Gold (UK)" `BIT816.EXE`
  8BPP demo) matches a detection entry
  (`engines/buried/detection_tables.h:406-415`) with **no** `GF_TRUECOLOR`
  flag, so that confirmed-working run actually took the
  `kTTFRenderModeMonochrome` branch, not `kTTFRenderModeLight`.
- Traced both render modes all the way into FreeType's own dispatch logic
  in this project's vendored copy
  (`scummvm-core/backends/platform/libretro/deps/libretro-deps/freetype`).
  `src/base/ftobjs.c`'s `FT_Load_Glyph()` forces `autohint = TRUE`
  unconditionally for `FT_RENDER_MODE_LIGHT` on any driver that doesn't
  set the `FT_MODULE_DRIVER_HINTS_LIGHTLY` module flag
  (`include/freetype/ftmodapi.h:120`) -- and grepping the whole vendored
  tree shows only the CFF driver (`src/cff/cffdrivr.c:950`) sets that
  flag. The TrueType driver (`src/truetype/ttdriver.c`, used by all fonts
  in play) never does, independent of `TT_CONFIG_OPTION_SUBPIXEL_HINTING`
  or `interpreter_version`.
- So: `FT_RENDER_MODE_LIGHT` (GLK's path) **always** engages FreeType's
  autofit module on this driver -- the exact subsystem where the crash
  traps. `FT_RENDER_MODE_MONO` (buried's actual tested path) only engages
  autofit if the font lacks native hinting bytecode; extracted
  `LiberationSans-Regular.ttf`, `GoMono-Regular.ttf`, and
  `NotoSerif-Regular.ttf` from `scummvm-core/dists/engine-data/fonts.dat`
  and confirmed via `fonttools`/`ttx` that all three have non-empty
  `fpgm`/`prep`/`cvt `/`gasp` tables -- so buried's font isn't somehow
  "unhinted" compared to GLK's; the font files are not the discriminator.
- **Conclusion:** `buried`'s success provides no evidence that the
  LIGHT-mode/autofit path (which GLK's crash actually goes through) works.
  This is a real, source-verified, load-bearing discriminating variable,
  not a coincidence or a naming mismatch. It does not by itself explain
  *why* autofit traps (that remains open), but it fully resolves the
  original contradiction.

Written up in full, with all source citations, under the new
"## Follow-up: buried vs GLK font-loading comparison" section of the
notes doc (and a short update to the original "Contradiction" section
pointing at it).

## Task B: retry `DEBUG=1`/`SAFE_HEAP=2` with lighter instrumentation

**Step 1 -- trim the logging.** Removed the two 256-iteration loops'
per-character `printf`+`fflush(stdout)` calls in `TTFFont::load()`
entirely (up to ~512 calls per font load, the leading suspect for the
first attempt's tab-unresponsive hang under Emscripten pthreads' proxied
stdout). Kept the remaining diagnostic `printf`s (`TTFFont::load()`'s
pre-loop line, `cacheGlyph()`'s two lines, `assureCached()`'s line) but
dropped `fflush(stdout)` from all of them except the one immediately
before the crashing `FT_Load_Glyph()` call in `cacheGlyph()` -- reasoning
inline in the code comments: every other line is either cheap on its own
(fires once per load, not per iteration) or only useful as after-the-fact
confirmation a glyph did *not* crash, so it never needs to survive as the
"last line before a trap." Committed to `scummvm-core` as `4ddbbfa52fb`
on the `debug/fonts-oob-crash-diagnostics` branch.

**Step 2 -- rebuild.** `bash build/build-core.sh` (incremental, only
recompiled `ttf.cpp`) then `DEBUG=1 bash
build/build-retroarch-core-debug.sh` then `bash build/package-core.sh`.
Artifact sizes came out essentially unchanged from the first attempt:
`.wasm` 378,733,353 bytes (~379MB, vs. 379MB before), packaged `.data`
122,011,804 bytes (~117MB, vs. 117MB before) -- exactly as expected, since
trimming a handful of log call sites was never going to move the needle
against a whole-program `-O0`/`SAFE_HEAP=2` rebuild's size; the goal was
runtime responsiveness, not size.

**Steps 3-4 -- test.** Served via `test-page/serve-coop-coep.py` (port
8934), driven via `mcp__claude-in-chrome`, with the user directly watching
their own Brave window in parallel. Four attempts across two tabs:

| # | Outcome | Notes |
|---|---|---|
| 1 | Reached ~76% decompress, then appeared stalled | Invalidated: tab was closed by user accident, not hung |
| 2 | Reached full core boot (58 real console lines, ending at GL display driver found), then appeared stalled for several minutes | Invalidated: confirmed by user as Brave's background-tab throttling, not a hang |
| 3 | Reached the same 58-line boot point, foregrounded this time | **Genuinely crashed** (user-confirmed, watching directly) |
| 4 | Reloaded, reached the same 58-line boot point again | **Crashed again at the same point** (user predicted it correctly) |

Positive control confirmed multiple times: `read_console_messages`
captured real-time main-thread RetroArch/EmulatorJS boot output (58 lines,
matching what the user's own manual DevTools paste showed independently)
right up to the point each run went silent -- so the absence of any
`[fonts-oob-debug]` line, ScummVM detection log, or `RuntimeError`/
`SAFE_HEAP` text is a real absence for these runs, not a broken console
reader. It does **not**, however, confirm or deny whether pthread-worker
`printf` output is visible to this tool -- the crash happened before
ScummVM's own worker-thread code (game detection, then font loading) ever
started, so that half of the notes doc's open "C1 hypothesis" question
remains untested by this round too.

**Step 5 -- verdict, folded into the notes doc's "Reusable tooling"
section (new "Follow-up (2026-09-03, Task B)" subsection, original text
left in place above it, not deleted).** Trimming the logging produced a
real, measurable improvement -- the build now reliably reaches full
RetroArch core initialization (GL context, shader linking, audio driver
start) before failing, versus the original attempt's earlier
unresponsive-then-lost tab. But the underlying practicality problem is
not fixed: two independent, user-confirmed hard crashes occurred at the
identical point (immediately after boot, before any game-specific code
runs), still well short of the actual diagnostic target (font loading
happens after game detection, which never got a chance to start in any of
the six attempts across both rounds). Most plausible unconfirmed
explanation: `SAFE_HEAP=2`'s per-memory-access instrumentation combined
with `-O0`'s lack of optimization drives real memory/CPU usage past some
hard per-tab limit shortly after startup completes. Recommended next step
(not attempted this round): isolate `SAFE_HEAP=1` alone or `-O1` without
`SAFE_HEAP` to find out which flag actually drives the crash, now that
the failure window is narrowed to "sometime between audio-driver-init and
game-detection completing" rather than "sometime between page load and
the crash."

## Constraints honored

- No fix attempted for the actual ScummVM/FreeType bug -- diagnosis only.
- `griffon.zip` and all other ROM files untouched.
- No pushes to any remote. `scummvm-core` commit (`4ddbbfa52fb`) is on
  `debug/fonts-oob-crash-diagnostics` in its own checkout; parent-repo
  commits are on `debug/fonts-oob-crash`.
- No merges performed.
- No subagents dispatched.

## Commits

- Parent repo (`debug/fonts-oob-crash`):
  - `990041c` -- Task A findings (buried-vs-GLK contradiction resolution)
  - (this report + Task B notes-doc update, committed after this file is written)
- Submodule (`scummvm-core`, `debug/fonts-oob-crash-diagnostics`):
  - `4ddbbfa52fb` -- trim fonts-oob-debug per-iteration logging
