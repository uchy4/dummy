class_name Critter
extends CharacterBody2D
## Wandering bunker livestock: chickens and pigs. A kick ragdolls them (they
## tumble, then get back up); a close bomb blast kills them outright, same
## rules as players. See scripts/player.gd for the gravity/facing pattern.
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

var alive := true
var _ragdoll: Ragdoll = null
var _stun_left := 0.0
var _shape_node: CollisionShape2D

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
	collision_layer = 4  # on the same physical plane: players bump into them
	collision_mask = 1   # they walk on terrain (shoves come from the bumper)
	floor_snap_length = 6.0

	_shape_node = CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	rs.size = Vector2(10, 9) if kind == Kind.CHICKEN else Vector2(16, 10)
	_shape_node.shape = rs
	add_child(_shape_node)
	_pick_intent()


func _physics_process(delta: float) -> void:
	if not alive:
		return
	if _stun_left > 0.0:
		# Riding our kicked ragdoll; stand back up where it lands.
		_stun_left -= delta
		if _ragdoll != null and is_instance_valid(_ragdoll):
			global_position = _ragdoll.torso_pos()
		if _stun_left <= 0.0:
			_end_ragdoll()
		return
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


## Public shove hook: kicks and blast knockback land here. A real wallop
## ragdolls the animal — it tumbles limp and gets back up where it lands.
func shove(vel: Vector2) -> void:
	if not alive:
		return
	if vel.length() > 140.0 and _stun_left <= 0.0:
		_start_ragdoll(vel)
	else:
		velocity += vel


## Blast handler, same rules as players: lethal range kills, otherwise the
## concussion just launches them into a ragdoll tumble.
func blast_hit(kick: Vector2, lethal: bool) -> void:
	if not alive:
		return
	if lethal:
		die(kick)
	else:
		shove(kick)


func die(kick: Vector2) -> void:
	if not alive:
		return
	alive = false
	if NetHub.has_viewers():  # fx kind 12 = critter death burst
		NetHub.broadcast({"t": "fx", "k": 12, "x": int(global_position.x),
			"y": int(global_position.y),
			"c": "h" if kind == Kind.CHICKEN else "p"})
	_end_ragdoll_silently()
	var rd := _make_ragdoll(kick)
	rd.persist = false  # fades out like a player's death ragdoll
	get_tree().call_group(&"sfx", &"play_splat", global_position)
	queue_free()


func _start_ragdoll(vel: Vector2) -> void:
	_stun_left = 1.3
	_ragdoll = _make_ragdoll(velocity + vel)
	_ragdoll.persist = true
	hide()
	_shape_node.set_deferred(&"disabled", true)
	velocity = Vector2.ZERO


func _end_ragdoll() -> void:
	if _ragdoll != null and is_instance_valid(_ragdoll):
		global_position = _ragdoll.torso_pos() + Vector2(0, -3)
	_end_ragdoll_silently()
	show()
	_shape_node.set_deferred(&"disabled", false)
	velocity = Vector2.ZERO


func _end_ragdoll_silently() -> void:
	if _ragdoll != null and is_instance_valid(_ragdoll):
		_ragdoll.queue_free()
	_ragdoll = null
	_stun_left = 0.0


func _make_ragdoll(impulse: Vector2) -> Ragdoll:
	var rd := Ragdoll.new()
	rd.part_scale = 0.55
	rd.color = Color("f5f5f0") if kind == Kind.CHICKEN else Color("f4a7b9")
	rd.impulse = impulse.limit_length(700.0)
	rd.position = global_position
	get_parent().add_child.call_deferred(rd)
	return rd


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
