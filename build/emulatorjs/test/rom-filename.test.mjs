// Tests the patched emulator.js half of the streaming path: that a streamed
// archive's entry names reach selectRomFile(), so this.fileName is a real
// name rather than undefined.
//
// A streamed item's files array is empty by design, so before the fileNames
// manifest existed this.fileName came out undefined and reached the core as
// the content path "/undefined" -- which is what RetroArch then named every
// save file after ("undefined.srm", "undefined.state").
//
// As with cache-streaming.test.mjs, emulator.js is vendored and patched at
// assemble time; point EJS_SRC at an EmulatorJS checkout's data/src.
import { readFileSync, mkdtempSync, cpSync, copyFileSync, rmSync, existsSync } from "node:fs";
import { join, dirname } from "node:path";
import { tmpdir, homedir } from "node:os";
import { fileURLToPath, pathToFileURL } from "node:url";
import { execFileSync } from "node:child_process";

const HERE = dirname(fileURLToPath(import.meta.url));
const PATCHES = join(HERE, "..", "patches");
const OURS = join(HERE, "..", "src");

const EJS_SRC = process.env.EJS_SRC || join(homedir(), "git", "EmulatorJS", "data", "src");
if (!existsSync(join(EJS_SRC, "emulator.js"))) {
  console.log(`SKIP  no EmulatorJS source at ${EJS_SRC}`);
  console.log("      set EJS_SRC=<EmulatorJS checkout>/data/src to run this test");
  process.exit(0);
}

const work = mkdtempSync(join(tmpdir(), "ejs-emu-test-"));
process.on("exit", () => rmSync(work, { recursive: true, force: true }));
cpSync(EJS_SRC, work, { recursive: true });
copyFileSync(join(OURS, "zipstream.js"), join(work, "zipstream.js"));
execFileSync("patch", ["-s", join(work, "cache.js")], {
  input: readFileSync(join(PATCHES, "01-cache-streaming.patch")),
});
execFileSync("patch", ["-s", join(work, "emulator.js")], {
  input: readFileSync(join(PATCHES, "02-emulator-onfile.patch")),
});

// emulator.js touches these at import time. navigator already exists in Node
// and is getter-only, so it is deliberately left alone.
globalThis.window = globalThis;
globalThis.document = {
  createElement: () => ({
    style: {}, classList: { add() {}, remove() {} },
    setAttribute() {}, appendChild() {},
  }),
  addEventListener() {},
  body: { appendChild() {} },
};

const EmulatorJS = (await import(pathToFileURL(join(work, "emulator.js")).href)).default;

let failures = 0;
function check(name, fn) {
  try { fn(); console.log(`  ok    ${name}`); }
  catch (e) { failures++; console.error(`  FAIL  ${name}\n        ${e.message}`); }
}
function eq(actual, expected, what) {
  const a = JSON.stringify(actual), b = JSON.stringify(expected);
  if (a !== b) throw new Error(`${what}: got ${a}, want ${b}`);
}

// Drives the two real methods against a fake instance carrying only what
// they touch, rather than constructing EmulatorJS (whose constructor builds
// a whole DOM). selectRomFile runs for real so this.fileName is genuinely
// the value the core would be launched with.
function launch(romData) {
  const fake = {
    config: {},
    fileName: undefined,
    started: [],
    supportsExtension: (ext) => ["scummvm", "svm", "exe", "000", "txt"].includes(ext),
    getCore: () => "scummvm",
    startGame() { this.started.push(this.fileName); },
    selectRomFile: EmulatorJS.prototype.selectRomFile,
    determineCueSettings: EmulatorJS.prototype.determineCueSettings,
  };
  EmulatorJS.prototype.startGameFromDownload.call(fake, romData);
  return fake.fileName;
}

const asFiles = (names) => ({ files: names.map((filename) => ({ filename })) });

check("a streamed item's manifest reaches selectRomFile", () => {
  const name = launch({
    files: [],
    fileNames: ["RIVEN/", "RIVEN/a_Data.MHK", "RIVEN/riven.scummvm"],
  });
  eq(name, "RIVEN/riven.scummvm", "fileName");
});

check("a streamed item never yields an undefined content path", () => {
  const name = launch({ files: [], fileNames: ["GK2/", "GK2/RESOURCE.000"] });
  if (name === undefined) throw new Error("fileName is undefined");
  eq(name, "GK2/RESOURCE.000", "fileName");
});

check("directory entries are filtered out of the manifest", () => {
  const name = launch({ files: [], fileNames: ["sub/", "sub/nested/", "sub/nested/game.scummvm"] });
  eq(name, "sub/nested/game.scummvm", "fileName");
});

check("a non-streamed item still selects from files", () => {
  const name = launch(asFiles(["DOTT/", "DOTT/tentacle.000", "DOTT/readme.txt"]));
  eq(name, "DOTT/tentacle.000", "fileName");
});

check("non-streamed and streamed shapes agree on the same entries", () => {
  const names = ["X/", "X/game.000", "X/notes.txt"];
  eq(launch({ files: [], fileNames: names }), launch(asFiles(names)), "fileName");
});

console.log(failures ? `\n${failures} failure(s)` : "\nall passed");
process.exit(failures ? 1 : 0);
