class_name Ragdoll
extends Node2D
## Cosmetic death ragdoll: six rigid-body parts (head, torso, arms, legs)
## pinned together, launched by the killing blast, tumbling off terrain.
## Fades out and frees itself after a few seconds.

const LIFE := 4.5
const FADE_START := 3.2

var color := Color.WHITE
var color2 := Color.TRANSPARENT  # second stripe color; unset means solid
var impulse := Vector2.ZERO
## Stun ragdolls persist (no fade/free) until the stunned player gets back
## up and frees them; death ragdolls fade out on their own.
var persist := false
## Critters use a shrunken rig (0.55) — same physics, smaller parts.
var part_scale := 1.0
## Still wearing the hard hat when stunned? The rig's head wears it too.
var hat := false

var _age := 0.0
var _parts: Array[RigidBody2D] = []


func _ready() -> void:
	z_index = 5
	if color2 == Color.TRANSPARENT:
		color2 = color
	var s := part_scale
	# Dimensions mirror the living player's art exactly: 12x10 torso with
	# the same two stripe bands, an 11.8-wide fused dome head, and 4-wide
	# capsule limbs (rounded at both ends) at the player's lengths.
	var torso := _part(Vector2(0, -2) * s, Vector2(12, 10) * s, color)
	if not color2.is_equal_approx(color):
		for by: float in [-1.75, 2.75]:
			var band := _rect_poly(Vector2(12, 2.5) * s, color2)
			band.position = Vector2(0, by) * s
			torso.add_child(band)
	var head := _part_dome(Vector2(0, -11) * s, Vector2(11.8, 9) * s, color)
	_decorate_head(head)
	if hat:
		var hb := _dome_poly(5.4 * s, 0.0, Color.BLACK)
		hb.position = Vector2(0, -4.4) * s
		head.add_child(hb)
		var hy := _dome_poly(4.8 * s, 0.0, Color("f5c518"))
		hy.position = Vector2(0, -4.2) * s
		head.add_child(hy)
	var arm_l := _part(Vector2(-7, 0) * s, Vector2(4, 10) * s, color.darkened(0.15), true)
	var arm_r := _part(Vector2(7, 0) * s, Vector2(4, 10) * s, color.darkened(0.15), true)
	var leg_l := _part(Vector2(-3, 9) * s, Vector2(4, 12) * s, color.darkened(0.35), true)
	var leg_r := _part(Vector2(3, 9) * s, Vector2(4, 12) * s, color.darkened(0.35), true)

	_pin(head, torso, Vector2(0, -7) * s)
	_pin(arm_l, torso, Vector2(-6, -5) * s)
	_pin(arm_r, torso, Vector2(6, -5) * s)
	_pin(leg_l, torso, Vector2(-3, 3) * s)
	_pin(leg_r, torso, Vector2(3, 3) * s)

	for p in _parts:
		p.linear_velocity = impulse * randf_range(0.7, 1.3) \
			+ Vector2(randf_range(-70.0, 70.0), randf_range(-140.0, 0.0))
		p.angular_velocity = randf_range(-12.0, 12.0)


func _process(delta: float) -> void:
	if persist:
		return
	_age += delta
	if _age >= LIFE:
		queue_free()
	elif _age >= FADE_START:
		modulate.a = 1.0 - (_age - FADE_START) / (LIFE - FADE_START)


## Where the body ended up — the stunned player stands back up here.
func torso_pos() -> Vector2:
	if _parts.is_empty():
		return global_position
	return _parts[0].global_position


## How fast the torso is still moving — near zero means the body has
## settled even if the ground ray misses (resting on a prop, wedged, etc).
func torso_speed() -> float:
	if _parts.is_empty():
		return 0.0
	return _parts[0].linear_velocity.length()


## True once the torso is resting on (or brushing) solid ground — a stunned
## player stays ragdolled while still flying through the air.
func torso_grounded() -> bool:
	if _parts.is_empty():
		return true
	var torso := _parts[0]
	var space := torso.get_world_2d().direct_space_state
	var q := PhysicsRayQueryParameters2D.create(torso.global_position,
		torso.global_position + Vector2(0, 14), 1)
	return not space.intersect_ray(q).is_empty()


func _part(pos: Vector2, size: Vector2, col: Color, capsule := false) -> RigidBody2D:
	var b := RigidBody2D.new()
	b.position = pos
	b.mass = 0.5
	b.collision_layer = 0
	b.collision_mask = 1  # tumbles off terrain, ignores players/bombs
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.3
	pm.friction = 0.6
	b.physics_material_override = pm

	b.add_to_group(&"ragdoll_parts")
	var cs := CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	rs.size = size
	cs.shape = rs
	b.add_child(cs)
	if capsule:
		# Rounded caps at both ends, matching the player's _limb art.
		var hy := size.y / 2.0
		var ro := size.x / 2.0 + 1.0
		b.add_child(_rect_poly(size + Vector2(2, 0), Color.BLACK))
		b.add_child(_circle_poly(ro, Color.BLACK, Vector2(0, -hy)))
		b.add_child(_circle_poly(ro, Color.BLACK, Vector2(0, hy)))
		b.add_child(_rect_poly(size, col))
		b.add_child(_circle_poly(size.x / 2.0, col, Vector2(0, -hy)))
		b.add_child(_circle_poly(size.x / 2.0, col, Vector2(0, hy)))
	else:
		b.add_child(_rect_poly(size + Vector2(2, 2), Color.BLACK))  # outline
		b.add_child(_rect_poly(size, col))

	add_child(b)
	_parts.append(b)
	return b


func _circle_poly(r: float, col: Color, pos: Vector2) -> Polygon2D:
	var pts := PackedVector2Array()
	for i in 12:
		var t := TAU * i / 12.0
		pts.append(pos + Vector2(cos(t), sin(t)) * r)
	var p := Polygon2D.new()
	p.polygon = pts
	p.color = col
	return p


func _decorate_head(head: RigidBody2D) -> void:
	for x in [-2.5, 2.5]:
		var eye := _rect_poly(Vector2(2, 2.5), Color.WHITE)
		eye.position = Vector2(x, -0.5)
		head.add_child(eye)


## A head-shaped part: round top, flat bottom, body-colored — matches the
## living player's fused dome head.
func _part_dome(pos: Vector2, size: Vector2, col: Color) -> RigidBody2D:
	var b := RigidBody2D.new()
	b.position = pos
	b.mass = 0.5
	b.collision_layer = 0
	b.collision_mask = 1
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.3
	pm.friction = 0.6
	b.physics_material_override = pm
	b.add_to_group(&"ragdoll_parts")
	var cs := CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	rs.size = size
	cs.shape = rs
	b.add_child(cs)
	b.add_child(_dome_poly(size.x / 2.0 + 1.0, size.y / 2.0 + 1.0, Color.BLACK))
	b.add_child(_dome_poly(size.x / 2.0, size.y / 2.0, col))
	add_child(b)
	_parts.append(b)
	return b


func _dome_poly(r: float, drop: float, col: Color) -> Polygon2D:
	var pts := PackedVector2Array()
	pts.append(Vector2(r, drop))
	for i in 9:
		var t := PI * i / 8.0
		pts.append(Vector2(cos(t) * r, -sin(t) * r))
	pts.append(Vector2(-r, drop))
	var p := Polygon2D.new()
	p.polygon = pts
	p.color = col
	return p


func _pin(a: RigidBody2D, b: RigidBody2D, anchor: Vector2) -> void:
	var j := PinJoint2D.new()
	j.position = anchor
	add_child(j)
	j.node_a = j.get_path_to(a)
	j.node_b = j.get_path_to(b)
	# Limbs swing but never fold across the torso.
	j.angular_limit_enabled = true
	j.angular_limit_lower = -1.1
	j.angular_limit_upper = 1.1


func _rect_poly(size: Vector2, col: Color) -> Polygon2D:
	var p := Polygon2D.new()
	var h := size / 2.0
	p.polygon = PackedVector2Array([
		Vector2(-h.x, -h.y), Vector2(h.x, -h.y), Vector2(h.x, h.y), Vector2(-h.x, h.y),
	])
	p.color = col
	return p
