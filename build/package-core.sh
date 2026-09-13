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

# core.json travels inside the .data and is how EmulatorJS learns a core's
# own defaults -- src/emulator.js reads it at decompression time and sets
# this.defaultCoreOpts, this.enableMouseLock, this.extensions and the rest.
# EmulatorJS's own build writes it straight from the core's cores.json stanza
# (build.sh: `echo ${row} | base64 --decode > ./core.json`), so this file is
# both the runtime defaults and the draft of our eventual cores.json entry --
# keep the two identical. Modelled on dosbox_pure, the closest analogue
# (threads + mouse + keyboard).
#
#   useKeyboard    -> "Direct Keyboard Input" defaults to Enabled, which
#                     parser-driven engines (agi, sci, hugo, glk) need and
#                     which no core option can set; it is an EmulatorJS
#                     setting, and this is the only per-core way to default it.
#   supportsMouse  -> "Lock Mouse" defaults to Enabled (ROMM also sets this
#                     per-deployment today; this makes it travel with the core).
#   requireThreads -> the core is built USE_LIBCO=0 on real pthreads; there is
#                     no non-threaded build to fall back to.
#   extensions     -> matches the core's own valid_extensions
#                     (libretro-core.cpp: info->valid_extensions = "scummvm"),
#                     the .scummvm hook-file mechanism in docs/GOTCHAS.md.
#                     Anything without one still falls back to fileNames[0].
mkdir -p build/pkg-staging
cat > build/pkg-staging/core.json <<'EOF_CORE'
{
  "name": "scummvm",
  "extensions": ["scummvm"],
  "options": {
    "requireThreads": true,
    "supportsMouse": true,
    "useKeyboard": true,
    "defaultWebGL2": true
  },
  "license": "COPYING",
  "repo": "https://github.com/libretro/scummvm"
}
EOF_CORE

7z a -y test-page/ejs/data/cores/scummvm-thread-wasm.data \
  retroarch/scummvm_libretro.wasm retroarch/scummvm_libretro.js
# Added from inside the staging dir so it lands at the archive ROOT: emulator.js
# matches it with `k === "core.json"`, not by suffix, so a stored path of
# "build/pkg-staging/core.json" would be ignored silently.
( cd build/pkg-staging && 7z a -y ../../test-page/ejs/data/cores/scummvm-thread-wasm.data core.json )
cp test-page/ejs/data/cores/scummvm-thread-wasm.data \
   test-page/ejs/data/cores/scummvm-thread-legacy-wasm.data


# Core report JSON. EmulatorJS (src/emulator.js, downloadGameCore) fetches
# cores/reports/<core>.json and reads exactly two things from it:
#   - buildStart: the key for its IndexedDB core cache. Without it EmulatorJS
#     logs "Could not fetch core report JSON! Core caching will be disabled!"
#     and re-downloads the ~88 MB core on every launch. Stamping the real
#     build time here means every new build invalidates the cache by itself,
#     so a stale core can never be served after a rebuild.
#   - options.defaultWebGL2: whether a first-time visitor is routed to the
#     regular or the "-legacy" core filename. This core is built with
#     HAVE_OPENGLES3 (WebGL2), so default to the regular name.
mkdir -p test-page/ejs/data/cores/reports
BUILD_STAMP="$(date -u +%Y-%m-%dT%H:%M:%S+00:00)"
cat > test-page/ejs/data/cores/reports/scummvm.json <<EOF_JSON
{ "core": "scummvm", "buildStart": "${BUILD_STAMP}", "buildEnd": "${BUILD_STAMP}", "options": { "defaultWebGL2": true } }
EOF_JSON
ls -la test-page/ejs/data/cores/scummvm* test-page/ejs/data/cores/reports/scummvm.json
