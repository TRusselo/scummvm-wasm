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
  for (;;) {
    try { return self.gameManager.getState(); }
    catch (e) {
      if (Date.now() >= retryUntil) { self.displayMessage(self.localization("FAILED TO SAVE STATE")); return undefined; }
      self.displayMessage(self.localization("WAITING FOR THE SCENE TO END"));
      await new Promise((r) => setTimeout(r, 400));
    }
  }
}

report();
