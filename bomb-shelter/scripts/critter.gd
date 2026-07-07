class_name Critter
extends CharacterBody2D
## Wandering bunker livestock: chickens and pigs. Cosmetic AI only — they
## never die; a blast or kick just relocates them. See scripts/player.gd for
## the gravity/facing pattern this follows.
##
## Usage: set `kind` (and optionally `home`) before adding to the tree, e.g.:
##   var c := Critter.new(); c.kind = Critter.Kind.CHICKEN
##   c.home = pen_rect_world_px; add_child(c)
## `position` is the critter's CENTER (chicken 10x9, pig 16x10) — to stand it
## on a floor at world y `floor_y`, set position.y = floor_y - h/2.
## They are CharacterBody2D, so they can't join "ragdoll_parts" like
## Furniture does — the lead's kick loop and blast handling should call
## `shove(vel)` on group "props" members instead of relying on RigidBody
## impulses.

enum Kind { CHICKEN, PIG }

var kind := Kind.CHICKEN
## Streamed to web viewers as [x, y, kind, rotation]; kept in sync with `kind`.
var prop_kind := 6
## Home pen, in world px. Wanderers softly prefer staying inside it but don't
## pathfind back once flung far out — set by the spawner (BunkerProps).
var home := Rect2()

enum _Intent { IDLE, WALK_LEFT, WALK_RIGHT }

const MAX_FALL := 900.0
const CHICKEN_SPEED := 40.0
const PIG_SPEED := 30.0

var _gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")
var _facing := 1
var _intent := _Intent.IDLE
var _intent_left := 0.0
var _flutter_left := 0.0  # chicken: short hop, reduced gravity while > 0
var _hop_cooldown := 0.0  # pig: cadence gate on little hops
var _wing_phase := 0.0


func _ready() -> void:
	prop_kind = 6 if kind == Kind.CHICKEN else 7
	add_to_group(&"props")
	z_index = 3
	collision_layer = 0
	collision_mask = 1  # walks on terrain, never blocks players/bombs
	floor_snap_length = 6.0

	var cs := CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	rs.size = Vector2(10, 9) if kind == Kind.CHICKEN else Vector2(16, 10)
	cs.shape = rs
	add_child(cs)
	_pick_intent()


func _physics_process(delta: float) -> void:
	var fall_mult := 0.35 if _flutter_left > 0.0 else 1.0
	velocity.y = minf(velocity.y + _gravity * fall_mult * delta, MAX_FALL)

	_intent_left -= delta
	if _intent_left <= 0.0:
		_pick_intent()

	var speed := CHICKEN_SPEED if kind == Kind.CHICKEN else PIG_SPEED
	match _intent:
		_Intent.WALK_LEFT:
			velocity.x = -speed
		_Intent.WALK_RIGHT:
			velocity.x = speed
		_:
			velocity.x = move_toward(velocity.x, 0.0, speed * 4.0 * delta)

	# Soft home preference: only kicks in once outside the pen horizontally —
	# no pathfinding back once flung far away, that's fine (and funny).
	if home.size != Vector2.ZERO:
		if global_position.x < home.position.x:
			velocity.x = speed
		elif global_position.x > home.end.x:
			velocity.x = -speed

	if velocity.x > 1.0:
		_facing = 1
	elif velocity.x < -1.0:
		_facing = -1

	if kind == Kind.CHICKEN:
		_update_flutter(delta)
	else:
		_update_hop(delta)

	move_and_slide()
	if is_on_wall():
		_intent = _Intent.WALK_RIGHT if _intent == _Intent.WALK_LEFT else _Intent.WALK_LEFT

	queue_redraw()


func _pick_intent() -> void:
	_intent_left = randf_range(0.8, 2.0)
	var roll := randf()
	if roll < 0.35:
		_intent = _Intent.IDLE
	elif roll < 0.67:
		_intent = _Intent.WALK_LEFT
	else:
		_intent = _Intent.WALK_RIGHT

	if kind == Kind.CHICKEN and _flutter_left <= 0.0 and randf() < 0.25:
		_flutter_left = 0.5
		velocity.y = -110.0
	elif kind == Kind.PIG and _hop_cooldown <= 0.0 and randf() < 0.2:
		_hop_cooldown = 1.2
		velocity.y = -90.0


func _update_flutter(delta: float) -> void:
	if _flutter_left > 0.0:
		_flutter_left -= delta
		_wing_phase += delta * 22.0
	else:
		_wing_phase = 0.0


func _update_hop(delta: float) -> void:
	_hop_cooldown = maxf(_hop_cooldown - delta, 0.0)


## Public shove hook: the lead's kick loop and blast handling call this on
## group "props" members instead of applying a RigidBody impulse (Critter is
## a CharacterBody2D, so it can't join "ragdoll_parts").
func shove(vel: Vector2) -> void:
	velocity += vel


func _draw() -> void:
	# One mirror transform for the whole body: art below is authored facing
	# right, and this flips it when _facing is -1 (see player.gd's _limb()
	# for the equivalent per-limb technique).
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(float(_facing), 1.0))
	if kind == Kind.CHICKEN:
		_draw_chicken()
	else:
		_draw_pig()


func _draw_chicken() -> void:
	draw_rect(Rect2(-6, -8, 12, 10), Color.BLACK)               # outline
	draw_rect(Rect2(-5, -7, 10, 8), Color("f5f5f0"))            # body
	draw_rect(Rect2(3.0, -9.5, 4.0, 2.5), Color("f5f5f0"))      # head bump
	draw_rect(Rect2(6.0, -8.5, 2.5, 1.5), Color("ffb300"))      # beak
	draw_rect(Rect2(3.5, -10.5, 2.0, 1.5), Color("e53935"))     # comb
	draw_rect(Rect2(-2.5, 1.0, 1.4, 3.0), Color("ffb300"))      # legs
	draw_rect(Rect2(1.1, 1.0, 1.4, 3.0), Color("ffb300"))
	var wing_ang := sin(_wing_phase) * 0.9 if _flutter_left > 0.0 else 0.15
	var tip := Vector2(-6.0, -2.0).rotated(wing_ang)
	draw_line(Vector2(-2.0, -3.0), Vector2(-2.0, -3.0) + tip, Color("e0e0d8"), 2.5)


func _draw_pig() -> void:
	draw_rect(Rect2(-9, -7, 18, 12), Color.BLACK)               # outline
	draw_rect(Rect2(-8, -6, 16, 10), Color("f4a7b9"))           # body
	draw_rect(Rect2(6.0, -5.0, 5.0, 6.0), Color("f4a7b9"))      # snout base
	draw_rect(Rect2(8.5, -3.0, 2.5, 3.0), Color("d97b95"))      # snout tip
	draw_rect(Rect2(4.0, -7.5, 3.0, 2.5), Color("e792a8"))      # ear
	draw_rect(Rect2(-5.0, 4.0, 3.0, 3.0), Color("d97b95"))      # legs
	draw_rect(Rect2(2.0, 4.0, 3.0, 3.0), Color("d97b95"))
	draw_arc(Vector2(-9.0, -2.0), 2.0, 0.0, TAU * 0.75, 8, Color("d97b95"), 1.2)   # curly tail
	draw_arc(Vector2(-10.0, -3.5), 1.4, 0.0, TAU * 0.75, 6, Color("d97b95"), 1.0)
