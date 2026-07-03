---
name: godot-performance
description: Godot 4.x performance profiling and optimization — built-in and tracing profilers (4.6+), rendering optimization for 2D and 3D (draw calls, lights, culling, MultiMesh), GDScript hot-path optimization, physics tuning, memory/leak hunting with ObjectDB snapshots, threading, and load-time optimization. Use when a Godot game is slow, stuttering, leaking memory, or loading slowly — or when reviewing code for performance.
---

# Godot Performance (4.x, current through 4.7)

## Rule zero: profile before touching anything

Guessing wastes days; the profiler takes minutes. Identify which of the four budgets is blown:

1. **CPU — script/game logic** → Debugger > Profiler (enable, play, sort by self-time). Watch for per-frame `_process` costs and physics callbacks.
2. **CPU — rendering prep / draw submission** → Visual Profiler + Monitors (draw calls, primitives).
3. **GPU** → Visual Profiler (per-pass timings); if frame time drops when you shrink the window, you're GPU fragment-bound.
4. **Stutter (spikes, not average)** → different beast: shader compilation, resource loads on main thread, GC-like bursts (freeing many nodes), physics spikes.

Tools:
- **Debugger > Monitors**: FPS, frame time, draw calls, video memory, object/node counts, physics active bodies — trend these while playing.
- **Visual Profiler**: CPU+GPU per render pass.
- **Tracing profilers (4.6+)**: hook Godot to Tracy / Perfetto / Instruments for real flame graphs across engine + scripts — use for anything the built-in profiler can't localize (spikes, threading).
- **ObjectDB snapshots + diff (4.6+)**: capture live object sets at two moments, diff to find leaks (nodes/RefCounted piling up).
- `Performance.get_monitor()` / custom monitors (`Performance.add_custom_monitor`) for in-game overlays.
- Print scene stats: `print_tree_pretty()`, `Performance.OBJECT_NODE_COUNT`.
- CLI: `--print-fps`, `--gpu-profile`; `--headless` for server perf tests.

Optimize the measured top item, re-measure, repeat. Below are the levers by area.

## GDScript / logic CPU

- Static-type hot paths (typed calls dispatch faster); typed `Array[T]`/`Packed*Array` over untyped.
- Kill per-frame allocations: no `[]`/`{}`/lambda/`String` concat churn inside `_process` of many instances.
- **N instances × per-frame script is the scaling wall.** Past ~hundreds: manager pattern — one node iterates a typed array of lightweight objects (`RefCounted` or struct-like arrays), applies results to visuals (or MultiMesh). Past ~thousands: Servers API (below) or GDExtension/C#.
- Timers/cooldowns for logic that doesn't need every frame: AI think at 5–10Hz (stagger offsets so they don't all think the same frame), `VisibleOnScreenNotifier2D/3D` to sleep off-screen entities, `_physics_process` only where physics actually matters (`set_physics_process(false)` aggressively).
- Distance checks: `distance_squared_to`; spatial partitioning rarely needed — physics queries (Area monitoring, `intersect_shape`) already use the broadphase.
- `await`/coroutines are cheap; signal emission is cheap; `get_node` per frame is not (cache in `@onready`).
- Move genuinely heavy pure computation (procgen, pathfind grids) to `WorkerThreadPool.add_task()` / `Thread`; interact with the scene tree only via `call_deferred` (the tree is not thread-safe). Servers (Physics/Rendering) support thread-safe commands.

## Rendering — 2D

- **Draw calls / batching**: 2D batches break on material, texture, and certain node changes. Use texture **atlases** (or sprite sheets) so neighbors share textures; share ShaderMaterials (per-instance look via modulate/vertex color, not duplicated materials). 4.6+ batching is faster but the same rules apply.
- Lights: each 2D light with shadows re-draws occluders; budget shadowed lights, shrink light `texture_scale`/range.
- Particles > many animated sprite nodes for ambient junk (leaves, sparks, crowds via MultiMesh2D).
- TileMapLayer: fine at huge sizes (4.5+ chunked physics); avoid per-frame `set_cell` storms — batch, or use a shader for animated overlays (water) instead of tile animation when massive.
- `_draw()` custom drawing is batched and cheap — often beats node spam (grids, graphs, hundreds of lines).
- Fullscreen `hint_screen_texture` shaders force a screen copy — a few are fine; ten stacked are not.
- Hide ≠ free: `visible = false` still processes scripts; `process_mode = DISABLED` to truly sleep.

## Rendering — 3D

Priority-ordered levers:
1. **Shadowed lights** — the classic killer. Audit every OmniLight3D/SpotLight3D `shadow_enabled`; use `distance_fade` on lights & shadows; DirectionalLight3D `directional_shadow_max_distance` as low as looks acceptable; shadow atlas size in project settings.
2. **Draw calls / instance count** — Monitors > drawcalls. Merge small static meshes (in DCC or via mesh merging), **MultiMeshInstance3D** for repeated meshes (grass, debris, crowds — one draw call for thousands; per-instance transform/color/custom data; update via `multimesh.set_instance_transform`).
3. **Culling** — Occlusion culling (bake OccluderInstance3D, enable in project settings) for indoor/dense scenes; `visibility_range_begin/end` (HLOD, fade modes) for open areas; camera `far` plane sanity.
4. **Mesh LOD** — automatic on import (check it's on); tune LOD bias per aggressive target.
5. **Fragment cost** — overdraw from transparency (particles, foliage): alpha scissor over alpha blend; fewer/larger particles; `depth_draw_opaque` on water. Expensive Environment features: SSR > volumetric fog > SSAO/SSIL > SDFGI — drop or half-res per target tier.
6. **Resolution scaling** — Rendering > Scaling 3D: FSR2/bilinear at 0.67–0.77 with sharpening rescues fragment-bound scenes; MetalFX on Apple; 4.7 nearest-neighbor for stylized.
7. GI: LightmapGI (baked) is the cheap runtime option; SDFGI/VoxelGI cost real GPU — reserve for hardware tiers that afford them (expose graphics settings).
- Renderer choice matters: Mobile renderer on mobile (or even desktop for simple games) is dramatically cheaper than Forward+.

## Physics

- Monitors: physics process time + active body count.
- Collision shapes: primitives (sphere < capsule < box < cylinder < convex < trimesh/concave). **Trimesh (ConcavePolygonShape3D) only for static level geometry, never moving bodies.** Simplify player-facing shapes to capsules.
- Fewer active rigid bodies: let them **sleep** (default; don't poke them per frame), freeze distant ones (`freeze = true` / streaming).
- Areas monitoring is not free — huge always-on Areas with broad masks scan everything: tighten layer/mask so pairs that can't interact are never tested.
- Raycast storms (AI vision × N agents): stagger across frames; use `intersect_ray` with tight masks.
- Physics tick: 60Hz default; lower to 30 + physics interpolation for mobile/large sims if gameplay tolerates; never raise it to fix tunneling — use CCD or shape casts.
- Jolt (default since 4.6) is faster and stabler for stacks/ragdolls; if on an older project, switching from Godot Physics is often a free win (retest tuning).
- Don't resize/rebuild collision shapes per frame (shape re-registration cost) — swap between pre-made shapes or use `disabled`.

## Memory & leaks

- Leak signature: Monitors > object/node count climbing across gameplay loops that should be steady-state.
- **ObjectDB snapshot diff (4.6+)**: snapshot before & after a suspect loop (open/close menu ×10), diff → the leaked class stares back.
- Usual suspects: RefCounted reference cycles (A↔B — break with `weakref` or explicit `clear()`), nodes removed from tree but never freed (`remove_child` without `queue_free`), signals holding lambdas capturing big objects, static vars in scripts, arrays in autoloads that only ever `append`.
- On exit with `--verbose`, Godot prints leaked instances ("ObjectDB instances leaked at exit").
- Textures dominate VRAM: VRAM-compressed import for 3D, mipmaps only where needed, check Monitors > video memory; `Image`/`Texture` you create in code are RefCounted — drop references.

## Stutter (frame spikes)

- **Shader compilation stutter**: first time a material variant renders. Fix: shader baker at export (4.5+), plus warm-up (instance every effect/material once behind a loading screen). Ubershaders reduce it on Forward+ but warming still helps.
- **Loading on main thread**: `load()` of big scenes/textures mid-gameplay. Fix: `ResourceLoader.load_threaded_request` (+ progress polling), preload during transitions, background-load next area.
- **Instantiating huge scenes**: `instantiate()` + `add_child` of a whole level spikes; split levels into chunks added across frames, or instantiate in a thread (scenes without tree access) then add.
- **Mass free**: `queue_free()` on 5,000 nodes in one frame stalls; stagger or pool.
- Physics spawn spikes: adding many bodies at once — stagger.
- Watch for OS/driver vsync anomalies: test `display/window/vsync` modes before blaming the engine.

## Load time & size

- Threaded loading for anything > a few MB; show progress.
- Import settings: texture sizes sane for target (no 4K albedo on mobile props), audio: streams (`.ogg`) for music, `.wav` (small, uncompressed) for SFX.
- `PackedScene` count over monolithic scenes → smaller incremental loads.
- Export: strip debug, compress textures per-platform (see godot-export-platforms skill).

## Quick reference: scaling ladders

| Entities | Approach |
|---|---|
| < 200 | plain nodes + scripts, don't optimize |
| 200–2,000 | manager iterating typed arrays; visuals as nodes or MultiMesh; sleep off-screen |
| 2,000–50,000 | MultiMesh + PackedArrays; PhysicsServer direct bodies/areas if needed |
| beyond / heavy math | Servers API end-to-end, GDExtension (C++/Rust) or C#, compute shaders |

Servers taste (bypass nodes entirely):
```gdscript
var rid := RenderingServer.canvas_item_create()
RenderingServer.canvas_item_set_parent(rid, get_canvas_item())
RenderingServer.canvas_item_add_texture_rect(rid, rect, tex.get_rid())
# same idea: PhysicsServer2D.body_create(), area_create() … store RIDs in PackedArrays
```
