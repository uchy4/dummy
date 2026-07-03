---
name: godot-3d
description: Godot 4.x (through 4.7) 3D game development — CharacterBody3D controllers, cameras, lighting and global illumination (LightmapGI/SDFGI/VoxelGI, AreaLight3D), WorldEnvironment and post-processing, asset import (glTF), Jolt physics, LOD/occlusion culling, 3D navigation, skeletons and animation. Use when building or debugging any 3D gameplay, scenes, rendering, or lighting in Godot.
---

# Godot 4.x 3D Development (current through 4.7)

## Project decisions first

- **Renderer**: Forward+ (desktop, full features), Mobile (mobile/quest, cheaper, fewer features), Compatibility (GLES3 — web, old hardware; no SDFGI/volumetrics). Choose early; test on target early.
- **Physics**: Jolt is the default 3D physics engine for new projects since 4.6 (Project Settings > Physics > 3D > Physics Engine). Prefer Jolt — more stable stacking, faster, deterministic-leaning. Godot Physics remains for legacy compat.
- **Scale**: 1 unit = 1 meter. Keep it. Lights, physics, audio attenuation, and GI all assume meters. Playable areas beyond ~few km from origin get float precision jitter — shift the world origin for space/open-world games (or enable large-world coordinates in custom builds).
- **Units of light**: optional physical light units (Project Settings > Rendering > Lights and Shadows) for lumens/lux/EV100 — use for realism pipelines, skip for stylized.

## Scene structure

```
Main (Node)
├── World (Node3D)
│   ├── WorldEnvironment (+ Environment, Camera attributes)
│   ├── Sun (DirectionalLight3D)
│   ├── Level (imported scene / GridMap / CSG greybox)
│   ├── Player (CharacterBody3D)
│   │   ├── CollisionShape3D (capsule)
│   │   ├── Visuals (Node3D → mesh/skeleton)
│   │   └── CameraRig (Node3D → SpringArm3D → Camera3D)
│   └── NPCs, props…
└── HUD (CanvasLayer)
```

- Greybox with CSG (CSGBox3D etc.) — fine for prototyping, has collision; replace with real meshes for production (CSG is slow to edit at scale and generates unoptimized geometry).
- GridMap + MeshLibrary for kit-based/tile-based 3D levels.

## Character controller (CharacterBody3D)

```gdscript
extends CharacterBody3D

@export var speed := 5.0
@export var jump_velocity := 4.5
@export var mouse_sens := 0.002

@onready var cam_pivot: Node3D = %CamPivot

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
        rotate_y(-event.relative.x * mouse_sens)
        cam_pivot.rotate_x(-event.relative.y * mouse_sens)
        cam_pivot.rotation.x = clampf(cam_pivot.rotation.x, -1.2, 1.2)

func _physics_process(delta: float) -> void:
    velocity += get_gravity() * delta          # get_gravity() respects Areas & project settings
    if Input.is_action_just_pressed(&"jump") and is_on_floor():
        velocity.y = jump_velocity

    var input := Input.get_vector(&"left", &"right", &"forward", &"back")
    var dir := (transform.basis * Vector3(input.x, 0, input.y)).normalized()
    var target := dir * speed
    velocity.x = move_toward(velocity.x, target.x, speed * 10.0 * delta)
    velocity.z = move_toward(velocity.z, target.z, speed * 10.0 * delta)
    move_and_slide()
```

- Capture mouse: `Input.mouse_mode = Input.MOUSE_MODE_CAPTURED` (Esc to release during dev).
- Third person: `SpringArm3D` (set its collision mask to world-only) → Camera3D child; camera never clips walls.
- Face movement direction: `visuals.rotation.y = lerp_angle(visuals.rotation.y, atan2(-dir.x, -dir.z) if… , 12.0 * delta)` — rotate a Visuals child, not the body (keeps input basis stable), or rotate the body and drive camera from a detached rig.
- Slopes/steps: `floor_max_angle`, `floor_snap_length`; Jolt handles stairs poorly out of the box — use a low step-height ray/shape-cast teleport or keep collision as a capsule and design ramps.
- RigidBody3D players: only for physics games; use `_integrate_forces` for direct control.

## Lighting & Global Illumination — decision table

| Technique | Cost | Dynamic? | Use when |
|---|---|---|---|
| Plain lights + SSAO/SSIL | low | yes | stylized, mobile |
| **LightmapGI** | bake time; cheapest at runtime | static geo, dynamic objects get probes | best quality/perf for static levels; mobile-friendly |
| **SDFGI** | medium-high GPU | semi (updates over frames) | open worlds, changing time-of-day; Forward+ only |
| **VoxelGI** | medium GPU + bake | yes within baked region | mid-size interiors with dynamic lights |
| ReflectionProbe | low-medium | update mode choice | local specular reflections everywhere you can |

- **DirectionalLight3D**: one sun; shadow mode PSSM 4-splits; tune `directional_shadow_max_distance` down (e.g. 50–100m) for sharper shadows; `light_angular_distance` ~0.5° for soft sun edges.
- OmniLight3D/SpotLight3D: shadows are the expensive part — budget shadowed lights; set `distance_fade` on lights and shadows.
- **AreaLight3D (4.7+)**: real-time rectangular emitters — softboxes, screens, window light. More physically plausible speculars than faking with wide spots; costlier than omni, budget accordingly.
- Emissive materials only light the world via GI (LightmapGI/SDFGI/VoxelGI) — an emissive mesh with no GI does not illuminate.
- Shadow bias artifacts: peter-panning → lower bias; acne → raise bias/normal bias. Tune per-light, not globally.

## WorldEnvironment & post

One `WorldEnvironment` per scene. Environment resource:
- **Tonemap**: AgX (best for HDR/filmic, 4.3+) or ACES. White ~6–16. Since 4.6 glow blends **before** tonemapping (better result, default mode Screen).
- **Glow/bloom**: keep threshold ≥ 1.0 and use emissive materials with energy > 1 rather than lowering threshold.
- Ambient light: from sky (ProceduralSkyMaterial / PhysicalSkyMaterial / panorama HDR).
- SSAO (contact shadows), SSIL (cheap dynamic-ish GI helper), SSR (rewritten in 4.6 — much more stable, explicit half/full-res modes), volumetric fog (Forward+; fog volumes via FogVolume), depth of field via CameraAttributesPractical/Physical.
- Anti-aliasing: MSAA 2–4x (geometry edges) + TAA (specular/foliage shimmer, adds blur) or FSR2 upscaling with built-in AA. Pixel-perfect stylized: consider viewport scaling with **nearest-neighbor 3D scaling (4.7+)**.
- **HDR output (4.7+)**: on supported displays/OS (Windows, macOS, iOS, Linux/Wayland), enable HDR output in display settings for true HDR presentation; author with AgX + emissives, verify SDR fallback.
- Custom full-screen effects: `CompositorEffect` (4.3+) with compute shaders — see godot-shaders-vfx skill.

## Asset import pipeline

- **Use glTF 2.0** (.glb) as the interchange format. `.blend` files import directly if Blender is installed (point Godot at the Blender path) — great for iteration, export .glb for CI/teams.
- Import dock: meshes get generated LODs automatically (mesh LOD); enable "Generate Lightmap UV2" for LightmapGI; physics: create collision from `-col`/`-colonly` suffixes in the DCC or via import settings.
- Materials: import as external so edits persist; or build `StandardMaterial3D` in Godot. `ORMMaterial3D` for packed occlusion/roughness/metallic textures.
- Texture compression: VRAM Compressed (default for 3D) — never Lossless for 3D color textures on GPU-memory-constrained targets. Normal maps: keep "Normal Map" flag so they compress correctly (RGTC).
- Skeletal assets: use consistent rest poses; Godot's retargeting (BoneMap + SkeletonProfileHumanoid) lets one AnimationLibrary drive many characters.

## Skeletons & animation

- `AnimationPlayer` holds libraries; `AnimationTree` for blending: `AnimationNodeStateMachine` (locomotion states) + `BlendSpace2D` (strafe sets) + `OneShot` nodes (attacks; `tree.set("parameters/Shot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)`).
- Root motion: set root motion track on the AnimationTree, apply via `get_root_motion_position()` in `_physics_process`.
- Skeleton modifiers (run after animation): `LookAtModifier3D` (4.4+, head tracking with limits/smoothing), `SpringBoneSimulator3D` (4.5+, hair/tails/cloth-ish jiggle), `SkeletonIK3D` (legacy) / modifier-based IK for foot placement.
- `BoneAttachment3D` to parent props to bones.
- Blend shapes via `MeshInstance3D.set_blend_shape_value()` or animation tracks.

## Physics (Jolt-first)

- Layers/masks same discipline as 2D: layer = what I am, mask = what I hit. Name them.
- RigidBody3D: forces in `_physics_process` or impulses on events; **never set global_position on a sleeping/simulated body per-frame** — teleport via `PhysicsServer3D.body_set_state` or `_integrate_forces`, then `reset_physics_interpolation()`.
- Queries: `get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, mask))` — physics frame only. `ShapeCast3D`/`RayCast3D` nodes for persistent casts (remember `force_raycast_update()` after moving them mid-frame).
- Areas for triggers, gravity/damping overrides, wind. `body_entered` requires the area to monitor and mask to match.
- Vehicle: `VehicleBody3D` for arcade; custom raycast suspension on RigidBody3D for anything serious.
- Continuous collision detection (`continuous_cd`) for fast small projectiles; or use ray/shape casts per-frame instead of physical bullets (hitscan or manual sweep — cheaper and reliable).

## Performance structure (see godot-performance skill for the deep dive)

- **Occlusion culling**: OccluderInstance3D + bake (Project Settings > Rendering > Occlusion Culling on). Big indoor wins.
- **Visibility ranges** (`visibility_range_begin/end` on GeometryInstance3D) for manual HLOD; automatic mesh LOD is on by default via import.
- MultiMeshInstance3D for thousands of identical meshes; GPUParticles3D for scattered animated things.
- Shadow atlas size and light count are the usual GPU killers; `Frame` debugger + visual profiler first.
- Draw-call reduction: merge static meshes where sensible, keep material count per mesh low.

## 3D navigation

- `NavigationRegion3D` → bake NavigationMesh from static geo (mark colliders/mesh sources via geometry parse settings; agent radius/height must match your characters).
- `NavigationAgent3D` same loop as 2D: set `target_position`, steer to `get_next_path_position()`, `move_and_slide()`.
- `NavigationLink3D` for jumps/drops, `NavigationObstacle3D` (carve = true) for dynamic blockers. Runtime rebake: `region.bake_navigation_mesh(true)` off-thread.

## Common 3D pitfalls

1. Rotating the whole CharacterBody3D with the camera pitch — pitch a pivot only, yaw the body.
2. `look_at()` with target == position, or colinear with UP → error; guard or use `look_at_from_position`.
3. Basis drift after many incremental rotations — `transform = transform.orthonormalized()` periodically for long-lived free-rotating bodies.
4. Moving StaticBody3D — it teleports, tunnels, and pushes nothing correctly. Use AnimatableBody3D (`sync_to_physics`) for platforms/doors.
5. Non-uniform scale on physics bodies/collision shapes — Jolt and Godot Physics both misbehave; scale meshes, size shapes.
6. Global transforms in `_ready` before parents finish — cache/setup order issues; use `await get_tree().process_frame` or `NOTIFICATION_TRANSFORM_CHANGED` patterns.
7. GI on Compatibility renderer — SDFGI/VoxelGI don't exist there; LightmapGI works.
8. Shadow-casting point lights everywhere — the #1 frame killer; audit `shadow_enabled`.
9. Baked LightmapGI then moving the level meshes — bakes are transform-dependent; rebake.
10. Forgetting `reset_physics_interpolation()` after teleports → one-frame streak across the level.
11. Water/glass: transparency is expensive and sorts badly — use `depth_draw_opaque`, avoid stacked transparent layers, consider dithered opacity (`alpha_scissor`/`alpha_hash`).

## Version highlights relevant to 3D (4.5–4.7)

- 4.5: stencil buffer support in materials/shaders (outlines, x-ray); shader baker (precompile pipelines → fewer stutters, faster load).
- 4.6: **Jolt default**; SSR rewrite; 3D debanding; glow-before-tonemap; 2× faster 3D (VRAM-compressed) texture import.
- 4.7: **AreaLight3D**; **HDR output**; improved clearcoat; per-particle 3D scale/rotation control improvements; nearest-neighbor 3D viewport scaling; inline shader previews in editor.
