---
name: godot-shaders-vfx
description: Godot 4.x shaders and visual effects — gdshader language (canvas_item, spatial, particles, sky, fog), screen-space effects, GPUParticles2D/3D, common effect recipes (outline, dissolve, hit flash, water, fresnel), CompositorEffects, and 4.7 DrawableTexture2D. Use when writing any .gdshader code, building particle effects, or implementing visual polish/juice.
---

# Godot Shaders & VFX (4.x, current through 4.7)

## gdshader fundamentals

Godot's shading language is GLSL-like with its own scaffolding. Files are `.gdshader`, attached via `ShaderMaterial`.

```glsl
shader_type canvas_item;   // or: spatial, particles, sky, fog

uniform vec4 tint : source_color = vec4(1.0);           // color picker in inspector
uniform float amount : hint_range(0.0, 1.0) = 0.5;
uniform sampler2D noise_tex;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap; // replaces SCREEN_TEXTURE

void fragment() {
    vec4 tex = texture(TEXTURE, UV);
    COLOR = tex * tint;
}
```

Key facts:
- Entry points: `vertex()`, `fragment()`, `light()` (+ `start()`/`process()` for particles).
- Uniform hints: `source_color`, `hint_range`, `hint_screen_texture`, `hint_depth_texture`, `hint_normal_roughness_texture` (Forward+ only), `filter_*`, `repeat_*`.
- **Instance uniforms** (spatial only): `instance uniform float progress;` → per-instance values without duplicating the material (`set_instance_shader_parameter`). For canvas_item, per-instance variation requires distinct materials (`material.duplicate()`) or vertex-color/CUSTOM channels.
- **Global uniforms**: define in Project Settings > Shader Globals, declare `global uniform vec3 wind_dir;`, set via `RenderingServer.global_shader_parameter_set(&"wind_dir", v)` — weather, time-of-day, player position for interactive foliage.
- Set params from script: `material.set_shader_parameter(&"amount", 0.7)` — tween this for animated effects.
- `TIME` is built-in. Random: sample a NoiseTexture2D — there's no rand().
- No `if`-heavy branching on mobile if avoidable; prefer `mix`/`step`/`smoothstep`.

**Editor workflow:** 4.7 adds inline shader previews. Shader errors show in the shader editor panel. VisualShader (node graph) is fine for artists/discovery, but text shaders are the norm for anything maintained in code review.

## canvas_item recipes (2D)

```glsl
// Hit flash — mix to white, drive `flash` from script (tween 1→0)
uniform float flash : hint_range(0.0, 1.0) = 0.0;
void fragment() {
    vec4 c = texture(TEXTURE, UV);
    COLOR = vec4(mix(c.rgb, vec3(1.0), flash), c.a);
}

// Outline — sample neighbors in texture space
uniform vec4 line_color : source_color = vec4(1.0);
uniform float width : hint_range(0.0, 10.0) = 1.0;
void fragment() {
    vec2 px = TEXTURE_PIXEL_SIZE * width;
    float a = texture(TEXTURE, UV).a;
    float outline = texture(TEXTURE, UV + vec2(px.x, 0)).a
        + texture(TEXTURE, UV - vec2(px.x, 0)).a
        + texture(TEXTURE, UV + vec2(0, px.y)).a
        + texture(TEXTURE, UV - vec2(0, px.y)).a;
    outline = min(outline, 1.0) - a;
    vec4 c = texture(TEXTURE, UV);
    COLOR = mix(c, line_color, clamp(outline, 0.0, 1.0));
}
// NOTE: needs transparent padding around the sprite — atlas margins or region padding.

// Dissolve — noise threshold + edge glow
uniform sampler2D noise;               // NoiseTexture2D, seamless
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 edge : source_color = vec4(1.0, 0.5, 0.0, 1.0);
void fragment() {
    vec4 c = texture(TEXTURE, UV);
    float n = texture(noise, UV).r;
    float e = step(n, progress + 0.05) - step(n, progress);
    COLOR = mix(c, edge, e);
    COLOR.a *= step(progress, n) * c.a + e;
}
```

Other staples: palette swap (LUT texture indexed by red channel), sprite wind sway (vertex: `VERTEX.x += sin(TIME * speed + VERTEX.y) * strength * (1.0 - UV.y)`), scrolling UVs, screen-space distortion via `hint_screen_texture` + offset UV (heat haze, shockwaves — put on a ColorRect or sprite ABOVE the scene).

## spatial recipes (3D)

Start from StandardMaterial3D when possible — convert to shader ("Convert to ShaderMaterial") only when you need custom logic; you get the full PBR code to modify.

```glsl
shader_type spatial;

// Fresnel rim (energy shield, ghosts, highlight)
uniform vec4 rim_color : source_color;
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
void fragment() {
    float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
    ALBEDO = vec3(0.1);
    EMISSION = rim_color.rgb * fresnel * 2.0;   // >1 values feed glow
}
```

- Triplanar: just enable UV1 Triplanar on StandardMaterial3D (terrain, greybox) — don't hand-write it first.
- Vertex displacement (flags, water surface): move `VERTEX` in `vertex()`; recompute or fudge `NORMAL` (or `NORMAL_MAP` from a matching normal texture).
- Water: scrolling normal maps ×2 directions, depth fade via `hint_depth_texture` (compare linearized scene depth to FRAGCOUNT depth for shore foam), `render_mode depth_draw_opaque; ` + transparency.
- Toon: custom `light()` function with `smoothstep` on `dot(NORMAL, LIGHT)` bands, or use render_mode `diffuse_toon, specular_toon`.
- Outlines (3D): inverted-hull second material pass (`grow` on StandardMaterial3D next_pass with `cull_front`), or stencil-based (4.5+ stencil support — cleaner for x-ray/see-through-walls).
- World-space effects reaching many objects (snow accumulation on up-facing normals, global wetness): global uniforms + a shared shader include (`#include "res://shaders/common.gdshaderinc"`).

## Screen-space & post

- **2D fullscreen**: ColorRect (Full Rect, on a top CanvasLayer) + canvas_item shader with `hint_screen_texture` — vignette, chromatic aberration, screen flash, pixelate transitions.
- **3D post**: Environment adjustments/glow first (free), then: quad-in-front-of-camera trick is obsolete — use **CompositorEffect** (4.3+): attach a `Compositor` to Camera3D/WorldEnvironment, write a `CompositorEffect` resource running a compute shader at a chosen stage (post-transparent etc.). This is the sanctioned hook for custom passes (SSAO variants, custom fog, painterly filters). It's RenderingDevice-level — Forward+/Mobile only, not Compatibility.
- Glow pipeline note: glow blends before tonemap since 4.6 (Screen default); author emissives in HDR (EMISSION > 1) rather than lowering glow threshold.

## Particles — GPUParticles2D/3D

Default to GPU particles; **CPUParticles** only for Compatibility-renderer targets or very few particles with per-particle script logic needs.

Workflow:
1. `GPUParticles2D/3D` node → `process_material` = **ParticleProcessMaterial** (covers 95%: emission shapes, direction/spread, gravity, velocity curves, scale/color over lifetime via CurveTexture/GradientTexture, turbulence, collision, attractors, sub-emitters).
2. `draw_pass`/`texture`: 3D = QuadMesh (billboard set in the mesh's material: StandardMaterial3D billboard mode, `vertex_color_use_as_albedo`), 2D = texture directly.
3. Only drop to a hand-written `shader_type particles` when ParticleProcessMaterial can't express it (flocking, scripted paths). You control `start()`/`process()`, write TRANSFORM/VELOCITY/COLOR/CUSTOM.

One-shot burst pattern (hits, explosions, pickups):
```gdscript
# effect scene root: GPUParticles2D, one_shot=true, emitting=false, explosiveness=1.0
func _ready() -> void:
    emitting = true
    finished.connect(queue_free)
```

Essentials & gotchas:
- `explosiveness` 1.0 = all at once; `preprocess` to pre-warm ambient loops (fire already burning when scene appears).
- Trails: GPUParticles3D trails (enable + trail sections; mesh must support it), 4.7 improves per-particle scale/rotation control.
- Particle collision (3D): needs `GPUParticlesCollision*3D` nodes (SDF/box/sphere/heightfield); particles don't see physics bodies.
- Attractors: `GPUParticlesAttractor*3D` for vortex/pull effects.
- 2D particles ignore normal 2D light unless material set accordingly; and they simulate in the node's local space unless `local_coords = false` (leave OFF for moving emitters so trails linger behind).
- Changing `amount` restarts the system; pre-size it.
- Frame-rate independence is built in; but `visibility_rect/aabb` must cover the particles or they vanish when the emitter is off-screen — set generously or bake.
- Pooling: `emitting = false` doesn't kill live particles; to hard reset use `restart()`.

## DrawableTexture2D (4.7+)

Runtime-writable texture you can stamp/draw into from script — replaces SubViewport contraptions for:
- Fog of war / exploration masks (draw circles at visited positions, sample in a shader to darken),
- Paint/terraform mechanics, splat maps,
- Minimap annotations, decal-like bullet marks in 2D.
Pattern: draw into the DrawableTexture2D, feed it as a `uniform sampler2D mask` to the world's shader material.

## Performance & correctness

- Overdraw is the classic particle/transparency killer (mobile especially): fewer, larger-alpha particles > many faint ones; avoid full-screen transparent quads stacking.
- Every unique shader × variant compiles a pipeline → **stutter on first use**. Mitigate: 4.5+ **shader baker** (precompiles at export), or warm materials at load (spawn one of each effect off-screen during a loading screen).
- `discard`/`ALPHA` moves the material into the transparent pass — expensive; prefer `alpha_scissor` (ALPHA_SCISSOR_THRESHOLD) for foliage.
- texture() in a loop with dynamic count = slow; unroll or limit taps (blur: use fewer taps + mipmaps: `filter_linear_mipmap` + `textureLod`).
- Keep uniform updates off hot paths where possible; batching (2D) breaks per unique material — share materials, use instance uniforms (3D) / vertex COLOR (2D) for variation.
- Debug: Rendering > Debug draw modes (overdraw, wireframe); Visual profiler for pass costs.

## Juice checklist (cheap, high-impact)

Hit flash (shader) · hitstop (Engine.time_scale 0.05 for 0.05–0.15s) · screen shake (camera offset noise) · squash/stretch (tween scale) · one-shot burst particles · damage numbers · trail (Line2D w/ gradient or GPUTrails) · impact frames · chromatic pulse on big hits (fullscreen shader) · controller rumble `Input.start_joy_vibration`.
