# Adding Another ScummVM Engine

This project started out shipping only ScummVM's SCUMM engine
(LucasArts adventure games), but the build has since been widened to
include every other ScummVM engine that doesn't require OpenGL --
`build/engine-lists/all-engines.list` currently lists 103 (SCUMM plus
102 more), and a systematic testing sweep confirming each one with a
real game is underway (see [ENGINE-TEST-PLAN.md](ENGINE-TEST-PLAN.md)
and the README's status table for current results). So for any engine
already in `all-engines.list`, the build-side work described below is
already done -- what's actually still per-engine work is packaging a
real game for it and confirming it boots, which is what the testing
sweep is doing.

This doc is still useful for two other cases: building a *smaller*
core scoped to one or a few engines instead of the full 103-engine
build (e.g. for a lighter release, or isolating an engine for
debugging), or adding an engine that needs the separate OpenGL-enabled
core (`build/engine-lists/gl-core.list`, 11 engines, not built by
default -- see the README). Either way, this covers what's actually
SCUMM-specific in this repo (very little) vs. generic (almost
everything), and what to expect to hit.

Read [GOTCHAS.md](GOTCHAS.md) first regardless of which engine you're
adding -- everything in it (the WebMIDI exclusion, the threading/stack
flags, the packaging conventions, the build-caching traps) applies to
*any* engine built through this same pipeline, not just SCUMM. None of it
is SCUMM-specific.

## What's actually SCUMM-specific in this repo

Surprisingly little. The entire engine-scoping mechanism is one file,
copied into place by `build/build-core.sh`:

```bash
ENGINES_LIST_FILE="${ENGINES_LIST_FILE:-build/engine-lists/all-engines.list}"
cp "$ENGINES_LIST_FILE" scummvm-core/backends/platform/libretro/lite_engines.list
```

`lite_engines.list` is ScummVM's libretro-port mechanism for building a
subset of engines instead of everything (see
`scummvm-core/backends/platform/libretro/Makefile`'s `LITE=1` handling).
One engine name per line, using ScummVM's own internal engine ID (the
same IDs used in `scummvm-core/engines/*/`, e.g. `scumm`, `sci`, `agi`,
`wintermute`). The default, `all-engines.list`, already lists 103 engines
-- so unless you're deliberately scoping down, there's nothing to add
here for an engine that's already in it.

To build a *smaller* core instead (recommended if you want independent
testing/release cycles for one engine, since the full 103-engine `.bc` is
one large monolithic build), point `ENGINES_LIST_FILE` at a different
file with just the engine(s) you want, one per line, e.g.:

```
scumm
sci
```

and either export `ENGINES_LIST_FILE` before running `build-core.sh`, or
copy the whole pipeline (`build-core.sh` plus matching copies of
`build-retroarch-core.sh` and `package-core.sh`) so the smaller core's
output filenames don't collide with the full build's in `retroarch/` and
`test-page/ejs/data/cores/`.

Nothing else in `build/`, `retroarch/`, or `test-page/` (besides the game
files themselves) references SCUMM by name. `test-page/index.html`'s
`EJS_core = "scummvm"` is the *core's* name (arbitrary, chosen by this
project), not an engine name -- it stays whatever you pick for your
core's `.data` filename, unrelated to which ScummVM engine(s) are built
into it.

## What to expect when you actually try it

1. **The WebMIDI exclusion is engine-agnostic and already applies.**
   `scummvm-core/backends/module.mk` excludes `midi/webmidi.o` for *all*
   Emscripten builds regardless of engine, and `base/plugins.cpp`'s
   `LINK_PLUGIN(WEBMIDI)` is commented out globally, not per-engine. You
   don't need to redo this work for a new engine -- it's already handled
   at the backend level, not the engine level.

2. **A new engine may have its own equivalent bug.** The WebMIDI failure
   pattern (an `EM_JS`/`EM_ASYNC_JS` block written for ScummVM's own
   standalone-Emscripten shell, referencing globals/exports this
   RetroArch-based build doesn't provide) is a `backends/` issue, not a
   SCUMM issue, so it's already fixed for every engine. But an engine's
   own code (`engines/<name>/`) could plausibly do something similar if
   it has Emscripten-specific branches of its own -- grep the new
   engine's source for `EM_JS`, `EM_ASYNC_JS`, and `#ifdef EMSCRIPTEN`
   before assuming a clean build means a clean *run*. The WebMIDI bug
   built and linked successfully; it only failed at runtime, and only
   inside the browser console, not in any build-time log. Follow the
   "read the console directly, fix errors in the order they appear"
   methodology from GOTCHAS.md's debugging-technique section if you hit
   something similar.

3. **File-format auto-detection will differ.** SCUMM auto-detects from
   `.LFL`/`.000`/`MONSTER.SOU` files sitting flat in one directory (see
   the README's "Adding a game" section). Other engines have their own
   detection conventions (e.g. SCI expects `RESOURCE.MAP`/`RESOURCE.00N`;
   AGI expects `LOGDIR`/`OBJECT`/`WORDS.TOK` and `VOL.N` files). The
   zip-flat packaging convention (zip the contents of the game's data
   folder, no parent directory, so EmulatorJS's basename-only extraction
   doesn't break ScummVM's directory-based detection) should still apply
   to any engine, since it's a property of how EmulatorJS's generic
   zip-extraction works, not of SCUMM specifically -- but verify a new
   engine's detector doesn't expect a *nested* directory structure it
   won't find after flat extraction.

4. **Threading/stack/heap flags may need re-tuning.** `STACK_SIZE`,
   `INITIAL_HEAP`, and `ASYNC=1`'s Asyncify instrumentation were tuned
   against SCUMM's actual call depth and the CD/talkie games' file sizes.
   A different engine's call patterns or a larger game's data size could
   hit the same class of failure (a native stack overflow, or running out
   of initial heap) at different thresholds. If you see a crash, check
   GOTCHAS.md's stack-overflow section for how to get Emscripten to
   report the *actual* limits involved (`-sASSERTIONS=1 -sSAFE_HEAP=2
   -sSTACK_OVERFLOW_CHECK=2`, temporarily) rather than guessing at a
   larger number.

5. **The `-thread`/`-legacy` EmulatorJS packaging convention is unrelated
   to engine choice** -- it's a property of the `HAVE_THREADS`/
   `HAVE_OPENGLES3` flags you build with, which you can carry over
   unchanged for a new engine's core unless you deliberately want a
   non-threaded build.

## Testing a new engine's games

Follow the same loop used to validate all six SCUMM games this project
ships:

1. Zip a game's data directory flat (see README's "Adding a game").
2. Point `EJS_gameUrl` at it in `test-page/index.html`.
3. Serve via `test-page/serve-coop-coep.py`, load the page, click into
   the canvas once (audio-autoplay + pointer-lock gate).

(The 34-engine testing sweep tracked in
[ENGINE-TEST-PLAN.md](ENGINE-TEST-PLAN.md) instead deploys each
candidate ROM to a hosted ROMM/EmulatorJS instance and uses its Play
button -- functionally the same verification, just against a real
multi-platform frontend instead of this repo's local single-game test
harness. Either approach works; the local harness above is the
lower-setup option if you're just testing one new engine in isolation.)
4. **Read the browser console directly and unfiltered** rather than
   guessing from symptoms alone (see GOTCHAS.md's debugging-technique
   notes) -- both for a clean boot confirmation and, if something's
   wrong, to see errors in the order they actually occurred. Bugs in this
   pipeline have repeatedly cascaded (an early, easy-to-miss error
   corrupting state that then crashes something unrelated-looking much
   later) -- fix top-down in log order, not bottom-up from the most
   visible symptom.

## Further reading

`docs/superpowers/` holds the detailed, session-by-session investigation
history behind how the SCUMM path was originally debugged -- in
particular
`docs/superpowers/notes/2026-08-29-autolaunch-diagnosis.md`, which
narrates the full WebMIDI/stack-overflow investigation end to end,
including the false starts and retracted conclusions. It's a much longer
read than GOTCHAS.md's condensed version, but useful if you want to see
the actual reasoning process (what was tried, what red herring looked
plausible and why, how each experiment narrowed things down) rather than
just the final answer -- that process is the part most likely to
transfer to debugging a *different* engine's Emscripten-specific issues.
