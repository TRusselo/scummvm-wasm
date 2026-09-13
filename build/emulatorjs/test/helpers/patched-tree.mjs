// Builds a throwaway copy of EmulatorJS's data/src with this project's
// patches applied, exactly as assemble.sh does, so tests exercise the real
// vendored code rather than a transcription of it.
//
// cache.js and emulator.js are not in this repository -- assemble.sh clones
// EmulatorJS at a pinned commit -- so point EJS_SRC at an EmulatorJS
// checkout's data/src. Tests skip rather than fail when there isn't one.
import { readFileSync, mkdtempSync, cpSync, copyFileSync, rmSync, existsSync } from "node:fs";
import { join, dirname } from "node:path";
import { tmpdir, homedir } from "node:os";
import { fileURLToPath } from "node:url";
import { execFileSync } from "node:child_process";

const HERE = dirname(fileURLToPath(import.meta.url));
const PATCHES = join(HERE, "..", "..", "patches");
const OURS = join(HERE, "..", "..", "src");

export const EJS_SRC = process.env.EJS_SRC || join(homedir(), "git", "EmulatorJS", "data", "src");

/**
 * @param {object} opts
 * @param {boolean} opts.full Copy the whole src tree and patch emulator.js
 *   too. Needed to import emulator.js; cache.js alone needs only a few files.
 * @returns {string|null} the work directory, or null when there is no
 *   EmulatorJS source to build from (the caller should skip).
 */
export function patchedTree({ full = false } = {}) {
  if (!existsSync(join(EJS_SRC, "cache.js"))) {
    console.log(`SKIP  no EmulatorJS source at ${EJS_SRC}`);
    console.log("      set EJS_SRC=<EmulatorJS checkout>/data/src to run this test");
    return null;
  }

  const work = mkdtempSync(join(tmpdir(), "ejs-test-"));
  process.on("exit", () => rmSync(work, { recursive: true, force: true }));

  if (full) {
    cpSync(EJS_SRC, work, { recursive: true });
  } else {
    for (const f of ["utils.js", "storage.js", "compression.js", "cache.js"]) {
      copyFileSync(join(EJS_SRC, f), join(work, f));
    }
  }
  copyFileSync(join(OURS, "zipstream.js"), join(work, "zipstream.js"));

  execFileSync("patch", ["-s", join(work, "cache.js")], {
    input: readFileSync(join(PATCHES, "01-cache-streaming.patch")),
  });
  if (full) {
    // Every emulator.js patch, in the order assemble.sh applies them -- a test
    // against a partially patched file is testing something we do not ship.
    for (const name of [
      "02-emulator-onfile.patch",
      "03-canvas-pointer-events.patch",
      "04-savestate-retry.patch",
    ]) {
      execFileSync("patch", ["-s", join(work, "emulator.js")], {
        input: readFileSync(join(PATCHES, name)),
      });
    }
  }
  return work;
}

/**
 * emulator.js touches these at import time. navigator already exists in Node
 * and is getter-only, so it is deliberately left alone.
 */
export function stubBrowserGlobals() {
  globalThis.window = globalThis;
  globalThis.document = {
    createElement: () => ({
      style: {}, classList: { add() {}, remove() {} },
      setAttribute() {}, appendChild() {},
    }),
    addEventListener() {},
    body: { appendChild() {} },
  };
}

/** The hand-rolled harness the other tests in this directory use. */
export function harness() {
  const state = { failures: 0 };
  const check = (name, fn) => {
    const done = () => console.log(`  ok    ${name}`);
    const fail = (e) => { state.failures++; console.error(`  FAIL  ${name}\n        ${e.message}`); };
    try {
      const r = fn();
      return r && typeof r.then === "function" ? r.then(done, fail) : (done(), Promise.resolve());
    } catch (e) { fail(e); return Promise.resolve(); }
  };
  const eq = (actual, expected, what) => {
    const a = JSON.stringify(actual), b = JSON.stringify(expected);
    if (a !== b) throw new Error(`${what}: got ${a}, want ${b}`);
  };
  const report = () => {
    console.log(state.failures ? `\n${state.failures} failure(s)` : "\nall passed");
    process.exit(state.failures ? 1 : 0);
  };
  return { check, eq, report };
}
