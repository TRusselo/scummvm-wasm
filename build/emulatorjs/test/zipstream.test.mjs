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
