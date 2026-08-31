#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -z "${1:-}" ]; then
  echo "Usage: $0 <path-to-romm-fork-checkout>" >&2
  echo "  e.g.: $0 /home/user/git/romm" >&2
  exit 1
fi

CORE_FILE="test-page/ejs/data/cores/scummvm-thread-wasm.data"
if [ ! -f "$CORE_FILE" ]; then
  echo "error: $CORE_FILE not found -- run build/package-core.sh first" >&2
  exit 1
fi

DEST_DIR="$1/docker/scummvm-core"
mkdir -p "$DEST_DIR"
cp "$CORE_FILE" "$DEST_DIR/scummvm-thread-wasm.data"

echo "Staged core at $DEST_DIR/scummvm-thread-wasm.data"
echo "Next, from $1:"
echo "  docker build -f docker/Dockerfile --target full-image -t romm-scummvm:local ."
