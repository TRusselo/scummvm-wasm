#!/usr/bin/env bash
# Build a self-contained EmulatorJS site that serves ONLY the ScummVM core,
# with no ROMM, no Docker and no other core present.
#
# Two modes, and the difference is the point:
#
#   --vanilla (default)  upstream EmulatorJS at the pinned commit, exactly as
#                        EmulatorJS would build it. What breaks here is what
#                        EmulatorJS itself is missing for our core.
#   --patched            the same tree with this project's patches applied,
#                        i.e. what ROMM runs today.
#
# Run both against the same game and the diff is the list of changes
# EmulatorJS has to accept -- or that we have to justify -- for the core to
# work in their distribution.
set -euo pipefail
cd "$(dirname "$0")/../.."
REPO="$PWD"

MODE="--vanilla"
EXTRA=()
OUTPUT="${HOME}/ejs-standalone"
for arg in "$@"; do
  case "$arg" in
    --vanilla) MODE="--vanilla" ;;
    --patched) MODE="" ;;
    --patch=*) MODE=""; EXTRA+=("$arg") ;;
    -*) echo "usage: standalone.sh [--vanilla|--patched|--patch=<file>...] [output-dir]" >&2; exit 2 ;;
    *) OUTPUT="$arg" ;;
  esac
done
OUTPUT="$(realpath -m -- "$OUTPUT")"

CORE_SRC="${REPO}/test-page/ejs/data/cores"
if [ ! -f "${CORE_SRC}/scummvm-thread-wasm.data" ]; then
  echo "error: no packaged core at ${CORE_SRC}/scummvm-thread-wasm.data" >&2
  echo "       run build/package-core.sh first." >&2
  exit 1
fi

echo "==> assembling EmulatorJS (${MODE:---patched}) at ${OUTPUT}"
bash build/emulatorjs/assemble.sh "$OUTPUT" --force ${MODE} ${EXTRA[@]+"${EXTRA[@]}"}

# EmulatorJS ships every core in its release 7z; here the cores directory is
# created empty by the JS-only tree and we drop in exactly one. Both the
# regular and "-legacy" names are needed: downloadGameCore() routes a
# first-time visitor to "-legacy" unless the core's report sets
# defaultWebGL2, and the report is only fetched after that choice is made.
echo "==> installing the ScummVM core"
mkdir -p "${OUTPUT}/data/cores/reports"
cp "${CORE_SRC}/scummvm-thread-wasm.data"        "${OUTPUT}/data/cores/"
cp "${CORE_SRC}/scummvm-thread-legacy-wasm.data" "${OUTPUT}/data/cores/"
cp "${CORE_SRC}/reports/scummvm.json"            "${OUTPUT}/data/cores/reports/"

echo "==> copying game fixtures"
shopt -s nullglob
GAMES=("${REPO}"/test-page/*.scm "${REPO}"/test-page/*.zip)
for g in "${GAMES[@]}"; do cp -n "$g" "${OUTPUT}/" || true; done
shopt -u nullglob

cp "${REPO}/test-page/serve-coop-coep.py" "${OUTPUT}/serve.py"

cat > "${OUTPUT}/index.html" <<'EOH'
<!doctype html>
<html>
<head><title>ScummVM WASM core -- standalone EmulatorJS</title></head>
<body style="background:#222;color:#eee;font-family:monospace;margin:0;padding:8px;">
<div id="pick"></div>
<div id="game-wrapper" style="width:100%;aspect-ratio:8/5;">
<div id="game" style="width:100%;height:100%;background:#000;"></div>
</div>
<script>
  const params = new URLSearchParams(location.search);
  const game = params.get("game") || "zak.scm";
  document.querySelector("#pick").textContent = "game: " + game + "  (?game=<file> to change)";

  EJS_player = "#game";
  EJS_core = "scummvm";
  EJS_pathtodata = "data/";
  EJS_startOnLoaded = true;
  EJS_gameUrl = game;
  EJS_threads = true;
  if (params.has("debug")) EJS_DEBUG_XX = true;
  EJS_defaultOptions = { lockMouse: "enabled" };

  EJS_onGameStart = () => {
    const wrapper = document.querySelector("#game-wrapper");
    let current = null;
    const sync = () => {
      const aspect = EJS_emulator.gameManager.getVideoDimensions("aspect");
      if (aspect && aspect !== current) { current = aspect; wrapper.style.aspectRatio = String(aspect); }
    };
    sync();
    const t = setInterval(sync, 500);
    setTimeout(() => clearInterval(t), 10000);
  };
</script>
<script src="data/loader.js"></script>
</body>
</html>
EOH

echo
echo "==> standalone site ready: ${OUTPUT}"
echo "    mode:  ${MODE:---patched}"
echo "    cores: $(find "${OUTPUT}/data/cores" -maxdepth 1 -name '*.data' | wc -l) (expect 2, both ScummVM)"
echo "    games: $(find "${OUTPUT}" -maxdepth 1 \( -name '*.scm' -o -name '*.zip' \) | wc -l)"
echo
echo "    python3 ${OUTPUT}/serve.py --port 8934"
echo "    http://127.0.0.1:8934/index.html?game=zak.scm"
