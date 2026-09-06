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
# fonts/ (added upstream 2026-09) holds the raw .otf/.ttf SOURCES that
# fonts-cjk.dat and fonts-imgui.dat are generated from -- 65MB of build input
# ScummVM never reads at runtime (engine_data.mk ships only the .dat files).
# Embedding it added ~65MB to the shipped wasm for nothing.
STAGE_DIR="build/embed-staging/engine-data"
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"
rsync -a \
  --exclude='patches/' \
  --exclude='fonts/' \
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
#
# INITIAL_HEAP is wired straight to -sINITIAL_MEMORY by Makefile.emulatorjs
# (line 166), so it has to cover static data + stack, not just the heap. 128MB
# sufficed until the 2026-09 rebase onto current upstream pulled in six months
# of new engines (macs2, harvester, colony, phoenixvr, alcachofa, ...) and
# wasm-ld began rejecting the link with "initial memory too small, 186199984
# bytes needed". ALLOW_MEMORY_GROWTH=1 is on, so this is only the startup
# floor, not a cap; MAXIMUM_MEMORY stays at 4GB.
EMCC_CFLAGS="--pre-js ../build/midi-stub-pre.js --embed-file ../build/embed-staging/engine-data@/engine-data" emmake make -f Makefile.emulatorjs \
  LD=em++ \
  HAVE_7ZIP=1 HAVE_CHD=1 \
  HAVE_THREADS=1 PTHREAD_POOL_SIZE=4 \
  ASYNC=1 HAVE_OPENGLES3=1 \
  STACK_SIZE=16777216 INITIAL_HEAP=268435456 \
  TARGET=scummvm_libretro.js \
  -j"$(nproc)"

echo "Build artifacts:"
ls -la scummvm_libretro.js scummvm_libretro.wasm
