// Every download failure in emulator.js is flattened to -1 and reported as
// "Network Error", whatever actually went wrong. That is fine for a dropped
// connection and useless for a deliberate refusal: the memory preflight in
// cache.js rejects with a message explaining that the game does not fit in
// the device's RAM, and the user would have seen "Network Error" instead.
//
// Errors carrying `ejsUserMessage` are shown as-is; everything else still
// falls back to the localized "Network Error", so a real network failure
// does not start leaking raw exception text at the user.
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { patchedTree, stubBrowserGlobals, harness } from "./helpers/patched-tree.mjs";

const work = patchedTree({ full: true });
if (!work) process.exit(0);
stubBrowserGlobals();

const EmulatorJS = (await import(pathToFileURL(join(work, "emulator.js")).href)).default;
const { check, eq, report } = harness();

function fakeEmulator(downloaderError) {
  return {
    debug: false,
    config: { dataPath: "", gameUrl: "http://localhost/game.zip" },
    toData: () => null,
    localization: (k) => k,
    downloadType: { rom: { name: "ROM", dontCache: false } },
    downloader: {
      downloadFile: async () => { throw downloaderError; },
    },
    downloadFile: EmulatorJS.prototype.downloadFile,
  };
}

await check("a refusal with a user message is carried off the download path", async () => {
  const err = new Error("This game needs 3.6 GB once unpacked, more than this device's 2.0 GB of memory.");
  err.ejsUserMessage = err.message;
  const fake = fakeEmulator(err);
  const result = await fake.downloadFile("http://localhost/game.zip", "ROM", null, true, {
    responseType: "arraybuffer", method: "GET",
  });
  eq(result, -1, "download result");
  eq(fake.downloadUserMessage, err.message, "message carried for the caller");
});

await check("an ordinary failure carries no user message", async () => {
  const fake = fakeEmulator(new TypeError("Failed to fetch"));
  const result = await fake.downloadFile("http://localhost/game.zip", "ROM", null, true, {
    responseType: "arraybuffer", method: "GET",
  });
  eq(result, -1, "download result");
  eq(fake.downloadUserMessage, undefined, "no user message");
});

// download()'s -1 branch is what actually puts text on screen.
async function shownFor(downloadFileResult, preset) {
  const shown = [];
  const fake = {
    debug: false,
    config: { gameUrl: "http://localhost/game.zip" },
    localization: (k) => k,
    toData: () => null,
    compression: {},
    getCore: () => "scummvm",
    downloadUserMessage: preset,
    startGameError: (m) => shown.push(m),
    downloadType: { rom: { name: "ROM", dontCache: false } },
    downloadFile: async () => downloadFileResult,
    download: EmulatorJS.prototype.download,
  };
  // download()'s promise never settles on failure -- the -1 branch calls
  // startGameError and returns without resolving -- so awaiting it hangs.
  // Kick it off and let the microtask queue drain instead.
  fake.download("http://localhost/game.zip", fake.downloadType.rom);
  await new Promise((r) => setTimeout(r, 0));
  return { shown, fake };
}

await check("the refusal reason is shown instead of Network Error", async () => {
  const msg = "This game needs 3.6 GB once unpacked, more than this device's 2.0 GB of memory.";
  const { shown } = await shownFor(-1, msg);
  eq(shown, [msg], "text shown to the user");
});

await check("an ordinary failure still shows Network Error", async () => {
  const { shown } = await shownFor(-1, undefined);
  eq(shown, ["Network Error"], "text shown to the user");
});

// Otherwise one refused game would make every later failure claim the same
// reason, long after it stopped being true.
await check("the message is cleared once shown", async () => {
  const { fake } = await shownFor(-1, "some earlier refusal");
  eq(fake.downloadUserMessage, null, "message cleared");
});

report();
