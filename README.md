# Godot 4.7 Development Skills for Claude Code

A set of Claude Code skills that make Claude (Opus & friends) highly effective at Godot 4.x game development — current through **Godot 4.7** (June 2026), including 4.5–4.7 changes like Jolt-by-default physics, abstract GDScript classes, AreaLight3D, HDR output, DrawableTexture2D, VirtualJoystick, and Control offset transforms.

## The skills

| Skill | Covers |
|---|---|
| [`godot-2d`](.claude/skills/godot-2d/SKILL.md) | 2D gameplay: TileMapLayer, sprites/animation, platformer & top-down movement, Camera2D, 2D lighting, parallax, Y-sort, pixel-art setup, 2D navigation |
| [`godot-3d`](.claude/skills/godot-3d/SKILL.md) | 3D gameplay: character controllers, cameras, lighting & GI decision-making, WorldEnvironment/post, glTF import pipeline, Jolt physics, LOD/occlusion, skeletons & animation |
| [`godot-gdscript`](.claude/skills/godot-gdscript/SKILL.md) | Language mastery: static typing, signals, annotations, abstract classes & variadics (4.5+), await/lifetime rules, performance idioms, review checklist |
| [`godot-architecture`](.claude/skills/godot-architecture/SKILL.md) | Project structure: scene composition, signals-up/calls-down, autoload discipline, custom Resources, state machines, scene transitions, save/load, testing |
| [`godot-ui`](.claude/skills/godot-ui/SKILL.md) | UI: anchors vs containers, themes & type variations, responsive layout, gamepad/keyboard focus, HUD data binding, UI animation (incl. 4.7 offset transforms) |
| [`godot-shaders-vfx`](.claude/skills/godot-shaders-vfx/SKILL.md) | gdshader (canvas_item/spatial/particles), effect recipes (outline, dissolve, fresnel…), GPUParticles, CompositorEffects, DrawableTexture2D, shader-stutter mitigation |
| [`godot-performance`](.claude/skills/godot-performance/SKILL.md) | Profiling-first optimization: built-in + tracing profilers (4.6), ObjectDB leak diffing, draw calls/lights/culling, physics tuning, stutter causes, scaling ladders to Servers API |
| [`godot-multiplayer`](.claude/skills/godot-multiplayer/SKILL.md) | High-level multiplayer: ENet/WebSocket/WebRTC, @rpc design & validation, MultiplayerSpawner/Synchronizer, authority, interpolation, lobby flow |
| [`godot-export-platforms`](.claude/skills/godot-export-platforms/SKILL.md) | Shipping: export presets & CI, desktop signing, Android GABE/Gradle (4.7), iOS, Web constraints (headers, Compatibility renderer), feature tags, PCK patching |

## How to use

Skills live in `.claude/skills/` and load automatically when this repository is your Claude Code project. To use them in another project, copy the skill folders into that project's `.claude/skills/` directory (or into `~/.claude/skills/` to make them available everywhere):

```bash
cp -r .claude/skills/godot-* /path/to/your-game/.claude/skills/
```

Claude picks the relevant skill from your request automatically — "add a dash to my platformer" pulls in `godot-2d`, "why is my frame rate dying" pulls in `godot-performance` — or invoke one explicitly with `/godot-3d`, `/godot-ui`, etc.

## Design notes

- **2D and 3D are separate skills** (as are the rest) so each stays focused and loads only when relevant.
- Every skill is written against **Godot 4.x APIs only** — no Godot 3 syntax — and flags the version floor (4.4/4.5/4.6/4.7) wherever a feature is newer than baseline 4.x.
- Skills cross-reference each other (e.g. `godot-2d` defers particle details to `godot-shaders-vfx`) instead of duplicating content.
