#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
EJS_VERSION="4.2.3"
if [ -d ejs/data ]; then
  echo "EmulatorJS already present at test-page/ejs — skipping download."
  exit 0
fi
curl -sL -o ejs.7z "https://github.com/EmulatorJS/EmulatorJS/releases/download/v${EJS_VERSION}/${EJS_VERSION}.7z"
mkdir -p ejs
7z x -y ejs.7z -o./ejs
rm ejs.7z
