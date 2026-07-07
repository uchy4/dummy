class_name RoomDecor
extends Node2D
## Cozy painted backgrounds for the bunker rooms — wallpaper, paintings,
## shelves, cupboards, bathroom tile, straw in the pens — so the rooms read
## as lived-in spaces instead of black holes. Pure backdrop: drawn beneath
## terrain, furniture, and players (z_index -5), no collision.

const TILE := 16

var terrain: Terrain

var _straw: Array[Rect2] = []  # precomputed so it doesn't flicker


func _ready() -> void:
	z_index = -5
	if terrain == null or terrain.bunker_rooms.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 7  # deterministic scatter
	for pen_name: String in ["chicken_pen", "pig_pen"]:
		if not terrain.bunker_rooms.has(pen_name):
			continue
		var r := _px(terrain.bunker_rooms[pen_name])
		for i in 14:
			_straw.append(Rect2(
				r.position.x + rng.randf() * (r.size.x - 8.0),
				r.end.y - 5.0 - rng.randf() * 6.0,
				rng.randf_range(4.0, 8.0), 1.5))
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
	if rooms.has("chicken_pen"):
		_draw_pen(_px(rooms["chicken_pen"]))
	if rooms.has("pig_pen"):
		_draw_pen(_px(rooms["pig_pen"]))
	for s in _straw:
		draw_rect(s, Color(0.85, 0.72, 0.35))
	if terrain.finish_room.size.x > 0:
		_draw_finish(_px(terrain.finish_room))


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


## Pens: warm barn wall strewn with hay, plus support beams.
func _draw_pen(r: Rect2) -> void:
	draw_rect(r, Color("6b4a26"))
	var yy := r.position.y + 5.0
	var row := 0
	while yy < r.end.y - 3.0:
		var xx := r.position.x + (4.0 if row % 2 == 0 else 10.0)
		while xx < r.end.x - 7.0:
			draw_line(Vector2(xx, yy + 3), Vector2(xx + 6, yy),
				Color(0.9, 0.77, 0.4, 0.85), 1.4)
			draw_line(Vector2(xx + 2, yy), Vector2(xx + 7, yy + 3),
				Color(0.82, 0.68, 0.32, 0.65), 1.2)
			xx += 12.0
		yy += 9.0
		row += 1
	draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 4.0), Color("54381f"))
	draw_rect(Rect2(r.position.x + r.size.x * 0.5 - 2, r.position.y, 4.0, r.size.y),
		Color("4a3118"))


## The finish chamber: black-and-white checkered wallpaper with a podium.
func _draw_finish(r: Rect2) -> void:
	var sq := 8.0
	var rows := int(ceil(r.size.y / sq))
	var cols := int(ceil(r.size.x / sq))
	for row in rows:
		for col in cols:
			var c := Color(0.92, 0.92, 0.92) if (row + col) % 2 == 0 \
				else Color(0.08, 0.08, 0.08)
			draw_rect(Rect2(r.position.x + col * sq, r.position.y + row * sq,
				minf(sq, r.end.x - (r.position.x + col * sq)),
				minf(sq, r.end.y - (r.position.y + row * sq))), c)
	# Gold / silver / bronze podium steps on the floor.
	var cx := r.get_center().x
	var base := r.end.y
	draw_rect(Rect2(cx - 22, base - 11, 14, 11), Color("b7bec9"))
	draw_rect(Rect2(cx - 7, base - 17, 14, 17), Color("c9a227"))
	draw_rect(Rect2(cx + 8, base - 7, 14, 7), Color("a06a3d"))


## Wooden trim along the bottom of a papered wall.
func _wainscot(r: Rect2, col: Color) -> void:
	draw_rect(Rect2(r.position.x, r.end.y - 8.0, r.size.x, 8.0), col)
	draw_rect(Rect2(r.position.x, r.end.y - 8.0, r.size.x, 1.5), col.darkened(0.3))
