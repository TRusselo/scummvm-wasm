#!/usr/bin/env bash
# Assemble a patched EmulatorJS tree with this project's streaming-zip
# patches applied, at <output>/data -- matching the layout the ROMM
# Dockerfile expects at docker/emulatorjs/data.
#
# INCOMPLETE ON ITS OWN -- READ THIS BEFORE STAGING THE RESULT.
#
# This produces the JavaScript half only: data/ with our patches applied,
# about 3.5 MB and zero cores. A ROMM deployment needs ~298 MB: the same
# data/ plus 187 core *.data files and 48 reports/*.json, which come from
# the 47 "@emulatorjs/core-*" packages listed in data/cores/package.json.
# `npm ci` at the repo root does NOT fetch them -- they are a separate
# install, and every one of them is pinned to "latest", so refetching can
# silently pull newer cores for every other platform in the library.
#
# Staging this output alone yields an image whose every non-ScummVM core is
# missing. Either install the core packages, or copy cores/ and
# cores/reports/ from a known-good complete tree (what the 2026-09-13 build
# did, to avoid an untested "latest" core bump riding along with unrelated
# JS fixes). Expect exactly 187 and 48; the ScummVM core and its report are
# COPYd in separately by ROMM'"'"'s Dockerfile and should not be included here.
#
# It writes to an explicit output
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
patch "$WORK/ejs/data/src/emulator.js" < build/emulatorjs/patches/03-canvas-pointer-events.patch

echo "==> npm ci"
( cd "$WORK/ejs" && npm ci --silent )

echo "==> npm run minify"
( cd "$WORK/ejs" && npm run minify )

# Both artifacts must carry the change: loader.js serves data/src/*.js when
# EJS_DEBUG_XX is true and emulator.min.js otherwise, so patching only the
# source would work under debug and silently do nothing in normal use.
for f in "$WORK/ejs/data/src/cache.js" "$WORK/ejs/data/emulator.min.js"; do
  grep -q "Streaming" "$f" || { echo "ERROR: cache.js patch missing from $f" >&2; exit 1; }
done
# The emulator.js half needs its own check: it carries no string literal, so
# the grep above cannot see it, and it was possible for that half to go
# missing while this script still reported success. The entry-name manifest
# is the discriminator -- "romData.fileNames" in the source (plain
# "fileNames" appears there unpatched, as a local), and "fileNames" in the
# bundle, where it appears nowhere unpatched and terser keeps property names.
grep -q "romData.fileNames" "$WORK/ejs/data/src/emulator.js" \
  || { echo "ERROR: emulator.js patch missing from the source" >&2; exit 1; }
grep -q "fileNames" "$WORK/ejs/data/emulator.min.js" \
  || { echo "ERROR: emulator.js patch missing from the minified bundle" >&2; exit 1; }
# Without this the canvas keeps pointer-events:none on any device reporting a
# touchscreen, and the mouse does nothing. "ejs-canvas-no-pointer" is present
# unpatched too, so the removal call is the discriminator.
grep -q "remove(\"ejs-canvas-no-pointer\")" "$WORK/ejs/data/src/emulator.js" \
  || { echo "ERROR: canvas pointer-events patch missing from the source" >&2; exit 1; }
grep -q "ejs-canvas-no-pointer" "$WORK/ejs/data/emulator.min.js" \
  || { echo "ERROR: canvas pointer-events patch missing from the bundle" >&2; exit 1; }
# The decompression readout is a third, independently droppable piece: it is
# what stops the loading text freezing on "Download Game Data 100%" for the
# whole unpack. "Decompress Game Data" is already translated in every
# localization/*.json but appears in no unpatched source or bundle, so it is
# a clean marker in both.
for f in "$WORK/ejs/data/src/emulator.js" "$WORK/ejs/data/emulator.min.js"; do
  grep -q "Decompress Game Data" "$f" \
    || { echo "ERROR: decompression-progress patch missing from $f" >&2; exit 1; }
done
echo "==> verified: both the source and the minified bundle carry both patches"

echo "==> writing tree to ${OUTPUT_ABS}/data"
rm -rf "${OUTPUT_ABS}"
mkdir -p "${OUTPUT_ABS}"
cp -r "$WORK/ejs/data" "${OUTPUT_ABS}/data"

CORE_COUNT="$(ls "${OUTPUT_ABS}"/data/cores/*.data 2>/dev/null | wc -l)"
echo "==> done. Patched tree is at ${OUTPUT_ABS}/data (JS only: ${CORE_COUNT} cores)."
echo "    INCOMPLETE: a deployment needs 187 cores and 48 reports as well -- see"
echo "    the note at the top of this script. Staging this as-is ships an image"
echo "    with no cores for any platform but ScummVM."
echo "    Staging it into a deployment (e.g. a ROMM checkout's docker/emulatorjs/) is a separate, deliberate step -- not performed by this script."
