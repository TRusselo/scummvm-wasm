#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source toolchain/emsdk/emsdk_env.sh

# DEBUG VARIANT -- see build/build-retroarch-core.sh for the production
# build this is copied from. This script adds debug-info generation
# (-g -gsource-map) and is used only to produce a diagnostic core for
# symbolicating crash stack traces (see
# .superpowers/sdd/2026-09-02-oob-crash-investigation/). Never wire this
# into the production build path.

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
#
# -g -gsource-map: emit DWARF debug info and a source map so the browser
# devtools / stack traces can symbolicate back to real C++ file/line
# instead of raw wasm-function[N]:0xADDR entries. This is intentionally
# NOT part of the production build (build-retroarch-core.sh) -- it makes
# the .wasm significantly larger and is only useful for diagnosing this
# specific crash.
# DEBUG=1: pass through to Makefile.emulatorjs's own existing debug mode
# (lines ~299-301) -- -O1 CFLAGS plus -g -gsource-map -s SAFE_HEAP=2
# -s STACK_OVERFLOW_CHECK=2 -s ASSERTIONS=1 in LDFLAGS. This is a Makefile
# variable checked with `ifeq ($(DEBUG), 1)`, so it must be passed as a
# make argument (like HAVE_THREADS=1 below), not just exported into the
# environment, to be certain it takes effect regardless of how emmake/make
# is invoked. See docs/GOTCHAS.md:114-124 for the prior bug this exact
# flag combination diagnosed (a 4MB-stack overflow presenting as a vague
# "memory access out of bounds"); untested until 2026-09-03 against this
# investigation's "function signature mismatch" crash.
#
# Confirmed 2026-09-03 (see docs/superpowers/notes/2026-09-02-oob-crash-findings.md's
# "Reusable tooling" > Task B follow-up): the full DEBUG=1 bundle (SAFE_HEAP=2 +
# STACK_OVERFLOW_CHECK=2 + ASSERTIONS=1 + -O0, all-or-nothing) reliably boots all
# the way through RetroArch core init (audio/GL) and then hard-crashes the tab
# (SIGILL) before ScummVM's own game detection ever runs -- too heavy to reach
# the actual bug under investigation. DEBUG=1 bundles all 4 flags as one
# ifeq($(DEBUG),1) block in the vendored Makefile.emulatorjs, so it can't be used
# to isolate which one is responsible without either editing that vendored file
# (avoided here) or overriding it externally.
#
# OPT_LEVEL / SAFE_HEAP_LEVEL / STACK_OVERFLOW_CHECK_LEVEL / ASSERTIONS_LEVEL below
# give independent control over each flag without touching Makefile.emulatorjs and
# without setting DEBUG=1 at all. This relies on the same mechanism already used
# above for --pre-js/--embed-file/-g/-gsource-map: Emscripten's em++ driver reads
# the EMCC_CFLAGS environment variable and appends its contents to the argument
# list of EVERY em++ invocation it makes (both compiling, per this Makefile's
# `$(CC) $(CFLAGS) ... -c` rule, and linking, per its `$(LD) ... $(LDFLAGS)` rule)
# regardless of what Makefile.emulatorjs's own CFLAGS/LDFLAGS variables already
# contain -- these EMCC_CFLAGS-supplied flags land after the Makefile's own (which
# unconditionally add "-O3" in the non-DEBUG branch: line ~305), and both emcc's
# optimization level and any "-s NAME=VALUE" setting are "last occurrence in the
# argument list wins", so appending here cleanly overrides the Makefile's default
# without needing DEBUG=1 or an edit to the vendored file.
#
# Defaults (empty/0) reproduce this script's pre-existing behavior exactly
# (Makefile's own -O3, no extra checks) -- only set when isolating a specific
# flag's cost. See the findings doc's Task C section for which combinations were
# tried and their outcomes.
OPT_LEVEL="${OPT_LEVEL:-}"
SAFE_HEAP_LEVEL="${SAFE_HEAP_LEVEL:-0}"
STACK_OVERFLOW_CHECK_LEVEL="${STACK_OVERFLOW_CHECK_LEVEL:-0}"
ASSERTIONS_LEVEL="${ASSERTIONS_LEVEL:-0}"

EXTRA_DEBUG_FLAGS=""
if [ -n "$OPT_LEVEL" ]; then
  EXTRA_DEBUG_FLAGS="$EXTRA_DEBUG_FLAGS -O${OPT_LEVEL}"
fi
if [ "$SAFE_HEAP_LEVEL" != "0" ]; then
  EXTRA_DEBUG_FLAGS="$EXTRA_DEBUG_FLAGS -s SAFE_HEAP=${SAFE_HEAP_LEVEL}"
fi
if [ "$STACK_OVERFLOW_CHECK_LEVEL" != "0" ]; then
  EXTRA_DEBUG_FLAGS="$EXTRA_DEBUG_FLAGS -s STACK_OVERFLOW_CHECK=${STACK_OVERFLOW_CHECK_LEVEL}"
fi
if [ "$ASSERTIONS_LEVEL" != "0" ]; then
  EXTRA_DEBUG_FLAGS="$EXTRA_DEBUG_FLAGS -s ASSERTIONS=${ASSERTIONS_LEVEL}"
fi
if [ -n "$EXTRA_DEBUG_FLAGS" ]; then
  echo "Extra debug flags (via EMCC_CFLAGS, bypassing Makefile.emulatorjs's DEBUG=1 block):$EXTRA_DEBUG_FLAGS"
fi

# Legacy full DEBUG=1 pass-through, kept only for regression comparison against
# the isolated flags above -- NOT used unless DEBUG=1 is explicitly set in the
# environment. Mutually exclusive in practice with the granular flags above
# (don't set both; if both are set, Makefile.emulatorjs's own DEBUG=1 LDFLAGS
# additions land in the argument list BEFORE the EMCC_CFLAGS ones above, so the
# granular flags would still win on "last wins" settings, but this combination
# was not a goal and was not tested).
DEBUG_ARG=""
if [ "${DEBUG:-0}" = "1" ]; then
  DEBUG_ARG="DEBUG=1"
fi

EMCC_CFLAGS="--pre-js ../build/midi-stub-pre.js --embed-file ../build/embed-staging/engine-data@/engine-data -g -gsource-map $EXTRA_DEBUG_FLAGS" emmake make -f Makefile.emulatorjs \
  LD=em++ \
  HAVE_7ZIP=1 HAVE_CHD=1 \
  HAVE_THREADS=1 PTHREAD_POOL_SIZE=4 \
  ASYNC=1 HAVE_OPENGLES3=1 \
  STACK_SIZE=16777216 INITIAL_HEAP=134217728 \
  TARGET=scummvm_libretro.js \
  $DEBUG_ARG \
  -j"$(nproc)"

echo "Build artifacts:"
ls -la scummvm_libretro.js scummvm_libretro.wasm
