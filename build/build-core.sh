#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Scope the build to the SCUMM engine only.
echo "scumm" > scummvm-core/backends/platform/libretro/lite_engines.list

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
EMCC_CFLAGS="-pthread -sSHARED_MEMORY" emmake make platform=emscripten LITE=1 \
  -j"$(nproc)"

echo "Build artifact:"
ls -la scummvm_libretro_emscripten.bc
