#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source toolchain/emsdk/emsdk_env.sh

cp -f scummvm-core/backends/platform/libretro/scummvm_libretro_emscripten.bc \
      retroarch/libretro_emscripten.a

cd retroarch
emmake make -f Makefile.emulatorjs \
  LD=em++ \
  HAVE_7ZIP=1 HAVE_CHD=1 \
  HAVE_THREADS=1 PTHREAD_POOL_SIZE=4 \
  ASYNC=1 HAVE_OPENGLES3=1 \
  STACK_SIZE=4194304 INITIAL_HEAP=134217728 \
  TARGET=scummvm_libretro.js \
  -j"$(nproc)"

echo "Build artifacts:"
ls -la scummvm_libretro.js scummvm_libretro.wasm
