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
		die()
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


func die() -> void:
	if not alive:
		return
	alive = false
	deaths += 1
	respawn_left = RESPAWN_TIME
	velocity = Vector2.ZERO
	hide()
	_shape.set_deferred("disabled", true)
	get_tree().call_group(&"sfx", &"play_splat", global_position)


func _respawn() -> void:
	global_position = respawn_point
	reset_physics_interpolation()
	velocity = Vector2.ZERO
	alive = true
	_invuln_left = INVULN_TIME
	show()
	_shape.set_deferred("disabled", false)


func _draw() -> void:
	draw_rect(Rect2(-9, -14, 18, 28), player_color.darkened(0.55))
	draw_rect(Rect2(-8, -13, 16, 26), player_color)
	draw_rect(Rect2(-8, -14, 16, 4), player_color.lightened(0.25))  # hard hat
	draw_rect(Rect2(-5, -7, 3, 4), Color.WHITE)
	draw_rect(Rect2(2, -7, 3, 4), Color.WHITE)
	draw_rect(Rect2(-4, -6, 1, 2), Color.BLACK)
	draw_rect(Rect2(3, -6, 1, 2), Color.BLACK)
