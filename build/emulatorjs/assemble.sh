#!/usr/bin/env bash
# Assemble a patched EmulatorJS tree with this project's streaming-zip
# patches applied, at <output>/data -- matching the layout the ROMM
# Dockerfile expects at docker/emulatorjs/data.
#
# The tree is ~286 MB and is committed to no repository, so this script is
# the only record of how it is built. It writes to an explicit output
# directory rather than staging into any deployment checkout directly --
# staging the result into a real deployment (e.g. a ROMM checkout's
# docker/emulatorjs/) is a separate, deliberate step left to the operator,
# so this script can never silently clobber a build source for an existing
# image (such as a release-candidate image that must not carry this
# experimental patch).
set -euo pipefail
cd "$(dirname "$0")/../.."

EJS_COMMIT="0b1c5e9"          # must match ARG EMULATORJS_COMMIT in romm's Dockerfile

usage() { echo "usage: assemble.sh <output-dir> [--force]" >&2; }

# Parse flags positionally-independent: --force may appear before or after
# the output directory, and any other flag-shaped or extra argument is a
# usage error rather than being silently treated as the output directory.
FORCE=""
OUTPUT=""
for arg in "$@"; do
  case "$arg" in
    --force)
      FORCE="--force"
      ;;
    -*)
      usage
      exit 2
      ;;
    *)
      if [ -n "$OUTPUT" ]; then
        usage
        exit 2
      fi
      OUTPUT="$arg"
      ;;
  esac
done

if [ -z "$OUTPUT" ]; then
  usage
  exit 2
fi

# Note: `cd` above already moved us to the repo root, so a relative OUTPUT
# would resolve against the repo, not the caller's original working
# directory -- surprising, and dangerous once this value flows into
# `rm -rf`. Normalise both paths (without requiring OUTPUT to exist) before
# comparing them, so a trailing slash, a "..", or a symlinked parent cannot
# defeat the checks below.
OUTPUT_ABS="$(realpath -m -- "$OUTPUT")"
REPO_ABS="$(realpath -m -- "$PWD")"

case "$OUTPUT_ABS" in
  /*) ;;
  *)
    echo "error: output directory must be an absolute path (got '$OUTPUT')" >&2
    exit 2
    ;;
esac

# Refuse a target that IS the repo root (in any spelling), that contains it
# (an ancestor directory), or that lives inside it -- rm -rf on any of these
# would destroy or corrupt this checkout.
if [ "$OUTPUT_ABS" = "$REPO_ABS" ] \
   || case "$REPO_ABS/" in "$OUTPUT_ABS"/*) true ;; *) false ;; esac \
   || case "$OUTPUT_ABS/" in "$REPO_ABS"/*) true ;; *) false ;; esac; then
  echo "error: refusing to write to '$OUTPUT' -- it is, contains, or lives inside this repository" >&2
  exit 2
fi

if [ -e "$OUTPUT_ABS" ] && [ -n "$(ls -A "$OUTPUT_ABS" 2>/dev/null)" ] && [ "$FORCE" != "--force" ]; then
  echo "ERROR: ${OUTPUT_ABS} already exists and is not empty. Pass --force to overwrite it." >&2
  exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> cloning EmulatorJS at ${EJS_COMMIT}"
git clone -q https://github.com/EmulatorJS/EmulatorJS "$WORK/ejs"
git -C "$WORK/ejs" checkout -q "$EJS_COMMIT"

echo "==> adding zipstream.js"
cp build/emulatorjs/src/zipstream.js "$WORK/ejs/data/src/zipstream.js"

echo "==> applying patches"
# The patches come from plain `diff -u`, so the target is named explicitly
# rather than inferred from the diff header.
patch "$WORK/ejs/data/src/cache.js"    < build/emulatorjs/patches/01-cache-streaming.patch
patch "$WORK/ejs/data/src/emulator.js" < build/emulatorjs/patches/02-emulator-onfile.patch

echo "==> npm ci"
( cd "$WORK/ejs" && npm ci --silent )

echo "==> npm run minify"
( cd "$WORK/ejs" && npm run minify )

# Both artifacts must carry the change: loader.js serves data/src/*.js when
# EJS_DEBUG_XX is true and emulator.min.js otherwise, so patching only the
# source would work under debug and silently do nothing in normal use.
for f in "$WORK/ejs/data/src/cache.js" "$WORK/ejs/data/emulator.min.js"; do
  grep -q "Streaming" "$f" || { echo "ERROR: patch missing from $f" >&2; exit 1; }
done
echo "==> verified: both the source and the minified bundle carry the patch"

echo "==> writing tree to ${OUTPUT_ABS}/data"
rm -rf "${OUTPUT_ABS}"
mkdir -p "${OUTPUT_ABS}"
cp -r "$WORK/ejs/data" "${OUTPUT_ABS}/data"

echo "==> done. Patched tree is at ${OUTPUT_ABS}/data."
echo "    Staging it into a deployment (e.g. a ROMM checkout's docker/emulatorjs/) is a separate, deliberate step -- not performed by this script."
