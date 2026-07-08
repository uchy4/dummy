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
	if terrain.cave_mouth != Vector2i.ZERO:
		var cave := CaveArt.new()
		cave.position = Vector2((float(terrain.cave_mouth.x) + 0.5) * TILE,
			float(terrain.cave_mouth.y) * TILE)
		add_child(cave)
	_build_truck()
	_build_lounge_sofas()

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
			pipe.terrain = terrain  # blasts scorch the pipe like wallpaper
			add_child(pipe)
			pump.pipe_bottom_y = pipe.bottom_y  # busted pump leaks all the way down


## Cutaway art: the well pipe running from the pump down into the ground.
## Destructible per 16px segment: a blast whose core reaches the pipe blows
## those segments clean off (flying metal bits), while near misses scorch
## the survivors 90% toward the carved-earth brown, like wallpaper.
class PipeArt:
	extends Node2D
	var top := Vector2.ZERO
	var bottom_y := 0.0
	var terrain: Terrain
	var _scorch := {}  # scorched 16px pipe segments, keyed by row
	var _broken := {}  # segments blown off entirely, keyed by row

	func _ready() -> void:
		z_index = 1  # over terrain, under players/bombs
		if terrain != null:
			terrain.carved.connect(_on_carved)

	func _on_carved(pos: Vector2, radius: float) -> void:
		if absf(pos.x - top.x) > radius * 1.6 + 8.0:
			return
		var direct := absf(pos.x - top.x) <= radius + 4.0
		var r0 := int(maxf(pos.y - radius * 1.6, top.y) / 16.0)
		var r1 := int(minf(pos.y + radius * 1.6, bottom_y) / 16.0)
		for ry in range(r0, r1 + 1):
			var seg_c := Vector2(top.x, float(ry) * 16.0 + 8.0)
			var d := pos.distance_to(seg_c)
			if direct and d <= radius and not _broken.has(ry):
				_broken[ry] = true
				_scorch.erase(ry)
				var bit := Plank.new()
				bit.size = Vector2(4, 12)
				bit.col = Color("41525f")
				bit.position = seg_c
				bit.rotation = randf_range(-0.5, 0.5)
				bit.linear_velocity = Vector2(randf_range(-150.0, 150.0),
					randf_range(-230.0, -60.0))
				bit.angular_velocity = randf_range(-8.0, 8.0)
				get_parent().add_child(bit)
			elif d <= radius * 1.6 and not _broken.has(ry):
				_scorch[ry] = true
		queue_redraw()

	func _draw() -> void:
		var scar := Color("2b1a0c")
		scar.a = 0.9
		var r0 := int(top.y / 16.0)
		var r1 := int((bottom_y - 0.01) / 16.0)
		for ry in range(r0, r1 + 1):
			if _broken.has(ry):
				continue
			var sy := maxf(float(ry) * 16.0, top.y)
			var sh := minf(float(ry) * 16.0 + 16.0, bottom_y) - sy
			if sh <= 0.0:
				continue
			draw_rect(Rect2(top.x - 3.0, sy, 6.0, sh), Color("23303a"))
			draw_rect(Rect2(top.x - 1.5, sy, 3.0, sh), Color("41525f"))
			if _scorch.has(ry):
				draw_rect(Rect2(top.x - 3.0, sy, 6.0, sh), scar)
		var y := top.y + 22.0
		while y < bottom_y - 8.0:
			if not _broken.has(int(y / 16.0)):
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
			pig_home.end.x - 8.0, t), ground_y - 10.5)
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


## Rocky covering over the surface cave mouth: a boulder arch with a dark
## maw leading into the carved passage below (prop kind 16 on the web
## stream). A blast that reaches it blows the boulders apart into tumbling
## rock chunks, leaving the bare hole.
class CaveArt:
	extends Node2D
	var prop_kind := 16
	var _dead := false

	func _ready() -> void:
		add_to_group(&"props")
		add_to_group(&"chests")  # blasts in range call blast_destroy()
		z_index = 1  # behind players and critters walking in

	func blast_destroy() -> void:
		if _dead:
			return
		_dead = true
		var grays: Array[Color] = [Color("6e7681"), Color("59616b"), Color("575f6a")]
		for i in 5:
			var rock := Plank.new()
			rock.size = Vector2(randf_range(7.0, 12.0), randf_range(5.0, 9.0))
			rock.col = grays[i % grays.size()]
			rock.position = global_position \
				+ Vector2(randf_range(-16.0, 16.0), randf_range(-20.0, -2.0))
			rock.rotation = randf_range(-0.6, 0.6)
			rock.linear_velocity = Vector2(randf_range(-170.0, 170.0),
				randf_range(-280.0, -90.0))
			rock.angular_velocity = randf_range(-7.0, 7.0)
			get_parent().add_child(rock)
		# Gray stone puff (mirrors to web as tinted fx 9) + a crunchy thud.
		var puff := DustPuff.new()
		puff.amount = 12
		puff.color = Color(0.45, 0.48, 0.53, 0.85)
		puff.position = global_position + Vector2(0, -10.0)
		get_parent().add_child(puff)
		get_tree().call_group(&"sfx", &"play_land", global_position)
		queue_free()

	func _draw() -> void:
		# Authored at full walk-in size (coordinates pre-scaled, no canvas
		# transform) so the rim stays a thin outline instead of a fattened
		# scaled-up stroke — same fix as the pigs.
		var mound := _x18([
			Vector2(-24, 2), Vector2(-23, -6), Vector2(-18, -12), Vector2(-14, -12),
			Vector2(-9, -18), Vector2(-3, -22), Vector2(4, -21), Vector2(9, -17),
			Vector2(14, -15), Vector2(18, -10), Vector2(22, -7), Vector2(24, 2),
		])
		# Constant ~2px black rim around the silhouette, whatever the size.
		var cen := Vector2(0, -14.4)
		var rim := PackedVector2Array()
		for p in mound:
			var d := p - cen
			rim.append(cen + d * (1.0 + 2.0 / maxf(d.length(), 1.0)))
		draw_colored_polygon(rim, Color.BLACK)
		draw_colored_polygon(mound, Color("6e7681"))
		# Shadow facet down the right flank, subtle light facet on the left.
		draw_colored_polygon(_x18([
			Vector2(4, -21), Vector2(9, -17), Vector2(14, -15), Vector2(18, -10),
			Vector2(22, -7), Vector2(24, 2), Vector2(10, 2), Vector2(6, -12),
		]), Color("59616b"))
		draw_colored_polygon(_x18([
			Vector2(-23, -6), Vector2(-18, -12), Vector2(-14, -12),
			Vector2(-16, -2), Vector2(-24, 2),
		]), Color("777d86"))
		draw_line(Vector2(-10.8, -30.6), Vector2(-16.2, -14.4), Color("4d545c"), 1.5)
		draw_line(Vector2(19.8, -23.4), Vector2(14.4, -9.0), Color("4d545c"), 1.5)
		# The maw hugs the actual carved opening (~1.5 cells wide) instead
		# of spilling a wide black doorway over solid ground beside it.
		var maw := Color("1c1310")
		draw_colored_polygon(PackedVector2Array([
			Vector2(-13, 6), Vector2(-12, -14), Vector2(-8, -23), Vector2(0, -27),
			Vector2(8, -23), Vector2(12, -14), Vector2(13, 6),
		]), maw)
		draw_rect(Rect2(-13, 4, 26, 30), maw)

	static func _x18(pts: Array) -> PackedVector2Array:
		var out := PackedVector2Array()
		for p: Vector2 in pts:
			out.append(p * 1.8)
		return out


## The pickup truck parks on a clear stretch of grass away from the other
## surface features (prop kind 17).
func _build_truck() -> void:
	var tx := -1
	for attempt in 60:
		var x := randi_range(10, Terrain.W - 10)
		if absi(x - terrain.outhouse_cell.x) < 9 or absi(x - terrain.cave_mouth.x) < 10:
			continue
		if terrain.pond_rect.size.x > 0 and x >= terrain.pond_rect.position.x - 4 \
				and x <= terrain.pond_rect.end.x + 4:
			continue
		var bad := false
		for r: Rect2i in [terrain.surface_pens, terrain.corn_field]:
			if r.size.x > 0 and x >= r.position.x - 5 and x <= r.end.x + 5:
				bad = true
		if bad:
			continue
		tx = x
		break
	if tx < 0:
		return
	var truck := TruckArt.new()
	truck.position = Vector2((float(tx) + 0.5) * TILE,
		float(Terrain.SURFACE_ROW) * TILE - 18.0)
	add_child(truck)


## Two sofas dress the finish hall — it doubles as the pre-match lounge.
func _build_lounge_sofas() -> void:
	var fr := terrain.finish_line_rect()
	if fr.size.x <= 0.0:
		return
	for k in 2:
		var sofa := SofaArt.new()
		sofa.position = Vector2(fr.position.x + fr.size.x * (0.2 + 0.6 * float(k)),
			fr.end.y - 12.0)
		add_child(sofa)


## The surface pickup truck (prop kind 17): player-plus sized, a kick
## shoves it one truck-length away from the kicker with a suspension
## wobble, and a blast in range blows it into red panel debris.
class TruckArt:
	extends Node2D
	var prop_kind := 17
	var _dead := false
	var _rolling := false

	func _ready() -> void:
		add_to_group(&"props")
		add_to_group(&"fixtures")  # kicks in range call kicked()
		add_to_group(&"chests")    # blasts in range call blast_destroy()
		z_index = 2

	func kicked() -> void:
		if _rolling or _dead:
			return
		_rolling = true
		# Shoved away from the nearest player — they just kicked the bumper.
		var s := 1.0
		var best := 1e18
		for n in get_tree().get_nodes_in_group(&"players"):
			var p := n as Node2D
			if p == null:
				continue
			var d := absf(p.global_position.x - global_position.x)
			if d < best:
				best = d
				s = 1.0 if global_position.x >= p.global_position.x else -1.0
		# One truck-length slide, no roll — just a suspension wobble.
		var tw := create_tween()
		tw.tween_property(self, "position:x", position.x + 72.0 * s, 0.5) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_callback(_roll_done)
		var wob := create_tween()
		wob.tween_property(self, "rotation", 0.09 * s, 0.1)
		wob.tween_property(self, "rotation", -0.05 * s, 0.14)
		wob.tween_property(self, "rotation", 0.0, 0.18)
		get_tree().call_group(&"sfx", &"play_land", global_position)

	func _roll_done() -> void:
		_rolling = false

	func blast_destroy() -> void:
		if _dead:
			return
		_dead = true
		if NetHub.has_viewers():  # fx kind 11 = plank debris burst
			NetHub.broadcast({"t": "fx", "k": 11,
				"x": int(global_position.x), "y": int(global_position.y)})
		for i in 8:
			var panel := Plank.new()
			panel.size = Vector2(randf_range(10.0, 18.0), 4.0)
			panel.col = Color("d32f2f") if i % 4 != 0 else Color("454049")
			panel.position = global_position \
				+ Vector2(randf_range(-30.0, 30.0), randf_range(-16.0, 6.0))
			panel.rotation = randf_range(-0.6, 0.6)
			panel.linear_velocity = Vector2(randf_range(-200.0, 200.0),
				randf_range(-320.0, -100.0))
			panel.angular_velocity = randf_range(-8.0, 8.0)
			get_parent().add_child(panel)
		var puff := DustPuff.new()
		puff.amount = 10
		puff.color = Color(0.6, 0.25, 0.2, 0.85)
		puff.position = global_position
		get_parent().add_child(puff)
		get_tree().call_group(&"sfx", &"play_land", global_position)
		queue_free()

	func _draw() -> void:
		# Authored ~72x36 with the origin at the body centre so the kick's
		# full rotation reads as the truck rolling over.
		draw_rect(Rect2(-36, -8, 72, 20), Color.BLACK)
		draw_rect(Rect2(-7, -19, 34, 13), Color.BLACK)
		draw_rect(Rect2(-35, -7, 70, 18), Color("d32f2f"))
		draw_rect(Rect2(-6, -18, 32, 12), Color("d32f2f"))
		draw_rect(Rect2(-2, -16, 20, 9), Color("bfe3f2"))
		draw_rect(Rect2(-35, 7, 70, 4), Color("8e2420"))
		draw_rect(Rect2(33, -4, 3, 4), Color("ffd54f"))
		for wx: float in [-22.0, 22.0]:
			draw_circle(Vector2(wx, 10), 8.0, Color("111111"))
			draw_circle(Vector2(wx, 10), 3.5, Color("666666"))


## A lounge sofa (prop kind 18): kicks make it hop, blasts shred it.
class SofaArt:
	extends Node2D
	var prop_kind := 18
	var _dead := false
	var _home_y := 0.0

	func _ready() -> void:
		add_to_group(&"props")
		add_to_group(&"fixtures")
		add_to_group(&"chests")
		_home_y = position.y
		z_index = 1

	func kicked() -> void:
		if _dead:
			return
		var tw := create_tween()
		tw.tween_property(self, "position:y", _home_y - 7.0, 0.12) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(self, "position:y", _home_y, 0.2) \
			.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)

	func blast_destroy() -> void:
		if _dead:
			return
		_dead = true
		if NetHub.has_viewers():
			NetHub.broadcast({"t": "fx", "k": 11,
				"x": int(global_position.x), "y": int(global_position.y)})
		for i in 6:
			var cushion := Plank.new()
			cushion.size = Vector2(randf_range(8.0, 13.0), 5.0)
			cushion.col = Color("a34a3c") if i % 2 == 0 else Color("8e3b2f")
			cushion.position = global_position \
				+ Vector2(randf_range(-20.0, 20.0), randf_range(-10.0, 4.0))
			cushion.linear_velocity = Vector2(randf_range(-160.0, 160.0),
				randf_range(-280.0, -80.0))
			cushion.angular_velocity = randf_range(-7.0, 7.0)
			get_parent().add_child(cushion)
		get_tree().call_group(&"sfx", &"play_land", global_position)
		queue_free()

	func _draw() -> void:
		draw_rect(Rect2(-26, -13, 52, 25), Color.BLACK)
		draw_rect(Rect2(-25, -12, 50, 23), Color("8e3b2f"))
		draw_rect(Rect2(-21, -11, 40, 6), Color("a34a3c"))
		draw_rect(Rect2(-21, -4, 19, 8), Color("a34a3c"))
		draw_rect(Rect2(1, -4, 19, 8), Color("a34a3c"))
		draw_rect(Rect2(-25, 7, 6, 4), Color("5c2620"))
		draw_rect(Rect2(19, 7, 6, 4), Color("5c2620"))


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
