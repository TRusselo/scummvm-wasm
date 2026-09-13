// Tests the streaming branch of the patched cache.js -- the real vendored
// file with patches/01-cache-streaming.patch applied to a throwaway copy,
// exactly as assemble.sh builds it, rather than a transcription of it.
//
// cache.js is not in this repository (assemble.sh clones EmulatorJS at a
// pinned commit), so point EJS_SRC at an EmulatorJS checkout's data/src to
// run this. Without one the test skips rather than failing.
import { readFileSync, mkdtempSync, copyFileSync, rmSync, existsSync } from "node:fs";
import { join, dirname } from "node:path";
import { tmpdir, homedir } from "node:os";
import { fileURLToPath, pathToFileURL } from "node:url";
import { execFileSync } from "node:child_process";

const HERE = dirname(fileURLToPath(import.meta.url));
const FIXTURES = join(HERE, "fixtures");
const PATCHES = join(HERE, "..", "patches");
const OURS = join(HERE, "..", "src");

const EJS_SRC = process.env.EJS_SRC || join(homedir(), "git", "EmulatorJS", "data", "src");
if (!existsSync(join(EJS_SRC, "cache.js"))) {
  console.log(`SKIP  no EmulatorJS source at ${EJS_SRC}`);
  console.log("      set EJS_SRC=<EmulatorJS checkout>/data/src to run this test");
  process.exit(0);
}

const work = mkdtempSync(join(tmpdir(), "ejs-cache-test-"));
process.on("exit", () => rmSync(work, { recursive: true, force: true }));
for (const f of ["utils.js", "storage.js", "compression.js", "cache.js"]) {
  copyFileSync(join(EJS_SRC, f), join(work, f));
}
copyFileSync(join(OURS, "zipstream.js"), join(work, "zipstream.js"));
execFileSync("patch", ["-s", join(work, "cache.js")], {
  input: readFileSync(join(PATCHES, "01-cache-streaming.patch")),
});

const { EJS_Download } = await import(pathToFileURL(join(work, "cache.js")).href);

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

// The threshold is read off window, which is also the only way to make a
// small fixture take the streaming path without a multi-GB archive.
globalThis.window = {};

const DIRS_ZIP_ENTRIES = ["sub/", "sub/nested/", "sub/nested/hello.txt"];

async function download(fixture, threshold, { dontExtract = false, forceExtract = false } = {}) {
  const bytes = readFileSync(join(FIXTURES, fixture));
  globalThis.fetch = async () => new Response(bytes, {
    status: 200,
    headers: { "Content-Length": String(bytes.length) },
  });
  globalThis.window.EJS_streamZipThreshold = threshold;
  const written = [];
  const item = await new EJS_Download(null, null).downloadFile(
    `http://localhost/${fixture}`, "rom", "GET", {}, null, null, null, 30000,
    "arraybuffer", forceExtract, true, dontExtract,
    (name, data) => { written.push([name, data.length]); }
  );
  return { item, written };
}

await check("streamed item carries the entry manifest", async () => {
  const { item } = await download("dirs.zip", 1);
  eq(item.streamed, true, "streamed flag");
  eq(item.fileNames, DIRS_ZIP_ENTRIES, "manifest");
});

await check("streamed item writes every entry through onFile", async () => {
  const { written } = await download("dirs.zip", 1);
  eq(written.map((w) => w[0]), DIRS_ZIP_ENTRIES, "written names");
});

// A populated files array would make emulator.js's extraction loop rewrite
// every entry with the bytes it holds -- which for a streamed item would be
// empty, destroying the content just written. It must stay empty.
await check("streamed item keeps files empty so the extraction loop cannot rewrite content", async () => {
  const { item } = await download("dirs.zip", 1);
  eq(item.files.length, 0, "files length");
});

// The gate itself: below the threshold the streaming branch must not run.
// Asked with dontExtract so the ordinary path stores the archive whole
// rather than handing off to EJS_COMPRESSION, which needs a browser runtime
// this test has no way to provide.
await check("an archive below the threshold does not take the streaming path", async () => {
  const { item, written } = await download("dirs.zip", 1 << 30, { dontExtract: true });
  eq(item.streamed, undefined, "streamed flag");
  eq(written.length, 0, "onFile calls");
  eq(item.files.map((f) => f.filename), ["dirs.zip"], "stored whole");
});

// dontExtract is how a core says it wants the archive itself, not its
// contents: the arcade/MAME family reads a romset zip directly. Streaming
// unpacks it to loose files, which is exactly what that core did not ask
// for, so the size gate must not override it. ScummVM never sets this, but
// one EmulatorJS build serves every core in a ROMM deployment.
await check("an oversized archive is not streamed when the core wants it unextracted", async () => {
  const { item, written } = await download("dirs.zip", 1, { dontExtract: true });
  eq(item.streamed, undefined, "streamed flag");
  eq(written.length, 0, "onFile calls");
  eq(item.files.map((f) => f.filename), ["dirs.zip"], "stored whole");
});

// forceExtract outranks dontExtract on the ordinary path, so it must here too.
await check("forceExtract still streams an oversized archive", async () => {
  const { item } = await download("dirs.zip", 1, { dontExtract: true, forceExtract: true });
  eq(item.streamed, true, "streamed flag");
  eq(item.fileNames, DIRS_ZIP_ENTRIES, "manifest");
});

console.log(failures ? `\n${failures} failure(s)` : "\nall passed");
process.exit(failures ? 1 : 0);
