// The loading readout (.ejs_loading_text) froze on "Download Game Data 100%"
// for the whole unpack of a streamed archive -- minutes, for a 2.6 GB ROM,
// with no sign of progress.
//
// Cause: emulator.js's progress adapter forwards only status "downloading"
// to the caller, so every "decompressing" tick from cache.js is dropped and
// the text keeps whatever the last download update wrote. Upstream has the
// same gap on the ordinary path; it is just too brief to notice there.
//
// That the labels "Decompress Game Data"/"Decompress Game Core" are
// translated in every localization/*.json while appearing nowhere in the
// source is the fossil evidence this readout was meant to exist.
import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { patchedTree, stubBrowserGlobals, harness } from "./helpers/patched-tree.mjs";

const FIXTURES = join(dirname(fileURLToPath(import.meta.url)), "fixtures");
const work = patchedTree({ full: true });
if (!work) process.exit(0);
stubBrowserGlobals();

const { EJS_Download } = await import(pathToFileURL(join(work, "cache.js")).href);
const EmulatorJS = (await import(pathToFileURL(join(work, "emulator.js")).href)).default;

const { check, eq, report } = harness();

// --- layer 1: cache.js reports decompression against a real total ---------

async function streamDownload(fixture) {
  const bytes = readFileSync(join(FIXTURES, fixture));
  globalThis.fetch = async () => new Response(bytes, {
    status: 200,
    headers: { "Content-Length": String(bytes.length) },
  });
  globalThis.window.EJS_streamZipThreshold = 1;
  const ticks = [];
  await new EJS_Download(null, null).downloadFile(
    `http://localhost/${fixture}`, "rom", "GET", {}, null,
    (status, percentage, loaded, total) => ticks.push({ status, percentage, loaded, total }),
    null, 30000, "arraybuffer", false, true, false,
    () => {}
  );
  return ticks;
}

await check("streaming reports decompression progress against a known total", async () => {
  const ticks = (await streamDownload("deflate.zip")).filter((t) => t.status === "decompressing");
  if (ticks.length === 0) throw new Error("no decompressing ticks were emitted");
  const last = ticks[ticks.length - 1];
  // deflate.zip is hello.txt (12 bytes) + big.txt (200000 bytes).
  eq(last.total, 200012, "total from the central directory");
  eq(last.loaded, 200012, "loaded at completion");
  eq(Math.round(last.percentage), 100, "percentage at completion");
});

await check("decompression percentage is monotonic and bounded", async () => {
  const ticks = (await streamDownload("deflate.zip")).filter((t) => t.status === "decompressing");
  let prev = -1;
  for (const t of ticks) {
    if (t.percentage < prev) throw new Error(`percentage went backwards: ${prev} -> ${t.percentage}`);
    if (t.percentage < 0 || t.percentage > 100) throw new Error(`percentage out of range: ${t.percentage}`);
    prev = t.percentage;
  }
});

// --- layer 2: emulator.js's adapter forwards the status -------------------

// Drives the real downloadFile() against a stubbed downloader that emits one
// tick of each status, and records what reached the caller's progress fn.
async function adapterTicks() {
  const seen = [];
  const fake = {
    debug: false,
    config: { dataPath: "" },
    toData: () => null,
    downloadType: { rom: { name: "ROM" } },
    downloader: {
      downloadFile: async (url, type, method, headers, body, onProgress) => {
        onProgress("downloading", 100, 1048576, 1048576);
        onProgress("decompressing", 42, 42000, 100000);
        // How upstream's own extractor reports: the value is in percentage,
        // with loaded and total both zero (cache.js:242).
        onProgress("decompressing", 37, 0, 0);
        return { files: [{ filename: "a", bytes: new Uint8Array(1) }] };
      },
    },
    downloadFile: EmulatorJS.prototype.downloadFile,
  };
  await fake.downloadFile("http://localhost/x.zip", "ROM", (text, status) => {
    seen.push({ text, status });
  }, true, { responseType: "arraybuffer", method: "GET" });
  return seen;
}

await check("the adapter forwards decompressing ticks, not only downloading", async () => {
  const seen = await adapterTicks();
  eq(seen.map((s) => s.status), ["downloading", "decompressing", "decompressing"], "statuses reaching the caller");
});

await check("a decompressing tick with a known total renders a percentage", async () => {
  const seen = await adapterTicks();
  const dec = seen.find((s) => s.status === "decompressing");
  if (!dec) throw new Error("no decompressing tick reached the caller");
  eq(dec.text, " 42%", "rendered text");
});

// --- layer 3: the caller labels the phase correctly -----------------------

// The ROM download's progress callback is defined inline inside download(),
// so it is reached by running download() against a stubbed downloadFile and
// capturing what gets written to the loading element.
async function labelsFor(statuses) {
  const written = [];
  const fake = {
    debug: false,
    config: { gameUrl: "http://localhost/game.zip" },
    textElem: { set innerText(v) { written.push(v); }, get innerText() { return ""; } },
    localization: (k) => k,
    toData: () => null,
    compression: {},
    getCore: () => "scummvm",
    gameManager: { FS: { analyzePath: () => ({ exists: true }), writeFile() {}, mkdir() {} } },
    startGameError() {},
    downloadType: { rom: { name: "ROM", dontCache: false } },
    downloadFile: async (url, typeName, progress) => {
      for (const s of statuses) progress(s === "downloading" ? " 100%" : " 42%", s);
      return { data: { files: [] }, headers: {} };
    },
    download: EmulatorJS.prototype.download,
  };
  await fake.download("http://localhost/game.zip", fake.downloadType.rom);
  return written;
}

await check("the loading text says Download while downloading", async () => {
  const written = await labelsFor(["downloading"]);
  eq(written, ["Download Game Data 100%"], "loading text");
});

await check("the loading text switches to Decompress while unpacking", async () => {
  const written = await labelsFor(["downloading", "decompressing"]);
  eq(written, ["Download Game Data 100%", "Decompress Game Data 42%"], "loading text");
});

// The wasm extractor reports progress in `percentage` with loaded and total
// both zero. Rendering "loaded / 1048576 MB" for those gives a readout stuck
// at "0.00MB" -- which is what shipped, for both the core and any game small
// enough to skip the streaming path.
await check("a decompressing tick with no total still renders its percentage", async () => {
  const seen = await adapterTicks();
  const noTotal = seen.filter((s) => s.status === "decompressing").pop();
  if (!noTotal) throw new Error("no decompressing tick reached the caller");
  eq(noTotal.text, " 37%", "rendered text");
});

report();
