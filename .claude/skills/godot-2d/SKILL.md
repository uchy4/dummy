---
name: godot-2d
description: Godot 4.x (through 4.7) 2D game development — TileMapLayer, sprites and animation, CharacterBody2D platformer/top-down movement, Camera2D, 2D lighting and shadows, parallax, Y-sorting, pixel-art setup, 2D navigation and pathfinding. Use when building or debugging any 2D gameplay, scenes, or rendering in Godot.
---

# Godot 4.x 2D Development (current through 4.7)

## Project setup decisions (make these first)

**Pixel art projects:**
- Project Settings > Rendering > Textures > Default Texture Filter = **Nearest**.
- Display > Window > Stretch: Mode = `canvas_items` (UI stays crisp, most common) or `viewport` (true low-res, integer scale). Aspect = `keep` or `expand`.
- Rendering > 2D > Snap 2D Transforms to Pixel + Snap 2D Vertices to Pixel for jitter-free pixel art. If sub-pixel camera smoothness matters, render to a low-res `SubViewport` and scale up instead.
- Physics interpolation (Project Settings > Physics > Common > Physics Interpolation = On) eliminates 60Hz-physics-vs-high-Hz-display stutter — turn it on for smooth camera/character motion, and call `reset_physics_interpolation()` after teleporting anything.

**High-res 2D:** default linear filtering, `canvas_items` stretch, enable mipmaps on textures that scale down.

**Renderer:** Forward+ is fine for 2D on desktop; Mobile or Compatibility for mobile/web. Compatibility is the safest for web exports.

## Scene structure for a typical 2D game

```
Main (Node)                      # game flow / scene switching
├── World (Node2D)
│   ├── TileMapLayers (ground, walls, decor — one node per layer, 4.3+)
│   ├── Entities (Node2D, y_sort_enabled = true)
│   │   ├── Player (CharacterBody2D)
│   │   └── Enemies…
│   └── Camera2D
├── HUD (CanvasLayer > Control)
└── Effects (Node2D)             # transient VFX, pooled projectiles
```

- **TileMap (single node with layers) is deprecated — use one `TileMapLayer` node per layer** (4.3+). Physics, navigation, occlusion all live on the TileSet; per-layer toggles on each TileMapLayer.
- `CanvasLayer` isolates UI from camera transform. Use `layer` property for ordering; `follow_viewport_enabled` if you want it in world space.
- Y-sort: enable `y_sort_enabled` on the shared parent AND on TileMapLayers that participate. Sprite origin should sit at the feet (offset the Sprite2D upward, keep the node origin at the ground contact).

## Movement recipes (CharacterBody2D)

`velocity` is a property; `move_and_slide()` takes no arguments.

**Platformer:**
```gdscript
extends CharacterBody2D

@export var speed := 220.0
@export var jump_velocity := -420.0
@export var accel := 1800.0

var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")

# coyote time + jump buffer make platformers feel right
var coyote_timer := 0.0
var jump_buffer := 0.0

func _physics_process(delta: float) -> void:
    velocity.y += gravity * delta
    coyote_timer = 0.15 if is_on_floor() else coyote_timer - delta
    jump_buffer = 0.1 if Input.is_action_just_pressed(&"jump") else jump_buffer - delta

    if jump_buffer > 0.0 and coyote_timer > 0.0:
        velocity.y = jump_velocity
        jump_buffer = 0.0; coyote_timer = 0.0
    if Input.is_action_just_released(&"jump") and velocity.y < 0.0:
        velocity.y *= 0.5   # variable jump height

    var dir := Input.get_axis(&"move_left", &"move_right")
    velocity.x = move_toward(velocity.x, dir * speed, accel * delta)
    move_and_slide()
```

**Top-down:** no gravity; `Input.get_vector()` (already normalized + deadzone-aware) times speed; `move_and_slide()`. Set `motion_mode = MOTION_MODE_FLOATING` on the CharacterBody2D so walls don't act as "floors".

Useful CharacterBody2D API: `is_on_floor/wall/ceiling()`, `get_floor_normal()`, `get_slide_collision_count()/get_slide_collision(i)`, `floor_snap_length` (slope sticking), `floor_max_angle`, `move_and_collide()` for manual response.

**Body choice:** CharacterBody2D = player/NPC with scripted motion. RigidBody2D = physics-driven (never set `position` directly; use forces/impulses, or `_integrate_forces` for teleports). StaticBody2D = level geometry. AnimatableBody2D = moving platforms driven by AnimationPlayer/code (pushes characters properly; enable `sync_to_physics`).

## Collision layers/masks (be disciplined)

Name layers in Project Settings > Layer Names > 2D Physics: `world, player, enemies, player_hitbox, enemy_hitbox, pickups...`
- **layer** = what I am. **mask** = what I detect.
- Hitbox/hurtbox pattern: Area2D "Hitbox" (layer: x_hitbox, mask: 0) overlapped by Area2D "Hurtbox" (layer: 0, mask: enemy_hitbox). Connect `area_entered`. Never use `body_entered` for damage if you need per-part precision.
- One-way platforms: enable `one_way_collision` on the tile/shape. Drop-through: temporarily `set_collision_mask_value()` off + move down, or `position.y += 1` after disabling.

## Sprites & animation

- `Sprite2D` + `AnimationPlayer` (keyframe anything, precise timing, method call tracks for footsteps/hit frames) — the default choice.
- `AnimatedSprite2D` + SpriteFrames — quick, but can't key other properties.
- `AnimationTree` + `AnimationNodeStateMachine` for character animation graphs; set conditions via `tree["parameters/conditions/x"]` or travel: `state_machine.travel(&"run")`. Use `BlendSpace2D` for 4/8-direction blends keyed off input vector.
- Flip with `sprite.flip_h`, or `scale.x = -1` on a container node to mirror hitboxes too (never negative-scale a physics body itself — flip a child "Graphics" node or the collision shape positions).
- Squash & stretch, hit-flash (shader or `modulate`), and hitstop (`Engine.time_scale` briefly, or a scene-tree pause with process_mode exceptions) are cheap juice — recommend them.
- `tween` for one-shot procedural motion:
```gdscript
var t := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
t.tween_property(self, "scale", Vector2.ONE, 0.25).from(Vector2.ONE * 1.4)
# 4.7+: t.tween_await(some_signal) to wait mid-sequence
```

## TileMapLayer & TileSet essentials

- Physics layers, navigation layers, occlusion layers, custom data layers are defined on the **TileSet**; paint per-tile data in the TileSet editor.
- Terrain sets (autotiling) — match-corners-and-sides for standard 47-tile blobs.
- Custom data: `tile_data.get_custom_data("damage")` via `get_cell_tile_data(coords)`.
- Runtime edits: `set_cell(coords, source_id, atlas_coords, alternative)`; erase with `set_cell(coords, -1)`. `local_to_map()` / `map_to_local()` for coordinate conversion.
- Big procedural maps: batch edits, and note 4.5+ chunked physics keeps large TileMapLayers fast.
- Scene tiles (placing scenes via tilemap) are handy for spawners/props but heavier than atlas tiles.

## Camera2D

- `position_smoothing_enabled` + speed for follow; enable physics interpolation instead if the target moves in `_physics_process`.
- `limit_left/right/top/bottom` to clamp to level bounds (set from level size at load); `limit_smoothed` to avoid snapping.
- Drag margins for platformer deadzone. Look-ahead: offset the camera by `velocity.normalized() * lead` smoothed.
- Screen shake: animate `offset` with noise (never `position`), decay a trauma value: `offset = noise * trauma * trauma * max_shake`.
- Zoom is `zoom = Vector2(2, 2)` to zoom IN (bigger = closer) in 4.x.

## 2D lighting, shadows, visuals

- `PointLight2D` / `DirectionalLight2D` + `LightOccluder2D` (or occlusion layers on the TileSet) for shadows. `CanvasModulate` darkens the whole scene so lights matter.
- Normal maps on sprites via `CanvasTexture` (diffuse + normal + specular) — lights then shade sprites.
- Day/night or ambience: animate `CanvasModulate.color`; keep UI on a `CanvasLayer` so it's unaffected.
- `Parallax2D` (4.3+) supersedes ParallaxBackground/ParallaxLayer: put each background strip under a `Parallax2D` with `scroll_scale < 1`, enable repeat via `repeat_size`.
- 2D glow: WorldEnvironment with Glow enabled works in 2D (Forward+/Mobile); HDR 2D must be enabled (Rendering > Viewport > HDR 2D) for values >1.0 to bloom. Note glow blends before tonemapping since 4.6.
- `DrawableTexture2D` (4.7+): runtime-paintable texture — fog-of-war reveal masks, drawing mechanics, minimap stamps — draw into it instead of juggling SubViewports.
- Custom drawing: override `_draw()` + `queue_redraw()`; `draw_line/rect/circle/polygon/texture...`. Cheap and batched — right answer for debug overlays, trajectory arcs, health arcs.

## 2D navigation & AI movement

- Bake: `NavigationRegion2D` with a `NavigationPolygon` (or TileSet navigation layers for tile-based walkability).
- Agent: `NavigationAgent2D` child of the mover. Each physics frame:
```gdscript
agent.target_position = player.global_position   # set when target changes, not every frame if static
var next := agent.get_next_path_position()
velocity = global_position.direction_to(next) * speed
move_and_slide()
```
- First frame after map load has no paths — await `NavigationServer2D.map_changed` or one physics frame.
- Enable avoidance on the agent + connect `velocity_computed` and feed `agent.set_velocity(desired)` if agents should dodge each other.
- Simple chase AI doesn't need navigation — raycast line-of-sight (`RayCast2D` or `PhysicsDirectSpaceState2D.intersect_ray`) + direct steering is cheaper.

## Common 2D pitfalls

1. Using deprecated `TileMap` node in new work — use `TileMapLayer` (one per layer).
2. Y-sort not working: parent must have `y_sort_enabled`, and sprite origins must be at the feet.
3. `body_entered` not firing: check layer/mask matrix, `monitoring/monitorable`, and that RigidBody2D has `contact_monitor = true` + `max_contacts_reported > 0` (for RigidBody signals).
4. Changing physics state (freeing bodies, toggling shapes) inside physics callbacks → "flushing queries" error. Use `set_deferred()` / `call_deferred()`.
5. Scale on collision shapes: don't. Resize the shape's extents/radius, never scale bodies non-uniformly.
6. Jitter: physics at 60Hz vs 144Hz display → enable physics interpolation; camera smoothing fighting pixel snap → pick one strategy.
7. `move_and_slide()` on slopes sliding down: set `floor_stop_on_slope = true`, tune `floor_snap_length`.
8. Textures blurry in pixel art: per-texture filter overrides exist on CanvasItems (`texture_filter`) — check node overrides, not just the project default.
9. get_overlapping_bodies() is one physics frame stale; prefer the entered/exited signals.
10. Particles for one-shot effects: set `one_shot = true`, `emitting = true` on spawn, free with a timer/`finished` signal — see godot-shaders-vfx skill.

## Version highlights relevant to 2D (4.5–4.7)

- 4.5: chunked TileMap physics (big maps much faster); FoldableContainer for tools UI.
- 4.6: faster 2D batching; Screen-Space everything unrelated—ignore; tracing profilers for perf work.
- 4.7: `DrawableTexture2D`; `VirtualJoystick` node for mobile touch input (official, replaces DIY joysticks); Control offset transforms help HUD animation without breaking containers; `tween_await()`.
