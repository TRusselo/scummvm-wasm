# Engine lists

Used with `ENGINES_LIST_FILE` in `build/build-core.sh` to override the
default SCUMM-only `lite_engines.list`.

## 2d-sweep.list

103 engines: every ScummVM engine except the 13 whose own
`configure.engine` declares a `3d` dependency or a `tinygl` component
(`alcachofa`, `freescape`, `grim`, `hpl1`, `myst3`, `playground3d`,
`stark`, `testbed`, `tetraedge`, `tinsel`, `twp`, `watchmaker`,
`wintermute`). Those need `FORCE_OPENGLES2=1` (an existing, untested-under-
Emscripten libretro build flag) and are being spiked separately, one
engine at a time, rather than folded into this compile-only sweep.

Compile-only signal: this list has not been runtime-tested. A clean
compile here means nothing more than "the C++ built" -- per-engine
runtime bugs (see SCUMM's own save-state fixes) are still expected and
get found by playing each engine's games individually.
