#!/usr/bin/env python3
"""Patch a Godot web export so it runs outside a browser "secure context".

Phones load the engine client over plain http from the host phone, which
browsers never treat as secure: Godot's shell refuses to start and the
AudioWorklet APIs are absent. This single-threaded build needs neither, so:
- shell: drop the Secure Context entry from the missing-features refusal
- engine js: only load the audio-position worklet when audioWorklet exists,
  and start samples directly when it doesn't (sfx are WAV samples that then
  play through plain WebAudio nodes; only position reporting is lost).

Usage: patch_web_shell.py <export-dir>   (expects index.html + index.js)
Asserts fail loudly if a Godot upgrade changes the anchored code.
"""
import sys

d = sys.argv[1].rstrip("/")

p = d + "/index.html"
s = open(p).read()
old = "const missing = Engine.getMissingFeatures({\n\t\tthreads: GODOT_THREADS_ENABLED,\n\t});"
assert s.count(old) == 1, "shell changed: update secure-context patch"
s = s.replace(old, old[:-1] + ".filter(function (m) { return m.indexOf('Secure Context') === -1; });")
open(p, "w").write(s)

p = d + "/index.js"
s = open(p).read()
old = "GodotAudio.audioPositionWorkletPromise=ctx.audioWorklet.addModule(path);"
assert s.count(old) == 1, "engine js changed: update audio-init patch"
s = s.replace(old, "GodotAudio.audioPositionWorkletPromise=ctx.audioWorklet?ctx.audioWorklet.addModule(path):Promise.resolve();")
old = "async connectPositionWorklet(start){await GodotAudio.audioPositionWorkletPromise;"
assert s.count(old) == 1, "engine js changed: update sample-start patch"
s = s.replace(old, "async connectPositionWorklet(start){if(!GodotAudio.ctx.audioWorklet){if(start){this.start()}return}await GodotAudio.audioPositionWorkletPromise;")
open(p, "w").write(s)

print("insecure-context patches applied to " + d)
