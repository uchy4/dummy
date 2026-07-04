class_name Terrain
extends TileMapLayer
## Destructible tile terrain. Builds its own TileSet at runtime, generates the
## level (flat grass surface, shelter, plugged cavern systems, finish hall) and
## lets explosions carve circular holes out of anything that isn't bedrock.

const TILE := 16
const W := 100          # the "100 feet wide" strip: 1 cell ~ 1 foot
const H := 120
const SURFACE_ROW := 20 # first solid row; everything above is sky

const CRUST_ROWS := 10  # solid rows under the grass: only bombs open the way down
const SHELTER_HALF_W := 7
const SHELTER_TOP := SURFACE_ROW + CRUST_ROWS  # buried just below the crust
const SHELTER_H := 7
const FINISH_TOP := 108 # finish hall rows 108..115, bedrock floor at 116
const PLUG_ROWS := 4    # every tunnel stops this many rows short: the dead end

enum Cell { EMPTY, DIRT, BEDROCK, GRASS }
enum Tile { GRASS, DIRT, DIRT_DARK, BEDROCK }

## Emitted for every blast so web clients can mirror the destruction.
signal carved(world_pos: Vector2, radius: float)

var rng := RandomNumberGenerator.new()
var room_count := 0
var chest_cells: Array[Vector2i] = []  # dead-end pockets where chests may spawn

var _grid := PackedByteArray()
var _src_id := 0


func _ready() -> void:
	rng.randomize()
	_build_tileset()
	_generate()
	_paint_all()


# ---------------------------------------------------------------- tileset ---

func _build_tileset() -> void:
	var img := Image.create(TILE * 4, TILE, false, Image.FORMAT_RGBA8)
	_fill_tile(img, Tile.DIRT, Color("7a5230"), Color("5e3d22"), 0.16)
	_fill_tile(img, Tile.DIRT_DARK, Color("5c3d22"), Color("452c17"), 0.2)
	_fill_tile(img, Tile.BEDROCK, Color("4b4b55"), Color("35353d"), 0.22)
	# Grass: dirt base with a green top edge.
	_fill_tile(img, Tile.GRASS, Color("7a5230"), Color("5e3d22"), 0.16)
	for y in 5:
		for x in TILE:
			var g := Color("4caf50").lerp(Color("2e7d32"), rng.randf() * 0.8)
			img.set_pixel(Tile.GRASS * TILE + x, y, g)

	var src := TileSetAtlasSource.new()
	src.texture = ImageTexture.create_from_image(img)
	src.texture_region_size = Vector2i(TILE, TILE)

	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(0, 1)
	_src_id = ts.add_source(src)

	var h := TILE / 2.0
	var square := PackedVector2Array([
		Vector2(-h, -h), Vector2(h, -h), Vector2(h, h), Vector2(-h, h),
	])
	for i in 4:
		src.create_tile(Vector2i(i, 0))
		var td := src.get_tile_data(Vector2i(i, 0), 0)
		td.add_collision_polygon(0)
		td.set_collision_polygon_points(0, 0, square)

	tile_set = ts


func _fill_tile(img: Image, index: int, base: Color, speck: Color, chance: float) -> void:
	for y in TILE:
		for x in TILE:
			var c := speck if rng.randf() < chance else base
			img.set_pixel(index * TILE + x, y, c)


# ------------------------------------------------------------- generation ---

func _generate() -> void:
	_grid.resize(W * H)
	_grid.fill(Cell.EMPTY)

	for y in range(SURFACE_ROW, H):
		for x in W:
			_gset(x, y, Cell.DIRT)
	# Indestructible frame: side walls and floor. The side walls rise above
	# the surface so players can't hop off the edge of the map.
	for y in range(SURFACE_ROW - 6, H):
		for x in [0, 1, W - 2, W - 1]:
			_gset(x, y, Cell.BEDROCK)
	for y in range(H - 4, H):
		for x in W:
			_gset(x, y, Cell.BEDROCK)

	var cx := W / 2
	# The shelter is buried under the crust — bombs must excavate the way in.
	_carve_rect(Rect2i(cx - SHELTER_HALF_W, SHELTER_TOP, SHELTER_HALF_W * 2, SHELTER_H))

	# Cavern bands going down. Every room is reached by a tunnel from above that
	# stops PLUG_ROWS short — a dead end that needs a bomb to open.
	var bands := [[41, 52], [58, 70], [76, 88], [92, 104]]
	var all_rooms: Array[Dictionary] = []
	var prev_centers: Array[Vector2i] = [Vector2i(cx, SHELTER_TOP + 4)]
	for band: Array in bands:
		var centers: Array[Vector2i] = []
		for i in rng.randi_range(2, 3):
			var room := {
				"c": Vector2i(rng.randi_range(10, W - 10), rng.randi_range(band[0] + 4, band[1] - 4)),
				"rw": rng.randi_range(5, 9),
				"rh": rng.randi_range(3, 5),
			}
			_carve_ellipse(room.c, room.rw, room.rh)
			all_rooms.append(room)
			centers.append(room.c)
			room_count += 1
			var from := _nearest(prev_centers, room.c)
			_carve_tunnel(from, Vector2i(room.c.x, room.c.y - room.rh))
		prev_centers = centers

	# Finish hall along the bottom; tunnels into it are plugged too.
	_carve_rect(Rect2i(3, FINISH_TOP, W - 6, H - 4 - FINISH_TOP))
	for c in prev_centers:
		_carve_tunnel(c, Vector2i(c.x, FINISH_TOP))

	# A couple of buried shafts away from the shelter — useful drops once the
	# crust above them is blown open, but they start below it and end in dirt.
	for i in 2:
		var sx := rng.randi_range(8, W - 8)
		if absi(sx - cx) < 14:
			sx = cx + 20 * (1 if rng.randf() < 0.5 else -1)
		_carve_rect(Rect2i(sx - 1, SURFACE_ROW + CRUST_ROWS, 3, rng.randi_range(20, 28)))

	# Decoy side tunnels that just stop in the dirt.
	for i in 4:
		var room: Dictionary = all_rooms.pick_random()
		var p := Vector2(room.c)
		var dir := 1.0 if rng.randf() < 0.5 else -1.0
		for step in rng.randi_range(7, 13):
			p.x = clampf(p.x + dir, 4, W - 5)
			p.y = clampf(p.y + rng.randf_range(-0.4, 0.8), SURFACE_ROW + CRUST_ROWS + 1, H - 6)
			_carve_disk(Vector2i(p), 1)
		chest_cells.append(Vector2i(p))

	# Grass on every exposed surface cell.
	for x in W:
		if _gget(x, SURFACE_ROW) == Cell.DIRT and _gget(x, SURFACE_ROW - 1) == Cell.EMPTY:
			_gset(x, SURFACE_ROW, Cell.GRASS)


func _carve_tunnel(from: Vector2i, to: Vector2i) -> void:
	var p := Vector2(from)
	var stop_y := to.y - PLUG_ROWS
	while p.y < stop_y:
		_carve_disk(Vector2i(p), 1)
		p.y += 1.0
		var dx := signf(to.x - p.x)
		p.x = clampf(p.x + clampf(dx + rng.randf_range(-0.8, 0.8), -1.0, 1.0), 4, W - 5)
	# Widen the dead end into a pocket a bomb can sit in.
	_carve_disk(Vector2i(p), 2)
	chest_cells.append(Vector2i(p))


func _carve_rect(r: Rect2i) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			_carve_cell(x, y)


func _carve_ellipse(c: Vector2i, rw: int, rh: int) -> void:
	for y in range(c.y - rh, c.y + rh + 1):
		for x in range(c.x - rw, c.x + rw + 1):
			var nx := float(x - c.x) / rw
			var ny := float(y - c.y) / rh
			if nx * nx + ny * ny <= 1.0:
				_carve_cell(x, y)


func _carve_disk(c: Vector2i, r: int) -> void:
	for y in range(c.y - r, c.y + r + 1):
		for x in range(c.x - r, c.x + r + 1):
			if Vector2i(x, y).distance_squared_to(c) <= r * r + 1:
				_carve_cell(x, y)


func _carve_cell(x: int, y: int) -> void:
	# Generation never touches the sky or the crust — the top CRUST_ROWS of
	# ground stay solid until bombs excavate them at runtime.
	if y < SURFACE_ROW + CRUST_ROWS:
		return
	if _gget(x, y) != Cell.BEDROCK:
		_gset(x, y, Cell.EMPTY)


func _nearest(points: Array[Vector2i], to: Vector2i) -> Vector2i:
	var best := points[0]
	for p in points:
		if p.distance_squared_to(to) < best.distance_squared_to(to):
			best = p
	return best


func _paint_all() -> void:
	for y in H:
		for x in W:
			var t := -1
			match _gget(x, y):
				Cell.GRASS:
					t = Tile.GRASS
				Cell.BEDROCK:
					t = Tile.BEDROCK
				Cell.DIRT:
					var dark_chance := remap(float(y), SURFACE_ROW, H, 0.1, 0.55)
					t = Tile.DIRT_DARK if rng.randf() < dark_chance else Tile.DIRT
			if t >= 0:
				set_cell(Vector2i(x, y), _src_id, Vector2i(t, 0))


# ------------------------------------------------------------- destruction ---

## The whole grid as one digit per cell (Cell enum values), row-major —
## the initial terrain payload for web clients.
func grid_string() -> String:
	var out := PackedByteArray()
	out.resize(_grid.size())
	for i in _grid.size():
		out[i] = 48 + _grid[i]
	return out.get_string_from_ascii()


## Blow a circular hole (world-space position and radius). Bedrock survives.
func carve_circle(world_pos: Vector2, radius: float) -> void:
	carved.emit(world_pos, radius)
	var c := local_to_map(to_local(world_pos))
	var r := ceili(radius / TILE)
	for y in range(maxi(c.y - r, 0), mini(c.y + r + 1, H)):
		for x in range(maxi(c.x - r, 0), mini(c.x + r + 1, W)):
			if _gget(x, y) in [Cell.EMPTY, Cell.BEDROCK]:
				continue
			if map_to_local(Vector2i(x, y)).distance_to(to_local(world_pos)) <= radius:
				_gset(x, y, Cell.EMPTY)
				erase_cell(Vector2i(x, y))


# ----------------------------------------------------------------- queries ---

func world_rect() -> Rect2:
	return Rect2(0, 0, W * TILE, H * TILE)


func surface_y() -> float:
	return SURFACE_ROW * TILE


func surface_spawns(n: int) -> Array[Vector2]:
	var cx := W / 2
	var cols := [cx - 6, cx - 3, cx + 3, cx + 6, cx - 9, cx + 9]
	var out: Array[Vector2] = []
	for i in n:
		out.append(Vector2((cols[i] + 0.5) * TILE, SURFACE_ROW * TILE - 20.0))
	return out


func shelter_spawn() -> Vector2:
	return Vector2((W / 2 + 0.5) * TILE, (SHELTER_TOP + SHELTER_H) * TILE - 16.0)


## A rare few of the dead-end pockets get an armor chest, resting on the
## pocket floor.
func chest_positions() -> Array[Vector2]:
	var cells := chest_cells.duplicate()
	cells.shuffle()
	var count := rng.randi_range(3, 5)
	var out: Array[Vector2] = []
	for c in cells:
		if out.size() >= count:
			break
		var y := c.y
		while y < H - 2 and _gget(c.x, y + 1) == Cell.EMPTY:
			y += 1
		out.append(Vector2((c.x + 0.5) * TILE, (y + 1) * TILE - 8.0))
	return out


## The gold strip resting on the bedrock floor of the finish hall.
func finish_line_rect() -> Rect2:
	var floor_top := (H - 4) * TILE
	return Rect2(3 * TILE, floor_top - 14, (W - 6) * TILE, 14)


# -------------------------------------------------------------------- grid ---

func _gget(x: int, y: int) -> int:
	if x < 0 or x >= W or y < 0 or y >= H:
		return Cell.BEDROCK
	return _grid[y * W + x]


func _gset(x: int, y: int, v: int) -> void:
	if x >= 0 and x < W and y >= 0 and y < H:
		_grid[y * W + x] = v
