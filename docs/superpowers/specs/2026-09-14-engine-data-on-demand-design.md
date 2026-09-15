# On-demand engine-data for the WASM core

**Status:** design, not approved for implementation. Depends on an answer from
EmulatorJS (issue #1263) about whether they will publish a second artifact.

**Supersedes** the embed half of
`2026-09-02-wasm-engine-data-embed-design.md`. That design stays correct for
any build that keeps `--embed-file`; this one replaces it when the data ships
beside the core instead of inside it.

## Problem

The core `.data` is 94.3 MB. 73.8 MiB of that is ScummVM engine-data embedded
by `--embed-file` in `build/build-retroarch-core.sh:50`. EmulatorJS's largest
core is 7.9 MB.

The weight is concentrated:

| file | size | needed by |
|---|---|---|
| `fonts-cjk.dat` | 36.5 MiB | see "The font coupling" below -- not only CJK games |
| `ultima.dat` | 15.2 MiB | Ultima engine only |
| `fonts.dat` | 6.2 MiB | reachable from the launcher, before any game |
| the other 39 files | 15.9 MiB | one engine each |

Every player currently downloads all 42 files to play any one game.

## The font coupling

Verified 2026-09-14, and it bounds what any of this can win.

`fonts.dat` is not engine-scoped. `ThemeEngine::loadFont`
(`gui/ThemeEngine.cpp:1792`) falls back to it when the GUI theme does not carry
a requested font, which happens at launcher time before a game is chosen. It
belongs in an always-available set under every design here.

`fonts-cjk.dat` is worse. `graphics/fonts/ttf.cpp:972` opens it whenever a font
is **not found in fonts.dat** -- any font, not only CJK ones:

    if (!f->open(..., *archive)) {
        // Trying fonts-cjk.dat

SCUMM HE reaches that path by design. `engines/scumm/he/font_he.cpp:303`
probes a list of candidate font names, calling `loadTTFFontFromArchive` for
each; every candidate absent from `fonts.dat` falls through to the 36.5 MiB
file. So HE titles -- Backyard Baseball, Blue's Clues, Pajama Sam and the rest
of a large family -- pay for `fonts-cjk.dat` whether or not they display a
single CJK glyph.

Consequences:

- The in-memory cache means one fetch per session, not one per probe.
- HE games see roughly 16 MB + 6.2 MiB + 36.5 MiB. Better than 94 MB, far
  worse than the best case.
- Non-HE, non-Ultima, non-CJK games -- the large majority, including every
  SCUMM v1-v6 title, AGI, SCI and Sierra adventure -- see roughly 16 MB plus
  one small file.
- Splitting `fonts-cjk.dat` per typeface would fix the HE case, but it means
  repacking upstream data and is out of scope here.

## Goal

A player fetches the core plus only the engine-data their game needs.

Non-goals: changing how engine-data is produced, changing ScummVM's lookup
code, requiring network access at play time for a self-hosted deployment that
already has the files, or fetching from any third-party origin.

## Constraints

1. **Offline must keep working.** Self-hosted and air-gapped deployments are the
   EmulatorJS/ROMM norm. The files ship inside EmulatorJS's release archive and
   npm package like every other core artifact; "fetch" means from the same
   origin that served the core.
2. **No third-party origin.** Not `raw.githubusercontent.com`, not
   `scummvm.org`. Rejected for offline breakage, hotlinking someone else's
   infrastructure, and adding a cross-origin request to a player that many
   sites embed.
3. **No new hosting burden.** EmulatorJS's `build.sh:174` already does
   `git clone "$repo" --depth 1`, and `dists/engine-data/` is inside that
   clone. The data and the core come from the same commit by construction, so
   there is nothing to mirror and nothing that can drift.
4. **Filesystem syscalls are proxied to the main browser thread.** Verified in
   the linked core: `proxiedFunctionTable` contains `___syscall_openat`,
   `___syscall_stat64`, `___syscall_newfstatat`, `___syscall_fstat64`. This
   rules out `FS.createLazyFile`, whose size probe is a synchronous `HEAD`
   fired from a `stat()` that would execute on the main thread, where
   synchronous XHR aborts.
5. **Asyncify is available.** `ASYNC=1` is set at
   `build/build-retroarch-core.sh:54`, `asyncify_start_unwind` is present in
   the linked JS, and `emscripten_async_wget` is already linked in.

## Design C: fetch per file, through a Common::Archive

### Build

Stop passing `--embed-file`. Publish the staged directory
(`build/embed-staging/engine-data/`, produced by the existing `rsync` with its
existing exclusions) as 42 loose files next to the core, under
`cores/scummvm-engine-data/`. No archive format, no packing step.

The `rsync` exclusions stay exactly as they are. `fonts/` in particular is
65 MB of build input that ScummVM never reads at runtime.

### Runtime

`OSystem_libretro::addSysArchivesToSearchSet()` currently registers
`/engine-data` as a `Common::FSDirectory` (commit `f09251ff1d1`). Replace that
registration with a new archive:

```
class LibretroRemoteDirectory : public Common::Archive {
    bool hasFile(const Path &path) const override;
    int listMembers(ArchiveMemberList &list) const override;
    const ArchiveMemberPtr getMember(const Path &path) const override;
    SeekableReadStream *createReadStreamForMember(const Path &path) const override;
};
```

**Registration must do no I/O.** `SearchManager::clear()`
(`common/archive.cpp:658`) calls `addSysArchivesToSearchSet` from the
SearchManager constructor, guarded by `if (g_system)`. That can run before
RetroArch's log callback is piped to the frontend, so work done there is both
early and invisible. Verified 2026-09-14 by a throwaway probe that fetched at
registration time: the core neither hung nor crashed, but no request was issued
and no log surfaced. Register the archive, nothing more.

- A manifest of the 42 names and sizes is generated at build time and compiled
  into the core as a static table. `hasFile()` and `listMembers()` answer from
  it with no network access, so detection and engine startup never block on a
  round trip.
- `createReadStreamForMember()` is the only method that fetches. On first call
  for a name it downloads `<base>/<name>` into memory, caches it for the
  process lifetime, and returns a `MemoryReadStream`. Subsequent calls hit the
  cache.
- `<base>` comes from a new core option, defaulting to the directory the core
  was served from. Deployments that want the files elsewhere set it; nobody is
  forced to a particular layout.

ScummVM's own lookup (`Common::load_engine_data`, `common/engine_data.cpp`) is
untouched. It asks the search set for a file and gets a stream, exactly as it
does today from `FSDirectory`. This is the same trick `f09251ff1d1` already
plays, one level further in.

### Blocking

`createReadStreamForMember()` is synchronous by interface. The fetch is
`emscripten_async_wget` with Asyncify unwinding the stack until it completes.
This happens on the emu thread, inside `retro_run`.

`LibretroTimerManager::switchThread` is time-based, so the frontend keeps
getting frames while the engine is unwound; nothing new is drawn, which is the
same visible behaviour as a long save-state wait. For a 36.5 MiB file that is
a multi-second stall with no progress indication.

**Mitigation:** report progress through the same file channel the save-state
work uses (`/savestate_error.txt` pattern, `libretro-core.cpp`), so the
frontend can render a real message rather than appearing hung.

## Measured, 2026-09-14

Built and run against five games on the standalone rig. Core dropped from
90.0 MB to **23.5 MB** (the spec's earlier ~16 MB estimate was wrong: the data
compressed better inside the wasm than subtracting raw sizes suggested).

| game | engine-data fetched |
|---|---|
| TeenAgent | `teenagent.dat` (403 KB) |
| Kyrandia | `kyra.dat` (2.0 MB) |
| Lure of the Temptress | `lure.dat` |
| Pajama Sam (HE) | none |
| Ultima VIII | none |

Every fetch matched its manifest size exactly. `kyra.dat` was requested and
returned inside the same log second, and was not perceptible in play -- over
loopback. That is not evidence about a 36.5 MB transfer on a real connection;
the progress-reporting mitigation is still required before `fonts-cjk.dat` can
be fetched this way.

Pajama Sam fetching nothing is worth noting against "The font coupling" above:
the HE font probe did not reach `fonts-cjk.dat` for that title. The coupling is
real in the code but its frequency is unmeasured.

### Every startup pays for the theme scan

`ThemeEngine::listUsableThemes` (`gui/ThemeEngine.cpp:2040`) scans the search
set for `*.zip` and opens each match to test it for a `THEMERC` member:

    archive.listMatchingMembers(fileList, "*.zip");
    ...
    Common::Archive *zipArchive = Common::makeZipArchive(member.createReadStream());

Engine-data holds two zips, `helpdialog.zip` (207 KB) and `wintermute.zip`
(4.5 KB), so both are fetched on every launch regardless of game -- 212 KB for
nothing. The embedded build did the same scan; it was free because the files
were local.

Fix: omit `.zip` from `listMembers()` while leaving `hasFile()`, `getMember()`
and `createReadStreamForMember()` answering for exact names. Theme scanning
stops fetching and Wintermute still gets its zip when it asks for it by name.
Not yet implemented -- the measurements above are from the build without it.

## Design B: two tiers (fallback)

If Asyncify blocking inside `retro_run` proves unsafe, or if per-file latency
over 42 files is worse than a single transfer:

- Bundle the 40 small files (22.1 MiB) into one archive, fetched once at core
  startup before any game runs. No blocking mid-`retro_run`.
- Fetch `fonts-cjk.dat` and `ultima.dat` on demand, as in C.

Common case becomes roughly 38 MB instead of 94 MB, versus roughly 16 MB plus
one small file for C. B needs no manifest and no per-file archive, only two
hardcoded names.

B is a strict subset of C's machinery: the same fetch-and-cache path, applied
to two names instead of 42.

## Design A: one sidecar (rejected as an end state)

Core plus one 74 MB archive. First play transfers the same total as today, so
it buys players nothing. Recorded only because it is the smallest possible
change and may be what EmulatorJS prefers; if so, take it and stop.

## What EmulatorJS has to do

For C and B: publish one more artifact from a build they already run, next to
`ppsspp-assets.zip`, which is the existing precedent for a core with a
companion payload. `makeoptions.custom` + `build_command` (`build.sh:189`) is
the supported hook.

They write no loader code. The core fetches from its own directory. This is
the difference between this design and the `loadPpssppAssets()` shape, which
needs a hardcoded `if (this.getCore() === "scummvm")` branch in
`emulator.js` that they would carry forever.

## Risks

| risk | handling |
|---|---|
| Asyncify unwind inside `retro_run` destabilises the frame loop | Still unverified. `emscripten_wget_data` links cleanly and its presence does not destabilise startup, but the probe was misplaced (I/O at registration, which this design forbids) so the fetch never fired. The valid probe hangs a fetch off a real `createReadStreamForMember` call. Falls back to B. |
| 42 sequential fetches are slower than one transfer | Only files an engine actually needs are fetched, usually one. Falls back to B. |
| A deployment serves the core but not the data directory | `hasFile()` answers from the manifest, so the failure surfaces as a fetch error at engine start, not as a silent missing-feature. Needs a clear message. |
| Upstream adds or renames an engine-data file | The manifest is generated at build time from the same clone, so it cannot drift. |
| EmulatorJS declines to publish a second artifact | Keep `--embed-file`. This design is shelved, not abandoned. |

## Open questions

1. Does Asyncify unwinding inside `retro_run` hold up in practice? Decides C
   versus B, and nothing else in the design depends on the answer.
2. Should the manifest carry sizes as well as names? Sizes let the fetch
   pre-allocate and let a progress message state a total; they also mean a
   mismatched deployment is detectable before the transfer completes.
3. ~~Does any engine-data file get read during detection?~~ **Answered
   2026-09-14.** Not during detection -- no `load_engine_data` call is
   reachable from detection code. But `fonts.dat` is reachable from the
   launcher GUI, so it joins the always-available set. See "The font
   coupling".
