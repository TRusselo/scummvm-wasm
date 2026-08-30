#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ ! -d toolchain/emsdk ]; then
  git clone https://github.com/emscripten-core/emsdk.git toolchain/emsdk
fi
cd toolchain/emsdk
./emsdk install latest
./emsdk activate latest
