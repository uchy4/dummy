---
name: godot-gdscript
description: GDScript language mastery for Godot 4.x (through 4.7) — static typing, signals, annotations, abstract classes, lambdas, await/coroutines, common pitfalls, and performance idioms. Use when writing or reviewing any GDScript code, debugging script errors, or deciding how to structure scripts.
---

# GDScript (Godot 4.x, current through 4.7)

Authoritative guidance for writing modern, fast, correct GDScript. Godot 4 GDScript is NOT Godot 3 GDScript — never emit 3.x syntax (`onready var`, `export var`, `yield`, `connect("sig", self, "_fn")`, KinematicBody).

## Non-negotiable defaults

- **Static-type everything**: parameters, returns, variables. Typed GDScript is safer and measurably faster (typed calls skip Variant dispatch).
- Use `:=` for inference only when the type is obvious on the same line: `var speed := 300.0`.
- `class_name` for any script referenced by other scripts. File names snake_case, class names PascalCase.
- Signals for upward communication, direct calls for downward (see godot-architecture skill).
- Prefer `@export` over hardcoding; prefer custom `Resource` over parallel arrays/dicts for structured data.

```gdscript
class_name Player
extends CharacterBody2D

signal died(cause: String)

@export var max_speed := 300.0
@export_range(0.0, 1.0) var friction := 0.15

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var hurtbox: Area2D = %Hurtbox   # % = scene-unique name, preferred over deep $ paths

func _physics_process(delta: float) -> void:
    var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
    velocity = velocity.lerp(input * max_speed, 1.0 - pow(friction, delta * 60.0))
    move_and_slide()
```

## Annotations you should actually use

| Annotation | Purpose |
|---|---|
| `@export`, `@export_range`, `@export_enum`, `@export_flags`, `@export_group`/`_subgroup`/`_category` | Inspector exposure and organization |
| `@export_node_path("Area2D")`, `@export_file("*.json")`, `@export_dir`, `@export_multiline`, `@export_color_no_alpha` | Typed pickers |
| `@export_custom(PROPERTY_HINT_*, "hint")` | Anything the shorthand annotations can't express |
| `@export_tool_button("Bake")` (4.4+) | Button in the inspector that calls a Callable — great for tool scripts |
| `@onready` | Defer init until node enters tree; required for `$`/`%` lookups in field initializers |
| `@tool` | Script runs in editor. Guard editor-only logic with `Engine.is_editor_hint()` |
| `@rpc(...)` | Network RPCs (see godot-multiplayer skill) |
| `@warning_ignore("...")` / `@warning_ignore_start` | Silence a specific warning at a specific site — never globally disable warnings |
| `@abstract` (4.5+) | Abstract classes and methods (see below) |

Enable **warnings as errors** for `UNTYPED_DECLARATION` and `INFERRED_DECLARATION` in Project Settings > Debug > GDScript on serious projects.

## Language features by version (know your floor)

- **4.1+**: static vars, static funcs in all contexts, first-class `Callable`/lambdas.
- **4.2+**: `@export_custom`, pattern guards in `match` (`PATTERN when COND:`).
- **4.3+**: typed dictionaries did NOT land here — that's 4.4.
- **4.4+**: **typed dictionaries** `Dictionary[String, int]`, `@export_tool_button`, `is not` operator.
- **4.5+**: **abstract classes** `@abstract class_name Enemy` with `@abstract func take_turn() -> void` (no body); **variadic functions** `func log_all(...args: Array) -> void`.
- **4.6+**: script tracing-profiler hooks (Tracy/Perfetto/Instruments) — see godot-performance skill.
- **4.7+**: better constant-expression evaluation for const arrays/dicts; GDScript can implement Java interfaces on Android; LSP improvements.

```gdscript
# 4.5+ abstract base
@abstract
class_name Ability
extends Resource

@abstract func execute(user: Node, target: Node) -> void

func can_execute(user: Node) -> bool:  # concrete members allowed
    return true
```

## Signals — the 4.x way

```gdscript
signal health_changed(new_value: int)

# emit
health_changed.emit(current_health)

# connect (idiomatically in _ready of the LISTENER)
health_changed.connect(_on_health_changed)
health_changed.connect(_on_health_changed.bind(extra_arg))
health_changed.connect(func(v: int): label.text = str(v))   # lambdas fine for trivial handlers
button.pressed.connect(queue_free, CONNECT_ONE_SHOT)

# await a signal (replaces yield)
await get_tree().create_timer(0.5).timeout
await animation_player.animation_finished
```

Pitfalls:
- Connecting the same Callable twice errors unless you check `is_connected()` or pass `CONNECT_REFERENCE_COUNTED`.
- A lambda connection cannot be disconnected unless you keep a reference to it.
- Editor-connected signals name handlers `_on_node_name_signal_name` — follow that convention in code too.

## await / coroutines

- Any function containing `await` returns a coroutine; callers that need its result must `await` it too.
- `await` on a signal from an object that gets freed leaves the coroutine suspended forever — no error. Guard long awaits: prefer `await` on your own signals, or check `is_instance_valid()` after resuming.
- Never `await` inside `_physics_process`/`_process` to "pause" logic — restructure with state or timers.
- `call_deferred()` / `set_deferred()` to mutate physics state or the scene tree during signal callbacks (e.g., you cannot `queue_free()` a body inside its own `body_entered` handling of physics — defer it; you cannot change monitoring/shape state during a physics callback).

## Memory & lifetime rules

- `Node` is manually managed: `queue_free()` (almost always) or `free()` (only when you know nothing references it this frame).
- `RefCounted` (and `Resource`) are reference-counted. **Reference cycles leak** — break them with `weakref()` or explicit teardown.
- After `queue_free()`, the node is valid until end of frame. Test with `is_instance_valid(node)`; a freed-node access is a hard error.
- Signals do not keep objects alive; connections to freed objects auto-disconnect.
- `Resource` instances loaded from the same path are **shared** (cached). Mutating one mutates all users. Use `resource.duplicate()` or "Local to Scene" for per-instance state.

## Strings, StringNames, NodePaths

- `&"jump"` is a `StringName` — use for input actions, animation names, groups, and any repeated string compare (interned, O(1) compare).
- `^"Path/To/Node"` is a `NodePath` literal.
- Build strings with `%` or `String.format()`, not repeated `+` in loops. `"HP: %d/%d" % [hp, max_hp]`.

## match

```gdscript
match state:
    State.IDLE:
        pass
    State.RUN when is_on_floor():   # 4.2+ guards
        pass
    [var x, var y]:                 # array destructuring
        pass
    {"type": "damage", "amount": var amt}:
        take_damage(amt)
    _:
        push_warning("unhandled state %s" % state)
```

## Properties, setters, getters

```gdscript
var health: int = 100:
    set(value):
        health = clampi(value, 0, max_health)
        health_changed.emit(health)
    get:
        return health
```

Setters run on inspector assignment too (in `@tool` scripts) — keep them side-effect-safe before `_ready` (guard with `if not is_node_ready(): return` when the setter touches child nodes).

## Performance idioms

- Typed arrays (`Array[Vector2]`) and `Packed*Array` are faster and more memory-dense than untyped `Array`. Use `PackedVector2Array`, `PackedFloat32Array`, `PackedByteArray` for bulk numeric data.
- Cache node lookups in `@onready` vars; `$Path` every frame is a hash lookup chain.
- Avoid allocating in `_process`/`_physics_process`: no new arrays/dicts/lambdas per frame in hot paths; reuse buffers.
- `for i in range(n)` allocates nothing in 4.x, fine. Dictionary iteration order is insertion order (stable).
- Prefer `Vector2.distance_squared_to()` over `distance_to()` for comparisons.
- Math helpers exist — use them: `move_toward`, `lerp`, `lerpf`, `lerp_angle`, `remap`, `wrapf`, `clampi/f`, `is_equal_approx`, `pingpong`.
- Frame-rate-independent damping: `lerp(a, b, 1.0 - exp(-decay * delta))` — never `lerp(a, b, 0.1)` in `_process`.
- For thousands of entities, move the inner loop out of per-node scripts: one manager script iterating typed arrays, or Servers/MultiMesh (see godot-performance skill).

## Common mistakes to catch in review

1. Godot 3 syntax (`yield`, `export var`, `KinematicBody2D`, `move_and_slide(velocity)` with an argument — in 4.x `velocity` is a property and `move_and_slide()` takes none).
2. `get_node()` in `_init()` — nodes aren't in the tree yet; use `_ready`/`@onready`.
3. Forgetting `super()` in overridden `_init`, or forgetting that `_ready` runs **children first, parents last**; `_enter_tree` runs parents first.
4. Float `==` comparisons — use `is_equal_approx()` / `is_zero_approx()`.
5. `randi() % n` after forgetting seeding is fine (auto-randomized in 4.x), but use `randi_range(a, b)` / `randf_range()` and `Array.pick_random()`.
6. Mutating an array/dict while iterating it.
7. Storing node references across frames without `is_instance_valid` checks (enemies that died).
8. Doing work in `_process` that belongs in `_physics_process` (anything touching physics state) and vice versa (rendering-only smoothing).
9. `preload` for hot-path scenes (compile-time, good), `load` inside a loop (bad — though results are cached, use `ResourceLoader.load_threaded_request` for big assets; see godot-performance).
10. `class_name` scripts referencing each other creating load-order cycles — break with `load()` at use-site or restructure.

## Tool scripts & the editor

- `@tool` + `Engine.is_editor_hint()` guards. `_get_configuration_warnings()` to show node warnings.
- Custom resources + `@export` make designers self-sufficient — prefer data-driven over code-driven tuning.
- Doc comments with `##` above members appear in the editor help and inspector tooltips. Write them for exported vars.
