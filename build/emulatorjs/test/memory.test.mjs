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
const before = process.memoryUsage().arrayBuffers;
let peak = 0;
let total = 0;

// Measure arrayBuffers, not heapUsed. Typed-array backing stores live in
// Node's "external" memory, not the JS heap, so heapUsed barely moves
// whether the reader streams or buffers -- it cannot tell them apart. A
// buffering consumer that retains every entry in an array was measured
// against this same fixture: heapUsed 5.1 MB (streaming) vs 2.8 MB
// (buffering) -- backwards, and a false pass either way -- while
// arrayBuffers reported 88.0 MB (streaming) vs 383.9 MB (buffering), which
// discriminates cleanly. Do not "simplify" this back to heapUsed.
await readZipEntries(blob, (name, bytes) => {
  total += bytes.length;
  const used = process.memoryUsage().arrayBuffers - before;
  if (used > peak) peak = used;
});

const mb = (n) => (n / 1048576).toFixed(1);
console.log(`entries total ${mb(total)} MB, peak arrayBuffers growth ${mb(peak)} MB`);

// Half the archive's content (320 MB), giving ~1.8x headroom over the
// measured 88 MB streaming peak while still catching a buffering
// implementation (measured ~384 MB) by a wide margin.
const LIMIT = 160 * 1048576;
if (peak > LIMIT) {
  console.error(`FAIL peak arrayBuffers ${mb(peak)} MB exceeds ${mb(LIMIT)} MB -- the reader is buffering`);
  process.exit(1);
}
console.log("ok    peak memory tracks the largest entry, not the archive");
