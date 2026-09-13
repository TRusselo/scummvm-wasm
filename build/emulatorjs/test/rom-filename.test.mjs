// Tests the patched emulator.js half of the streaming path: that a streamed
// archive's entry names reach selectRomFile(), so this.fileName is a real
// name rather than undefined.
//
// A streamed item's files array is empty by design, so before the fileNames
// manifest existed this.fileName came out undefined and reached the core as
// the content path "/undefined" -- which is what RetroArch then named every
// save file after ("undefined.srm", "undefined.state").
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { patchedTree, stubBrowserGlobals, harness } from "./helpers/patched-tree.mjs";

const work = patchedTree({ full: true });
if (!work) process.exit(0);
stubBrowserGlobals();

const EmulatorJS = (await import(pathToFileURL(join(work, "emulator.js")).href)).default;
const { check, eq, report } = harness();

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

report();
