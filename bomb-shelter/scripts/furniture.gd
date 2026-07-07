class_name Furniture
extends RigidBody2D
## Movable, kickable, explodable bunker furniture: tables, chairs, beds and
## pillows. Never breaks — it just tumbles, like scripts/ragdoll.gd's parts
## (same collision_layer/mask + physics-material trick), and gets flung by
## kicks (group "props") and blasts (group "ragdoll_parts").
##
## Usage: set `kind` before adding to the tree, e.g.:
##   var t := Furniture.new(); t.kind = Furniture.Kind.TABLE; add_child(t)
## `position` is the piece's CENTER, same convention as Player/Ragdoll — to
## stand it on a floor at world y `floor_y`, set position.y = floor_y - h/2
## where h is the piece's height (36x20 / 16x22 / 44x16 / 18x10 below).

enum Kind { TABLE, CHAIR, BED, PILLOW }

var kind := Kind.TABLE
## Streamed to web viewers as [x, y, kind, rotation]; kept in sync with `kind`.
var prop_kind := 0


func _ready() -> void:
	prop_kind = int(kind)
	add_to_group(&"props")
	add_to_group(&"ragdoll_parts")
	z_index = 3
	collision_layer = 4  # players and bombs collide with (and push) it
	collision_mask = 1 | 2 | 4

	var size := Vector2(36, 20)
	mass = 1.6
	match kind:
		Kind.CHAIR:
			size = Vector2(16, 22)
			mass = 0.8
		Kind.BED:
			size = Vector2(44, 16)
			mass = 2.0
		Kind.PILLOW:
			size = Vector2(18, 10)
			mass = 0.25

	var pm := PhysicsMaterial.new()
	pm.bounce = 0.5 if kind == Kind.PILLOW else 0.3
	pm.friction = 0.6
	physics_material_override = pm

	var cs := CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	rs.size = size
	cs.shape = rs
	add_child(cs)

	match kind:
		Kind.TABLE:
			_build_table(size)
		Kind.CHAIR:
			_build_chair(size)
		Kind.BED:
			_build_bed(size)
		Kind.PILLOW:
			_build_pillow(size)


func _build_table(size: Vector2) -> void:
	add_child(_rect_poly(size + Vector2(2, 2), Color.BLACK))
	add_child(_rect_poly(Vector2(size.x, size.y * 0.4), Color("8a6238"),
		Vector2(0, -size.y * 0.3)))  # tabletop slab
	var leg_h := size.y * 0.55
	for side in [-1.0, 1.0]:
		add_child(_rect_poly(Vector2(4, leg_h), Color("5e3d22"),
			Vector2(side * (size.x / 2.0 - 3.0), size.y / 2.0 - leg_h / 2.0)))


func _build_chair(size: Vector2) -> void:
	add_child(_rect_poly(size + Vector2(2, 2), Color.BLACK))
	add_child(_rect_poly(Vector2(size.x, size.y * 0.35), Color("7a5230"),
		Vector2(0, size.y * 0.32)))  # seat
	add_child(_rect_poly(Vector2(size.x * 0.85, size.y * 0.55), Color("8a6238"),
		Vector2(0, -size.y * 0.22)))  # back


func _build_bed(size: Vector2) -> void:
	add_child(_rect_poly(size + Vector2(2, 2), Color.BLACK))
	add_child(_rect_poly(size, Color("6d4c2f")))  # frame
	add_child(_rect_poly(Vector2(size.x * 0.92, size.y * 0.55), Color("e8e0c8")))  # mattress
	add_child(_rect_poly(Vector2(6, size.y * 1.3), Color("5e3d22"),
		Vector2(-size.x / 2.0 + 3.0, -size.y * 0.1)))  # headboard


func _build_pillow(size: Vector2) -> void:
	add_child(_rounded_poly(size + Vector2(2, 2), Color.BLACK))
	add_child(_rounded_poly(size, Color("f5f0e1")))


func _rect_poly(size: Vector2, col: Color, offset := Vector2.ZERO) -> Polygon2D:
	var p := Polygon2D.new()
	var h := size / 2.0
	p.polygon = PackedVector2Array([
		Vector2(-h.x, -h.y), Vector2(h.x, -h.y), Vector2(h.x, h.y), Vector2(-h.x, h.y),
	])
	p.color = col
	p.position = offset
	return p


## A cut-corner octagon — cheap stand-in for a rounded rect (pillow).
func _rounded_poly(size: Vector2, col: Color) -> Polygon2D:
	var h := size / 2.0
	var c := minf(h.x, h.y) * 0.5
	var p := Polygon2D.new()
	p.polygon = PackedVector2Array([
		Vector2(-h.x + c, -h.y), Vector2(h.x - c, -h.y), Vector2(h.x, -h.y + c),
		Vector2(h.x, h.y - c), Vector2(h.x - c, h.y), Vector2(-h.x + c, h.y),
		Vector2(-h.x, h.y - c), Vector2(-h.x, -h.y + c),
	])
	p.color = col
	return p
