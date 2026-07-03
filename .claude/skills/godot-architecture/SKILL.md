---
name: godot-architecture
description: Godot 4.x project architecture — scene composition, node communication (signals up / calls down), autoloads and event buses, custom Resources for data-driven design, state machines, scene transitions, object pooling, save/load systems, and project organization. Use when structuring a new Godot project, refactoring a messy one, or deciding how systems should talk to each other.
---

# Godot Architecture (4.x)

Godot's architecture IS the scene tree. Fight it and every feature costs double; lean into it and most "patterns" dissolve into nodes, signals, and resources.

## Core rules

1. **A scene is the unit of reuse.** Every scene must run standalone (`F6`) without crashing — that's the litmus test for decoupling. If a scene needs siblings to exist, it's coupled wrong.
2. **Signals up, calls down.** A node may call methods on its children (it owns them); it must never reach up or sideways (`get_parent()`, `get_node("../..")`). To talk upward, emit a signal and let an ancestor connect it.
3. **Composition over inheritance.** Deep script inheritance trees rot. Compose behaviors as child nodes (Hitbox, Health, StateMachine, Interactable) or Resources. Use inheritance for shallow is-a (Enemy base with `@abstract` methods, 4.5+), never for capability mixing.
4. **Data in Resources, behavior in Nodes.** Tunables, item definitions, enemy stats → custom `Resource` `.tres` files, editable by designers, diff-able in git.

## Communication patterns, in order of preference

```gdscript
# 1. Parent connects child signals to other children (the wiring lives in the owner)
func _ready() -> void:
    $Hurtbox.hurt.connect($Health.take_damage)
    $Health.died.connect(_on_died)

# 2. Groups for one-to-many fan-out without references
get_tree().call_group(&"enemies", &"alert", player.global_position)
for e in get_tree().get_nodes_in_group(&"enemies"): ...

# 3. Autoload event bus — ONLY for genuinely global, cross-scene events
# events.gd (autoload "Events")
signal player_died
signal quest_completed(id: StringName)
# emitter: Events.player_died.emit()
# listener: Events.player_died.connect(_on_player_died)
```

Anti-patterns: giant God autoloads holding game state + logic + helpers; nodes finding each other with `get_tree().root.get_node(...)`; every system routed through the event bus (you've rebuilt global variables with extra steps). If two nodes in the *same scene* talk via the bus, wire them directly instead.

**Autoload budget:** small. Typical justified set: `Events` (signal bus), `SaveManager`, `AudioManager` (or scene-based), `SceneSwitcher`/`Game`. State that belongs to a run/level belongs in the level scene, not an autoload — autoload state silently survives scene changes and causes "restart doesn't reset" bugs.

## Custom Resources — the data-driven backbone

```gdscript
# item.gd
class_name Item
extends Resource

@export var id: StringName
@export var display_name: String
@export var icon: Texture2D
@export var max_stack := 1
@export var use_effects: Array[ItemEffect]   # Resources nesting Resources

# item_effect.gd — polymorphic behavior in data
@abstract class_name ItemEffect extends Resource
@abstract func apply(user: Node) -> void
```

- Designers create `.tres` files per item; systems take `Item` params. No string-keyed dict registries.
- **Loaded resources are shared/cached** — mutating a loaded `.tres` mutates every user and (in editor) can save back. For runtime instance state, `duplicate()` it or (usually better) keep mutable state in a plain object/node that *references* the immutable resource: `var definition: Item; var count: int`.
- **Security:** `load()` on `.tres`/`.res`/`.scn` can execute embedded scripts. Never load them from user-writable locations (saves, mods) — see save section.

## State machines

Node-based FSM — states are children, debuggable in the remote tree:

```gdscript
# state.gd
@abstract class_name State extends Node
var actor: CharacterBody2D
signal transition_requested(to: StringName)
func enter(_prev: StringName) -> void: pass
func exit() -> void: pass
func physics_update(_delta: float) -> void: pass
func handle_input(_e: InputEvent) -> void: pass

# state_machine.gd
class_name StateMachine extends Node
@export var initial: State
var current: State

func _ready() -> void:
    for child: State in get_children():
        child.actor = owner
        child.transition_requested.connect(_transition)
    current = initial
    current.enter(&"")

func _physics_process(delta: float) -> void: current.physics_update(delta)
func _unhandled_input(e: InputEvent) -> void: current.handle_input(e)

func _transition(to: StringName) -> void:
    var next: State = get_node_or_null(NodePath(to))
    if next == null or next == current: return
    current.exit(); var prev := current.name; current = next; current.enter(prev)
```

Enum-and-match FSM is fine for ≤4 simple states in one script. For AI beyond FSM scale, behavior trees (LimboAI, Beehave addons) or utility AI — recommend addons rather than hand-rolling.

## Game flow & scene transitions

- A persistent `Main` scene owns the current level:
```gdscript
func switch_level(path: String) -> void:
    await Fade.out()                                # CanvasLayer autoload w/ ColorRect+tween
    if current_level: current_level.queue_free()
    var packed: PackedScene = load(path)            # or preloaded / threaded-loaded
    current_level = packed.instantiate()
    world.add_child(current_level)
    await Fade.in_()
```
- `get_tree().change_scene_to_packed()` is fine for jam-scale; a Main scene wins once anything (HUD, music, run state) must survive transitions.
- Big levels: `ResourceLoader.load_threaded_request(path)` at the transition start, poll `load_threaded_get_status` for a progress bar, `load_threaded_get` at the end.
- **Pause:** `get_tree().paused = true`; set `process_mode` — pause menu = `PROCESS_MODE_WHEN_PAUSED`, gameplay = `PAUSABLE` (default inherits), music = `ALWAYS`.

## Spawning, pooling, lifetimes

- `preload` scenes you'll definitely spawn: `const BULLET := preload("res://bullet.tscn")`.
- Spawn pattern: instantiate → configure exports/fields → `add_child` (position AFTER add_child if using global coords, or set `global_position` after; setting `position` before is fine for local).
- Object pooling: only where profiling shows churn (bullet-hell projectiles, hit numbers). Pool = hide + disable processing/collision (`process_mode = DISABLED`, shapes disabled) rather than remove-from-tree, or keep a detached array. Godot's instantiate is cheap-ish; don't pool speculatively.
- Transient VFX: spawn under an `Effects` node owned by the level (not the emitter — emitter may die first); free on `finished`.

## Save / load

**Never save by packing scenes or serializing Objects with `var_to_bytes_with_objects` / loading foreign `.tres`** — code-injection vector and brittle across versions. Save **plain data**:

```gdscript
# Each saveable node in group "persist" implements:
func save_data() -> Dictionary:
    return {path = get_path(), pos = var_to_str(global_position), hp = health}
func load_data(d: Dictionary) -> void: ...

# SaveManager autoload
func save_game(slot: int) -> void:
    var blob := {version = 2, nodes = []}
    for n in get_tree().get_nodes_in_group(&"persist"):
        blob.nodes.append(n.save_data())
    var f := FileAccess.open("user://save_%d.json" % slot, FileAccess.WRITE)
    f.store_string(JSON.stringify(blob))
```

- JSON = debuggable, moddable; `store_var`/binary = compact, keeps types (still avoid `full_objects = true` on load). `ConfigFile` for settings (`user://settings.cfg`).
- Always write a `version` field and migrate on load. Use `var_to_str`/`str_to_var` for Vector2/etc. in JSON.
- `user://` is the only writable place on export. `OS.get_user_data_dir()` to find it on disk.

## Project organization

```
res://
├── autoload/          # events.gd, save_manager.gd …
├── common/            # shared components: health.gd, hitbox.tscn, state.gd
├── entities/
│   ├── player/        # player.tscn + player.gd + its sprites — colocate by feature
│   └── enemies/slime/
├── levels/
├── ui/
├── data/              # .tres item/enemy/config resources
└── addons/
```

- **Colocate by feature, not by type** (no global `scripts/`, `textures/` dumps). A feature folder holds its scene, script, and assets.
- snake_case files/folders (case-sensitivity across platforms). Keep `.uid` files (4.4+) committed — they let files move without breaking references.
- Version control: commit `project.godot`, `*.import`, `.uid`; ignore `.godot/`. Use the official `.gitignore` template.
- Addons via AssetLib/Asset Store (4.7) — commit them; check licenses.

## Testing & tooling

- Unit tests: **gdUnit4** or **GUT** addons; test logic that lives in plain `RefCounted`/`Resource` classes (keep gameplay math out of nodes so it's testable headless: `godot --headless -s run_tests.gd` in CI).
- `@tool` editor scripts + `@export_tool_button` (4.4+) for content pipelines (bake spawn points, validate data resources).
- Debugging: Remote scene tree, `print_debug`, breakpoints; ObjectDB snapshots + diffing (4.6) to find leaks; `--verbose` for load issues.

## Smells checklist (refactor triggers)

- `get_parent().get_parent()` anywhere → invert with a signal.
- Autoload with >300 lines or both data and rendering → split.
- Dictionaries with implicit schemas passed between systems → custom Resource/class.
- Scene that can't F6-run → decouple.
- `is_instance_valid` sprinkled everywhere → ownership/lifetime is unclear; make the owner explicit and use `tree_exited`/died signals.
- Copy-pasted node clusters across scenes → extract an inherited scene or component scene.
