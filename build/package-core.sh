#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p test-page/ejs/data/cores

# Naming follows EmulatorJS's own convention (see
# retroarch/emulatorjs/build-emulatorjs.sh's `out_name` logic): "-thread" is
# appended when the core is built with pthread support (HAVE_THREADS=1,
# PTHREAD_POOL_SIZE!=0, as this build is -- see build-retroarch-core.sh),
# and "-legacy" normally means a separate GLES2 build (HAVE_OPENGLES3=0).
# This build uses HAVE_OPENGLES3=1 and is not itself a legacy build --
# but EmulatorJS's own downloadGameCore() (src/emulator.js) defaults
# EVERY core to the "-legacy" filename on a user's first visit whenever
# the core's reports/<core>.json doesn't set `options.defaultWebGL2`
# (confirmed: dosbox_pure's own shipped report doesn't set it either),
# regardless of the browser's actual WebGL2 support. Every core in the
# official EmulatorJS distribution ships both filenames for exactly this
# reason. SCUMM's rendering is simple 2D sprite blitting with no
# GLES3-only calls, so shipping this same GLES3 build under both names
# is expected to work identically under either context -- confirmed by
# testing (see docs/GOTCHAS.md). If a future SCUMM feature needs a real
# GLES3-only call, a genuine HAVE_OPENGLES3=0 second build would be
# needed instead of this duplicate.
rm -f test-page/ejs/data/cores/scummvm-wasm.data \
      test-page/ejs/data/cores/scummvm-legacy-wasm.data

7z a -y test-page/ejs/data/cores/scummvm-thread-wasm.data \
  retroarch/scummvm_libretro.wasm retroarch/scummvm_libretro.js
cp test-page/ejs/data/cores/scummvm-thread-wasm.data \
   test-page/ejs/data/cores/scummvm-thread-legacy-wasm.data

ls -la test-page/ejs/data/cores/scummvm*
