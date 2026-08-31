# ROMM ScummVM Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. **Task 6 is a live-deployment task against the user's running Unraid `romm` container and must NOT be executed autonomously by an implementer subagent** — it requires the user's explicit confirmation at each destructive step (see Task 6's own note).

**Goal:** Make the scummvm-wasm libretro core playable from inside the
user's real ROMM instance, via ROMM's own Play button, with EmulatorJS's
native client-side save states working — mirroring what's already proven
in this project's local `test-page/` harness.

**Architecture:** Fork `rommapp/romm` to `TRusselo/romm` on branch
`emulatorjs-wasm-fixes`. Patch two lines in the frontend's hardcoded
platform→core map, patch `docker/Dockerfile` to layer our pre-built core
file into the image, add a small script in this repo to stage that file
into the fork's build context, build the image, then redeploy the user's
existing `romm` Unraid container from it.

**Tech Stack:** TypeScript/Vue (ROMM frontend, unchanged logic, two data
additions), Dockerfile (multi-stage build), bash (staging script) — no
Python/backend changes.

**Spec:** [docs/superpowers/specs/2026-08-30-romm-scummvm-integration-design.md](../specs/2026-08-30-romm-scummvm-integration-design.md)

## Global Constraints

- No changes to ROMM's backend (Python) — confirmed unnecessary in the spec.
- No committed binary artifacts in the `TRusselo/romm` fork's git history —
  the core file is gitignored there, same as this project's own build
  artifacts.
- No changes to the `romm` container's mounts, ports, or environment
  variables — this is an image swap only.
- The core artifact is exactly `test-page/ejs/data/cores/scummvm-thread-wasm.data`,
  produced by this project's own `build/package-core.sh` — no separate
  build path for ROMM.
- Task 6 (live redeploy) requires the user's explicit confirmation before
  each command that touches the running `romm` container or its Unraid
  template — do not run it unattended.

---

### Task 1: Fork `rommapp/romm` and set up the branch

**Files:**
- Create: local clone at `/home/user/git/romm` (new sibling repo, not part
  of `scummvm-wasm`)

**Interfaces:**
- Produces: a local checkout of `TRusselo/romm` on branch
  `emulatorjs-wasm-fixes`, tracked against `origin` (the fork), that Tasks
  2-3 commit to and Task 5 builds from.

- [ ] **Step 1: Fork the repo on GitHub**

```bash
gh repo fork rommapp/romm --org TRusselo --clone=false
```

Expected: creates `TRusselo/romm` as a fork (idempotent if it already
exists from an earlier attempt).

- [ ] **Step 2: Clone the fork locally and create the branch**

```bash
cd /home/user/git
git clone https://github.com/TRusselo/romm.git
cd romm
git checkout -b emulatorjs-wasm-fixes
```

Expected: `/home/user/git/romm` exists, `git branch --show-current` prints
`emulatorjs-wasm-fixes`.

- [ ] **Step 3: Verify the upstream remote for future reference**

```bash
git remote -v
```

Expected: `origin` points at `https://github.com/TRusselo/romm.git`. (No
`upstream` remote is needed for this pass — this fork isn't being
upstreamed as part of this plan, per the spec's stated out-of-scope.)

---

### Task 2: Patch the frontend platform/core maps

**Files:**
- Modify: `/home/user/git/romm/frontend/src/utils/index.ts`

**Interfaces:**
- Consumes: nothing new — uses the existing `_EJS_CORES_MAP` and
  `areThreadsRequiredForEJSCore` already defined in this file.
- Produces: `getSupportedEJSCores("scummvm")` returns `["scummvm"]`, and
  `areThreadsRequiredForEJSCore("scummvm")` returns `true`. `Player.vue`
  consumes both of these already — no changes needed there.

- [ ] **Step 1: Add the `scummvm` platform to `_EJS_CORES_MAP`**

In `_EJS_CORES_MAP` (the object literal starting `const _EJS_CORES_MAP:
Record<string, string[]> = {`), add a `scummvm` entry. Keep the
map's existing alphabetical-ish grouping by inserting it near `saturn`/
`snes` (or anywhere in the object — order doesn't affect behavior, but
matching the file's existing style keeps the diff easy to review):

```ts
  saturn: ["yabause"],
  scummvm: ["scummvm"],
  snes: ["snes9x"],
```

- [ ] **Step 2: Add `"scummvm"` to the threads whitelist**

Change:

```ts
export function areThreadsRequiredForEJSCore(core: string): boolean {
  return ["dosbox_pure", "ppsspp", "azahar"].includes(core);
}
```

to:

```ts
export function areThreadsRequiredForEJSCore(core: string): boolean {
  return ["dosbox_pure", "ppsspp", "azahar", "scummvm"].includes(core);
}
```

- [ ] **Step 3: Install dependencies and verify the type check passes**

```bash
cd /home/user/git/romm/frontend
npm install
npm run typecheck
```

Expected: exits 0, no new type errors.

- [ ] **Step 4: Run the existing test suite**

```bash
npm run test
```

Expected: exits 0. (No existing test references `_EJS_CORES_MAP` or
`areThreadsRequiredForEJSCore` as of this writing — this is a regression
check, not a targeted test run.)

- [ ] **Step 5: Commit**

```bash
cd /home/user/git/romm
git add frontend/src/utils/index.ts
git commit -m "Add scummvm as a supported EJS platform/core"
```

---

### Task 3: Patch the Dockerfile to bundle the ScummVM core

**Files:**
- Modify: `/home/user/git/romm/docker/Dockerfile`
- Create: `/home/user/git/romm/docker/scummvm-core/README.md`
- Modify: `/home/user/git/romm/.gitignore`

**Interfaces:**
- Consumes: a file expected to exist at build time at
  `docker/scummvm-core/scummvm-thread-wasm.data` (staged by Task 4's
  script, not committed).
- Produces: the final `full-image` build stage's
  `${WEBSERVER_FOLDER}/assets/emulatorjs/data/cores/scummvm-thread-wasm.data`
  path, which Task 5 verifies and which ROMM's frontend (patched in
  Task 2) will request at runtime.

- [ ] **Step 1: Add the COPY instruction to the `emulator-stage` build stage**

In `docker/Dockerfile`, find this existing block (the EmulatorJS release
fetch, in the `emulator-stage`):

```dockerfile
ARG EMULATORJS_VERSION=4.2.3
ARG EMULATORJS_SHA256=07d451bc06fa3ad04ab30d9b94eb63ac34ad0babee52d60357b002bde8f3850b

RUN wget "https://github.com/EmulatorJS/EmulatorJS/releases/download/v${EMULATORJS_VERSION}/${EMULATORJS_VERSION}.7z" && \
    echo "${EMULATORJS_SHA256}  ${EMULATORJS_VERSION}.7z" | sha256sum -c - && \
    7z x -y "${EMULATORJS_VERSION}.7z" -o/emulatorjs && \
    rm -f "${EMULATORJS_VERSION}.7z"
```

Add immediately after it:

```dockerfile
# ScummVM core (built separately by the scummvm-wasm project, staged here
# by that project's build/deploy-to-romm.sh -- not part of the official
# EmulatorJS release above). See docker/scummvm-core/README.md.
COPY docker/scummvm-core/scummvm-thread-wasm.data /emulatorjs/data/cores/scummvm-thread-wasm.data
```

This rides along with the official release's own core files into the
final image via the existing (unmodified)
`COPY --from=emulator-stage /emulatorjs ${WEBSERVER_FOLDER}/assets/emulatorjs`
line later in the file.

- [ ] **Step 2: Add the gitignore entry**

Append to `/home/user/git/romm/.gitignore`:

```
# scummvm-wasm core artifact, staged locally by that project's
# build/deploy-to-romm.sh before `docker build` -- not committed here.
/docker/scummvm-core/*.data
```

- [ ] **Step 3: Write the placeholder README so the directory exists in git**

Create `/home/user/git/romm/docker/scummvm-core/README.md`:

```markdown
# ScummVM core staging directory

`scummvm-thread-wasm.data` in this directory is NOT committed (see
`.gitignore`). It's staged here by the `scummvm-wasm` project's
`build/deploy-to-romm.sh` script before running `docker build`, so that
`docker/Dockerfile`'s `emulator-stage` can `COPY` it into the image
alongside the official EmulatorJS release's own core files.

Build the core first: https://github.com/TRusselo/scummvm-wasm
```

- [ ] **Step 4: Commit**

```bash
cd /home/user/git/romm
git add docker/Dockerfile .gitignore docker/scummvm-core/README.md
git commit -m "Bundle the scummvm-wasm core into the EmulatorJS data folder"
```

---

### Task 4: Add the staging script to scummvm-wasm

**Files:**
- Create: `/home/user/git/scummvm-wasm/build/deploy-to-romm.sh`

**Interfaces:**
- Consumes: `test-page/ejs/data/cores/scummvm-thread-wasm.data` (produced
  by this project's own `build/package-core.sh`, already run in earlier
  work this session).
- Produces: a copy of that file at
  `<romm-checkout>/docker/scummvm-core/scummvm-thread-wasm.data`, which
  Task 3's Dockerfile `COPY` instruction consumes.

- [ ] **Step 1: Write the script**

```bash
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
```

Save this to `build/deploy-to-romm.sh`.

- [ ] **Step 2: Make it executable**

```bash
chmod +x build/deploy-to-romm.sh
```

- [ ] **Step 3: Run it against the Task 1 checkout to verify**

```bash
./build/deploy-to-romm.sh /home/user/git/romm
ls -la /home/user/git/romm/docker/scummvm-core/
```

Expected: `scummvm-thread-wasm.data` present in that directory, same size
as `test-page/ejs/data/cores/scummvm-thread-wasm.data`.

- [ ] **Step 4: Commit (in scummvm-wasm, not the romm fork)**

```bash
cd /home/user/git/scummvm-wasm
git add build/deploy-to-romm.sh
git commit -m "Add script to stage the built core into a ROMM fork checkout"
```

---

### Task 5: Build the image locally and verify the core is bundled

**Files:** none (build/verification only, no source changes)

**Interfaces:**
- Consumes: the `TRusselo/romm` checkout from Tasks 1-3, with the core
  file staged by Task 4.
- Produces: a local Docker image tagged `romm-scummvm:local`, verified (not
  yet deployed) — Task 6 is the deployment step.

- [ ] **Step 1: Build the image**

```bash
cd /home/user/git/romm
docker build -f docker/Dockerfile --target full-image -t romm-scummvm:local .
```

Expected: build completes successfully (this rebuilds ROMM's full stack —
backend, frontend, and the emulator-stage — expect this to take a while,
matching the ~40-50 minute Emscripten build times already seen in this
project's own CI).

- [ ] **Step 2: Verify the core file landed at the expected path**

```bash
docker run --rm romm-scummvm:local ls -la /var/www/html/assets/emulatorjs/data/cores/ | grep scummvm
```

Expected: `scummvm-thread-wasm.data` listed, same size as the source file.

- [ ] **Step 3: Verify the frontend bundle contains the patch**

```bash
docker run --rm romm-scummvm:local sh -c 'grep -o "scummvm" /var/www/html/assets/*.js 2>/dev/null | head -5'
```

Expected: at least one match, confirming the built frontend bundle
includes the `_EJS_CORES_MAP`/`areThreadsRequiredForEJSCore` patch (exact
asset filename will vary — this is a smoke check, not an exact-path
assertion).

---

### Task 6: Deploy to the running Unraid `romm` container (manual checkpoint)

**This task touches the user's live, shared Unraid deployment. Do not run
these steps unattended — confirm with the user before each command that
changes the running container or its Unraid template.** This is exactly
the kind of side effect outside the working repo that requires explicit
confirmation first, per this project's own safety norms.

**Files:** none (deployment only)

**Interfaces:**
- Consumes: the `romm-scummvm:local` image built and verified in Task 5.
- Produces: the user's `romm` Unraid container running that image instead
  of `rommapp/romm:latest`.

- [ ] **Step 1: Confirm with the user before proceeding**

Ask explicitly: "Ready to point your `romm` container at the new image
and restart it? This replaces the running container's image; the
existing library/config/db volumes are untouched, but the container will
be briefly unavailable during the restart." Wait for a clear yes.

- [ ] **Step 2: Make the built image available to the Unraid box**

If the build in Task 5 ran directly on the Unraid box's Docker daemon,
the image is already available locally. If it was built elsewhere, push
it somewhere the Unraid box can pull from (e.g. a registry), or transfer
it via `docker save` / `docker load`. (Which of these applies depends on
where Task 5 was actually run — confirm with the user which case applies
before choosing a transfer method.)

- [ ] **Step 3: Update the Unraid `romm` container's template**

Via the Unraid WebUI (Docker tab → `romm` container → Edit), change the
"Repository" field from `rommapp/romm:latest` to `romm-scummvm:local`
(or the registry tag chosen in Step 2), leaving every other field
(ports, volumes, environment variables) unchanged. Apply.

- [ ] **Step 4: Restart and verify health**

Confirm the container comes back up in a `RUNNING (healthy)` or
`RUNNING` state (check via the Unraid Docker tab or the unraid-mcp
`docker/details` action) before proceeding.

- [ ] **Step 5: Trigger a library rescan and verify the Play button**

In ROMM's own UI: trigger a library rescan (this is a regression check —
the ScummVM games were already correctly identified before this change,
per the spec). Then open one game (e.g. Zak McKracken) and confirm the
Play button is now present (it was previously absent/disabled for this
platform).

- [ ] **Step 6: Play-test**

Click Play. Confirm: the core loads, the game boots to a playable state,
video/audio/mouse input all work, and EmulatorJS's native Save State /
Load State buttons work (client-side download/upload round-trip) — same
checklist already used for the local `test-page/` harness.

- [ ] **Step 7: Regression-check one other platform**

Play one game on a platform that already worked in ROMM before this
change (any platform already in `_EJS_CORES_MAP`), to confirm the patch's
pure-addition nature didn't break anything else.
