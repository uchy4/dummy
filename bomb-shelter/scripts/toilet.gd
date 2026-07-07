class_name Toilet
extends RigidBody2D
## The bathroom throne, fully physical: it falls, tips over, gets kicked
## across the room and launched by blasts like any furniture — and every
## kick or blast makes it squirt water. It cracks after a few hits but
## never stops squirting.

const PROP_KIND := 4

var prop_kind := PROP_KIND

var _squirt_count := 0
var _cracked := false


func _ready() -> void:
	add_to_group(&"props")
	add_to_group(&"ragdoll_parts")  # blasts fling it like furniture
	add_to_group(&"fixtures")       # kicks in range call kicked()
	add_to_group(&"chests")         # blasts in range call blast_destroy()
	z_index = 3
	mass = 1.8
	collision_layer = 4  # players and bombs collide with (and push) it
	collision_mask = 1 | 2 | 4
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.2
	pm.friction = 0.7
	physics_material_override = pm
	var cs := CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	rs.size = Vector2(16, 18)
	cs.shape = rs
	add_child(cs)


func kicked() -> void:
	_squirt()


func blast_destroy() -> void:
	_squirt(1.6)


func _squirt(mult := 1.0) -> void:
	_squirt_count += 1
	if _squirt_count >= 3:
		_cracked = true
	var spray := WaterSpray.new()
	spray.dir = Vector2(randf_range(-0.3, 0.3), -1.0).normalized()
	spray.amount = int(14 * mult)
	spray.spread = 0.5
	spray.speed = 200.0 * mult
	spray.global_position = global_position + Vector2(0, -8)
	get_parent().add_child.call_deferred(spray)
	queue_redraw()


func _draw() -> void:
	var tint := Color(0.85, 0.85, 0.85) if _cracked else Color.WHITE
	draw_rect(Rect2(-9, -9, 18, 20), Color.BLACK)              # outline
	draw_rect(Rect2(-7, 2, 14, 7), Color("d8d8d8") * tint)     # base
	draw_rect(Rect2(-8, -3, 16, 8), Color("f2f2f2") * tint)    # bowl
	draw_rect(Rect2(-8, -9, 16, 6), Color("ffffff") * tint)    # tank
	draw_rect(Rect2(-8, -4, 16, 1.5), Color("c9c9c9"))         # seat line
	if _cracked:
		draw_line(Vector2(-4, -8), Vector2(3, 5), Color("555555"), 1.2)
