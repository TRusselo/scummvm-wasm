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

usage() { echo "usage: assemble.sh <output-dir> [--force] [--vanilla] [--patch=<file>]..." >&2; }

# Parse flags positionally-independent: --force may appear before or after
# the output directory, and any other flag-shaped or extra argument is a
# usage error rather than being silently treated as the output directory.
FORCE=""
VANILLA=""
OUTPUT=""
PATCH_OVERRIDE=()
for arg in "$@"; do
  case "$arg" in
    --force)
      FORCE="--force"
      ;;
    --vanilla)
      VANILLA="1"
      ;;
    --patch=*)
      PATCH_OVERRIDE+=("$(realpath -m -- "${arg#--patch=}")")
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

if [ -n "$VANILLA" ]; then
echo "==> vanilla: no patches, no zipstream.js -- this is upstream EmulatorJS at ${EJS_COMMIT}"
elif [ ${#PATCH_OVERRIDE[@]} -gt 0 ]; then
echo "==> applying ${#PATCH_OVERRIDE[@]} override patch(es) only -- the standard set is NOT applied"
for pf in "${PATCH_OVERRIDE[@]}"; do
  [ -f "$pf" ] || { echo "error: no such patch: $pf" >&2; exit 2; }
  echo "    $pf"
  ( cd "$WORK/ejs/data/src" && patch -p0 --forward < "$pf" )
done
else
echo "==> adding zipstream.js"
cp build/emulatorjs/src/zipstream.js "$WORK/ejs/data/src/zipstream.js"

echo "==> applying patches"
# The patches come from plain `diff -u`, so the target is named explicitly
# rather than inferred from the diff header.
patch "$WORK/ejs/data/src/cache.js"    < build/emulatorjs/patches/01-cache-streaming.patch
patch "$WORK/ejs/data/src/emulator.js" < build/emulatorjs/patches/02-emulator-onfile.patch
# 03b supersedes 03: same fix, scoped to cores whose core.json declares
# supportsMouse. 03 is kept on disk as the unscoped variant; the two conflict.
patch "$WORK/ejs/data/src/emulator.js" < build/emulatorjs/patches/03b-canvas-pointer-supports-mouse.patch
patch "$WORK/ejs/data/src/emulator.js" < build/emulatorjs/patches/04-savestate-retry.patch
patch "$WORK/ejs/data/src/cache.js"    < build/emulatorjs/patches/05-download-debug-logging.patch
patch "$WORK/ejs/data/src/emulator.js" < build/emulatorjs/patches/06-parse-core-report.patch
# Touches four files, so it keeps its diff headers and is applied by path.
patch -p1 -d "$WORK/ejs"               < build/emulatorjs/patches/08-message-severity.patch
patch "$WORK/ejs/data/src/GameManager.js" < build/emulatorjs/patches/09-loadstate-retry.patch
fi

echo "==> npm ci"
( cd "$WORK/ejs" && npm ci --silent )

echo "==> npm run minify"
( cd "$WORK/ejs" && npm run minify )

if [ -n "$VANILLA" ] || [ ${#PATCH_OVERRIDE[@]} -gt 0 ]; then
echo "==> skipping patch verification (not the standard set)"
else
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
# unpatched too, so the supportsMouse test is the discriminator -- it is the
# narrow form (patch 03b), and the unscoped 03 would pass a bare class check.
grep -q "defaultCoreOpts && this.defaultCoreOpts.supportsMouse" "$WORK/ejs/data/src/emulator.js" \
  || { echo "ERROR: canvas pointer-events patch missing from the source" >&2; exit 1; }
grep -q "defaultCoreOpts.supportsMouse" "$WORK/ejs/data/emulator.min.js" \
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

# Save-state retry. An engine that refuses to save mid-animation (Riven, while
# it has queued scripts) is retried from here rather than waited out inside the
# core, which would block the main thread and freeze the tab. The waiting
# message appears in no unpatched source or bundle, so it is a clean marker.
for f in "$WORK/ejs/data/src/emulator.js" "$WORK/ejs/data/emulator.min.js"; do
  grep -q "WAITING FOR THE SCENE TO END" "$f" \
    || { echo "ERROR: save-state-retry patch missing from $f" >&2; exit 1; }
done

# Cache-hit logging. EJS_Download never assigned this.debug upstream, so its
# three "Using cached version of" statements could never run -- there was no
# way to tell a cache hit from a miss without the Network panel. Submitted
# upstream as EmulatorJS/EmulatorJS (fix-download-debug-logging); drop this
# patch once that lands.
# Source only, unlike the checks above. Every other marker is a string literal
# and survives minification verbatim; this patch adds no literal, and the
# minifier renames the identifiers it does add (EJS -> i), so there is nothing
# stable to grep for in the bundle.
grep -Eq "this\\.debug *= *EJS *\\? *EJS\\.debug" "$WORK/ejs/data/src/cache.js" \
  || { echo "ERROR: download-debug-logging patch missing from src/cache.js" >&2; exit 1; }

# Core report decoding. The report resolves to a cache item whose bytes are
# never decoded, so buildStart is missing, core caching is disabled and every
# core is fetched under its "-legacy" name. decodeReport is a local const and
# is mangled in the bundle, so the ternary it builds is the marker there.
grep -q "decodeReport" "$WORK/ejs/data/src/emulator.js" \
  || { echo "ERROR: core-report patch missing from the source" >&2; exit 1; }
grep -q ".files\[0\]:null" "$WORK/ejs/data/emulator.min.js" \
  || { echo "ERROR: core-report patch missing from the bundle" >&2; exit 1; }

# Message severity. Upstream styles every .ejs_message red, so a successful
# save reads as a failure; the class is what carries the distinction. It is a
# string literal in the source and in the bundle, and the stylesheet is copied
# verbatim, so all three are checked.
for f in "$WORK/ejs/data/src/emulator.js" "$WORK/ejs/data/emulator.min.js" "$WORK/ejs/data/emulator.css"; do
  grep -q "ejs_message_error" "$f" \
    || { echo "ERROR: message-severity patch missing from $f" >&2; exit 1; }
done

# Load-state retry. A load is refused for as long as the engine says no, and
# several engines stay shut for seconds. The core cannot wait -- it holds the
# main thread -- so the retry lives here. Without it a load fired at launch
# (emulator.js does it 10ms after "start") never succeeds.
grep -q "savestate_error.txt" "$WORK/ejs/data/src/GameManager.js" \
  || { echo "ERROR: load-state retry patch missing from the source" >&2; exit 1; }
grep -q "savestate_error.txt" "$WORK/ejs/data/emulator.min.js" \
  || { echo "ERROR: load-state retry patch missing from the bundle" >&2; exit 1; }

echo "==> verified: both the source and the minified bundle carry all patches"
fi

echo "==> writing tree to ${OUTPUT_ABS}/data"
[ -n "$VANILLA" ] && echo "    (vanilla upstream tree -- none of this project's patches are in it)"
rm -rf "${OUTPUT_ABS}"
mkdir -p "${OUTPUT_ABS}"
cp -r "$WORK/ejs/data" "${OUTPUT_ABS}/data"

CORE_COUNT="$(find "${OUTPUT_ABS}/data/cores" -maxdepth 1 -name '*.data' 2>/dev/null | wc -l)"
LABEL="Patched"; [ -n "$VANILLA" ] && LABEL="Vanilla"
[ ${#PATCH_OVERRIDE[@]} -gt 0 ] && LABEL="Override-patched"
echo "==> done. ${LABEL} tree is at ${OUTPUT_ABS}/data (JS only: ${CORE_COUNT} cores)."
echo "    INCOMPLETE: a deployment needs 187 cores and 48 reports as well -- see"
echo "    the note at the top of this script. Staging this as-is ships an image"
echo "    with no cores for any platform but ScummVM."
echo "    Staging it into a deployment (e.g. a ROMM checkout's docker/emulatorjs/) is a separate, deliberate step -- not performed by this script."
