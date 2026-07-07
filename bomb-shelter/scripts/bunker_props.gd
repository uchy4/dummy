class_name BunkerProps
extends Node2D
## Furnishes the generated bunker: an outhouse entrance on the surface, a
## kitchen (table + chairs + a decorative counter), a bedroom (bed +
## pillows), a bathroom (toilet + shower) and two animal pens (chickens,
## pigs, decorative fence posts). Purely additive on top of terrain.gd's
## room layout — reads `terrain.bunker_rooms` / `terrain.outhouse_cell` and
## spawns Furniture / Fixture / Critter children.
##
## IMPORTANT: assumes this node is added at position (0, 0) alongside Terrain
## (e.g. `world.add_child(bunker_props)` where `world` is Terrain's parent
## too), so its local coordinates line up with terrain world-px coordinates.
##
## Usage:
##   var bp := BunkerProps.new()
##   bp.terrain = terrain
##   world.add_child(bp)   # builds everything in _ready()

const TILE := 16

var terrain: Terrain

## Invisible marker so purely-decorative art (outhouse hut, fence posts —
## drawn directly in _draw() below) still streams to web viewers as a
## "props" entry with the right kind/position.
class PropMarker:
	extends Node2D
	var prop_kind := 0

	func _ready() -> void:
		add_to_group(&"props")


var _has_outhouse := false
var _outhouse_local := Vector2.ZERO
var _counters: Array[Rect2] = []
var _fence_local: Array[Vector2] = []


func _ready() -> void:
	if terrain == null or terrain.bunker_rooms.is_empty():
		return

	_build_outhouse()

	if terrain.bunker_rooms.has("kitchen"):
		var kitchen_rect: Rect2i = terrain.bunker_rooms["kitchen"]
		_build_kitchen(kitchen_rect)
	if terrain.bunker_rooms.has("bedroom"):
		var bedroom_rect: Rect2i = terrain.bunker_rooms["bedroom"]
		_build_bedroom(bedroom_rect)
	if terrain.bunker_rooms.has("bathroom"):
		var bathroom_rect: Rect2i = terrain.bunker_rooms["bathroom"]
		_build_bathroom(bathroom_rect)
	if terrain.bunker_rooms.has("chicken_pen"):
		var chicken_rect: Rect2i = terrain.bunker_rooms["chicken_pen"]
		_build_pen(chicken_rect, Critter.Kind.CHICKEN, 3)
	if terrain.bunker_rooms.has("pig_pen"):
		var pig_rect: Rect2i = terrain.bunker_rooms["pig_pen"]
		_build_pen(pig_rect, Critter.Kind.PIG, 2)

	queue_redraw()


func _floor_y(rect: Rect2i) -> float:
	return float(rect.end.y) * TILE


# ------------------------------------------------------------- outhouse ---

func _build_outhouse() -> void:
	_has_outhouse = true
	var floor_y := float(terrain.outhouse_cell.y) * TILE
	var cx := (float(terrain.outhouse_cell.x) + 0.5) * TILE
	_outhouse_local = Vector2(cx, floor_y)

	var marker := PropMarker.new()
	marker.prop_kind = 9  # outhouse
	marker.position = _outhouse_local
	add_child(marker)


# -------------------------------------------------------------- kitchen ---

func _build_kitchen(rect: Rect2i) -> void:
	var floor_y := _floor_y(rect)
	var left := float(rect.position.x) * TILE
	var right := float(rect.end.x) * TILE
	var cx := (left + right) / 2.0

	var table := Furniture.new()
	table.kind = Furniture.Kind.TABLE
	table.position = Vector2(cx, floor_y - 10.0)
	add_child(table)

	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var chair := Furniture.new()
		chair.kind = Furniture.Kind.CHAIR
		chair.position = Vector2(cx + side * 26.0, floor_y - 11.0)
		add_child(chair)

	# Decorative-only counter along the left wall; no collision.
	var counter_w := clampf(right - left - 8.0, 12.0, 40.0)
	_counters.append(Rect2(left + 4.0, floor_y - 14.0, counter_w, 14.0))


func _draw_counter(c: Rect2) -> void:
	draw_rect(c.grow(1.0), Color.BLACK)
	draw_rect(c, Color("8a6238"))
	draw_rect(Rect2(c.position.x, c.position.y, c.size.x, 3.0), Color("caa64a"))


# -------------------------------------------------------------- bedroom ---

func _build_bedroom(rect: Rect2i) -> void:
	var floor_y := _floor_y(rect)
	var left := float(rect.position.x) * TILE
	var right := float(rect.end.x) * TILE
	var cx := (left + right) / 2.0

	var bed := Furniture.new()
	bed.kind = Furniture.Kind.BED
	bed.position = Vector2(cx, floor_y - 8.0)
	add_child(bed)

	for i in 2:
		var pillow := Furniture.new()
		pillow.kind = Furniture.Kind.PILLOW
		pillow.position = Vector2(cx + (float(i) - 0.5) * 10.0, floor_y - 22.0)
		add_child(pillow)  # settles onto the bed by physics


# ------------------------------------------------------------- bathroom ---

func _build_bathroom(rect: Rect2i) -> void:
	var floor_y := _floor_y(rect)
	var left := float(rect.position.x) * TILE
	var right := float(rect.end.x) * TILE

	var toilet := Fixture.new()
	toilet.kind = Fixture.Kind.TOILET
	toilet.position = Vector2(left + 14.0, floor_y - 9.0)
	add_child(toilet)

	var shower := Fixture.new()
	shower.kind = Fixture.Kind.SHOWER
	shower.position = Vector2(right - 14.0, floor_y - 13.0)
	add_child(shower)


# ------------------------------------------------------------------ pens ---

func _build_pen(rect: Rect2i, kind: int, count: int) -> void:
	var floor_y := _floor_y(rect)
	var left := float(rect.position.x) * TILE
	var right := float(rect.end.x) * TILE
	var top := float(rect.position.y) * TILE
	var pen_home := Rect2(left, top, right - left, floor_y - top)

	var half := 4.5 if kind == Critter.Kind.CHICKEN else 5.5
	for i in count:
		var t := 0.5 if count <= 1 else float(i) / float(count - 1)
		var critter := Critter.new()
		critter.kind = kind
		critter.position = Vector2(lerpf(left + 10.0, right - 10.0, t), floor_y - half)
		critter.home = pen_home
		add_child(critter)

	# Decorative-only fence posts along the pen's floor edges; no collision.
	for x in [left + 2.0, (left + right) / 2.0, right - 2.0]:
		_fence_local.append(Vector2(x, floor_y))
		var marker := PropMarker.new()
		marker.prop_kind = 8  # fence_post
		marker.position = Vector2(x, floor_y)
		add_child(marker)


# ------------------------------------------------------------------ draw ---

func _draw() -> void:
	if _has_outhouse:
		_draw_outhouse(_outhouse_local)
	for c in _counters:
		_draw_counter(c)
	for p in _fence_local:
		_draw_fence_post(p)


func _draw_outhouse(base: Vector2) -> void:
	var w := 36.0
	var h := 44.0
	var top_left := base + Vector2(-w / 2.0, -h + 8.0)

	# plank walls
	draw_rect(Rect2(top_left, Vector2(w, h - 8.0)).grow(1.0), Color.BLACK)  # outline
	draw_rect(Rect2(top_left, Vector2(w, h - 8.0)), Color("6d4c2f"))
	for i in 4:
		var px := top_left.x + 2.0 + float(i) * (w - 4.0) / 3.0
		draw_line(Vector2(px, top_left.y + 1.0), Vector2(px, base.y - 1.0),
			Color("5e3d22"), 1.0)

	# slanted roof
	var roof := PackedVector2Array([
		base + Vector2(-w / 2.0 - 3.0, -h + 9.0),
		base + Vector2(w / 2.0 + 3.0, -h + 9.0),
		base + Vector2(w / 2.0 - 2.0, -h - 3.0),
		base + Vector2(-w / 2.0 + 2.0, -h - 3.0),
	])
	draw_colored_polygon(roof, Color("4a3517"))

	# dark open doorway
	draw_rect(Rect2(base + Vector2(-6.0, -20.0), Vector2(12.0, 20.0)), Color("2b1d10"))

	# crescent-moon cutout, high on the door-facing wall
	draw_circle(base + Vector2(0.0, -32.0), 3.5, Color("e8d9b0"))
	draw_circle(base + Vector2(1.3, -32.0), 3.0, Color("6d4c2f"))


func _draw_fence_post(p: Vector2) -> void:
	draw_rect(Rect2(p.x - 2.0, p.y - 16.0, 4.0, 16.0).grow(1.0), Color.BLACK)
	draw_rect(Rect2(p.x - 2.0, p.y - 16.0, 4.0, 16.0), Color("8a6238"))
	draw_rect(Rect2(p.x - 3.0, p.y - 13.0, 6.0, 2.0), Color("5e3d22"))  # rail nub
