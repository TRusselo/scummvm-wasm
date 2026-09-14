// Tests the streaming branch of the patched cache.js -- the real vendored
// file with patches/01-cache-streaming.patch applied to a throwaway copy,
// exactly as assemble.sh builds it, rather than a transcription of it.
import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { patchedTree, harness } from "./helpers/patched-tree.mjs";

const FIXTURES = join(dirname(fileURLToPath(import.meta.url)), "fixtures");
const work = patchedTree();
if (!work) process.exit(0);

const { EJS_Download } = await import(pathToFileURL(join(work, "cache.js")).href);
const { check, eq, report } = harness();

// The threshold is read off window, which is also the only way to make a
// small fixture take the streaming path without a multi-GB archive.
globalThis.window = {};

const DIRS_ZIP_ENTRIES = ["sub/", "sub/nested/", "sub/nested/hello.txt"];

async function download(fixture, threshold, { dontExtract = false, forceExtract = false, onFileImpl } = {}) {
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
    onFileImpl || ((name, data, canOwn) => { written.push([name, data.length, canOwn]); })
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

// A failure during the unpack used to reject with a bare string, which
// download() cannot tell apart from a dropped connection -- so the user was
// shown "Network Error" for a download that had already finished. Both
// branches must reject with an Error carrying ejsUserMessage.
//
// MEMFS allocates inside onFile, so that is where a real out-of-memory
// failure surfaces: the throw propagates out of readZipEntries into the
// catch. Feeding the error through that path rather than asserting on the
// regex keeps the test honest about the shape the code actually sees.
await check("running out of memory mid-unpack says so, and does not say network", async () => {
  let err = null;
  try {
    await download("dirs.zip", 1, {
      onFileImpl: () => { throw new RangeError("Array buffer allocation failed"); },
    });
  } catch (e) { err = e; }
  if (err === null) throw new Error("expected the unpack to fail");
  if (typeof err.ejsUserMessage !== "string") throw new Error(`no ejsUserMessage: ${err}`);
  if (!/memory/i.test(err.ejsUserMessage)) throw new Error(`should name memory: ${err.ejsUserMessage}`);
  if (/network/i.test(err.ejsUserMessage)) throw new Error(`must not blame the network: ${err.ejsUserMessage}`);
});

// A corrupt archive is a real, non-memory unpack failure. It must still be
// reported as an unpacking problem rather than a network one.
// Without this the log says only that decompression failed. How far it got
// separates "died immediately" from "nearly made it", and is the only way to
// compare two builds' memory behaviour without reading a system memory graph.
await check("a failed unpack records how far it got", async () => {
  let err = null;
  try {
    await download("dirs.zip", 1, {
      onFileImpl: (name) => { if (!name.endsWith("/")) throw new RangeError("Array buffer allocation failed"); },
    });
  } catch (e) { err = e; }
  if (err === null) throw new Error("expected the unpack to fail");
  if (!/MB of .* MB unpacked \(\d+%\)/.test(err.message)) {
    throw new Error(`message should state progress: ${err.message}`);
  }
});

await check("a corrupt archive is reported as an unpack failure, not a network one", async () => {
  let err = null;
  try {
    await download("badcrc.zip", 1);
  } catch (e) { err = e; }
  if (err === null) throw new Error("expected the unpack to fail");
  if (typeof err.ejsUserMessage !== "string") throw new Error(`no ejsUserMessage: ${err}`);
  if (!/unpack/i.test(err.ejsUserMessage)) throw new Error(`should name unpacking: ${err.ejsUserMessage}`);
  if (/network/i.test(err.ejsUserMessage)) throw new Error(`must not blame the network: ${err.ejsUserMessage}`);
});

// MEMFS copies the buffer unless the caller says it may keep it:
// write() does node.contents = buffer.slice(...) without canOwn, and
// buffer.subarray(...) with it. Every streamed entry is therefore held twice
// at peak unless the streaming path asks for adoption -- which it safely can,
// since readZipEntries allocates a fresh array per entry and a streamed item
// keeps files empty, so nothing else aliases the bytes.
await check("streamed entries are handed to the filesystem without a copy", async () => {
  const { written } = await download("dirs.zip", 1);
  const files = written.filter((w) => !w[0].endsWith("/"));
  if (!files.length) throw new Error("expected at least one file entry");
  for (const [name, , canOwn] of files) {
    if (canOwn !== true) throw new Error(`${name} was written without canOwn`);
  }
});

report();
