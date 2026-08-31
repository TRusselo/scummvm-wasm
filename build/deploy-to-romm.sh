#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -z "${1:-}" ]; then
  echo "Usage: $0 <path-to-romm-fork-checkout>" >&2
  echo "  e.g.: $0 /home/user/git/romm" >&2
  exit 1
fi

# EmulatorJS's browser-side loader picks between the plain and "-legacy"
# filename at runtime based on the browser's own WebGL2 capability
# detection -- both must be staged or a browser routed to "-legacy" 404s.
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

echo "Staged core (both variants) at $DEST_DIR/"
echo "Next, from $1:"
echo "  docker build -f docker/Dockerfile --target full-image -t romm-scummvm:local ."
