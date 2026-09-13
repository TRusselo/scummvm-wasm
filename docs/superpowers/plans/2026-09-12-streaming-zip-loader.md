# Streaming ROM Loader Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let EmulatorJS load ROM archives larger than 2 GiB by reading the zip's central directory and inflating one entry at a time, instead of buffering the whole archive into a single `ArrayBuffer` and handing it to a 32-bit wasm extractor.

**Architecture:** A standalone zip reader (`zipstream.js`) takes a `Blob` and emits one file at a time via callback. `cache.js` calls it instead of `blob.arrayBuffer()` when a download is a zip over a size threshold. `emulator.js` threads its existing filesystem-write helper down as that callback. Everything under the threshold takes the current path unchanged.

**Tech Stack:** Plain ES modules, no dependencies. Browser/Node built-ins only: `Blob`, `DecompressionStream("deflate-raw")`, `DataView`. Node 24 for headless tests (it has all three). EmulatorJS has **no test framework** — tests are plain `node` scripts that exit non-zero on failure.

**Spec:** `docs/superpowers/specs/2026-09-12-streaming-zip-loader-design.md` — read it first.

## Global Constraints

- **Work on branch `streaming-zip-loader`, never on `master`.** This modifies vendored third-party code and may be abandoned.
- **No ScummVM-specific or core-specific conditions in any code.** The fallback plan (gate to our core only) happens *after* an upstream rejection, not before. A core check in v1 poisons the PR.
- **Below the threshold, behaviour must be byte-for-byte identical to today.** This is the property that makes the change reviewable upstream and safe for the other 180 cores.
- **Target EmulatorJS commit: `0b1c5e9`.** All line numbers and code quoted below are from that commit.
- Threshold default: `1610612736` bytes (1.5 GiB). Overridable via `window.EJS_streamZipThreshold`.
- Supported methods: `0` (stored) and `8` (deflate) only.
- Every error message must name the file or entry it refers to.
- Commit after every task. Commit messages end with `Assisted-by: Claude:claude-opus-5`.

## File Structure

All new files live in **our** repo (`scummvm-wasm`), not in the EmulatorJS tree. The assembly script copies/patches them in.

| File | Responsibility |
|---|---|
| `build/emulatorjs/src/zipstream.js` | The zip reader. Pure; no EmulatorJS knowledge. Copied to `data/src/zipstream.js`. |
| `build/emulatorjs/test/make-fixtures.mjs` | Generates fixture zips. No binaries committed. |
| `build/emulatorjs/test/zipstream.test.mjs` | Headless test runner. Exits non-zero on failure. |
| `build/emulatorjs/patches/*.patch` | Diffs against `cache.js` and `emulator.js`. |
| `build/emulatorjs/assemble.sh` | Clone pinned EJS, copy module, apply patches, `npm ci`, `npm run minify`, stage. |

---

### Task 1: Fixture generator

Builds the zips every later task tests against. Writing zips by hand is the only way to produce the awkward cases (zip64, truncation, bad CRC) reliably.

**Files:**
- Create: `build/emulatorjs/test/make-fixtures.mjs`

**Interfaces:**
- Produces: fixture files in `build/emulatorjs/test/fixtures/`, regenerated on every run. Each fixture is described below by name and expected content, and later tasks reference them by those names.

- [ ] **Step 1: Write the generator**

```js
// build/emulatorjs/test/make-fixtures.mjs
// Regenerates test fixtures. Run: node build/emulatorjs/test/make-fixtures.mjs
import { mkdirSync, writeFileSync, rmSync } from "node:fs";
import { deflateRawSync, crc32 } from "node:zlib";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const DIR = join(dirname(fileURLToPath(import.meta.url)), "fixtures");

// Minimal zip writer. Not general purpose -- it exists to produce exactly the
// shapes the reader must cope with, including malformed ones.
function u16(n) { const b = Buffer.alloc(2); b.writeUInt16LE(n); return b; }
function u32(n) { const b = Buffer.alloc(4); b.writeUInt32LE(n >>> 0); return b; }
function u64(n) { const b = Buffer.alloc(8); b.writeBigUInt64LE(BigInt(n)); return b; }

// entries: [{ name, data: Buffer, store?: bool, crcOverride?: number }]
// opts: { zip64?: bool, comment?: string }
function makeZip(entries, opts = {}) {
  const locals = [];
  const centrals = [];
  let offset = 0;

  for (const e of entries) {
    const isDir = e.name.endsWith("/");
    const raw = isDir ? Buffer.alloc(0) : e.data;
    const store = isDir || e.store === true;
    const comp = store ? raw : deflateRawSync(raw);
    const crc = e.crcOverride !== undefined ? e.crcOverride : crc32(raw);
    const nameBuf = Buffer.from(e.name, "utf8");

    const local = Buffer.concat([
      u32(0x04034b50), u16(20), u16(0), u16(store ? 0 : 8),
      u16(0), u16(0), u32(crc), u32(comp.length), u32(raw.length),
      u16(nameBuf.length), u16(0), nameBuf, comp,
    ]);
    locals.push(local);

    // Zip64 marks the 32-bit fields saturated and moves the real values into
    // the extra field. Exercised by the zip64 fixture even though the file is
    // small -- the reader must follow the pointer, not guess from size.
    const extra = opts.zip64
      ? Buffer.concat([u16(0x0001), u16(24), u64(raw.length), u64(comp.length), u64(offset)])
      : Buffer.alloc(0);

    centrals.push(Buffer.concat([
      u32(0x02014b50), u16(20), u16(20), u16(0), u16(store ? 0 : 8),
      u16(0), u16(0), u32(crc),
      u32(opts.zip64 ? 0xFFFFFFFF : comp.length),
      u32(opts.zip64 ? 0xFFFFFFFF : raw.length),
      u16(nameBuf.length), u16(extra.length), u16(0), u16(0), u16(0), u32(0),
      u32(opts.zip64 ? 0xFFFFFFFF : offset),
      nameBuf, extra,
    ]));
    offset += local.length;
  }

  const cd = Buffer.concat(centrals);
  const cdOffset = offset;
  const parts = [Buffer.concat(locals), cd];

  if (opts.zip64) {
    parts.push(Buffer.concat([
      u32(0x06064b50), u64(44), u16(45), u16(45), u32(0), u32(0),
      u64(entries.length), u64(entries.length), u64(cd.length), u64(cdOffset),
    ]));
    parts.push(Buffer.concat([
      u32(0x07064b50), u32(0), u64(cdOffset + cd.length), u32(1),
    ]));
  }

  const comment = Buffer.from(opts.comment || "", "utf8");
  parts.push(Buffer.concat([
    u32(0x06054b50), u16(0), u16(0),
    u16(opts.zip64 ? 0xFFFF : entries.length),
    u16(opts.zip64 ? 0xFFFF : entries.length),
    u32(opts.zip64 ? 0xFFFFFFFF : cd.length),
    u32(opts.zip64 ? 0xFFFFFFFF : cdOffset),
    u16(comment.length), comment,
  ]));

  return Buffer.concat(parts);
}

const HELLO = Buffer.from("hello world\n", "utf8");
// Deliberately compressible, and big enough that deflate actually shrinks it.
const BIG = Buffer.from("A".repeat(200000), "utf8");

rmSync(DIR, { recursive: true, force: true });
mkdirSync(DIR, { recursive: true });

const write = (name, buf) => { writeFileSync(join(DIR, name), buf); console.log(`  ${name}  ${buf.length} bytes`); };

console.log("fixtures:");

// 1. plain deflate, two files
write("deflate.zip", makeZip([
  { name: "hello.txt", data: HELLO },
  { name: "big.txt", data: BIG },
]));

// 2. stored (method 0), no compression
write("stored.zip", makeZip([{ name: "hello.txt", data: HELLO, store: true }]));

// 3. explicit directory entries -- the ENOTDIR class of bug
write("dirs.zip", makeZip([
  { name: "sub/", data: Buffer.alloc(0) },
  { name: "sub/nested/", data: Buffer.alloc(0) },
  { name: "sub/nested/hello.txt", data: HELLO },
]));

// 4. zip64 -- 32-bit fields saturated, real values in the extra field
write("zip64.zip", makeZip([{ name: "hello.txt", data: HELLO }], { zip64: true }));

// 5. a trailing comment, so the EOCD is not at the very end
write("comment.zip", makeZip([{ name: "hello.txt", data: HELLO }], { comment: "x".repeat(300) }));

// 6. truncated -- last 100 bytes lopped off, so no EOCD survives
const good = makeZip([{ name: "hello.txt", data: HELLO }]);
write("truncated.zip", good.subarray(0, good.length - 100));

// 7. wrong CRC recorded for an otherwise valid entry
write("badcrc.zip", makeZip([{ name: "hello.txt", data: HELLO, crcOverride: 0x12345678 }]));

// 8. not a zip at all
write("notazip.bin", Buffer.from("this is not a zip file", "utf8"));

console.log("done ->", DIR);
```

- [ ] **Step 2: Run it**

Run: `node build/emulatorjs/test/make-fixtures.mjs`
Expected: eight lines listing fixture names and byte counts, then `done -> .../fixtures`.

- [ ] **Step 3: Sanity-check the generator against a real unzip**

Run: `cd build/emulatorjs/test/fixtures && unzip -t deflate.zip && unzip -t dirs.zip && unzip -t zip64.zip`
Expected: `No errors detected` for all three. If `unzip` rejects them, the generator is wrong and every later test would be validating against a broken fixture.

- [ ] **Step 4: Ignore the fixtures, commit the generator**

```bash
echo "build/emulatorjs/test/fixtures/" >> .gitignore
git add build/emulatorjs/test/make-fixtures.mjs .gitignore
git commit -m "test: zip fixture generator for the streaming loader

Assisted-by: Claude:claude-opus-5"
```

---

### Task 2: Central directory parsing

Locating and reading the index. No decompression yet — this task answers "what is in this archive and where", which is the half of the format that makes approach A work.

**Files:**
- Create: `build/emulatorjs/src/zipstream.js`
- Create: `build/emulatorjs/test/zipstream.test.mjs`

**Interfaces:**
- Produces: `readCentralDirectory(blob) -> Promise<Entry[]>` where
  `Entry = { name: string, method: number, flags: number, crc: number, compressedSize: number, uncompressedSize: number, localOffset: number }`.
  Exported for tests. Task 3 consumes it.

- [ ] **Step 1: Write the failing test**

```js
// build/emulatorjs/test/zipstream.test.mjs
import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { readCentralDirectory } from "../src/zipstream.js";

const DIR = join(dirname(fileURLToPath(import.meta.url)), "fixtures");
const blobOf = (name) => new Blob([readFileSync(join(DIR, name))]);

let failures = 0;
function check(name, fn) {
  return fn().then(
    () => console.log(`  ok    ${name}`),
    (e) => { failures++; console.error(`  FAIL  ${name}\n        ${e.message}`); }
  );
}
function eq(actual, expected, what) {
  const a = JSON.stringify(actual), b = JSON.stringify(expected);
  if (a !== b) throw new Error(`${what}: got ${a}, want ${b}`);
}

await check("lists both entries of a deflate zip", async () => {
  const e = await readCentralDirectory(blobOf("deflate.zip"));
  eq(e.map(x => x.name), ["hello.txt", "big.txt"], "names");
  eq(e[0].method, 8, "method");
  eq(e[1].uncompressedSize, 200000, "uncompressedSize");
});

await check("reads a stored entry", async () => {
  const e = await readCentralDirectory(blobOf("stored.zip"));
  eq(e[0].method, 0, "method");
  eq(e[0].compressedSize, e[0].uncompressedSize, "stored sizes equal");
});

await check("keeps explicit directory entries", async () => {
  const e = await readCentralDirectory(blobOf("dirs.zip"));
  eq(e.map(x => x.name), ["sub/", "sub/nested/", "sub/nested/hello.txt"], "names");
});

await check("follows the zip64 pointer", async () => {
  const e = await readCentralDirectory(blobOf("zip64.zip"));
  eq(e.length, 1, "entry count");
  eq(e[0].name, "hello.txt", "name");
  eq(e[0].uncompressedSize, 12, "uncompressedSize from the extra field");
});

await check("finds the EOCD behind a trailing comment", async () => {
  const e = await readCentralDirectory(blobOf("comment.zip"));
  eq(e[0].name, "hello.txt", "name");
});

await check("rejects a truncated archive by name", async () => {
  try {
    await readCentralDirectory(blobOf("truncated.zip"));
  } catch (err) {
    if (!/end of central directory/i.test(err.message)) throw new Error(`wrong message: ${err.message}`);
    return;
  }
  throw new Error("expected a throw");
});

await check("rejects a non-zip by name", async () => {
  try {
    await readCentralDirectory(blobOf("notazip.bin"));
  } catch (err) {
    if (!/end of central directory/i.test(err.message)) throw new Error(`wrong message: ${err.message}`);
    return;
  }
  throw new Error("expected a throw");
});

console.log(failures ? `\n${failures} failure(s)` : "\nall passed");
process.exit(failures ? 1 : 0);
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `node build/emulatorjs/test/zipstream.test.mjs`
Expected: FAIL — `Cannot find module .../src/zipstream.js`.

- [ ] **Step 3: Implement the parser**

```js
// build/emulatorjs/src/zipstream.js
//
// Streaming zip reader. Reads the central directory from the tail of a Blob,
// then extracts entries one at a time so the whole archive is never held in
// memory. Supports stored (0) and deflate (8) entries, including zip64.
//
// No EmulatorJS dependencies by design: it takes a Blob and emits files.

const SIG_EOCD = 0x06054b50;
const SIG_EOCD64 = 0x06064b50;
const SIG_EOCD64_LOC = 0x07064b50;
const SIG_CENTRAL = 0x02014b50;
const EOCD_MIN = 22;
const MAX_COMMENT = 0xFFFF;

async function bytesOf(blob, start, end) {
  return new Uint8Array(await blob.slice(start, end).arrayBuffer());
}

// The EOCD sits at the end, but a trailing comment of up to 64 KB can follow
// it, so scan backwards for the signature rather than assuming a position.
async function findEocd(blob) {
  const scan = Math.min(blob.size, MAX_COMMENT + EOCD_MIN);
  if (scan < EOCD_MIN) throw new Error("zip: file is too small to contain an end of central directory record");
  const base = blob.size - scan;
  const buf = await bytesOf(blob, base, blob.size);
  const dv = new DataView(buf.buffer);
  for (let i = buf.length - EOCD_MIN; i >= 0; i--) {
    if (dv.getUint32(i, true) === SIG_EOCD) return { dv, at: i, base };
  }
  throw new Error("zip: no end of central directory record found (truncated or not a zip archive)");
}

export async function readCentralDirectory(blob) {
  const { dv, at, base } = await findEocd(blob);

  let count = dv.getUint16(at + 10, true);
  let cdSize = dv.getUint32(at + 12, true);
  let cdOffset = dv.getUint32(at + 16, true);

  // Any saturated field means the real values live in the zip64 records.
  if (count === 0xFFFF || cdSize === 0xFFFFFFFF || cdOffset === 0xFFFFFFFF) {
    const locAt = at - 20;
    if (locAt < 0 || dv.getUint32(locAt, true) !== SIG_EOCD64_LOC) {
      throw new Error("zip: archive claims zip64 but its locator record is missing");
    }
    const eocd64At = Number(dv.getBigUint64(locAt + 8, true));
    const head = await bytesOf(blob, eocd64At, eocd64At + 56);
    const hdv = new DataView(head.buffer);
    if (hdv.getUint32(0, true) !== SIG_EOCD64) {
      throw new Error("zip: zip64 locator points at something that is not a zip64 end of central directory record");
    }
    count = Number(hdv.getBigUint64(32, true));
    cdSize = Number(hdv.getBigUint64(40, true));
    cdOffset = Number(hdv.getBigUint64(48, true));
  }

  const cd = await bytesOf(blob, cdOffset, cdOffset + cdSize);
  const cdv = new DataView(cd.buffer);
  const entries = [];
  let p = 0;

  for (let i = 0; i < count; i++) {
    if (cdv.getUint32(p, true) !== SIG_CENTRAL) {
      throw new Error(`zip: central directory entry ${i} has a bad signature`);
    }
    const flags = cdv.getUint16(p + 8, true);
    const method = cdv.getUint16(p + 10, true);
    const crc = cdv.getUint32(p + 16, true);
    let compressedSize = cdv.getUint32(p + 20, true);
    let uncompressedSize = cdv.getUint32(p + 24, true);
    const nameLen = cdv.getUint16(p + 28, true);
    const extraLen = cdv.getUint16(p + 30, true);
    const commentLen = cdv.getUint16(p + 32, true);
    let localOffset = cdv.getUint32(p + 42, true);
    const name = new TextDecoder().decode(cd.subarray(p + 46, p + 46 + nameLen));

    // Zip64 extra field: present values appear in a fixed order, but only for
    // the fields that were saturated above.
    if (extraLen) {
      const exStart = p + 46 + nameLen;
      let q = exStart;
      const exEnd = exStart + extraLen;
      while (q + 4 <= exEnd) {
        const id = cdv.getUint16(q, true);
        const size = cdv.getUint16(q + 2, true);
        if (id === 0x0001) {
          let r = q + 4;
          if (uncompressedSize === 0xFFFFFFFF) { uncompressedSize = Number(cdv.getBigUint64(r, true)); r += 8; }
          if (compressedSize === 0xFFFFFFFF) { compressedSize = Number(cdv.getBigUint64(r, true)); r += 8; }
          if (localOffset === 0xFFFFFFFF) { localOffset = Number(cdv.getBigUint64(r, true)); r += 8; }
          break;
        }
        q += 4 + size;
      }
    }

    entries.push({ name, method, flags, crc, compressedSize, uncompressedSize, localOffset });
    p += 46 + nameLen + extraLen + commentLen;
  }

  return entries;
}
```

- [ ] **Step 4: Run the test to confirm it passes**

Run: `node build/emulatorjs/test/zipstream.test.mjs`
Expected: seven `ok` lines, then `all passed`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add build/emulatorjs/src/zipstream.js build/emulatorjs/test/zipstream.test.mjs
git commit -m "zipstream: read the zip central directory, including zip64

Assisted-by: Claude:claude-opus-5"
```

---

### Task 3: Entry extraction

Turning an index entry into bytes: seek past the local header, slice the compressed range, inflate, verify.

**Files:**
- Modify: `build/emulatorjs/src/zipstream.js`
- Modify: `build/emulatorjs/test/zipstream.test.mjs`

**Interfaces:**
- Consumes: `readCentralDirectory(blob)` from Task 2.
- Produces: `readZipEntries(blob, onEntry) -> Promise<number>`, resolving with the number of entries emitted. `onEntry(name, bytes)` is called once per entry in central-directory order; `bytes` is a `Uint8Array`, empty for directory entries (names ending `/`). Task 5 consumes this.

- [ ] **Step 1: Write the failing test (append to the existing file, above the summary lines)**

```js
// --- Task 3 additions: append before the `console.log(failures ...)` line ---
import { readZipEntries } from "../src/zipstream.js";

const collect = async (name) => {
  const out = [];
  const n = await readZipEntries(blobOf(name), (f, b) => out.push([f, Buffer.from(b).toString("utf8")]));
  return { out, n };
};

await check("extracts deflated content", async () => {
  const { out, n } = await collect("deflate.zip");
  eq(n, 2, "count");
  eq(out[0], ["hello.txt", "hello world\n"], "first entry");
  eq(out[1][1].length, 200000, "second entry length");
});

await check("extracts stored content", async () => {
  const { out } = await collect("stored.zip");
  eq(out[0], ["hello.txt", "hello world\n"], "entry");
});

await check("emits directory entries with empty bytes", async () => {
  const { out } = await collect("dirs.zip");
  eq(out.map(x => x[0]), ["sub/", "sub/nested/", "sub/nested/hello.txt"], "names");
  eq(out[0][1], "", "directory payload is empty");
  eq(out[2][1], "hello world\n", "file payload");
});

await check("extracts a zip64 entry", async () => {
  const { out } = await collect("zip64.zip");
  eq(out[0], ["hello.txt", "hello world\n"], "entry");
});

await check("rejects a CRC mismatch by entry name", async () => {
  try {
    await collect("badcrc.zip");
  } catch (err) {
    if (!/hello\.txt/.test(err.message) || !/crc/i.test(err.message)) {
      throw new Error(`wrong message: ${err.message}`);
    }
    return;
  }
  throw new Error("expected a throw");
});
```

- [ ] **Step 2: Run to confirm the new checks fail**

Run: `node build/emulatorjs/test/zipstream.test.mjs`
Expected: FAIL — `readZipEntries` is not exported.

- [ ] **Step 3: Implement extraction**

```js
// Append to build/emulatorjs/src/zipstream.js

const SIG_LOCAL = 0x04034b50;
const METHOD_STORE = 0;
const METHOD_DEFLATE = 8;
const FLAG_ENCRYPTED = 0x0001;

const CRC_TABLE = (() => {
  const t = new Uint32Array(256);
  for (let i = 0; i < 256; i++) {
    let c = i;
    for (let k = 0; k < 8; k++) c = (c & 1) ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
    t[i] = c >>> 0;
  }
  return t;
})();

function crc32(bytes) {
  let c = 0xFFFFFFFF;
  for (let i = 0; i < bytes.length; i++) c = CRC_TABLE[(c ^ bytes[i]) & 0xFF] ^ (c >>> 8);
  return (c ^ 0xFFFFFFFF) >>> 0;
}

async function inflateRaw(blob, name) {
  try {
    const stream = blob.stream().pipeThrough(new DecompressionStream("deflate-raw"));
    return new Uint8Array(await new Response(stream).arrayBuffer());
  } catch (e) {
    throw new Error(`zip: failed to decompress "${name}": ${e.message}`);
  }
}

export function streamingSupported() {
  return typeof DecompressionStream === "function" && typeof Blob !== "undefined";
}

export async function readZipEntries(blob, onEntry) {
  const entries = await readCentralDirectory(blob);

  for (const e of entries) {
    if (e.flags & FLAG_ENCRYPTED) {
      throw new Error(`zip: "${e.name}" is encrypted, which is not supported`);
    }

    if (e.name.endsWith("/")) {
      onEntry(e.name, new Uint8Array(0));
      continue;
    }

    if (e.method !== METHOD_STORE && e.method !== METHOD_DEFLATE) {
      throw new Error(`zip: "${e.name}" uses compression method ${e.method}; only stored and deflate are supported`);
    }

    // The central directory's name and extra lengths need not match the local
    // header's, so the data offset must come from the local header itself.
    const head = new Uint8Array(await blob.slice(e.localOffset, e.localOffset + 30).arrayBuffer());
    const hdv = new DataView(head.buffer);
    if (hdv.getUint32(0, true) !== SIG_LOCAL) {
      throw new Error(`zip: "${e.name}" has a bad local header signature`);
    }
    const dataStart = e.localOffset + 30 + hdv.getUint16(26, true) + hdv.getUint16(28, true);
    const slice = blob.slice(dataStart, dataStart + e.compressedSize);

    const bytes = e.method === METHOD_STORE
      ? new Uint8Array(await slice.arrayBuffer())
      : await inflateRaw(slice, e.name);

    if (bytes.length !== e.uncompressedSize) {
      throw new Error(`zip: "${e.name}" unpacked to ${bytes.length} bytes, expected ${e.uncompressedSize}`);
    }
    if (crc32(bytes) !== e.crc) {
      throw new Error(`zip: "${e.name}" failed its CRC check (archive is corrupt)`);
    }

    onEntry(e.name, bytes);
  }

  return entries.length;
}
```

- [ ] **Step 4: Run to confirm all pass**

Run: `node build/emulatorjs/test/zipstream.test.mjs`
Expected: twelve `ok` lines, `all passed`, exit 0.

- [ ] **Step 5: Lint against EmulatorJS's own config**

Run: `cd /tmp && git clone -q --depth 1 https://github.com/EmulatorJS/EmulatorJS ejs-lint && cd ejs-lint && npm ci --silent && npx eslint "$OLDPWD/build/emulatorjs/src/zipstream.js"`
Expected: no errors. The file ships inside their tree and must satisfy their linter, or the PR starts with review noise.

- [ ] **Step 6: Commit**

```bash
git add build/emulatorjs/src/zipstream.js build/emulatorjs/test/zipstream.test.mjs
git commit -m "zipstream: extract entries with DecompressionStream and verify CRCs

Assisted-by: Claude:claude-opus-5"
```

---

### Task 4: Memory proof

The entire point of the change is the memory profile. This task proves it, because nothing in Tasks 2 and 3 would fail if the implementation quietly buffered everything.

**Files:**
- Create: `build/emulatorjs/test/make-big-fixture.mjs`
- Create: `build/emulatorjs/test/memory.test.mjs`

**Interfaces:**
- Consumes: `readZipEntries` from Task 3.

**Step order:** write the generator (Step 2) *before* the test that invokes it
(Step 1), or the first run fails with ENOENT.

- [ ] **Step 1: Write the test**

```js
// build/emulatorjs/test/memory.test.mjs
// Proves the reader's peak memory tracks the largest single entry, not the
// archive. Run with: node --expose-gc build/emulatorjs/test/memory.test.mjs
import { deflateRawSync } from "node:zlib";
import { execFileSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { readZipEntries } from "../src/zipstream.js";

const HERE = dirname(fileURLToPath(import.meta.url));

// 40 entries x 8 MB = 320 MB of content in one archive. Large enough that
// buffering everything is unmistakable in the numbers, small enough to run
// in CI in seconds.
execFileSync(process.execPath, [join(HERE, "make-big-fixture.mjs")], { stdio: "inherit" });
const buf = readFileSync(join(HERE, "fixtures", "big-many.zip"));
const blob = new Blob([buf]);

if (!global.gc) { console.error("run with --expose-gc"); process.exit(1); }
global.gc();
const before = process.memoryUsage().heapUsed;
let peak = 0;
let total = 0;

await readZipEntries(blob, (name, bytes) => {
  total += bytes.length;
  const used = process.memoryUsage().heapUsed - before;
  if (used > peak) peak = used;
});

const mb = (n) => (n / 1048576).toFixed(1);
console.log(`entries total ${mb(total)} MB, peak heap growth ${mb(peak)} MB`);

// Generous bound: one 8 MB entry plus interpreter noise. A buffering
// implementation would sit near 320 MB and fail this outright.
const LIMIT = 64 * 1048576;
if (peak > LIMIT) {
  console.error(`FAIL peak ${mb(peak)} MB exceeds ${mb(LIMIT)} MB -- the reader is buffering`);
  process.exit(1);
}
console.log("ok    peak memory tracks the largest entry, not the archive");
```

- [ ] **Step 2: Write the big-fixture generator**

```js
// build/emulatorjs/test/make-big-fixture.mjs
import { writeFileSync, mkdirSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { deflateRawSync, crc32 } from "node:zlib";

const DIR = join(dirname(fileURLToPath(import.meta.url)), "fixtures");
mkdirSync(DIR, { recursive: true });

const u16 = (n) => { const b = Buffer.alloc(2); b.writeUInt16LE(n); return b; };
const u32 = (n) => { const b = Buffer.alloc(4); b.writeUInt32LE(n >>> 0); return b; };

const COUNT = 40;
const SIZE = 8 * 1048576;
const locals = [], centrals = [];
let offset = 0;

for (let i = 0; i < COUNT; i++) {
  // Pseudo-random so deflate cannot collapse it to nothing, deterministic so
  // the test is reproducible.
  const raw = Buffer.alloc(SIZE);
  for (let j = 0; j < SIZE; j += 4) raw.writeUInt32LE((j * 2654435761 + i) >>> 0, j);
  const comp = deflateRawSync(raw);
  const crc = crc32(raw);
  const name = Buffer.from(`file${String(i).padStart(2, "0")}.bin`, "utf8");

  const local = Buffer.concat([
    u32(0x04034b50), u16(20), u16(0), u16(8), u16(0), u16(0),
    u32(crc), u32(comp.length), u32(raw.length), u16(name.length), u16(0), name, comp,
  ]);
  locals.push(local);
  centrals.push(Buffer.concat([
    u32(0x02014b50), u16(20), u16(20), u16(0), u16(8), u16(0), u16(0),
    u32(crc), u32(comp.length), u32(raw.length),
    u16(name.length), u16(0), u16(0), u16(0), u16(0), u32(0), u32(offset), name,
  ]));
  offset += local.length;
}

const cd = Buffer.concat(centrals);
const out = Buffer.concat([
  Buffer.concat(locals), cd,
  Buffer.concat([u32(0x06054b50), u16(0), u16(0), u16(COUNT), u16(COUNT), u32(cd.length), u32(offset), u16(0)]),
]);
writeFileSync(join(DIR, "big-many.zip"), out);
console.log(`big-many.zip ${(out.length / 1048576).toFixed(1)} MB, ${COUNT} entries`);
```

- [ ] **Step 3: Run it**

Run: `node --expose-gc build/emulatorjs/test/memory.test.mjs`
Expected: a line reporting roughly 320 MB of content with peak heap growth well under 64 MB, then `ok`.

- [ ] **Step 4: Commit**

```bash
git add build/emulatorjs/test/memory.test.mjs build/emulatorjs/test/make-big-fixture.mjs
git commit -m "test: prove peak memory tracks the largest entry, not the archive

Assisted-by: Claude:claude-opus-5"
```

---

### Task 5: The `cache.js` hook

Wiring the reader into the download path, behind the size gate.

**Files:**
- Create: `build/emulatorjs/patches/01-cache-streaming.patch`
- Reference: pinned `data/src/cache.js` lines 109 and 194-221

**Interfaces:**
- Consumes: `readZipEntries`, `streamingSupported` from Task 3.
- Produces: `downloadFile(..., dontExtract, onFile)` — one new trailing optional parameter. Cache items from the streaming path carry `streamed = true` and an empty `files` array.

**On caching:** the streaming branch resolves *before* reaching
`this.storageCache.put(...)`, so oversized archives are never cached. This is
the spec's `dontCache` requirement, achieved by placement rather than by a
flag — worth knowing, because moving the branch later in the function would
silently start caching 2 GB archives.

- [ ] **Step 1: Obtain the pristine source to diff against**

```bash
mkdir -p /tmp/ejs-patch && cd /tmp/ejs-patch
curl -sL "https://raw.githubusercontent.com/EmulatorJS/EmulatorJS/0b1c5e9/data/src/cache.js" -o cache.js.orig
cp cache.js.orig cache.js
```

- [ ] **Step 2: Edit `cache.js` — add the parameter**

Change the signature at line 109 from:

```js
    downloadFile(url, type, method = "GET", headers = {}, body = null, onProgress = null, onComplete = null, timeout = 30000, responseType = "arraybuffer", forceExtract = false, dontCache = false, dontExtract = false) {
```

to:

```js
    downloadFile(url, type, method = "GET", headers = {}, body = null, onProgress = null, onComplete = null, timeout = 30000, responseType = "arraybuffer", forceExtract = false, dontCache = false, dontExtract = false, onFile = null) {
```

- [ ] **Step 3: Edit `cache.js` — add the import at the top of the file**

```js
import { readZipEntries, streamingSupported } from "./zipstream.js";
```

- [ ] **Step 4: Edit `cache.js` — replace the buffering lines**

Replace exactly this:

```js
                        const blob = new Blob(chunks);
                        const ab = await blob.arrayBuffer();
                        data = new Uint8Array(ab);
```

with:

```js
                        const blob = new Blob(chunks);

                        // Archives beyond this size cannot be flattened into a
                        // single ArrayBuffer (V8 caps one at ~2 GiB), and the
                        // wasm extractor could not hold them either. Read them
                        // straight out of the Blob one entry at a time instead.
                        // Everything smaller keeps the original path exactly.
                        const streamThreshold = (typeof window !== "undefined" && window.EJS_streamZipThreshold) || 1610612736;
                        const isZip = (filename.toLowerCase().split(".").pop() === "zip");
                        if (blob.size > streamThreshold && isZip && typeof onFile === "function" && streamingSupported()) {
                            console.log(`[EJS Download] Streaming ${filename} (${(blob.size / 1048576).toFixed(0)} MB) directly to the filesystem`);
                            // Report bytes written, not entry count: the caller
                            // renders `loaded / 1048576` MB whenever total is 0.
                            let written = 0;
                            await readZipEntries(blob, (entryName, entryBytes) => {
                                onFile(entryName, entryBytes);
                                written += entryBytes.length;
                                if (onProgress) onProgress("decompressing", 0, written, 0);
                            });
                            const streamedItem = new EJS_CacheItem(
                                "streamed-" + Date.now(), [], now, type, responseType, filename, url, null
                            );
                            streamedItem.streamed = true;
                            resolve(streamedItem);
                            return;
                        }

                        const ab = await blob.arrayBuffer();
                        data = new Uint8Array(ab);
```

- [ ] **Step 5: Generate the patch**

```bash
cd /tmp/ejs-patch
diff -u cache.js.orig cache.js > "$OLDPWD/build/emulatorjs/patches/01-cache-streaming.patch" || true
head -5 "$OLDPWD/build/emulatorjs/patches/01-cache-streaming.patch"
```

Expected: a unified diff whose header names `cache.js.orig` and `cache.js`.

- [ ] **Step 6: Verify the patch applies cleanly to a pristine copy**

```bash
cd /tmp/ejs-patch && cp cache.js.orig verify.js
patch --dry-run verify.js < "$OLDPWD/build/emulatorjs/patches/01-cache-streaming.patch"
```

Expected: `Hunk #1 succeeded` for each hunk, no rejects. If it fails, the patch was generated against an edited file.

- [ ] **Step 7: Commit**

```bash
git add build/emulatorjs/patches/01-cache-streaming.patch
git commit -m "patch: route oversized zip downloads through the streaming reader

Assisted-by: Claude:claude-opus-5"
```

---

### Task 6: The `emulator.js` hook

Threading the filesystem writer down, and accepting a streamed cache item as valid.

**Files:**
- Create: `build/emulatorjs/patches/02-emulator-onfile.patch`
- Reference: pinned `data/src/emulator.js` lines 81, 124-140, 143-148, 907-916, 938-965

**Interfaces:**
- Consumes: `downloadFile(..., onFile)` from Task 5.
- Produces: nothing new; this is the last link in the chain.

- [ ] **Step 1: Obtain the pristine source**

```bash
cd /tmp/ejs-patch
curl -sL "https://raw.githubusercontent.com/EmulatorJS/EmulatorJS/0b1c5e9/data/src/emulator.js" -o emulator.js.orig
cp emulator.js.orig emulator.js
```

- [ ] **Step 2: Edit — thread `onFile` through the wrapper (line 81)**

Change:

```js
    downloadFile(path, type, progress, notWithPath, opts, forceExtract = false, dontCache = false, dontExtract = false) {
```

to:

```js
    downloadFile(path, type, progress, notWithPath, opts, forceExtract = false, dontCache = false, dontExtract = false, onFile = null) {
```

and in the `this.downloader.downloadFile(` call inside it, change the final argument list from:

```js
                        forceExtract,
                        dontCache,
                        dontExtract
                    );
```

to:

```js
                        forceExtract,
                        dontCache,
                        dontExtract,
                        onFile
                    );
```

- [ ] **Step 3: Edit — accept a streamed cache item**

Change:

```js
                    if (cacheItem.files && cacheItem.files.length > 0) {
```

to:

```js
                    if (cacheItem.streamed === true) {
                        return { data: cacheItem, headers: {} };
                    }

                    if (cacheItem.files && cacheItem.files.length > 0) {
```

- [ ] **Step 4: Edit — hoist `writeFilesToFS` above the download**

Cut this block entirely from its current position (it sits after the download, just before the `if (returnData && returnData.files)` loop):

```js
            const writeFilesToFS = (fileName, fileData) => {
                if (fileName.includes("/")) {
                    const paths = fileName.split("/");
                    let cp = "";
                    for (let i = 0; i < paths.length - 1; i++) {
                        if (paths[i] === "") continue;
                        cp += `/${paths[i]}`;
                        if (!this.gameManager.FS.analyzePath(cp).exists) {
                            this.gameManager.FS.mkdir(cp);
                        }
                    }
                }
                if (fileName.endsWith("/")) {
                    if (!this.gameManager.FS.analyzePath(fileName).exists) {
                        this.gameManager.FS.mkdir(fileName);
                    }
                    return null;
                }
                this.gameManager.FS.writeFile(`/${fileName}`, fileData);
                return fileName;
            };
```

and paste it unchanged immediately **before** this line:

```js
            if (this.config.gameUrl instanceof File || this.toData(this.config.gameUrl, true)) {
```

(If that exact line differs, the correct anchor is the start of the `if`/`else` that chooses between the local-file and URL download paths. The helper must be defined before both branches.)

- [ ] **Step 5: Edit — pass it to the URL download**

Change:

```js
                    false,
                    type.dontCache,
                    dontExtract
                );
```

to:

```js
                    false,
                    type.dontCache,
                    dontExtract,
                    writeFilesToFS
                );
```

- [ ] **Step 6: Generate and verify the patch**

```bash
cd /tmp/ejs-patch
diff -u emulator.js.orig emulator.js > "$OLDPWD/build/emulatorjs/patches/02-emulator-onfile.patch" || true
cp emulator.js.orig verify2.js
patch --dry-run verify2.js < "$OLDPWD/build/emulatorjs/patches/02-emulator-onfile.patch"
```

Expected: every hunk succeeds, no rejects.

- [ ] **Step 7: Commit**

```bash
git add build/emulatorjs/patches/02-emulator-onfile.patch
git commit -m "patch: thread the filesystem writer into the streaming download path

Assisted-by: Claude:claude-opus-5"
```

---

### Task 7: Reproducible assembly

The staged EmulatorJS tree is in no repository, so a hand-edit would vanish silently on the next assembly. This makes the tree reproducible from a script, which is also what makes the change survivable.

**Files:**
- Create: `build/emulatorjs/assemble.sh`
- Modify: `docs/BUILD.md`

**Interfaces:**
- Consumes: everything from Tasks 2 through 6.

- [ ] **Step 1: Write the script**

```bash
#!/usr/bin/env bash
# Assemble the EmulatorJS tree that docker/Dockerfile COPYs into the ROMM
# image, with this project's patches applied.
#
# The tree is ~286 MB and is committed to no repository, so this script is the
# only record of how it is built. Run it, then deploy-to-romm.sh stages the
# core files alongside it.
set -euo pipefail
cd "$(dirname "$0")/../.."

EJS_COMMIT="0b1c5e9"          # must match ARG EMULATORJS_COMMIT in romm's Dockerfile
ROMM_CHECKOUT="${1:?usage: assemble.sh <path-to-romm-checkout>}"
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

echo "==> staging into ${ROMM_CHECKOUT}/docker/emulatorjs"
rm -rf "${ROMM_CHECKOUT}/docker/emulatorjs"
mkdir -p "${ROMM_CHECKOUT}/docker/emulatorjs"
cp -r "$WORK/ejs/data" "${ROMM_CHECKOUT}/docker/emulatorjs/data"

echo "==> done. Core .data files are staged separately by build/deploy-to-romm.sh"
```

- [ ] **Step 2: Make it executable and run it**

Run: `chmod +x build/emulatorjs/assemble.sh && bash build/emulatorjs/assemble.sh /home/user/git/romm`
Expected: each stage printed, then the verification line confirming both artifacts carry the patch, then `done`. If the verification fails, the minify step did not pick up the patched source and nothing further will work.

- [ ] **Step 3: Document it**

Add to `docs/BUILD.md`, in the section describing the ROMM deployment:

```markdown
### Assembling the EmulatorJS tree

`docker/emulatorjs/` in the ROMM checkout is ~286 MB and is committed to no
repository. `build/emulatorjs/assemble.sh <romm-checkout>` rebuilds it: clone
EmulatorJS at the pinned commit, add `zipstream.js`, apply
`build/emulatorjs/patches/*.patch`, `npm ci`, `npm run minify`, stage.

Run it whenever a patch changes or the pinned commit moves. It verifies that
both `data/src/cache.js` and `data/emulator.min.js` carry the patch, because
`loader.js` serves the source only when `EJS_DEBUG_XX` is true and the minified
bundle otherwise — patching one and not the other works under debug and fails
silently in normal use.
```

- [ ] **Step 4: Commit**

```bash
git add build/emulatorjs/assemble.sh docs/BUILD.md
git commit -m "build: reproducible EmulatorJS tree assembly with patches

Assisted-by: Claude:claude-opus-5"
```

---

### Task 8: Live validation

**Files:** none changed. This task produces evidence.

- [ ] **Step 1: Build and deploy the patched tree**

```bash
bash build/emulatorjs/assemble.sh /home/user/git/romm
scp -r /home/user/git/romm/docker/emulatorjs root@192.168.1.12:/tmp/romm-build/docker/
ssh root@192.168.1.12 'cd /tmp/romm-build && docker build -f docker/Dockerfile --target full-image -t romm-scummvm:ejs-stream .'
```

Expected: image builds. Tag is deliberately **not** `ejs-rc` — the RC candidate must stay untouched until this is proven.

- [ ] **Step 2: Force the path on a small ROM**

Switch the container to `romm-scummvm:ejs-stream`, hard-reload, and in the browser console before launching:

```js
window.EJS_streamZipThreshold = 0;
```

Launch Day of the Tentacle. Expected in the console: `[EJS Download] Streaming ... directly to the filesystem`, then the game boots and plays with sound. This drives the entire streaming path in seconds and is the check that matters most — it is how the path stays exercised without a 2 GB download.

- [ ] **Step 3: Confirm the normal path is untouched**

Reload without setting the threshold. Launch the same game. Expected: **no** streaming log line, game boots normally. This is the regression check that the other 180 cores are unaffected.

- [ ] **Step 4: The real target**

Launch Riven (CD Windows), 2.036 GiB. Expected: downloads, streams, boots into gameplay with sound. Record the console log to `~/Desktop/test logs/riven-streaming.log`.

- [ ] **Step 5: The second target**

Launch The Feeble Files (4CD Windows), which fails today on the extractor rather than the download. Expected: boots. This proves both original ceilings are gone, not just the first.

- [ ] **Step 6: Record the outcome**

Update issue #5 with what now loads and what the new ceiling is, per the spec's "What the new ceiling becomes" section. If Gabriel Knight 2 (3.343 GiB unpacked) also loads, say so; if it exhausts browser memory, record the figure — that is the real new limit and it belongs in the issue rather than in a guess.

- [ ] **Step 7: Commit the evidence**

```bash
git add docs/  # any notes updated
git commit -m "docs: record streaming loader validation results

Assisted-by: Claude:claude-opus-5"
```

---

## After the plan

1. Merge `streaming-zip-loader` to `master` only once Task 8 steps 2, 3 and 4 all pass.
2. Submit upstream to `EmulatorJS/EmulatorJS` as a PR containing `zipstream.js` and the two source changes, noting the benefit for multi-disc ScummVM titles. Their PR conventions: rebase first, one topic per PR, squash to a single commit. No AI policy exists in that repo; use the `Assisted-by` trailer anyway, consistent with this project's standing convention.
3. **If rejected:** gate the `cache.js` branch on the core name and fold it into the ScummVM core submission. Only then does a core-specific condition enter the code.
