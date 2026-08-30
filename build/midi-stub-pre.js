// ScummVM's WebMIDI plugin (scummvm-core/backends/midi/webmidi.cpp) is
// compiled in unconditionally for any Emscripten build (see
// scummvm-core/backends/module.mk's unconditional `ifdef EMSCRIPTEN`
// block), but the JS glue that populates `midiOutputMap` via
// navigator.requestMIDIAccess() only exists in ScummVM's own standalone
// Emscripten shell (scummvm-core/dists/emscripten/custom_shell-pre.js),
// which this RetroArch/EmulatorJS-based build never includes. Without it,
// the plugin's EM_JS/EM_ASYNC_JS blocks throw "midiOutputMap is not
// defined" the first time ScummVM's sound driver enumerates MIDI outputs
// at startup -- fatally, since HAVE_THREADS=1 runs that enumeration on a
// spawned pthread worker, where Web MIDI is unavailable regardless.
//
// This build has no use for real MIDI hardware output, so rather than
// wiring up real navigator.requestMIDIAccess() support (which wouldn't
// work from a worker thread anyway), stub the map as permanently empty:
// ScummVM's getDevices() then correctly reports zero MIDI devices and
// falls back to its built-in music drivers, instead of crashing.
var midiOutputMap = new Map();
