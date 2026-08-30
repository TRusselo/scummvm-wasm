#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Scope the build to the SCUMM engine only.
echo "scumm" > scummvm-core/backends/platform/libretro/lite_engines.list

source toolchain/emsdk/emsdk_env.sh

cd scummvm-core/backends/platform/libretro
emmake make platform=emscripten LITE=1 -j"$(nproc)"

echo "Build artifact:"
ls -la scummvm_libretro_emscripten.bc
