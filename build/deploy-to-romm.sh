#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Where the image is actually built. /mnt/user/Code on the Unraid box is the
# same folder as /mnt/unraid/Code here -- a cache-only share mounted both ways --
# so staging is a local copy rather than an rsync over ssh, and there is no
# second copy to drift. The checkout used to live in the box's /tmp, which is
# RAM there: 929 MB held permanently and lost on every reboot.
STAGE_DEFAULT="/mnt/unraid/Code/scummvm-wasm/romm-build"

usage() {
  echo "Usage: $0 [path-to-romm-checkout] [--ejs=<assembled-data-dir>]" >&2
  echo "  default destination: $STAGE_DEFAULT" >&2
  echo "  --ejs stages an assemble.sh output tree as well; without it the" >&2
  echo "        EmulatorJS half of the deploy is left untouched." >&2
  exit 1
}

DEST_ROOT=""
EJS_SRC=""
for arg in "$@"; do
  case "$arg" in
    --ejs=*) EJS_SRC="${arg#--ejs=}" ;;
    -h|--help) usage ;;
    -*) echo "error: unknown option $arg" >&2; usage ;;
    *) DEST_ROOT="$arg" ;;
  esac
done
DEST_ROOT="${DEST_ROOT:-$STAGE_DEFAULT}"
if [ ! -d "$DEST_ROOT" ]; then
  echo "error: no such checkout: $DEST_ROOT" >&2
  usage
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

DEST_DIR="$DEST_ROOT/docker/scummvm-core"
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

# The EmulatorJS half. assemble.sh emits the JS only -- the ~298 MB of
# The cores are not staged by this script and are in no repository: they arrive
# as a binary bundle and are preserved untouched on every run, which is exactly
# how a 4.2.3 bundle built 2025-06-14 survived an EmulatorJS pin bump to a 2026
# commit. The JS began calling EmulatorJSGetState() in 2025-09, no core in that
# bundle exports it, and save states failed on all 186 non-ScummVM cores for
# months. ScummVM kept working and hid it, because this project builds that one
# core itself against a current RetroArch.
#
# Checked by SYMBOL, not by version or date. version.json still reads "4.2.3"
# whatever the pin says, and the CDN's Last-Modified reflects when a file was
# copied rather than when the core was built -- both proxies, and a proxy is
# what hid this. Re-derive the required names with:
#   grep -rho 'this\.Module\.[A-Za-z_][A-Za-z0-9_]*' <ejs>/data/src/*.js | sort -u
# keeping only what EmulatorJS defines; the rest are emscripten runtime methods
# present in every core.
check_core_abi() {
  local dir="$1" sample js tmp
  [ -d "$dir" ] || return 0
  command -v 7z >/dev/null 2>&1 || return 0
  # Any core answers this; they are built as one batch. Never ours -- ScummVM
  # is built here and would always pass, which is the blind spot itself.
  # Matched on the basename: every path in this project contains "scummvm-wasm",
  # so filtering the full path silently discarded every core and the check
  # passed on a bundle it was written to reject.
  local base
  sample=""
  for f in "$dir"/*-wasm.data; do
    [ -e "$f" ] || continue
    base="$(basename "$f")"
    case "$base" in scummvm*) continue ;; esac
    sample="$f"; break
  done
  [ -n "$sample" ] || return 0
  tmp="$(mktemp -d)"
  7z e -y -o"$tmp" "$sample" '*.js' >/dev/null 2>&1
  js="$(ls "$tmp"/*.js 2>/dev/null | head -1)"
  if [ -n "$js" ] && ! grep -q 'EmulatorJSGetState' "$js"; then
    echo                                                                        >&2
    echo "WARNING: the bundled cores are older than the JS that drives them."    >&2
    echo "  $(basename "$sample") does not export EmulatorJSGetState(), which"   >&2
    echo "  GameManager.getState() calls on every save. Save states will fail"   >&2
    echo "  on every core in this bundle except ScummVM, silently -- the games"  >&2
    echo "  still load and play."                                               >&2
    echo "  Refresh from https://cdn.emulatorjs.org/nightly/data/cores/ ; the"   >&2
    echo "  stable and latest channels still serve the 2025 bundle. Record what" >&2
    echo "  you pulled in data/cores/PROVENANCE.txt."                            >&2
    echo                                                                        >&2
  fi
  rm -rf "$tmp"
}

# cores/*.data and cores/reports/*.json in a deployment come from elsewhere and
# must survive, so those two are excluded and everything else is replaced.
# Forgetting this half is how a core once shipped against a bundle missing its
# patches, with nothing to show for it in the logs.
if [ -n "$EJS_SRC" ]; then
  if [ ! -f "$EJS_SRC/emulator.min.js" ]; then
    echo "error: $EJS_SRC does not look like an assemble.sh output (no emulator.min.js)" >&2
    exit 1
  fi
  EJS_DEST="$DEST_ROOT/docker/emulatorjs/data"
  [ -d "$EJS_DEST" ] || { echo "error: no EmulatorJS tree at $EJS_DEST" >&2; exit 1; }
  # --delete, or anything we stop producing lives on in the deploy forever.
  # GNU patch used to leave .orig backups next to every file it shifted, and
  # those kept shipping for a week after the patches stopped creating them.
  # The two excludes protect cores/ and reports/ from the delete as well as
  # from the copy, which is what keeps the 187 staged cores out of harm.
  rsync -a --delete --exclude 'cores/' --exclude 'reports/' "$EJS_SRC/" "$EJS_DEST/"
  echo "Staged EmulatorJS JS from $EJS_SRC"
  echo "  cores preserved:   $(ls "$EJS_DEST"/cores/*.data 2>/dev/null | wc -l)"
  echo "  reports preserved: $(ls "$EJS_DEST"/cores/reports/*.json 2>/dev/null | wc -l)"
  check_core_abi "$EJS_DEST/cores"
else
  echo "NOTE: EmulatorJS not staged. Pass --ejs=<assemble.sh output>/data if a"
  echo "      patch changed, or the image keeps the bundle it already has."
  check_core_abi "$DEST_ROOT/docker/emulatorjs/data/cores"
fi

echo
echo "Next, on the Unraid box (the share is /mnt/user/Code there):"
echo "  cd /mnt/user/Code/scummvm-wasm/romm-build && docker build -f docker/Dockerfile --target full-image -t romm-scummvm:local ."
