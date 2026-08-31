# Engine lists

Used with `ENGINES_LIST_FILE` in `build/build-core.sh` to override the
default `lite_engines.list` content. `build-core.sh` uses
`all-engines.list` by default; point `ENGINES_LIST_FILE` elsewhere (e.g.
a single-engine file) for a narrower/faster build.

## all-engines.list

103 engines: every ScummVM engine except the 13 whose own
`configure.engine` declares a `3d` dependency or a `tinygl` component
(`alcachofa`, `freescape`, `grim`, `hpl1`, `myst3`, `playground3d`,
`stark`, `testbed`, `tetraedge`, `tinsel`, `twp`, `watchmaker`,
`wintermute`). Those need `FORCE_OPENGLES2=1` (an existing, untested-under-
Emscripten libretro build flag) and are being spiked separately, one
engine at a time, rather than folded into this build.

Built with `USE_HIGHRES=1` (this project's default -- see
`docs/GOTCHAS.md`'s `USE_HIGHRES` section for why, and the pillarboxing
tradeoff that decision carries for SCUMM and other lowres-native engines).
An earlier `USE_HIGHRES=0` compile-only pass with this same list linked
only 55 of the 103 engines -- the other 48 all declare `highres` as a
dependency and were silently disabled, not broken. That's why this list
now requires `USE_HIGHRES=1` to build all 103 engines it names.

Compile-only signal: this list has not been runtime-tested game-by-game.
A clean compile here means nothing more than "the C++ built" -- per-engine
runtime bugs (see SCUMM's own save-state fixes) are still expected and
get found by playing each engine's games individually.
