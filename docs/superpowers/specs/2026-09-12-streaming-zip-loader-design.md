# Streaming ROM loader for EmulatorJS ("unpack at the door")

**Status:** design, approved 2026-09-12. Not yet implemented.
**Problem:** [issue #5](https://github.com/TRusselo/scummvm-wasm/issues/5).
**Scope:** one new module plus small changes in `cache.js` and `emulator.js`.

## The problem

Five titles in the library cannot load at all. Not because of the core, the
engines or the dumps, but because of how EmulatorJS moves a ROM from the
network to the emulator's filesystem. Figures measured in issue #5.

| Title | Zip | Unpacked | Zip+unpacked | Fails on |
|---|---|---|---|---|
| Riven (CD Windows) | 2.036 GiB | 2.674 GiB | 4.711 GiB | rule 1, ArrayBuffer |
| Riven (DVD Windows) | 2.17 GiB | 2.74 GiB | — | rule 1, ArrayBuffer |
| Zork Grand Inquisitor (DVD) | 2.091 GiB | 2.359 GiB | 4.450 GiB | rule 1, ArrayBuffer |
| Gabriel Knight 2 (CD DOS) | 2.618 GiB | 3.343 GiB | 5.961 GiB | rule 1, ArrayBuffer |
| The Feeble Files (4CD Windows) | 1.996 GiB | 2.071 GiB | 4.067 GiB | rule 2, extractor heap |

For contrast, Phantasmagoria (1.787 GiB zip, 3.931 GiB combined) **plays**, and
sits 74 MB under rule 2. It is the practical ceiling today and the proof that
unpacked size alone predicts nothing: Zork GI unpacks *smaller* than
Phantasmagoria and still fails, because the zip size is what binds.

`cache.js`'s `downloadFile()` already streams the response into chunks and
builds a `Blob`, which is disk-backed and has no 2 GB limit. The next two
lines undo that:

```js
const blob = new Blob(chunks);
const ab = await blob.arrayBuffer();   // V8 caps an ArrayBuffer at ~2 GiB
data = new Uint8Array(ab);
```

That single buffer is then handed whole to the 7z wasm worker, whose 32-bit
heap must hold the archive *and* everything it inflates — the second ceiling,
around 4 GB combined. A third, smaller problem sits behind both: the worker
returns a `files[]` array holding every extracted file in memory at once,
before the caller writes any of them out.

## Why it is fixable at all

Emscripten's MEMFS stores each file as its own `Uint8Array` **on the JS side**
(`libmemfs.js`: `node.contents = new Uint8Array(newCapacity)`), not in the
core's wasm linear memory. Verified in the pinned toolchain, not assumed.

So the unpacked game does not compete with the core's 4 GB heap. Total
extracted size is bounded by browser RAM; each individual file has its own
2 GB ceiling that no game file approaches; the wasm heap only ever holds what
the engine is actively reading. Had MEMFS been backed by the wasm heap, no
amount of streaming would have helped and this design would be impossible.

## Approach

Three were considered:

- **A. Random access over the Blob via the zip central directory.** Chosen.
- **B. Forward-parse the response body while downloading.** Rejected: entries
  written by streaming writers carry their sizes in a trailing data descriptor,
  so a forward parser must handle the ambiguous case with no ability to seek
  back and recover. More failure modes, on archives we do not control.
- **C. Feed the wasm extractor incrementally, or move it to wasm64.** Rejected:
  its entry point takes one whole buffer, wasm64 is not broadly available, and
  it is by far the largest change to code we did not write.

A wins because the zip format already solved the hard parts. The central
directory sits at the end of the file and carries every entry's offset, sizes,
method and CRC, including 64-bit variants. Reading backwards makes zip64 nearly
free and sidesteps data descriptors entirely. Inflation uses a browser
primitive rather than shipping another decoder.

Its honest limit: stored and deflate only. 7z and rar above the threshold keep
today's behaviour, which is to fail. Every oversized title we have is a plain
zip, and ROMs are not normally distributed as rar or 7z, so this costs nothing
today and keeps the upstream diff small.

## Architecture

### Trigger

One branch in `downloadFile()`, at the line that breaks today. Take the
streaming path only when all of:

- `responseType === "arraybuffer"`
- the filename extension is `zip`
- total bytes exceed the threshold
- `DecompressionStream` exists

Otherwise, `blob.arrayBuffer()` exactly as now. **Everything below the
threshold, every non-zip, and every other core keeps its current behaviour
byte for byte.** That is the property that makes this reviewable upstream and
keeps the blast radius near zero for the other 180 cores.

Threshold: 1.5 GiB by default, safely under the 2 GiB cap, overridable at
runtime. The override is not a convenience — a size-gated branch is otherwise
the least-exercised code in the file, and forcing it on small ROMs is how it
gets tested at all.

### Files touched

| File | Change |
|---|---|
| `data/src/zipstream.js` | **new.** The zip reader. Knows nothing about EmulatorJS. |
| `data/src/cache.js` | `onFile` parameter; the streaming branch; `streamed` marker. |
| `data/src/emulator.js` | hoist `writeFilesToFS`; thread `onFile` through both download wrappers; widen the cache-item validity check. |

### The new unit

One self-contained module, `data/src/zipstream.js`, roughly 150 lines:

```
readZipEntries(blob, onEntry) -> Promise<void>
  onEntry(name, bytes) — called once per file, in central-directory order
```

It knows nothing about EmulatorJS, ROMs, cores or the filesystem. That is what
makes it unit-testable without a browser and reviewable on its own merits.

Responsibilities, in order:

1. Scan the last 64 KB backwards for the End of Central Directory signature.
2. If its fields are saturated (`0xFFFF`/`0xFFFFFFFF`), follow the zip64
   locator to the zip64 EOCD.
3. Walk the central directory, yielding per entry: name, method, compressed
   size, uncompressed size, CRC, local header offset, flags.
4. Per entry, read the local header to learn its variable name and extra field
   lengths, then slice exactly the compressed byte range.
5. Stored (method 0): pass through. Deflate (method 8): pipe through
   `DecompressionStream("deflate-raw")`.
6. Verify CRC32 against the central directory value.
7. Hand the bytes to `onEntry`, then drop the reference.

### Data flow

Today:

```
chunks[] -> Blob -> one Uint8Array (2 GiB cap) -> wasm worker (4 GiB cap)
         -> files[] holding everything at once -> writeFilesToFS per file
```

Streaming:

```
chunks[] -> Blob -> per entry: slice -> inflate -> writeFilesToFS -> release
```

Peak memory becomes the largest single file in the archive rather than the
archive plus its full expansion.

The streaming path performs its writes through the caller's existing
`writeFilesToFS` helper, threaded down as a new optional `onFile` callback. The
filesystem layout — directory creation, the trailing-slash directory-entry
case, the leading `/` — is therefore produced by the code that already does it
and cannot drift from the normal path.

**Correction, found while planning (2026-09-12).** An earlier draft of this
spec said the streaming path would resolve with an empty `files` list. That
cannot work: `emulator.js` treats an empty list as a failure —

```js
if (cacheItem.files && cacheItem.files.length > 0) { return { data: cacheItem, ... }; }
console.error("Invalid cache item returned:", cacheItem);
return -1;
```

so a streamed download would be reported as a network error. The cache item
therefore carries a `streamed = true` marker and that validity check is widened
to accept it. This is why the change touches `emulator.js` as well, and why the
diff is three modified files rather than one.

Threading `onFile` down requires one further move: `writeFilesToFS` is
currently defined *after* the download call in the same function, so it is
hoisted above it. It is a pure function of `this.gameManager.FS` and moving it
changes nothing else.

### Caching

The streaming path sets `dontCache`. Oversized titles re-download each launch;
everything under the threshold caches exactly as today. Rationale: holding the
archive is the thing being avoided, these titles do not load at all today so
any behaviour is an improvement, and it leaves the cache logic untouched.

## Failure handling

Every case ends in a message naming the file, not a stack trace.

| Case | Outcome |
|---|---|
| No EOCD found (truncated, or not a zip) | Fail, name the file. Falling back is pointless at this size; it would only die differently. |
| Method not stored or deflate | Fail that entry, name the method. This is the approach's honest limit and the message says so. |
| Encrypted entry (general purpose bit 0) | Fail, name the file. The old path cannot open these either. |
| `DecompressionStream` absent | Feature-detect before choosing the path; fall back to the existing one, restoring today's behaviour exactly, including today's failure for big files. |
| Inflate throws mid-entry | Fail, name the entry. Entries are independent, so the message points at one file. |
| CRC mismatch | Fail, name the entry. |

CRC verification is deliberate rather than incidental. The inflater rejects
malformed streams but not silent corruption, and this project has already lost
time to a dump that matched both its declared size and ScummVM's prefix hash
while being corrupt deeper in. It costs one pass over bytes already in hand.

Browser floor from the `DecompressionStream("deflate-raw")` requirement:
Chrome 103, Firefox 113, Safari 16.4. The README's documented minimums are
above all three.

## Testing

Three layers. The first is what makes this maintainable.

1. **Unit.** `readZipEntries` against fixture archives: stored, deflated,
   zip64, explicit directory entries, an entry with a data descriptor, a
   deliberately truncated file, and one with a corrupted CRC. No browser, no
   emulator, no large download.
2. **Forced path.** Threshold to zero, load an ordinary small ROM. Drives the
   whole streaming path end to end in seconds. This is how the path stays
   exercised rather than waiting on rare huge titles.
3. **Real target.** Riven (CD Windows), 2.04 GB, must reach gameplay with
   sound. Plus a regression check that a normal ROM at the default threshold
   still takes the untouched path, confirmed by the absence of the streaming
   log line.

## How it ships

`loader.js` serves unminified `data/src/*.js` when `EJS_DEBUG_XX` is true and
`emulator.min.js` otherwise. A patch to the source alone therefore works under
debug and silently does nothing in normal use — a trap worth stating plainly.

So: a patch file applied when the EmulatorJS tree is assembled, followed by the
project's own `npm run minify`, so both artifacts carry the change. The staged
tree at `docker/emulatorjs/` is in no repository (zero tracked files, 286 MB,
assembled onto the build box), so a hand-edit would vanish on the next assembly
with no trace. The patch file and the assembly step are the reproducible record.

## Sequence

1. Build and test locally against the staged tree.
2. Submit upstream to `EmulatorJS/EmulatorJS`, noting the benefit for
   multi-disc ScummVM titles specifically.
3. **If rejected:** gate the branch to fire only for the ScummVM core and fold
   it into the eventual ScummVM core submission. Only this step introduces a
   core-specific condition, which is why v1 must not contain one.

## What the new ceiling becomes

Both of issue #5's rules describe limits of the current path, and the streaming
path removes both: no single `ArrayBuffer` is ever made, and the wasm extractor
is not used for zips. What remains:

- **Total unpacked size must fit in browser RAM**, since MEMFS holds it as JS
  arrays. GK2 at 3.343 GiB is the largest case and is plausible on a desktop,
  untested.
- **No single file inside the archive may exceed 2 GiB**, the per-array cap. No
  game file approaches this.

So the honest claim is that the ceiling moves from roughly 2 GiB of *archive*
to available RAM for *unpacked content*. Issue #5's stated rules should be
rewritten once this is measured, not before.

## Out of scope

- 7z and rar above the threshold. They keep today's behaviour.
- Caching oversized ROMs. Decided against above.
- The core's own `.data` download, which has the same `arrayBuffer()` call but
  is 94 MB and nowhere near the ceiling.

