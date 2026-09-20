#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."

# Writes each commit of the divergence branch to the patch file assemble.sh
# consumes. The branch is the source of truth; patches/ is generated from it.
#
# patch(1) cannot follow code that moves -- it matches context and rejects --
# so an upstream restructure used to cost a manual re-cut of every patch that
# touched the moved region. Rebasing the branch handles that; this script turns
# the result back into the build's input.
#
# The output filename comes from the commit's Patch-File: trailer rather than a
# slug of its subject, so rewording a commit message cannot silently rename a
# patch that assemble.sh references by name.

BRANCH="${1:-scummvm-wasm}"
BASE="${2:-}"
WORKTREE="${EJS_WORKTREE:-/tmp/ejs-branch}"
OUT="build/emulatorjs/patches"

[ -d "$WORKTREE" ] || { echo "error: no worktree at $WORKTREE" >&2; exit 2; }
[ -d "$OUT" ] || { echo "error: no patches dir at $OUT" >&2; exit 2; }

if [ -z "$BASE" ]; then
  BASE="$(grep -oP 'EJS_COMMIT="\K[^"]+' build/emulatorjs/assemble.sh)"
  [ -n "$BASE" ] || { echo "error: could not read EJS_COMMIT from assemble.sh" >&2; exit 2; }
fi

git -C "$WORKTREE" rev-parse --verify -q "$BRANCH" >/dev/null \
  || { echo "error: no branch '$BRANCH' in $WORKTREE" >&2; exit 2; }

echo "==> exporting ${BASE}..${BRANCH} from $WORKTREE"

count=0
for sha in $(git -C "$WORKTREE" rev-list --reverse "${BASE}..${BRANCH}"); do
  name="$(git -C "$WORKTREE" show -s --format='%(trailers:key=Patch-File,valueonly)' "$sha" | tr -d '[:space:]')"
  if [ -z "$name" ]; then
    echo "error: commit $sha has no Patch-File: trailer" >&2
    git -C "$WORKTREE" show -s --oneline "$sha" >&2
    exit 1
  fi
  git -C "$WORKTREE" diff "${sha}^" "$sha" > "$OUT/$name"
  echo "    $name"
  count=$((count + 1))
done

echo "==> wrote $count patch(es) to $OUT/"
