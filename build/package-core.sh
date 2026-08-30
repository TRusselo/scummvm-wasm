#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p test-page/ejs/data/cores

7z a -y test-page/ejs/data/cores/scummvm-wasm.data \
  retroarch/scummvm_libretro.wasm retroarch/scummvm_libretro.js

# EmulatorJS's loader requests the "-legacy" variant by default (confirmed
# during the spike). Until Task 5/6 investigates GLES3 vs legacy properly,
# ship both variants identically so the loader's default request succeeds.
cp test-page/ejs/data/cores/scummvm-wasm.data \
   test-page/ejs/data/cores/scummvm-legacy-wasm.data

ls -la test-page/ejs/data/cores/scummvm*
