class_name BunkerProps
extends Node2D
## Furnishes the generated bunker: an outhouse entrance on the surface, a
## kitchen (table + chairs + a decorative counter), a bedroom (bed +
## pillows), a bathroom (toilet + shower), an arsenal room (wall-mounted
## rifles that misfire when blasted, plus a table), a surface animal strip
## (chickens/pigs behind Fence sections, standing under open sky) and a
## surface corn field (swaying CornStalks). Purely additive on top of
## terrain.gd's layout — reads `terrain.bunker_rooms` / `terrain.outhouse_cell`
## / `terrain.surface_pens` / `terrain.fence_xs` / `terrain.corn_field` and
## spawns Furniture / Fixture / Critter / Fence / CornStalk / WallGun children.
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


var _outhouse_local := Vector2.ZERO
var _counters: Array[Rect2] = []


func _ready() -> void:
	if terrain == null or terrain.bunker_rooms.is_empty():
		return

	# Painted room backgrounds (wallpaper, paintings, shelves, bathroom
	# tile) rendered behind terrain, furniture, and players.
	var decor := RoomDecor.new()
	decor.terrain = terrain
	add_child(decor)

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
	if terrain.bunker_rooms.has("arsenal"):
		var arsenal_rect: Rect2i = terrain.bunker_rooms["arsenal"]
		if arsenal_rect.size.x > 0:
			_build_arsenal(arsenal_rect)

	if terrain.surface_pens.size.x > 0:
		_build_surface_pens()
	if terrain.corn_field.size.x > 0:
		_build_corn()

	queue_redraw()


func _floor_y(rect: Rect2i) -> float:
	return float(rect.end.y) * TILE


# ------------------------------------------------------------- outhouse ---

func _build_outhouse() -> void:
	var floor_y := float(terrain.outhouse_cell.y) * TILE
	var cx := (float(terrain.outhouse_cell.x) + 0.5) * TILE
	_outhouse_local = Vector2(cx, floor_y)

	var hut := OuthouseArt.new()
	hut.position = _outhouse_local
	add_child(hut)

	# The well: hand pump on the surface, pipe straight down to the buried
	# reservoir (pipe is pure cutaway art, drawn over the ground).
	if terrain.pump_cell != Vector2i.ZERO:
		var pump := Fixture.new()
		pump.kind = Fixture.Kind.PUMP
		pump.position = Vector2((float(terrain.pump_cell.x) + 0.5) * TILE,
			float(terrain.pump_cell.y) * TILE - 10.0)
		add_child(pump)
		if terrain.reservoir_rect.size.x > 0:
			var pipe := PipeArt.new()
			pipe.top = Vector2(pump.position.x, float(terrain.pump_cell.y) * TILE)
			pipe.bottom_y = float(terrain.reservoir_rect.position.y) * TILE + 4.0
			add_child(pipe)
			pump.pipe_bottom_y = pipe.bottom_y  # busted pump leaks all the way down


## Cutaway art: the well pipe running from the pump down into the ground.
class PipeArt:
	extends Node2D
	var top := Vector2.ZERO
	var bottom_y := 0.0

	func _ready() -> void:
		z_index = 1  # over terrain, under players/bombs

	func _draw() -> void:
		draw_line(top, Vector2(top.x, bottom_y), Color("23303a"), 6.0)
		draw_line(top, Vector2(top.x, bottom_y), Color("41525f"), 3.0)
		var y := top.y + 22.0
		while y < bottom_y - 8.0:
			draw_rect(Rect2(top.x - 4.0, y, 8.0, 3.0), Color("2c3c48"))
			y += 34.0


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

	# Fully physical: falls, tips, launches — and squirts on every hit.
	var toilet := Toilet.new()
	toilet.position = Vector2(left + 14.0, floor_y - 9.0)
	add_child(toilet)

	var shower := Fixture.new()
	shower.kind = Fixture.Kind.SHOWER
	shower.position = Vector2(right - 14.0, floor_y - 13.0)
	add_child(shower)


# -------------------------------------------------------------- surface ---

## Surface animal strip: fence posts at `terrain.fence_xs`, chickens in the
## left half and pigs in the right half (split at the middle fence). Animals
## stand at the grass line under open sky — no room walls involved.
func _build_surface_pens() -> void:
	var strip: Rect2i = terrain.surface_pens
	var ground_y := float(strip.position.y) * TILE

	for x in terrain.fence_xs:
		var fx: int = x
		var fence := Fence.new()
		fence.position = Vector2((float(fx) + 0.5) * TILE, ground_y - 11.0)
		add_child(fence)

	var left := float(strip.position.x) * TILE
	var right := float(strip.end.x) * TILE
	var mid := (left + right) / 2.0
	# Prefer the middle fence post (if any) as the actual split point so the
	# animals' homes line up with the fence they're penned behind.
	for x in terrain.fence_xs:
		var fx2: int = x
		var fx_world := (float(fx2) + 0.5) * TILE
		if fx_world > left + TILE and fx_world < right - TILE:
			mid = fx_world

	var chicken_home := Rect2(left, ground_y - 40.0, mid - left, 40.0)
	var pig_home := Rect2(mid, ground_y - 40.0, right - mid, 40.0)

	for i in 3:
		var t := 0.5 if i == 1 else (0.15 if i == 0 else 0.85)
		var chicken := Critter.new()
		chicken.kind = Critter.Kind.CHICKEN
		chicken.position = Vector2(lerpf(chicken_home.position.x + 6.0,
			chicken_home.end.x - 6.0, t), ground_y - 4.5)
		chicken.home = chicken_home
		add_child(chicken)

	for i in 2:
		var t := 0.3 if i == 0 else 0.7
		var pig := Critter.new()
		pig.kind = Critter.Kind.PIG
		pig.position = Vector2(lerpf(pig_home.position.x + 8.0,
			pig_home.end.x - 8.0, t), ground_y - 5.5)
		pig.home = pig_home
		add_child(pig)


# ------------------------------------------------------------------ corn ---

## Surface corn field: one swaying CornStalk per cell across the strip.
func _build_corn() -> void:
	var strip: Rect2i = terrain.corn_field
	var ground_y := float(strip.position.y) * TILE

	for i in strip.size.x:
		var stalk := CornStalk.new()
		stalk.position = Vector2((float(strip.position.x + i) + 0.5) * TILE, ground_y)
		add_child(stalk)


# --------------------------------------------------------------- arsenal ---

## The lower-level room where the pens used to be: wall-mounted rifles that
## misfire when a nearby blast goes off, plus a table for flavor.
func _build_arsenal(rect: Rect2i) -> void:
	var floor_y := _floor_y(rect)
	var left := float(rect.position.x) * TILE
	var right := float(rect.end.x) * TILE
	var wall_y := float(rect.position.y) * TILE + float(rect.size.y) * TILE * 0.45

	var gun_count := 3 if rect.size.x < 8 else 4
	var margin := 12.0
	for i in gun_count:
		var t := 0.5 if gun_count <= 1 else float(i) / float(gun_count - 1)
		var gun := WallGun.new()
		gun.position = Vector2(lerpf(left + margin, right - margin, t), wall_y)
		add_child(gun)

	var table := Furniture.new()
	table.kind = Furniture.Kind.TABLE
	table.position = Vector2((left + right) / 2.0, floor_y - 10.0)
	add_child(table)


# ------------------------------------------------------------------ draw ---

func _draw() -> void:
	for c in _counters:
		_draw_counter(c)


## The outhouse hut: streamed to web (prop kind 9), and blown to plank
## debris when a blast reaches it (group "chests" -> blast_destroy).
class OuthouseArt:
	extends Node2D
	var prop_kind := 9
	var _dead := false

	func _ready() -> void:
		add_to_group(&"props")
		add_to_group(&"chests")

	func blast_destroy() -> void:
		if _dead:
			return
		_dead = true
		if NetHub.has_viewers():  # fx kind 11 = plank debris burst
			NetHub.broadcast({"t": "fx", "k": 11,
				"x": int(global_position.x), "y": int(global_position.y - 20.0)})
		# The hut bursts into tumbling planks plus its roof slab.
		for i in 9:
			var plank := Plank.new()
			plank.size = Vector2(randf_range(9.0, 16.0), 3.0)
			plank.position = global_position \
				+ Vector2(randf_range(-16.0, 16.0), randf_range(-38.0, -6.0))
			plank.rotation = randf_range(-0.6, 0.6)
			plank.linear_velocity = Vector2(randf_range(-190.0, 190.0),
				randf_range(-330.0, -110.0))
			plank.angular_velocity = randf_range(-9.0, 9.0)
			get_parent().add_child(plank)
		var roof := Plank.new()
		roof.size = Vector2(26.0, 5.0)
		roof.col = Color("4a3517")
		roof.position = global_position + Vector2(0, -44.0)
		roof.linear_velocity = Vector2(randf_range(-90.0, 90.0), -360.0)
		roof.angular_velocity = randf_range(-6.0, 6.0)
		get_parent().add_child(roof)
		queue_free()

	func _draw() -> void:
		var w := 36.0
		var h := 44.0
		var top_left := Vector2(-w / 2.0, -h + 8.0)
		# plank walls
		draw_rect(Rect2(top_left, Vector2(w, h - 8.0)).grow(1.0), Color.BLACK)
		draw_rect(Rect2(top_left, Vector2(w, h - 8.0)), Color("6d4c2f"))
		for i in 4:
			var px := top_left.x + 2.0 + float(i) * (w - 4.0) / 3.0
			draw_line(Vector2(px, top_left.y + 1.0), Vector2(px, -1.0),
				Color("5e3d22"), 1.0)
		# slanted roof
		draw_colored_polygon(PackedVector2Array([
			Vector2(-w / 2.0 - 3.0, -h + 9.0), Vector2(w / 2.0 + 3.0, -h + 9.0),
			Vector2(w / 2.0 - 2.0, -h - 3.0), Vector2(-w / 2.0 + 2.0, -h - 3.0),
		]), Color("4a3517"))
		# dark open doorway + crescent-moon cutout
		draw_rect(Rect2(Vector2(-6.0, -20.0), Vector2(12.0, 20.0)), Color("2b1d10"))
		draw_circle(Vector2(0.0, -32.0), 3.5, Color("e8d9b0"))
		draw_circle(Vector2(1.3, -32.0), 3.0, Color("6d4c2f"))


## A flying piece of busted outhouse: tumbles off terrain, gets tossed by
## later blasts (ragdoll_parts), fades away after a few seconds.
class Plank:
	extends RigidBody2D
	var size := Vector2(14, 3)
	var col := Color("6d4c2f")
	var _age := 0.0

	func _ready() -> void:
		add_to_group(&"ragdoll_parts")
		z_index = 4
		mass = 0.4
		collision_layer = 0
		collision_mask = 1
		var pm := PhysicsMaterial.new()
		pm.bounce = 0.3
		pm.friction = 0.6
		physics_material_override = pm
		var cs := CollisionShape2D.new()
		var rs := RectangleShape2D.new()
		rs.size = size
		cs.shape = rs
		add_child(cs)

	func _process(delta: float) -> void:
		_age += delta
		if _age > 3.4:
			modulate.a = maxf(0.0, 1.0 - (_age - 3.4))
		if _age > 4.4:
			queue_free()

	func _draw() -> void:
		draw_rect(Rect2(-size / 2.0 - Vector2.ONE, size + Vector2(2, 2)), Color.BLACK)
		draw_rect(Rect2(-size / 2.0, size), col)
