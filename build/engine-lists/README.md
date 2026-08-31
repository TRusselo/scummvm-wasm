# Engine lists

Used with `ENGINES_LIST_FILE` in `build/build-core.sh` to override the
default `lite_engines.list` content. `build-core.sh` uses
`all-engines.list` by default; point `ENGINES_LIST_FILE` elsewhere (e.g.
a single-engine file) for a narrower/faster build.

## Two cores, split by GL involvement, not by which engines strictly require it

Two engines' worth of ScummVM game code involve GL/3D concepts in any way
-- literally or via ScummVM's own bundled software rasterizer -- go into
`gl-core.list`, not just the ones that hard-require it. Only 3 engines
(`hpl1`, `twp`, `watchmaker`) actually declare the gated
`opengl_game_shaders`/`opengl_game_classic` tokens that require
`FORCE_OPENGLES2=1`; the rest of `gl-core.list` only reference `3d`/
`tinygl` (ScummVM's own bundled *software* 3D rasterizer, unconditionally
compiled in regardless of `FORCE_OPENGLES2` -- confirmed by an isolated
`grim`-only build that linked cleanly with no GL flag at all). They'd
compile fine in the main core. They're kept out anyway: one core for pure
2D, one core for anything GL-touching, rather than a small set of
case-by-case exceptions to remember. `testbed` and `playground3d` are
excluded from both lists entirely -- they're ScummVM's own internal
dev/test harnesses (`build-by-default: no`), not real games.

## all-engines.list

103 engines: every ScummVM engine except the 11 in `gl-core.list` (and
`testbed`/`playground3d`, excluded from both). Built with `USE_HIGHRES=1`
(this project's default -- see `docs/GOTCHAS.md`'s `USE_HIGHRES` section
for why, and the pillarboxing tradeoff that decision carries for SCUMM and
other lowres-native engines). An earlier `USE_HIGHRES=0` compile-only pass
linked only 55 of the-then 103 engines in this list -- the other 48 all
declare `highres` as a dependency and were silently disabled, not broken.
That's why this list now requires `USE_HIGHRES=1`.

Compile-only signal: this list has not been runtime-tested game-by-game.
A clean compile here means nothing more than "the C++ built" -- per-engine
runtime bugs (see SCUMM's own save-state fixes) are still expected and
get found by playing each engine's games individually.

## gl-core.list

11 engines: `alcachofa`, `freescape`, `grim`, `hpl1`, `myst3`, `stark`,
`tetraedge`, `tinsel`, `twp`, `watchmaker`, `wintermute`. Meant to be built
as a *separate* core/binary with `FORCE_OPENGLES2=1` (needed by 3 of the
11; harmless for the other 8, which only use TinyGL). Not yet built or
runtime-tested as a group -- only `grim` has been compile-tested in
isolation so far, and only without the GL flag. See
`docs/GOTCHAS.md`'s `USE_HIGHRES` section for how this maps onto ROMM/EJS
(a second named core under the same "ScummVM" platform, not a separate
platform).
