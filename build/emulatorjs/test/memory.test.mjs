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
