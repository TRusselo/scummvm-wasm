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
emmake make platform=emscripten LITE=1 \
  CFLAGS="-pthread -s SHARED_MEMORY" CXXFLAGS="-pthread -s SHARED_MEMORY" \
  -j"$(nproc)"

echo "Build artifact:"
ls -la scummvm_libretro_emscripten.bc
