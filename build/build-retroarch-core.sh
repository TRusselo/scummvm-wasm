#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source toolchain/emsdk/emsdk_env.sh

# Stage a filtered copy of ScummVM's own engine-data directory so it can
# be embedded directly into the compiled core (see
# docs/superpowers/specs/2026-09-02-wasm-engine-data-embed-design.md).
# This eliminates the need for individual ROMs to carry their own copy
# of fonts.dat/toon.dat/nancy.dat/etc. Excludes files that are dev
# tooling or belong to engines this build doesn't compile (grim/monkey4
# patches are for the separate, not-yet-built GL-core).
STAGE_DIR="build/embed-staging/engine-data"
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"
rsync -a \
  --exclude='patches/' \
  --exclude='testbed-audiocd-files/' \
  --exclude='README' \
  --exclude='engine_data.mk' \
  --exclude='engine_data_core.mk' \
  --exclude='engine_data_big.mk' \
  --exclude='create-playground3d-data.sh' \
  --exclude='create-testbed-data.sh' \
  scummvm-core/dists/engine-data/ "$STAGE_DIR/"

echo "Staged engine-data for embedding:"
du -sh "$STAGE_DIR"

cp -f scummvm-core/backends/platform/libretro/scummvm_libretro_emscripten.bc \
      retroarch/libretro_emscripten.a

cd retroarch
# --pre-js supplies a stub `midiOutputMap` global: ScummVM's WebMIDI plugin
# is excluded from this build entirely (see scummvm-core/backends/module.mk
# and scummvm-core/base/plugins.cpp), so nothing reads this anymore, but the
# stub is kept as harmless defense-in-depth against any future reference to
# the bare global. STACK_SIZE=16777216 (16MB, vs Emscripten's 4MB default)
# was a real, necessary fix for a genuine stack overflow found while
# diagnosing this -- see docs/superpowers/notes/2026-08-29-autolaunch-diagnosis.md.
# -sASYNCIFY_STACK_SIZE overrides Makefile.emulatorjs's own 8192 (emcc's stock
# default is 4096). That buffer has to hold the entire call stack and locals
# whenever Asyncify unwinds. ScummVM engines have deep C++ stacks, and at -O3
# a single engine translation unit inlines into frames tens of kilobytes wide,
# so 8 KB is not enough. Because this build links without -sASSERTIONS, an
# overflow is not diagnosed: it silently writes past the buffer and surfaces
# later as "memory access out of bounds" on the emulator worker. That is what
# saving in The Griffon Legend hit -- its save routine writes ~316,000
# formatted values, by far the deepest and longest save path in the library.
# 128 KB costs nothing meaningful against a 128 MB initial heap.
# emcc applies EMCC_CFLAGS after the Makefile's own LDFLAGS, and the last
# -s FLAG=value wins, so this overrides without patching the RetroArch tree.
EMCC_CFLAGS="--pre-js ../build/midi-stub-pre.js --embed-file ../build/embed-staging/engine-data@/engine-data -sASYNCIFY_STACK_SIZE=131072" emmake make -f Makefile.emulatorjs \
  LD=em++ \
  HAVE_7ZIP=1 HAVE_CHD=1 \
  HAVE_THREADS=1 PTHREAD_POOL_SIZE=4 \
  ASYNC=1 HAVE_OPENGLES3=1 \
  STACK_SIZE=16777216 INITIAL_HEAP=134217728 \
  TARGET=scummvm_libretro.js \
  -j"$(nproc)"

echo "Build artifacts:"
ls -la scummvm_libretro.js scummvm_libretro.wasm
