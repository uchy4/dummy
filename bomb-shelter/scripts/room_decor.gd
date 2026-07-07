class_name RoomDecor
extends Node2D
## Cozy painted backgrounds for the bunker rooms — wallpaper, paintings,
## shelves, cupboards, bathroom tile, concrete in the arsenal — so the rooms
## read as lived-in spaces instead of black holes. Pure backdrop: drawn
## beneath terrain, furniture, and players (z_index -5), no collision.

const TILE := 16

var terrain: Terrain

var _scorch := {}  # cell key -> Vector2i: wallpaper squares scorched by blasts


func _ready() -> void:
	z_index = -5
	if terrain == null or terrain.bunker_rooms.is_empty():
		return
	terrain.carved.connect(_on_carved)
	queue_redraw()


func _px(cells: Rect2i) -> Rect2:
	return Rect2(cells.position.x * TILE, cells.position.y * TILE,
		cells.size.x * TILE, cells.size.y * TILE)


func _draw() -> void:
	if terrain == null or terrain.bunker_rooms.is_empty():
		return
	var rooms: Dictionary = terrain.bunker_rooms
	if rooms.has("stairs"):
		_draw_planks(_px(rooms["stairs"]))
	if rooms.has("kitchen"):
		_draw_kitchen(_px(rooms["kitchen"]))
	if rooms.has("bedroom"):
		_draw_bedroom(_px(rooms["bedroom"]))
	if rooms.has("bathroom"):
		_draw_bathroom(_px(rooms["bathroom"]))
	if rooms.has("arsenal"):
		_draw_arsenal(_px(rooms["arsenal"]))
	if terrain.finish_room.size.x > 0:
		_draw_finish(_px(terrain.finish_room))
	# Blast scars: wallpaper squares caught in an explosion darken 90%
	# toward the carved-earth backdrop color — the same extra-dark brown
	# you see where the ground has been blown away.
	var scar := Color("2b1a0c")
	scar.a = 0.9
	for k in _scorch:
		var cell: Vector2i = _scorch[k]
		draw_rect(Rect2(cell.x * TILE, cell.y * TILE, TILE, TILE), scar)


## Mark every wallpaper square inside the blast circle as scorched.
func _on_carved(world_pos: Vector2, radius: float) -> void:
	var rects: Array[Rect2i] = []
	for rn in terrain.bunker_rooms:
		rects.append(terrain.bunker_rooms[rn])
	if terrain.finish_room.size.x > 0:
		rects.append(terrain.finish_room)
	var c := Vector2i(int(world_pos.x / TILE), int(world_pos.y / TILE))
	var r := ceili(radius / TILE)
	for y in range(c.y - r, c.y + r + 1):
		for x in range(c.x - r, c.x + r + 1):
			var center := Vector2(x * TILE + TILE * 0.5, y * TILE + TILE * 0.5)
			if center.distance_to(world_pos) > radius:
				continue
			for rc in rects:
				if rc.has_point(Vector2i(x, y)):
					_scorch[y * 1000 + x] = Vector2i(x, y)
					break
	queue_redraw()


# --- room painters -----------------------------------------------------------

## Rough timber cladding for the stair landing.
func _draw_planks(r: Rect2) -> void:
	draw_rect(r, Color("54381f"))
	var x := r.position.x
	while x < r.end.x:
		draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), Color("46301b"), 1.5)
		x += 11.0
	draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 3.0), Color("3c2917"))


func _draw_kitchen(r: Rect2) -> void:
	# Warm striped wallpaper.
	draw_rect(r, Color("e4d3ac"))
	var x := r.position.x + 4.0
	while x < r.end.x:
		draw_rect(Rect2(x, r.position.y, 3.0, r.size.y), Color("d8c298"))
		x += 10.0
	_wainscot(r, Color("8a5a2b"))
	# Shelf with jars and plates.
	var sy := r.position.y + 22.0
	var sx := r.position.x + 10.0
	draw_rect(Rect2(sx, sy, 44.0, 3.0), Color("6d4423"))
	draw_rect(Rect2(sx + 3, sy - 9, 6, 9), Color("b0483a"))     # jam jar
	draw_rect(Rect2(sx + 3, sy - 11, 6, 2.5), Color("caa64a"))  # lid
	draw_rect(Rect2(sx + 12, sy - 8, 6, 8), Color("5f8f4e"))    # pickle jar
	draw_rect(Rect2(sx + 12, sy - 10, 6, 2.5), Color("caa64a"))
	draw_circle(Vector2(sx + 28, sy - 4), 4.5, Color("f2ede2")) # plates
	draw_circle(Vector2(sx + 36, sy - 4), 4.5, Color("e7e0d2"))
	# Cupboard.
	var cx := r.end.x - 30.0
	var cy := r.position.y + 12.0
	draw_rect(Rect2(cx - 1, cy - 1, 24, 30), Color("4a3118"))
	draw_rect(Rect2(cx, cy, 22, 28), Color("7c5128"))
	draw_line(Vector2(cx + 11, cy + 1), Vector2(cx + 11, cy + 27), Color("4a3118"), 1.5)
	draw_circle(Vector2(cx + 8, cy + 14), 1.4, Color("d8c298"))
	draw_circle(Vector2(cx + 14, cy + 14), 1.4, Color("d8c298"))
	# Hanging pan.
	draw_line(Vector2(sx + 54, r.position.y + 6), Vector2(sx + 54, r.position.y + 12),
		Color("3c2917"), 1.5)
	draw_circle(Vector2(sx + 54, r.position.y + 17), 5.0, Color("3a3a40"))
	draw_circle(Vector2(sx + 54, r.position.y + 16), 3.4, Color("55555e"))


func _draw_bedroom(r: Rect2) -> void:
	# Dusty blue wallpaper with a dot grid.
	draw_rect(r, Color("aebccd"))
	var y := r.position.y + 6.0
	while y < r.end.y - 8.0:
		var x2 := r.position.x + 6.0
		while x2 < r.end.x:
			draw_circle(Vector2(x2, y), 1.2, Color("9aabbf"))
			x2 += 12.0
		y += 12.0
	_wainscot(r, Color("6d5540"))
	# Framed landscape painting: hills and a sun.
	var px := r.position.x + 14.0
	var py := r.position.y + 12.0
	draw_rect(Rect2(px - 2, py - 2, 32, 24), Color("5a3d22"))
	draw_rect(Rect2(px, py, 28, 20), Color("bfe0f2"))
	draw_circle(Vector2(px + 21, py + 6), 3.5, Color("ffd54f"))
	draw_circle(Vector2(px + 8, py + 20), 9.0, Color("7cb56b"))
	draw_circle(Vector2(px + 21, py + 21), 10.0, Color("639a54"))
	# Book shelf.
	var sx := r.end.x - 46.0
	var sy := r.position.y + 30.0
	draw_rect(Rect2(sx, sy, 36.0, 3.0), Color("6d4423"))
	var spines: Array[Color] = [Color("b0483a"), Color("3f6fae"), Color("5f8f4e"),
		Color("caa64a"), Color("7a4b8f")]
	for i in spines.size():
		draw_rect(Rect2(sx + 3 + i * 6, sy - 10, 5, 10), spines[i])
	# Rug on the floor.
	draw_rect(Rect2(r.position.x + 20, r.end.y - 4, r.size.x - 52, 4), Color("a04b40"))
	draw_rect(Rect2(r.position.x + 24, r.end.y - 4, r.size.x - 60, 4), Color("c76b58"))


func _draw_bathroom(r: Rect2) -> void:
	# Aqua ceramic tile.
	draw_rect(r, Color("dcebec"))
	var x := r.position.x
	while x <= r.end.x:
		draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), Color("b8d2d4"), 1.0)
		x += 8.0
	var y := r.position.y
	while y <= r.end.y:
		draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), Color("b8d2d4"), 1.0)
		y += 8.0
	# Mirror.
	var mx := r.position.x + 12.0
	var my := r.position.y + 10.0
	draw_rect(Rect2(mx - 1.5, my - 1.5, 15, 19), Color("8a8f96"))
	draw_rect(Rect2(mx, my, 12, 16), Color("cfe6f5"))
	draw_line(Vector2(mx + 2, my + 12), Vector2(mx + 9, my + 3), Color("eef7fd"), 1.5)
	# Towel on a hook.
	var tx := r.end.x - 18.0
	draw_circle(Vector2(tx + 3, r.position.y + 12), 1.5, Color("6d4423"))
	draw_rect(Rect2(tx, r.position.y + 13, 7, 14), Color("c25b50"))
	draw_rect(Rect2(tx, r.position.y + 18, 7, 2), Color("a84a41"))


## The arsenal: cold poured-concrete walls with hazard striping and a
## stenciled ammo crate — the props layer racks the actual guns on top.
func _draw_arsenal(r: Rect2) -> void:
	draw_rect(r, Color("6a6f76"))
	# Concrete pour seams.
	var y := r.position.y + 12.0
	while y < r.end.y:
		draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), Color("5b6067"), 1.2)
		y += 14.0
	# Yellow/black hazard chevrons along the top edge.
	var x := r.position.x
	var k := 0
	while x < r.end.x:
		var w := minf(8.0, r.end.x - x)
		draw_rect(Rect2(x, r.position.y, w, 5.0),
			Color("e0b73c") if k % 2 == 0 else Color("2c2c30"))
		x += 8.0
		k += 1
	# Stenciled ammo crate against the back wall.
	var bx := r.position.x + 8.0
	var by := r.end.y - 16.0
	draw_rect(Rect2(bx - 1, by - 1, 22, 14), Color("3e4a33"))
	draw_rect(Rect2(bx, by, 20, 12), Color("55643f"))
	draw_line(Vector2(bx, by + 4), Vector2(bx + 20, by + 4), Color("3e4a33"), 1.2)
	draw_rect(Rect2(bx + 7, by + 6, 6, 3), Color("c9a227"))


## Podium step rects for the finish hall, world px, in place order
## [1st, 2nd, 3rd]. Shared with the ceremony so the celebrating winners
## stand exactly on the drawn steps.
static func podium_steps(r: Rect2) -> Array[Rect2]:
	var cx := r.get_center().x
	var base := r.end.y
	return [Rect2(cx - 12, base - 36, 24, 36),
		Rect2(cx - 38, base - 24, 24, 24),
		Rect2(cx + 14, base - 12, 24, 12)]


## The finish hall: pale cyan walls inside a black-and-white checkered
## border, with a big gold/silver/bronze podium on the floor.
func _draw_finish(r: Rect2) -> void:
	draw_rect(r, Color("c9ecec"))
	# Checkered border ring, one 8px checker band thick, all four edges.
	var sq := 8.0
	var cols := int(round(r.size.x / sq))
	var rows := int(round(r.size.y / sq))
	for col in cols:
		for row in rows:
			if col > 0 and col < cols - 1 and row > 0 and row < rows - 1:
				continue
			var c := Color(0.94, 0.94, 0.94) if (row + col) % 2 == 0 \
				else Color(0.1, 0.1, 0.12)
			draw_rect(Rect2(r.position.x + col * sq, r.position.y + row * sq, sq, sq), c)
	# The podium: 1st center, 2nd left, 3rd right, with place numbers.
	var steps := podium_steps(r)
	var cols2: Array[Color] = [Color("c9a227"), Color("b7bec9"), Color("a06a3d")]
	for i in steps.size():
		var s: Rect2 = steps[i]
		draw_rect(Rect2(s.position.x - 1, s.position.y - 1, s.size.x + 2, s.size.y + 1),
			Color(0.1, 0.1, 0.12))
		draw_rect(s, cols2[i])
		draw_rect(Rect2(s.position.x, s.position.y, s.size.x, 3.0),
			cols2[i].lightened(0.25))


## Wooden trim along the bottom of a papered wall.
func _wainscot(r: Rect2, col: Color) -> void:
	draw_rect(Rect2(r.position.x, r.end.y - 8.0, r.size.x, 8.0), col)
	draw_rect(Rect2(r.position.x, r.end.y - 8.0, r.size.x, 1.5), col.darkened(0.3))
