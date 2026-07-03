class_name Ragdoll
extends Node2D
## Cosmetic death ragdoll: six rigid-body parts (head, torso, arms, legs)
## pinned together, launched by the killing blast, tumbling off terrain.
## Fades out and frees itself after a few seconds.

const LIFE := 4.5
const FADE_START := 3.2

var color := Color.WHITE
var impulse := Vector2.ZERO

var _age := 0.0
var _parts: Array[RigidBody2D] = []


func _ready() -> void:
	z_index = 5
	var torso := _part(Vector2(0, -2), Vector2(12, 10), color)
	var head := _part(Vector2(0, -11), Vector2(10, 9), color.lightened(0.35))
	_decorate_head(head)
	var arm_l := _part(Vector2(-7, 0), Vector2(4, 10), color.darkened(0.15))
	var arm_r := _part(Vector2(7, 0), Vector2(4, 10), color.darkened(0.15))
	var leg_l := _part(Vector2(-3, 9), Vector2(4, 12), color.darkened(0.35))
	var leg_r := _part(Vector2(3, 9), Vector2(4, 12), color.darkened(0.35))

	_pin(head, torso, Vector2(0, -7))
	_pin(arm_l, torso, Vector2(-6, -5))
	_pin(arm_r, torso, Vector2(6, -5))
	_pin(leg_l, torso, Vector2(-3, 3))
	_pin(leg_r, torso, Vector2(3, 3))

	for p in _parts:
		p.linear_velocity = impulse * randf_range(0.7, 1.3) \
			+ Vector2(randf_range(-70.0, 70.0), randf_range(-140.0, 0.0))
		p.angular_velocity = randf_range(-12.0, 12.0)


func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFE:
		queue_free()
	elif _age >= FADE_START:
		modulate.a = 1.0 - (_age - FADE_START) / (LIFE - FADE_START)


func _part(pos: Vector2, size: Vector2, col: Color) -> RigidBody2D:
	var b := RigidBody2D.new()
	b.position = pos
	b.mass = 0.5
	b.collision_layer = 0
	b.collision_mask = 1  # tumbles off terrain, ignores players/bombs
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.3
	pm.friction = 0.6
	b.physics_material_override = pm

	var cs := CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	rs.size = size
	cs.shape = rs
	b.add_child(cs)
	b.add_child(_rect_poly(size + Vector2(2, 2), Color.BLACK))  # outline
	b.add_child(_rect_poly(size, col))

	add_child(b)
	_parts.append(b)
	return b


func _decorate_head(head: RigidBody2D) -> void:
	var hat := _rect_poly(Vector2(12, 3.5), color.lightened(0.15))
	hat.position = Vector2(0, -5.5)
	head.add_child(hat)
	for x in [-2.5, 2.5]:
		var eye := _rect_poly(Vector2(2, 2.5), Color.WHITE)
		eye.position = Vector2(x, -0.5)
		head.add_child(eye)


func _pin(a: RigidBody2D, b: RigidBody2D, anchor: Vector2) -> void:
	var j := PinJoint2D.new()
	j.position = anchor
	add_child(j)
	j.node_a = j.get_path_to(a)
	j.node_b = j.get_path_to(b)


func _rect_poly(size: Vector2, col: Color) -> Polygon2D:
	var p := Polygon2D.new()
	var h := size / 2.0
	p.polygon = PackedVector2Array([
		Vector2(-h.x, -h.y), Vector2(h.x, -h.y), Vector2(h.x, h.y), Vector2(-h.x, h.y),
	])
	p.color = col
	return p
