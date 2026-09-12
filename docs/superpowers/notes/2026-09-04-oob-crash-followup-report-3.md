# Follow-up report 3: fonts OOB-crash investigation -- exact dispatch point found

## Status: DONE

## Commit hashes

- Parent repo (`scummvm-wasm`, branch `debug/fonts-oob-crash`):
  `be33c75` -- "Document the confirmed root cause of the fonts OOB crash"
  (updates `docs/superpowers/notes/2026-09-02-oob-crash-findings.md` only).
- `scummvm-core` submodule: **no new commit**. `ttf.cpp` was not touched
  further this round; the only source change was diagnostic logging in the
  vendored FreeType tree, which turns out to live outside `scummvm-core`'s
  own git history entirely (see "Important tooling finding" below). The
  submodule's working tree currently shows only build-artifact diffs
  (`lite_engines.list`, `config.mk`, `scummvm_libretro_emscripten.bc`,
  `config.h.engines`, `config.mk.engines`) from running the build -- not
  committed, as these are byproducts, not source changes.
- FreeType diagnostic change, committed **locally** (not part of
  `scummvm-core`'s history -- see below) inside
  `scummvm-core/backends/platform/libretro/deps/libretro-deps`, branch
  `debug/fonts-oob-crash-diagnostics`: commit `ca51a5f` -- "LIBRETRO/FREETYPE:
  add diagnostic logging for the fonts OOB-crash investigation". This
  checkout's prior state was `7e6e34f` (the pinned `DEPS_COMMIT_libretro-deps`),
  detached HEAD.

## Important tooling finding (read before running another build in this tree)

`scummvm-core/backends/platform/libretro/deps/libretro-deps` is **not** a
real git submodule of `scummvm-core` -- it's gitignored
(`backends/platform/libretro/.gitignore` excludes `deps/`) and is instead a
separate nested git checkout of `https://github.com/libretro/libretro-deps`,
fetched/pinned by `backends/platform/libretro/dependencies.mk` +
`backends/platform/libretro/scripts/configure_submodules.sh`. This means:

1. **The FreeType source I edited this round cannot be committed into
   `scummvm-core`'s own git history at all.** I committed it locally inside
   the nested checkout instead (see hash above) purely for this-round
   continuity; there was no way to fully satisfy the task's literal
   instruction to put FreeType changes on `scummvm-core`'s
   `debug/fonts-oob-crash-diagnostics` branch, because that file isn't part
   of `scummvm-core`'s repository.
2. **`configure_submodules.sh` runs on every `make` invocation** and will
   `rm -rf` + fresh-clone this checkout if `git rev-parse HEAD` doesn't
   match the pinned `DEPS_COMMIT_libretro-deps` -- which it no longer does,
   since I committed on top of it. **The next `build/build-core.sh` run in
   this worktree will silently wipe this diagnostic commit and the checkout
   back to pristine `7e6e34f`.** This is likely fine/expected (nobody wants
   permanent debug printfs in a pinned dependency), but flagging it
   explicitly so nobody is surprised. A full patch of the diagnostic diff
   is also saved at
   `/tmp/claude-1000/.../scratchpad/backups/afloader-diagnostic.patch` and
   reproduced in full in the notes doc, so it can be reapplied if a future
   round wants to pick this up again.
3. Separately (and this is what let the build succeed at all this round):
   the same script will `git reset --hard` this checkout if it's dirty,
   *unless* the Makefile variable `DEBUG_ALLOW_DIRTY_SUBMODULES` is `1`. It
   is declared `?= 0` in `Makefile.common`, so exporting
   `DEBUG_ALLOW_DIRTY_SUBMODULES=1` as a shell environment variable before
   invoking `build/build-core.sh` (no script edits needed) is what let the
   diagnostic edit survive the build. Documented in the notes doc's new
   "Build/tooling note" section for future rounds.

## Task 1: which font, and what's special about glyph 33

**Font: `GoMono-Regular.ttf`.** `engines/glk/screen.cpp`'s
`Screen::loadFonts(Common::Archive*)` calls `loadFont(MONOR, ...)` first
(`MONOR == 0` per the `FACES` enum in `engines/glk/fonts.h:30`), and
`FILENAMES[0]` in `Screen::loadFont` is `"GoMono-Regular.ttf"`. Confirmed by
extracting it from `fonts.dat` and checking with `fonttools`:
`maxp.numGlyphs == 712`, matching the crash log's `num_glyphs=712` exactly.

**Glyph 33 (`exclam`) is not structurally unusual.** It's a normal
two-contour glyph (a bar + a dot, 10 points, 76 bytes of ordinary TrueType
hinting bytecode). What *is* true, and load-bearing: characters 0 (NUL), 13
(CR), and 32 (space) are all **empty-outline glyphs** (`numberOfContours ==
0`) in this font, and `!` is the first character in the load sequence with
any outline at all. This directly confirms the second framing offered in
the task: it's not "what's special about `!`," it's "what's broken in
autofit's real per-glyph analysis path in general" -- `!` just happens to
be first in line to exercise it.

## Task 2: the exact failing dispatch point

**Found by source reading, then confirmed live.** `src/autofit/afloader.c`'s
`af_loader_load_g()` has `if ( slot->outline.n_points == 0 ) goto
Hint_Metrics;`, which skips the `writing_system_class->style_hints_apply(...)`
indirect call entirely for empty-outline glyphs. Every glyph before `!`
skips it; `!` is the first to reach it.

**The likely defect:** every `AF_WritingSystem_ApplyHintsFunc`
implementation in this vendored FreeType (`af_latin_hints_apply`,
`af_cjk_hints_apply`, `af_indic_hints_apply`, `af_dummy_hints_apply`) is
declared returning `FT_Error`, but every one is stored into its
writing-system class struct via an explicit cast to
`AF_WritingSystem_ApplyHintsFunc`, which is typed as returning **`void`**
(`aftypes.h:224-228`). This return-type mismatch is silently tolerated by
native ABIs (textbook undefined behavior via incompatible function-pointer
cast, but harmless in practice on every conventional target) -- WASM's
`call_indirect` type-checks the full function type including return arity,
and does not tolerate it. This is exactly what a "function signature
mismatch" trap describes, and it's systemic across all four writing
systems, not particular to Latin or to this font. The sibling calls on the
same path (`style_metrics_scale`, `style_hints_init`) have no such
mismatch in any implementation checked.

**Confirmed live** with diagnostic `printf` logging added at all three
dispatch points in `afloader.c` (full diff in the notes doc and in the
backup patch mentioned above), rebuilt with the normal `-O3` recipe (not
the impractical `DEBUG=1`/`SAFE_HEAP=2` variant), and reproduced against
`test-page/griffon.zip`. The user's own DevTools capture
(`~/Desktop/console2.log`) shows glyph index 3 (space, `n_points=0`) and
glyph index 4 (`!`, `n_points=10`) resolving to the **identical** writing
system (1 = Latin), **identical** style (44), and **identical three
function-pointer values** -- `style_metrics_scale` and `style_hints_init`
both return normally for both glyphs, and the trap fires exactly at, and
only at, the `style_hints_apply` call for glyph 4, with no "returned (did
not trap)" line ever printed for it. This is as precise a confirmation as
this investigation is likely to get without disassembling the WASM binary
directly.

This is diagnosis only, per the standing rule -- no fix applied. A real fix
would plausibly be correcting the four writing systems' `style_hints_apply`
implementations (or their stored function-pointer type) to genuinely return
`void`, since `af_loader_load_g` calls `style_hints_apply` as a bare
statement and never uses its return value anyway -- not attempted here.

## Task 3: the ThemeEngine cross-check

**The earlier round's counter-evidence doesn't hold up.** ScummVM's GUI
text does contain `!` constantly (error dialogs, "Scan complete!", credits),
but `ThemeEngine::loadFont()` only calls `loadScalableFont()`
(the `kTTFRenderModeLight` path) when a theme supplies a non-empty
`scalableFilename`. This WASM build does not bundle any external theme
`.zip` (`scummmodern.zip`/`scummclassic.zip` exist in source but are absent
from `build/embed-staging/engine-data/` and from every build script
checked), so `ThemeEngine` falls back to the hardcoded `"builtin"` theme,
whose font declarations (`gui/themes/default.inc`) use **only `.bdf` bitmap
fonts** -- no scalable font is ever configured. So
`ThemeEngine::loadScalableFont`'s autofit path is very likely **never
exercised at all** in this build, regardless of how many engines are
"confirmed working" -- that status only proves the BDF-rendered GUI
displayed, not that any TTF/autofit code ran. This removes the earlier
round's counter-evidence rather than confirming it.

One other `kTTFRenderModeLight` call site (`engines/asylum/system/text.cpp`,
Sanitarium, confirmed working) was checked and found non-comparable for the
same reason `buried` was found non-comparable in an earlier round: it's
specifically the engine's Chinese-localization font
(`NotoSansSC-Regular.otf`, likely CFF-flavored and thus routed through the
CFF driver's own native hinter rather than autofit per this doc's own
already-established `FT_DRIVER_HINTS_LIGHTLY` logic), and near-certainly
never exercised by the confirmed English test run anyway. The remaining
`kTTFRenderModeLight` call sites belong to engines not confirmed working
(`vcruise`, `grim`, `stark`) or already inside this bug's own 9-engine
cluster (`neverhood`) -- not usable as evidence either way without actually
testing them, flagged as a reasonable future step, not pursued further per
the task's own "don't overinvest" guidance.

## Full detail

All of the above, with exact line numbers, full log excerpts, and the
reasoning trail (including the parts that didn't pan out, e.g. an initial
concern about whether the trap could instead be in `style_hints_init`, ruled
out by its own return-type match), is in
`docs/superpowers/notes/2026-09-02-oob-crash-findings.md`'s new "RESOLVED
(2026-09-04, follow-up round)" section, committed at `be33c75`.
