#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Scope the build's engine set. Defaults to all-engines.list (103 engines,
# every ScummVM engine except the 13 requiring OpenGL -- see
# build/engine-lists/README.md); override by pointing ENGINES_LIST_FILE at
# a different file with one ScummVM engine name per line.
ENGINES_LIST_FILE="${ENGINES_LIST_FILE:-build/engine-lists/all-engines.list}"
cp "$ENGINES_LIST_FILE" scummvm-core/backends/platform/libretro/lite_engines.list

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
# here deliberately. It's a compile-time engine-scoping gate as much as a
# canvas-size setting: any engine whose own configure.engine declares a
# "highres" dependency (48 of the 103 in all-engines.list, including
# Broken Sword 1/2, Little Big Adventure, Director, and SCUMM's own `he`
# subengine) is silently excluded from the build when USE_HIGHRES=0. The
# cost of leaving it at 1 is real but cosmetic: lowres-native engines like
# SCUMM render into a smaller centered region of a fixed 1280x720 overlay,
# with black bars baked into the framebuffer itself (not a CSS/display
# letterbox -- confirmed the in-game mouse cursor's own coordinate space
# still clamps correctly to the real content area, so input/gameplay is
# unaffected). See docs/GOTCHAS.md's "USE_HIGHRES" section for the full
# tradeoff and the two-binary alternative that eliminates the pillarboxing
# at the cost of a second core to build/ship/maintain.
EMCC_CFLAGS="-pthread -sSHARED_MEMORY" emmake make platform=emscripten LITE=1 \
  -j"$(nproc)"

echo "Build artifact:"
ls -la scummvm_libretro_emscripten.bc
