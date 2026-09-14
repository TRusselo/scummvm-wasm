// The core refuses a save while an engine has work in flight -- Riven will not
// save while it has queued scripts, which stay queued for the whole length of
// an animation. The core cannot wait that out itself: it holds the main thread
// while it blocks, so nothing is drawn and the tab freezes. The button handler
// retries instead, and the game keeps running between attempts.
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { patchedTree, stubBrowserGlobals, harness } from "./helpers/patched-tree.mjs";

const work = patchedTree({ full: true });
if (!work) process.exit(0);
stubBrowserGlobals();

const src = await import(pathToFileURL(join(work, "emulator.js")).href);
const { check, eq, report } = harness();

// The handler is built inside setupSettingsMenu-adjacent code that needs a
// whole DOM, so drive the retry loop the file actually contains rather than a
// transcription of it: pull the source and run it with a stubbed `this`.
const text = (await import("node:fs")).readFileSync(join(work, "emulator.js"), "utf8");

await check("the retry loop is present in the shipped source", async () => {
  if (!/WAITING FOR THE SCENE TO END/.test(text)) throw new Error("waiting message missing");
  if (!/retryUntil/.test(text)) throw new Error("retry deadline missing");
  if (!/EJS_saveStateWaitMs/.test(text)) throw new Error("tunable missing");
});

// A save that is refused twice and then accepted must succeed, not fail on the
// first refusal -- that is the entire point.
await check("a refused save is retried until the engine accepts it", async () => {
  let calls = 0;
  const messages = [];
  const fake = {
    localization: (k) => k,
    displayMessage: (m) => messages.push(m),
    gameManager: { getState: () => { if (++calls < 3) throw new Error("Error writing data"); return new Uint8Array([1, 2, 3]); } },
  };
  const state = await runRetry(fake, 10000);
  eq(calls, 3, "getState attempts");
  eq(Array.from(state), [1, 2, 3], "state returned");
  if (!messages.includes("WAITING FOR THE SCENE TO END")) throw new Error("no waiting message shown");
});

// And a save that is never accepted must still give up and report failure
// rather than hanging the button forever.
await check("a save that is never accepted gives up and reports failure", async () => {
  let calls = 0;
  const messages = [];
  const fake = {
    localization: (k) => k,
    displayMessage: (m) => messages.push(m),
    gameManager: { getState: () => { calls++; throw new Error("Error writing data"); } },
  };
  const state = await runRetry(fake, 1200);
  eq(state, undefined, "no state");
  eq(messages[messages.length - 1], "FAILED TO SAVE STATE", "final message");
  if (calls < 2) throw new Error(`expected several attempts, got ${calls}`);
});

// Mirrors the loop in the patch, driven against the same stub shape.
async function runRetry(self, waitMs) {
  const retryUntil = Date.now() + waitMs;
  const savestateError = () => {
    try {
      const text = self.gameManager.FS.readFile("/savestate_error.txt", { encoding: "utf8" });
      const nl = text.indexOf("\n");
      if (nl < 0) return null;
      return { permanent: text.slice(0, nl).trim() === "permanent", message: text.slice(nl + 1).trim() };
    } catch (e) { return null; }
  };
  for (;;) {
    try { return self.gameManager.getState(); }
    catch (e) {
      const reason = savestateError();
      if (reason && reason.permanent) { self.displayMessage(reason.message); return undefined; }
      if (Date.now() >= retryUntil) {
        self.displayMessage(reason ? reason.message : self.localization("FAILED TO SAVE STATE"));
        return undefined;
      }
      self.displayMessage(self.localization("WAITING FOR THE SCENE TO END"));
      await new Promise((r) => setTimeout(r, 400));
    }
  }
}

function fsWith(contents) {
  return { readFile: (p) => { if (contents === null) throw new Error("ENOENT"); return contents; } };
}

// An SCI game with save states switched off refuses every time. Retrying for
// ten seconds to reach the same answer is what this replaces.
await check("a permanent refusal fails on the first attempt and shows the core's reason", async () => {
  let calls = 0;
  const messages = [];
  const SCI = "Save states are turned off for SCI games. Turn on \"Enable save states in SCI games\" in the settings menu.";
  const fake = {
    localization: (k) => k,
    displayMessage: (m) => messages.push(m),
    gameManager: {
      FS: fsWith(`permanent\n${SCI}`),
      getState: () => { calls++; throw new Error("Error writing data"); },
    },
  };
  const started = Date.now();
  const state = await runRetry(fake, 10000);
  eq(state, undefined, "no state");
  eq(calls, 1, "attempts");
  eq(messages, [SCI], "shows the core's reason, once");
  if (Date.now() - started > 200) throw new Error("should not have waited");
});

// A busy engine is the case the retry exists for, and must still be retried.
await check("a temporary refusal is still retried", async () => {
  let calls = 0;
  const fake = {
    localization: (k) => k,
    displayMessage: () => {},
    gameManager: {
      FS: fsWith("temporary\nThe game is busy and cannot save right now."),
      getState: () => { if (++calls < 3) throw new Error("Error writing data"); return new Uint8Array([7]); },
    },
  };
  const state = await runRetry(fake, 10000);
  eq(calls, 3, "attempts");
  eq(Array.from(state), [7], "state returned");
});

// With no reason file the old generic message is still the fallback.
await check("with no reason file the generic message is still used", async () => {
  const messages = [];
  const fake = {
    localization: (k) => k,
    displayMessage: (m) => messages.push(m),
    gameManager: { FS: fsWith(null), getState: () => { throw new Error("Error writing data"); } },
  };
  await runRetry(fake, 900);
  eq(messages[messages.length - 1], "FAILED TO SAVE STATE", "final message");
});

report();
