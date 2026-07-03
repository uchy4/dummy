class_name Player
extends CharacterBody2D
## One local player. Platformer movement (coyote time + jump buffer), can push
## bombs around, dies to close unshielded blasts and respawns in the shelter.

const SPEED := 230.0
const ACCEL := 1900.0
const JUMP_VELOCITY := -430.0
const MAX_FALL := 900.0
const PUSH_FORCE := 380.0
const RESPAWN_TIME := 3.0
const INVULN_TIME := 1.5

var index := 0
var player_color := Color.WHITE
var alive := true
var deaths := 0
var respawn_left := 0.0
var respawn_point := Vector2.ZERO

var world_bounds := Rect2(-100000, -100000, 200000, 200000)

var _invuln_left := 0.0
var _coyote := 0.0
var _jump_buffer := 0.0
var _walk_phase := 0.0
var _swing := 0.0
var _a_left: StringName
var _a_right: StringName
var _a_jump: StringName
var _shape: CollisionShape2D

var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")


func setup(i: int, color: Color) -> void:
	index = i
	player_color = color
	_a_left = StringName("p%d_left" % (i + 1))
	_a_right = StringName("p%d_right" % (i + 1))
	_a_jump = StringName("p%d_jump" % (i + 1))


func _ready() -> void:
	add_to_group(&"players")
	z_index = 5
	collision_layer = 2
	collision_mask = 1 | 4
	floor_snap_length = 6.0
	_shape = CollisionShape2D.new()
	var cap := CapsuleShape2D.new()
	cap.radius = 7.0
	cap.height = 26.0
	_shape.shape = cap
	add_child(_shape)


func _physics_process(delta: float) -> void:
	if not alive:
		respawn_left -= delta
		if respawn_left <= 0.0:
			_respawn()
		return

	if _invuln_left > 0.0:
		_invuln_left -= delta
		modulate.a = 0.4 + 0.6 * absf(sin(_invuln_left * 18.0))
		if _invuln_left <= 0.0:
			modulate.a = 1.0

	velocity.y = minf(velocity.y + gravity * delta, MAX_FALL)
	_coyote = 0.15 if is_on_floor() else _coyote - delta
	_jump_buffer = 0.1 if Input.is_action_just_pressed(_a_jump) else _jump_buffer - delta

	if _jump_buffer > 0.0 and _coyote > 0.0:
		velocity.y = JUMP_VELOCITY
		_jump_buffer = 0.0
		_coyote = 0.0
	if Input.is_action_just_released(_a_jump) and velocity.y < 0.0:
		velocity.y *= 0.55  # variable jump height

	var dir := Input.get_axis(_a_left, _a_right)
	velocity.x = move_toward(velocity.x, dir * SPEED, ACCEL * delta)
	move_and_slide()

	# Limb swing: legs/arms pump while walking, settle when idle or airborne.
	var swing_target := 0.0
	if is_on_floor() and absf(velocity.x) > 20.0:
		_walk_phase += velocity.x * delta * 0.055
		swing_target = sin(_walk_phase) * 0.6
	elif not is_on_floor():
		swing_target = 0.35  # arms/legs trail in the air
	_swing = lerpf(_swing, swing_target, 0.35)
	queue_redraw()

	# Shove bombs we walk into.
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var rb := c.get_collider() as RigidBody2D
		if rb:
			rb.apply_central_impulse(-c.get_normal() * PUSH_FORCE * delta)

	# Failsafe: anyone who escapes the map dies and respawns in the shelter.
	if not world_bounds.has_point(global_position):
		die()


func take_blast(kick: Vector2, lethal: bool) -> void:
	if not alive:
		return
	if lethal and _invuln_left <= 0.0:
		die(kick)
		return
	velocity += kick
	_coyote = 0.0


## Move the player somewhere safe without a death penalty (Quick Settings
## "reset" button). A dead player respawns almost immediately instead.
func teleport_to(pos: Vector2) -> void:
	global_position = pos
	reset_physics_interpolation()
	velocity = Vector2.ZERO
	_invuln_left = INVULN_TIME
	if not alive:
		respawn_left = minf(respawn_left, 0.1)


func die(kick := Vector2.ZERO) -> void:
	if not alive:
		return
	alive = false
	deaths += 1
	respawn_left = RESPAWN_TIME
	velocity = Vector2.ZERO
	hide()
	_shape.set_deferred("disabled", true)
	get_tree().call_group(&"sfx", &"play_splat", global_position)

	var rd := Ragdoll.new()
	rd.color = player_color
	rd.impulse = kick.limit_length(700.0) if kick != Vector2.ZERO else Vector2(0, -220)
	rd.position = global_position
	get_parent().add_child.call_deferred(rd)


func _respawn() -> void:
	global_position = respawn_point
	reset_physics_interpolation()
	velocity = Vector2.ZERO
	alive = true
	_invuln_left = INVULN_TIME
	show()
	_shape.set_deferred("disabled", false)


func _draw() -> void:
	var arm_c := player_color.darkened(0.15)
	var leg_c := player_color.darkened(0.35)
	# Far arm and far leg swing opposite the near ones.
	draw_set_transform(Vector2(5, -6), _swing, Vector2.ONE)
	draw_rect(Rect2(-2, 0, 4, 10), arm_c.darkened(0.2))
	draw_set_transform(Vector2(3, 2), -_swing, Vector2.ONE)
	draw_rect(Rect2(-2, 0, 4, 12), leg_c.darkened(0.2))
	draw_set_transform(Vector2(-3, 2), _swing, Vector2.ONE)
	draw_rect(Rect2(-2, 0, 4, 12), leg_c)
	# Torso and head in body space.
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_rect(Rect2(-6, -7, 12, 10), player_color)
	draw_rect(Rect2(-5, -15, 10, 9), player_color.lightened(0.35))
	draw_rect(Rect2(-6, -17, 12, 4), player_color.lightened(0.15))  # hard hat
	draw_rect(Rect2(-3, -12, 2, 3), Color.WHITE)
	draw_rect(Rect2(1, -12, 2, 3), Color.WHITE)
	draw_rect(Rect2(-2.5, -11, 1, 1.5), Color.BLACK)
	draw_rect(Rect2(1.5, -11, 1, 1.5), Color.BLACK)
	# Near arm drawn over the torso.
	draw_set_transform(Vector2(-5, -6), -_swing, Vector2.ONE)
	draw_rect(Rect2(-2, 0, 4, 10), arm_c)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
