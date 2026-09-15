# Draft comment -> EmulatorJS/EmulatorJS#1263

Status: the core runs in unmodified EmulatorJS. I built a stock tree at 0b1c5e9
with only this core installed, and Zak McKracken, Beneath a Steel Sky and
King's Quest 1 all auto-detect, launch and play with sound. 89 engines of 107
confirmed so far.

Before I polish anything I'd rather ask about size, because the answer changes
what I build.

The core `.data` is 94.3 MB. 77.4 MB of that is ScummVM's engine-data, which I
currently bake into the wasm with `--embed-file`. For comparison your largest
core is fbneo at 7.9 MB.

I don't think that's as bad as it first looks: cores are per-core npm packages,
so nobody who doesn't want it installs it, and it's fetched on demand and
cached, so a site that installs it but whose users never open a ScummVM game
transfers none of it. But it's your distribution, so it's your call.

Three shapes, and I'm happy with any:

1. Leave it baked. Nothing to write, works today.
2. Companion asset, like ppsspp. libretro's makefile already has a `datafiles`
   target that produces `scummvm.zip` for exactly this; the core drops to
   roughly 16 MB and the data is fetched at game start. This needs something on
   your side equivalent to `loadPpssppAssets()`.
3. Same as 2, but split per engine later. `fonts-cjk.dat` is 38.3 MB and
   `ultima.dat` is 16.0 MB of the 77.4 MB, and almost no game needs either.
   This is the only option that makes the common case small.

Two things I found in EmulatorJS while testing, both fixed locally and happy to
PR separately:

- `cores/reports/<core>.json` is requested with `responseType: "text"` and then
  discarded by the `typeof rep.data === "string"` branch, so `defaultWebGL2` is
  never read and every core is requested under its `-legacy` filename. For a
  core this size that doubles what has to be published.
- The canvas gets `ejs-canvas-no-pointer` whenever the device reports a
  touchscreen, but the virtual gamepad is only shown on a real touch. On a
  touchscreen laptop neither is active and the mouse does nothing. Honouring
  `core.json`'s `supportsMouse` fixes it without affecting other cores.

Is a ScummVM fork under EmulatorJS something you'd want, and which of the three
shapes should I aim at?
