#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Scope the build's engine set. Defaults to SCUMM only; override by pointing
# ENGINES_LIST_FILE at a file with one ScummVM engine name per line (see
# build/engine-lists/).
ENGINES_LIST_FILE="${ENGINES_LIST_FILE:-}"
if [ -n "$ENGINES_LIST_FILE" ]; then
  cp "$ENGINES_LIST_FILE" scummvm-core/backends/platform/libretro/lite_engines.list
else
  echo "scumm" > scummvm-core/backends/platform/libretro/lite_engines.list
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
# USE_HIGHRES defaults to 1 (Makefile.common), initializing the reported
# canvas at a fixed 1280x720 (16:9) overlay resolution meant for high-res
# engines (GRIM, Director) -- SCUMM never needs more than 320x200-ish, and
# leaving this enabled produces a 16:9-shaped video output with the actual
# game rendered into a smaller centered region, padded with permanent black
# bars baked into the framebuffer itself (not a CSS/display letterbox --
# the in-game mouse cursor's own coordinate space is clamped to the smaller
# real content area, confirming ScummVM draws into a sub-rect of a larger
# canvas rather than the frontend adding bars around a correctly-sized one).
# Several other constrained libretro platforms (miyoo, miyoomini, armv7)
# already disable this for the same class of reason.
EMCC_CFLAGS="-pthread -sSHARED_MEMORY" emmake make platform=emscripten LITE=1 USE_HIGHRES=0 \
  -j"$(nproc)"

echo "Build artifact:"
ls -la scummvm_libretro_emscripten.bc
