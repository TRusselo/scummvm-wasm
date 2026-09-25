# Upstream rebase and branch cleanup, 2026-09-24

**Goal:** put every repo on current upstream (RomM 5.3.1 plus what merged
since, EmulatorJS main past 4.3.0-pre, libretro/scummvm staging_master,
EmulatorJS/RetroArch v1.22.2), drop the code upstream has taken, and delete the
branches nothing needs any more.

**Flow:** rebase and test-build on the workstation (`/home/user/git`), push to
GitHub, then update the Unraid checkout and build the image over ssh. The box
only ever takes what is on GitHub.

**Supersedes:** `docs/REBASE-PLAN.md` (2026-09-19) and the "Suggested order" in
`docs/ROMM-REBASE-REVIEW.md`.

## Global constraints

- Commit trailer `Assisted-by: Claude:claude-opus-5-5`. Never `Co-Authored-By`.
- No comments in submitted code. Terse upstream commit messages.
- Nothing is opened, commented on, or deleted on GitHub without Tristyn's ok,
  one item at a time.
- Unraid: Claude may read and back up containers and info, build images, and
  stage `:local`. **Nothing on Unraid is stopped or deleted**: no stop,
  restart, rm, rmi, prune, git branch delete, `fetch --prune`, or file
  delete. Tristyn force-updates `/romm` on `:local`. Retag `:local` to
  `:rollback` before every build (a retag deletes nothing). After a build, list the orphaned images, ask,
  and hand Tristyn the command.
- Check the Docker vdisk headroom with the unraid skill before building.
- Every git operation that rewrites history runs on the workstation, never
  through the `/mnt/unraid` mount. On the mount, git reports "local changes
  would be overwritten" for files `git status` calls clean.
- Before a force-push, push a backup branch. Push with `--force-with-lease`.
- Savestate and loading changes stay gated to our core.

---

## Where everything stands (measured 2026-09-24, after `git fetch --all`)

| Repo | We build from | Upstream now | New upstream commits | Action |
|---|---|---|---|---|
| EmulatorJS | `f4f0f1c` + 8 patches (`scummvm-wasm-split`) | `main` = `f4f0f1c` (Sep 19) | **0** | none. `v4.3.0-pre` (May 17) is 36 commits behind our pin |
| RetroArch | `v1.22.2` + 4 (`emulatorjs-wasm-fixes` @ `f21b106`) | `v1.22.2` = `1eb5edf2b3` (Sep 19) | **0** | none |
| scummvm-core | `364e70216ab` + 42 | `staging_master` = `92366fad72b` (Sep 22) | 1 (our own #117) | **rebase, drop 4, swap 1** |
| libretro-deps | `libretro/libretro-deps@e639e0c` | master = `e639e0c` | 0 | none. The fork is no longer used |
| RomM | `8e61199d7` + 31 (`unraid-stage-20260916` @ `4ec540182`) | `5.3.1` = `95599dadb` (Sep 22), `master` = `b834b35cb` (Sep 24) | 384 (163 to 5.3.1, then 221) | **rebase onto master** |

`scummvm/scummvm` master is 73 ahead of `staging_master`. We do not merge it
ourselves. It arrives when libretro next merges it into staging_master; they did
so on Sep 15 and Sep 19.

## What merged, and what each merge drops

| PR | State | Effect on our code |
|---|---|---|
| libretro/scummvm #110, #113, #114, #116 | merged | already dropped in the Sep 19 rebase |
| libretro/scummvm #117 (deps bump) + libretro-deps #15 | merged | our 3 deps-pin commits net out to exactly #117. **Drop all 3** |
| scummvm/scummvm #7945 (SCUMM save name) | merged | already gone from our branch |
| scummvm/scummvm #7946 (CHAMBER) | merged to scummvm master, **not yet** in staging_master | **swap** ours for upstream's `62923730255`, so it drops itself at libretro's next sync. Ours differs only by a 10-line comment |
| scummvm/scummvm #7935 (lephilousophe, not ours) | in staging_master | makes `loadStream` own and free the stream on failure. Our `456ea93f` nulls `_fileStream` before `close()` on two paths, so under #7935 it **leaks** the stream. **Drop it** |
| EmulatorJS #1267, #1268, #1269, #1271 | merged | patches already deleted |
| EmulatorJS #1270, #1272, #1273 | open, no movement since Sep 23 | keep patches 08 and 12; see Task 8 |
| EmulatorJS/RetroArch #48 | draft | keep the branch |
| rommapp/romm #4313 | merged, v2 UI only | keep our `287270a3c`, which is the v1 `Base.vue` counterpart |
| rommapp/romm #4539 | closed | nothing carried |

`git cherry` marks nothing as `-` in RomM (0 of 31). In scummvm-core it marks
nothing either. The 5 drops above come from reading the diffs, not from cherry.

## Dry runs (no refs written)

- **scummvm-core**, rebased onto `staging_master` with the 4 drops and the swap:
  clean, 38 commits. The resulting tree differs from today's `0b967c68bbe` in
  exactly two places: `engines/chamber/cga.cpp` loses the 10-line comment, and
  `video/avi_decoder.cpp` loses our 5 lines. `dependencies.mk` is
  byte-identical.
- **RomM**, all 31 replayed onto `5.3.1` and onto `master`: clean both ways.
  Upstream touched 4 of our 11 files. `docker/Dockerfile` (6 commits) merges
  coherently, and our staged-EJS block replaces the new sha256-checked
  download. `Player.vue` (1 commit) gains only `purpose: "play"` on
  `getDownloadPath`. Also touched: `utils/index.ts` (3) and `.gitignore` (6).
- **romm `fix-quickload-undefined-state`** (the N64 draft): replays clean onto
  master. Issue #4476 is still open and unassigned.

## DECISION NEEDED before Task 3: master brings 6 database migrations

`5.3.1` adds no migrations over our base. `master` adds six, which run one-way
against the live `romm-db` at container start:

| Migration | Change |
|---|---|
| `0129` | `saves` and `states` gain `is_favorite` (NOT NULL, default false) and `labels` (nullable) |
| `0130`, `0131` | new `notifications` and `notification_channels` tables |
| `0132` | new `audit_events` table |
| `0133`, `0134` | gallery sort indexes on `roms` |

Consequence for rollback: the `:rollback` image would boot against a schema
it does not know. `init` logs "Failed to run database migrations" (unknown
revision `0134`) and carries on. The new columns all have defaults or are
nullable, so the old code should run, but that is untested. The safe rollback
is the old image **plus a database restore**, both done by Tristyn. Claude takes
the dump (a backup) but never restores it.

- **Recommended: `master`, as asked, with a `romm-db` dump taken first** (Task
  6, step 4).
- Alternative: the `5.3.1` tag. No migrations and a plain rollback, but it
  leaves 221 commits for a second rebase.

The `romm-latest` reference pair has its own `romm-latest-db`, so it is
unaffected either way.

---

## Task 1: Local backups (workstation, nothing pushed)

- [ ] **Step 1: tag the current tips**

```bash
git -C /home/user/git/scummvm-wasm/scummvm-core branch backup-pre-rebase-20260924 emulatorjs-wasm-fixes
git -C /home/user/git/romm branch backup-unraid-stage-pre-531-rebase unraid-stage-20260916
```

- [ ] **Step 2: confirm both working trees are clean**

```bash
git -C /home/user/git/scummvm-wasm/scummvm-core status --porcelain
git -C /home/user/git/romm switch unraid-stage-20260916 && git -C /home/user/git/romm status --porcelain
```

Expected: no output from either. (`docker/emulatorjs/` and
`docker/scummvm-core/` are ignored on the staging branch.)

## Task 2: Rebase scummvm-core and test-build the core

**Files:** `scummvm-core` history only. No source edits.

- [ ] **Step 1: rebase with the drops and the swap**

```bash
cd /home/user/git/scummvm-wasm/scummvm-core
git switch emulatorjs-wasm-fixes
GIT_EDITOR=true GIT_SEQUENCE_EDITOR="sed -i \
  -e '/^pick 8db1a349/d' -e '/^pick 7c27b2c5/d' -e '/^pick ee48dcdb/d' \
  -e '/^pick 456ea93f/d' \
  -e 's/^pick bf3c3aa8.*/pick 62923730255/'" \
  git rebase -i --onto origin/staging_master 364e70216ab
```

Expected: completes with no stops.

- [ ] **Step 2: prove the tree moved only where intended**

```bash
git diff --stat backup-pre-rebase-20260924 HEAD
git rev-list --count origin/staging_master..HEAD
git cherry upstream/master HEAD origin/staging_master | grep '^-'
```

Expected: `engines/chamber/cga.cpp | 10 -` and `video/avi_decoder.cpp | 5 -`,
and nothing else. A count of `38`. Exactly one `-` line, the CHAMBER commit,
which proves the swap is patch-identical to upstream's.

- [ ] **Step 3: all three build stages, then check the wasm is newer than the bitcode**

```bash
cd /home/user/git/scummvm-wasm
build/build-core.sh && build/build-retroarch-core.sh && build/package-core.sh
```

Expected: `package-core.sh` does not refuse the build (it refuses a wasm older
than the bitcode, `d05a74c`). Note the md5 of both `scummvm-thread*-wasm.data`
files for Task 6.

- [ ] **Step 4: bump the submodule pointer in the project repo**

```bash
cd /home/user/git/scummvm-wasm
git add scummvm-core
git commit -m "build: rebase the core onto staging_master and drop what upstream took" \
  -m "Assisted-by: Claude:claude-opus-5-5"
```

## Task 3: Rebase RomM onto master and check it locally

- [ ] **Step 1: rebase**

```bash
cd /home/user/git/romm
git rebase --onto upstream/master 8e61199d7 unraid-stage-20260916
```

Expected: 31 commits applied with no stops.

- [ ] **Step 2: confirm each of our commits survived as itself**

```bash
git range-diff 8e61199d7..backup-unraid-stage-pre-531-rebase upstream/master..unraid-stage-20260916
git cherry upstream/master unraid-stage-20260916 | grep -c '^-'
```

Expected: 31 pairs, each `=` or `!` with context-only changes, and a `-` count
of `0`. Read every `!` pair. `Dockerfile` and `Player.vue` are the ones that
can change meaning without conflicting.

- [ ] **Step 3: typecheck and unit tests** (`vite build` does not typecheck)

```bash
cd /home/user/git/romm/frontend
npm ci && npm run typecheck && npm test
```

Expected: typecheck clean, and vitest green. Our player tests passed 48/48
last time.

- [ ] **Step 4: carry-forward checks**

  - `docker/nginx/templates/default.conf.template` still holds the test-only
    no-cache block (issues #12 and #22). It stays for now and must come out
    before a release.
  - `docker/Dockerfile` still reads `ARG EMULATORJS_COMMIT=f4f0f1c`, matching
    `EJS_COMMIT` in `build/emulatorjs/assemble.sh`.

- [ ] **Step 5: bring the N64 draft branch along** (it stays unsubmitted)

```bash
git -C /home/user/git/romm rebase upstream/master fix-quickload-undefined-state
```

## Task 4: Project-repo housekeeping (one commit per item)

- [ ] `docs/pr/PR-DRAFTS.md`: commit the pending PR 28 and PR 29 drafts, which
      are uncommitted since the last session.
- [ ] PR 19: inline its one-line `consts.js` diff into `PR-DRAFTS.md`, then
      `git rm build/emulatorjs/patches/07-scummvm-requires-threads.patch`. It
      is PR 19's only copy of the diff, which is why it goes second.
- [ ] `docs/RELEASE-PLAN.md` §2.1: libretro-deps #15 MERGED 2026-09-19, the
      pin is upstream `e639e0c`, and there is no personal-fork dependency.
- [ ] `docs/GOTCHAS.md`: add the two corrections stranded on local branch
      `ejs-frontend-split` (`9ed9b4b`): rebase RomM locally, never on the
      mount; and `vite build` does not typecheck.
- [ ] `docs/REBASE-PLAN.md` and `docs/ROMM-REBASE-REVIEW.md`: add a first line
      pointing here.

## Task 5: Push (GitHub). Backups first, then leased force-pushes

```bash
git -C /home/user/git/scummvm-wasm/scummvm-core push fork backup-pre-rebase-20260924
git -C /home/user/git/scummvm-wasm/scummvm-core push --force-with-lease=emulatorjs-wasm-fixes:0b967c68bbe fork emulatorjs-wasm-fixes
git -C /home/user/git/romm push origin backup-unraid-stage-pre-531-rebase
git -C /home/user/git/romm push --force-with-lease=unraid-stage-20260916:4ec540182 origin unraid-stage-20260916
git -C /home/user/git/scummvm-wasm push github master
```

Then resync the stale launch-anchor copy:
`git -C "/mnt/unraid/Docs Photos and Files/AI Projects/scummvm-wasm" fetch github && git -C "/mnt/unraid/Docs Photos and Files/AI Projects/scummvm-wasm" reset --hard github/master`.

## Task 6: Build on Unraid

- [ ] **Step 1: move the box's checkout** (over ssh, on the box's own filesystem)

```bash
ssh root@big-z 'cd /mnt/user/Code/scummvm-wasm/romm-build && git fetch origin \
  && git status --porcelain && git checkout -B unraid-stage-20260916 origin/unraid-stage-20260916 \
  && git log -1 --oneline'
```

Expected: the rebased tip. No `--prune`, and never `git clean`: the staged
`docker/emulatorjs/` and `docker/scummvm-core/` are untracked on purpose.

- [ ] **Step 2: stage the new core.** EmulatorJS is unchanged, so this is core only.
      **BLOCKED on Tristyn's answer:** the script `rm -rf`s the staged
      `scummvm-engine-data/` on the share before copying (line 71). If
      deleting our own staged files is out too, change that line to copy over
      the top instead (`cp -f`), and do the same for `--ejs`'s `rsync --delete`.

```bash
/home/user/git/scummvm-wasm/build/deploy-to-romm.sh
```

- [ ] **Step 3: headroom.** Check the Docker vdisk with the unraid skill. Stop if it is tight.

- [x] **Step 4: database dump** (the decision above). A read-only backup,
      so Claude runs it, before handing over for the force-update. Done
      2026-09-24: 260 MB at revision 0128, md5 `a8b3fc47`. The app user is
      used because the root password may be random
      (`MARIADB_RANDOM_ROOT_PASSWORD` is set):

```bash
ssh root@big-z 'D=/mnt/user/Backups/Unraid/Docker/romm-db && mkdir -p $D && docker exec romm-db sh -c \
  '\''exec mariadb-dump --single-transaction --no-tablespaces -u"$MARIADB_USER" -p"$MARIADB_PASSWORD" "$MARIADB_DATABASE"'\'' \
  > $D/romm-db-pre-rebase-20260924.sql && chown -R tristyn:users $D && ls -la $D'
```

- [ ] **Step 5: retag, then build**

```bash
ssh root@big-z 'docker tag romm-scummvm:local romm-scummvm:rollback && \
  cd /mnt/user/Code/scummvm-wasm/romm-build && \
  docker build -f docker/Dockerfile --target full-image -t romm-scummvm:local .'
```

`:rollback` becomes `ab904bf82537` (round 10). The old `3227cb7131bc` is left
untagged, and goes on the orphan list.

- [ ] **Step 6: verify inside the image,** against the md5s from Task 2, Step 3.
      This starts a throwaway container from the new image; the running `/romm`
      is not touched.

```bash
ssh root@big-z 'docker run --rm --entrypoint md5sum romm-scummvm:local \
  /var/www/html/assets/emulatorjs/data/cores/scummvm-thread-wasm.data \
  /var/www/html/assets/emulatorjs/data/cores/scummvm-thread-legacy-wasm.data'
```

- [ ] **Step 7: orphans.** List the untagged `romm-scummvm` images, ask Tristyn,
      and hand him the `docker rmi` line if he says yes.

## Task 7: Round 11 (Tristyn force-updates `/romm`, then tests)

| # | Test | Why this round |
|---|---|---|
| 1 | Container log shows "Database migrations succeeded". Library lists, a scan runs, a ROM edit saves | RomM +384, 6 migrations, CSRF path |
| 2 | Zak: save, then load, both accepted on attempt 1 | regression canary across the whole stack |
| 3 | Zak: launch with a state from the RomM picker | `Player.vue` moved under us |
| 4 | Beavis and Butt-head in Virtual Stupidity boots into the game | our AVI fix is gone and upstream's #7935 now handles that path |
| 5 | Clear cache, then relaunch: core and ROM re-fetched | our `4ec540182` replayed onto new code |
| 6 | Regression list from `tests.list`: one toast per save, `[save]` lines with EJS_DEBUG on, mouse speed 0.2, N64 unchanged | standing |

TeenAgent, Orion Burger and KQ1 Amiga are not retested. They are covered by
#14 and #25, and nothing in this rebase touches them.

## Task 8: Branch cleanup, after round 11 passes

**Each GitHub deletion needs Tristyn's ok.** Local deletions are our own build
work. Branches marked *not ours* are libretro or RomM maintainer branches that
came across with the fork, or Tristyn's own work outside this project. None of
those are touched.

### GitHub

| Fork | Delete | Why |
|---|---|---|
| TRusselo/scummvm-scummvm | `libretro-keep-warning`, `libretro-log-unknown-game-report`, `libretro-osd-severity`, `libretro-deps-upstream-pin`, `chamber-hercules-path`, `scumm-getsavestatename` | PR merged (#110, #113, #116, #117, #7946, #7945) |
| | `libretro-exclude-webmidi`, `libretro-scan-vfs-root`, `glk-level9-detector-precedence`, `up-chamber-herc-guard`, `up-scumm-savestatename`, `up-avi-double-free`, `video-avi-loadstream-double-free` | PR closed. The scan-root code stays on the build branch |
| | `rebase/onto-current` | old work branch (Sep 6) |
| | `backup-pre-rebase-20260924` | once round 11 passes |
| | **keep** `emulatorjs-wasm-fixes`, `debug/fonts-oob-crash-diagnostics` | build branch; cited by the 2026-09-04 crash notes |
| | *not ours:* `add_SAF`, `test_xbox`, `threads_fixes`, `disable_glad`, `fix_indent`, `split_libdeps` | libretro maintainer branches |
| TRusselo/EmulatorJS | `fix-canvas-pointer-supports-mouse`, `fix-core-report-decode`, `fix-decompress-progress`, `fix-download-debug-logging` | PR merged |
| | `scummvm-wasm` | pre-split patch branch, superseded by `scummvm-wasm-split` |
| | `split-frontend-backend` | stale copy of upstream's branch (`8b135ea`; upstream's is `a29955a`) |
| | **keep** `scummvm-wasm-split`, `msg-severity`, `fix-missing-newlines`, `fix-core-url-versioning` | patch source of truth; #1270, #1272, #1273 |
| TRusselo/RetroArch | `fix-canvas-size-guard`, `ejs-v1222-20260910`, `backup-emulatorjs-wasm-fixes-20260910` | every commit already on `emulatorjs-wasm-fixes` |
| | **keep** `emulatorjs-wasm-fixes`, `add-scummvm-needsasync` | build branch; #48 |
| TRusselo/romm | `emulatorjs-wasm-fixes`, `emulatorjs-wasm-fixes-merged`, `emulatorjs-wasm-fixes-pre-merge-20260910` | older versions of what `unraid-stage` carries |
| | `fix/threaded-core-https-error-message` | #4313 merged |
| | `backup-unraid-stage-pre-csrf-rebase`; later `backup-unraid-stage-pre-531-rebase` | superseded once round 11 passes |
| | *not ours:* `claude/kind-goodall-0b77y7`, `feat/confirm-before-leaving-player`, `feat/files-scan-and-rom-folder-uploads`, `feat/retroarch-cloud-sync`, and the 38 mirrors | outside this project |
| TRusselo/libretro-deps | the whole fork, or at least `fix/wasm-autofit-signature-mismatch` | #15 merged; the fork's master equals upstream and nothing references it. Deleting a repo is Tristyn's call |

Optional, non-destructive: fast-forward the stale mirrors with
`gh repo sync TRusselo/EmulatorJS -b main` (16 behind),
`gh repo sync TRusselo/RetroArch -b v1.22.2` (4 behind), and the same for
`scummvm-scummvm` `staging_master`.

### Workstation

| Checkout | Delete |
|---|---|
| `scummvm-core` | `backup-pre-rebase-20260915`, `backup-pre-rebase-20260919`, `chamber-rebased` (the parked branch that gave a wrong TeenAgent answer), `diag-griffon-quit-save`, `libretro-deps-upstream-pin`, `libretro-exclude-webmidi`, `libretro-keep-warning`, `libretro-osd-severity`, `libretro-scan-vfs-root`, `pr-open-url`, `pr-unknown-report`, `resubmit/up-avi-double-free`, `resubmit/up-chamber-herc-guard`, `resubmit/up-scumm-savestatename`, `up-avi-double-free`, `up-chamber-herc-guard`, `up-scumm-savestatename`, `up-tinsel-discworld-variants`, `up-webmidi-libretro-guard`, and stale local `master`; plus both stashes (a generated `lite_engines.list` and a `configure` edit) |
| `retroarch` | `backup-pre-rebase-20260915`, `ejs-v1222-20260910`, `fix-canvas-size-guard`, stale `v1.22.2` and `next`. **Keep** `ejs-build-scummvm-arrays`, which is PR 12's code |
| `EmulatorJS` | `git worktree prune` (4 dead `/tmp` worktrees), the 4 merged-PR branches, stale `msg-severity` (the PR head is `msg-severity-v2`), and `scummvm-wasm` (its unpushed `6e8429c` is the pre-split patch 12). Fast-forward `main` |
| `romm` | `backup-pre-rebase-20260915`, `backup-pre-rebase-20260919`, `backup-pre-rebase2-20260916`, `emulatorjs-wasm-fixes`, `emulatorjs-wasm-fixes-pre-merge-20260910`, `fix/threaded-core-https-error-message`, `merge-upstream-20260910`, `rebased-on-upstream`, `stale-workspace-rebase-20260919` |
| `scummvm-wasm` | `ejs-frontend-split`, after Task 4 salvages its two notes |

### Unraid checkout (`/mnt/user/Code/scummvm-wasm/romm-build`)

Claude deletes nothing here. Stale, and harmless to leave: the local branches
`backup-pre-rebase-20260919`, `ejs-main` and `emulatorjs-wasm-fixes`, and
remote-tracking refs for branches since deleted on GitHub. If Tristyn wants
them gone, he runs:
`git -C /mnt/user/Code/scummvm-wasm/romm-build branch -D backup-pre-rebase-20260919 ejs-main emulatorjs-wasm-fixes && git -C /mnt/user/Code/scummvm-wasm/romm-build fetch --prune origin`.

## Task 9: Standing triggers (EmulatorJS; nothing to do today)

EmulatorJS `main` has not moved since our pin, so there is nothing to rebase.
When it does:

- **#1272 merges** (it is the one most likely to move `main`): rebase
  `scummvm-wasm-split` onto the new main in `/tmp/ejs-branch`, run
  `build/emulatorjs/export-patches.sh`, bump `EJS_COMMIT` in `assemble.sh`
  **and** `ARG EMULATORJS_COMMIT` in RomM's `docker/Dockerfile` together, then
  assemble and deploy with `--ejs=`.
- **#1270 merges**: drop patch 08, then re-check RomM's two severity commits
  (`fd73c12e2`, `958fd7966`) against the merged signature.
- **#1273 merges**: drop patch 12.
- **v4.3.0 is tagged**: nothing changes by itself. We pin commits, not
  releases.
