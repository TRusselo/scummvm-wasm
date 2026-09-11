#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Scope the build's engine set. Defaults to all-engines.list -- every ScummVM
# engine except those requiring real OpenGL, which live in gl-core.list (see
# build/engine-lists/README.md). Override by pointing ENGINES_LIST_FILE at a
# different file with one ScummVM engine name per line.
ENGINES_LIST_FILE="${ENGINES_LIST_FILE:-build/engine-lists/all-engines.list}"

LIBRETRO_DIR="scummvm-core/backends/platform/libretro"
LITE_LIST="${LIBRETRO_DIR}/lite_engines.list"

# Changing the engine list must invalidate everything derived from it.
#
# make rebuilds a target when a declared prerequisite is newer. The generated
# engine configuration is not a declared prerequisite of the three artifacts
# that embed it, so a changed list leaves them untouched: make finds every
# object up to date, relinks, and produces a freshly timestamped core that
# still contains the previous engine set. Nothing fails, which is what makes
# it dangerous -- the only symptom is an engine that should be present being
# absent (or vice versa) at runtime, which reads like a ROM-packaging problem.
#
#   libdetect.a      the detection tables
#   libdeps.a        the dependency archive
#   base/plugins.o   the plugin registry; deleting it also forces the
#                    containing base/libbase.a to be rebuilt, so that
#                    archive does not need removing separately
#
# Only invalidate when the list actually changed, so ordinary incremental
# builds stay fast.
if cmp -s "$ENGINES_LIST_FILE" "$LITE_LIST"; then
  echo "Engine list unchanged ($(grep -cve '^[[:space:]]*$' "$LITE_LIST") engines); incremental build."
else
  echo "Engine list changed -- invalidating engine-derived artifacts."
  cp "$ENGINES_LIST_FILE" "$LITE_LIST"
  rm -fv "${LIBRETRO_DIR}/libdetect.a" \
         "${LIBRETRO_DIR}/libdeps.a" \
         "${LIBRETRO_DIR}/base/plugins.o"
fi

source toolchain/emsdk/emsdk_env.sh

cd scummvm-core/backends/platform/libretro
# HAVE_THREADS=1 on the RetroArch link side (build-retroarch-core.sh) requires
# every object file wasm-ld combines to share the same 'atomics'/'bulk-memory'
# target features (wasm-ld: "--shared-memory is disallowed by ... because it
# was not compiled with 'atomics' or 'bulk-memory' features"). This core is
# built with USE_LIBCO=0 (real pthreads), so it must be compiled with
# -pthread too, matching Makefile.emulatorjs's own HAVE_THREADS=1 CFLAGS.
#
# These flags are passed via the EMCC_CFLAGS environment variable, NOT as
# CFLAGS=/CXXFLAGS= make command-line variable overrides. GNU Make command-line
# variable assignments override ALL in-makefile assignments to that variable,
# including this Makefile's own '+=' accumulator lines -- which would silently
# discard the '-std=c++11' this Makefile's emscripten platform block adds via
# 'CXXFLAGS += -std=c++11', along with any other warning-suppression flags it
# appends, and compile the whole tree at emcc's default C++ standard instead.
# EMCC_CFLAGS is read directly by emcc.py and appended to every invocation's
# argument list unconditionally (confirmed in
# toolchain/emsdk/upstream/emscripten/emcc.py), so it adds these flags on top
# of whatever CFLAGS/CXXFLAGS the Makefile assembles on its own, rather than
# replacing them.
# USE_HIGHRES defaults to 1 (Makefile.common) and is left at that default
# here deliberately. It's a compile-time engine-scoping gate: any engine
# whose own configure.engine declares a "highres" dependency (48 of the
# engines in all-engines.list when last counted, including Broken Sword 1/2, Little Big
# Adventure, Director, and SCUMM's own `he` subengine) is silently
# excluded from the build when USE_HIGHRES=0. No pillarboxing cost from
# leaving it at 1, confirmed by live testing -- RES_W_OVERLAY/RES_H_OVERLAY
# only seed the pre-game-load launcher-screen state; retro_set_size()
# reports each game's real resolution once it loads, regardless of this
# flag. See docs/GOTCHAS.md's "USE_HIGHRES" section for the full story.
EMCC_CFLAGS="-pthread -sSHARED_MEMORY" emmake make platform=emscripten LITE=1 \
  -j"$(nproc)"

echo "Build artifact:"
ls -la scummvm_libretro_emscripten.bc

# Independent check that the core actually contains the engines that were
# asked for. This catches the stale-artifact trap above no matter what caused
# it, including a stale tree or a hand-run make that skipped this script.
# Printed last so it cannot scroll away; non-fatal, because a future upstream
# change to how ENABLE_ entries are generated should not break the build.
ENGINES_CONFIG="../../../config.mk.engines"
if [ -f "$ENGINES_CONFIG" ]; then
  requested="$(grep -ve '^[[:space:]]*$' "../../../../${ENGINES_LIST_FILE}" | tr 'A-Z' 'a-z' | sort -u)"
  enabled="$(grep '^ENABLE_' "$ENGINES_CONFIG" | sed 's/^ENABLE_//; s/[ =].*//' | tr 'A-Z' 'a-z' | sort -u)"
  missing="$(comm -23 <(echo "$requested") <(echo "$enabled") | tr '\n' ' ')"
  extra="$(comm -13 <(echo "$requested") <(echo "$enabled") | tr '\n' ' ')"
  if [ -z "$missing" ] && [ -z "$extra" ]; then
    echo "Engine set verified: $(echo "$requested" | wc -l) engines, matches ${ENGINES_LIST_FILE}."
  else
    echo "########################################################################"
    echo "WARNING: built engine set does not match ${ENGINES_LIST_FILE}"
    [ -n "$missing" ] && echo "  requested but NOT built: $missing"
    [ -n "$extra" ]   && echo "  built but NOT requested: $extra"
    echo "  This is the stale-artifact trap. See docs/GOTCHAS.md."
    echo "########################################################################"
  fi
fi

# Check the lists and the docs against what ScummVM upstream actually declares.
# Engine flags and build-by-default values change under us on every rebase, and
# a claim written down once is trusted for weeks -- four were wrong at once on
# 2026-09-10. Informational: never fails the build (pass --strict by hand for
# that).
if [ -x "../../../../build/check-engines.py" ]; then
  ../../../../build/check-engines.py || true
fi
