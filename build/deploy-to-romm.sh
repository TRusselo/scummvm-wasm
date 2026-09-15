#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -z "${1:-}" ]; then
  echo "Usage: $0 <path-to-romm-fork-checkout>" >&2
  echo "  e.g.: $0 /home/user/git/romm" >&2
  exit 1
fi

# EmulatorJS's own downloadGameCore() (src/emulator.js) defaults EVERY core
# to the "-legacy" filename on a user's first visit whenever the core's
# reports/<core>.json doesn't set `options.defaultWebGL2` -- unconditional
# on first visit, not a real check of the browser's actual WebGL2 support
# (confirmed: dosbox_pure's own shipped report doesn't set it either).
# Both must be staged or a first-time visitor routed to "-legacy" 404s.
CORE_FILE="test-page/ejs/data/cores/scummvm-thread-wasm.data"
CORE_FILE_LEGACY="test-page/ejs/data/cores/scummvm-thread-legacy-wasm.data"
if [ ! -f "$CORE_FILE" ]; then
  echo "error: $CORE_FILE not found -- run build/package-core.sh first" >&2
  exit 1
fi
if [ ! -f "$CORE_FILE_LEGACY" ]; then
  echo "error: $CORE_FILE_LEGACY not found -- run build/package-core.sh first" >&2
  exit 1
fi

DEST_DIR="$1/docker/scummvm-core"
mkdir -p "$DEST_DIR"
cp "$CORE_FILE" "$DEST_DIR/scummvm-thread-wasm.data"
cp "$CORE_FILE_LEGACY" "$DEST_DIR/scummvm-thread-legacy-wasm.data"
# Core report JSON (see build/package-core.sh) -- the ROMM Dockerfile copies
# it to /emulatorjs/data/cores/reports/scummvm.json so EmulatorJS can cache
# the core keyed on this build's timestamp.
cp "test-page/ejs/data/cores/reports/scummvm.json" "$DEST_DIR/scummvm.json"

# Engine-data is no longer embedded in the wasm: the core fetches each file
# from cores/scummvm-engine-data/ on first read. Without this the core loads
# and then 404s on every engine that needs a .dat -- see the design doc at
# docs/superpowers/specs/2026-09-14-engine-data-on-demand-design.md.
ENGINE_DATA_SRC="test-page/ejs/data/cores/scummvm-engine-data"
if [ ! -d "$ENGINE_DATA_SRC" ]; then
  echo "error: $ENGINE_DATA_SRC not found -- run build/package-core.sh first" >&2
  exit 1
fi
rm -rf "$DEST_DIR/scummvm-engine-data"
mkdir -p "$DEST_DIR/scummvm-engine-data"
cp "$ENGINE_DATA_SRC"/* "$DEST_DIR/scummvm-engine-data/"

echo "Staged core (both variants), report JSON, and $(ls "$DEST_DIR/scummvm-engine-data" | wc -l) engine-data files at $DEST_DIR/"
echo "Next, from $1:"
echo "  docker build -f docker/Dockerfile --target full-image -t romm-scummvm:local ."
