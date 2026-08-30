#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p test-page/ejs/data/cores

# Naming follows EmulatorJS's own convention (see
# retroarch/emulatorjs/build-emulatorjs.sh's `out_name` logic): "-thread" is
# appended when the core is built with pthread support (HAVE_THREADS=1,
# PTHREAD_POOL_SIZE!=0, as this build is -- see build-retroarch-core.sh),
# and "-legacy" is appended only when GLES3 is disabled (HAVE_OPENGLES3=0).
# This build uses HAVE_OPENGLES3=1, so it is a GLES3, threaded build --
# "scummvm-thread-wasm.data" -- not a "legacy" one. Shipping a GLES2/legacy
# copy under the "-legacy" name would misrepresent this build's actual
# capabilities to the loader.
rm -f test-page/ejs/data/cores/scummvm-wasm.data \
      test-page/ejs/data/cores/scummvm-legacy-wasm.data

7z a -y test-page/ejs/data/cores/scummvm-thread-wasm.data \
  retroarch/scummvm_libretro.wasm retroarch/scummvm_libretro.js

ls -la test-page/ejs/data/cores/scummvm*
