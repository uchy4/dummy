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

enum Cell { EMPTY, DIRT, BEDROCK, GRASS, WATER, CLAY, STONE, DEEP }
enum Tile { GRASS, DIRT, DIRT_DARK, BEDROCK, WATER, CLAY, STONE, DEEP, WATER_TOP,
	CLAY_DARK, STONE_DARK, DEEP_DARK }

## One solid translucent water color — surface cells use the partial tile.
const WATER_COLOR := Color(0.24, 0.5, 0.88, 0.55)

## Strata: the ground changes character with depth — dirt, then clay, then
## stone, then deep slate, down to the bedrock frame.
const CLAY_TOP := 40
const STONE_TOP := 65
const DEEP_TOP := 90

## Emitted for every blast so web clients can mirror the destruction.
signal carved(world_pos: Vector2, radius: float)

## Emitted each water tick: `moves` are traveling drops ([[from, to]], with
## to = -1 when a looping drop evaporates), `eq` are settled-pool level
## shifts. Clients replay both to keep their grids identical.
signal water_moved(moves: Array, eq: Array)

const WATER_TICK := 0.1     ## seconds between fluid steps
const WATER_MAX_MOVES := 600

var rng := RandomNumberGenerator.new()
var room_count := 0
var chest_cells: Array[Vector2i] = []  # dead-end pockets where chests may spawn

## Bunker complex under the surface crust: room name -> Rect2i (cells).
## Keys: stairs, kitchen, bedroom, bathroom, chicken_pen, pig_pen.
## Layout is randomized every match (room order and widths, min 5 wide).
var bunker_rooms := {}
## Surface cell where the outhouse (stair entrance) stands.
var outhouse_cell := Vector2i.ZERO
## The 5x5 checkered finish chamber at the bottom center.
var finish_room := Rect2i()
## The hand pump beside the outhouse and the reservoir its pipe feeds from.
var pump_cell := Vector2i.ZERO
var reservoir_rect := Rect2i()
## Random generation (caves/shafts/tunnels) never carves inside this zone —
## the bunker must not give way to pits.
var _gen_guard := Rect2i()

var _grid := PackedByteArray()
var _src_id := 0
var _water_acc := 0.0
var _flow_dir := {}   ## water cell index -> current flow heading (-1 / +1)
var _transit := {}    ## cells in flight this tick: drawn as droplets, not tiles
var _drop_trail := {} ## per-drop visited cells: revisiting one = loop = evaporate


## Client mode: no generation — the grid arrives from the host over the
## network via load_from_string() and carve events.
var client_mode := false


func _ready() -> void:
	add_to_group(&"terrain")
	rng.randomize()
	_build_tileset()
	if client_mode:
		return
	_generate()
	_paint_all()


## Fill the grid from the wire format (one digit per cell, row-major).
func load_from_string(s: String) -> void:
	_grid.resize(W * H)
	_grid.fill(Cell.EMPTY)
	for i in mini(s.length(), _grid.size()):
		_grid[i] = s.unicode_at(i) - 48
	clear()
	_paint_all()


# ---------------------------------------------------------------- tileset ---

func _build_tileset() -> void:
	var img := Image.create(TILE * 12, TILE, false, Image.FORMAT_RGBA8)
	_fill_tile(img, Tile.DIRT, Color("7a5230"), Color("5e3d22"), 0.16)
	_fill_tile(img, Tile.DIRT_DARK, Color("5c3d22"), Color("452c17"), 0.2)
	_fill_tile(img, Tile.BEDROCK, Color("4b4b55"), Color("35353d"), 0.22)
	# Every stratum is dual-toned like the dirt layer: a light and a dark
	# block variant mixed at paint time.
	_fill_tile(img, Tile.CLAY, Color("a5623b"), Color("874e2e"), 0.2)
	_fill_tile(img, Tile.CLAY_DARK, Color("8a4f2e"), Color("6f3f24"), 0.22)
	_fill_tile(img, Tile.STONE, Color("6e7681"), Color("59616b"), 0.24)
	_fill_tile(img, Tile.STONE_DARK, Color("575f6a"), Color("454c56"), 0.24)
	_fill_tile(img, Tile.DEEP, Color("553f4d"), Color("42313c"), 0.24)
	_fill_tile(img, Tile.DEEP_DARK, Color("41303b"), Color("32252e"), 0.26)
	# Grass: dirt base with a green top edge.
	_fill_tile(img, Tile.GRASS, Color("7a5230"), Color("5e3d22"), 0.16)
	for y in 5:
		for x in TILE:
			var g := Color("4caf50").lerp(Color("2e7d32"), rng.randf() * 0.8)
			img.set_pixel(Tile.GRASS * TILE + x, y, g)
	# Water: one flat translucent color. Full tile for submerged cells,
	# WATER_TOP (top 5px clear) for the surface so pools have a waterline.
	for y in TILE:
		for x in TILE:
			img.set_pixel(Tile.WATER * TILE + x, y, WATER_COLOR)
	for y in range(5, TILE):
		for x in TILE:
			img.set_pixel(Tile.WATER_TOP * TILE + x, y, WATER_COLOR)

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
	for i in 12:
		src.create_tile(Vector2i(i, 0))
		if i == Tile.WATER or i == Tile.WATER_TOP:
			continue  # water is swim-through: no collision polygon
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
			_gset(x, y, _stratum_at(y))
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

	_build_bunker()

	# Cavern bands going down. Every room is reached by a tunnel from above that
	# stops PLUG_ROWS short — a dead end that needs a bomb to open.
	var bands := [[41, 52], [58, 70], [76, 88], [92, 104]]
	var all_rooms: Array[Dictionary] = []
	var prev_centers: Array[Vector2i] = [Vector2i(cx, SHELTER_TOP + 4)]
	for band: Array in bands:
		var centers: Array[Vector2i] = []
		for i in rng.randi_range(2, 3):
			# Wide, flat caverns: caves (and their pools) spread horizontally.
			var room := {
				"c": Vector2i(rng.randi_range(14, W - 14), rng.randi_range(band[0] + 3, band[1] - 3)),
				"rw": rng.randi_range(9, 16),
				"rh": rng.randi_range(2, 3),
			}
			_carve_ellipse(room.c, room.rw, room.rh)
			all_rooms.append(room)
			centers.append(room.c)
			room_count += 1
			var from := _nearest(prev_centers, room.c)
			_carve_tunnel(from, Vector2i(room.c.x, room.c.y - room.rh))
		prev_centers = centers

	# Underground aquifers: a couple of the cavern rooms keep a pool of
	# groundwater in their lower half. Players bob on it; bombs sink slowly.
	all_rooms.shuffle()
	for i in mini(2, all_rooms.size()):
		var room: Dictionary = all_rooms[i]
		var c: Vector2i = room.c
		var rw: int = room.rw
		var rh: int = room.rh
		for y in range(c.y + 1, c.y + rh + 1):
			for x in range(c.x - rw, c.x + rw + 1):
				var nx := float(x - c.x) / rw
				var ny := float(y - c.y) / rh
				if nx * nx + ny * ny <= 1.0 and _gget(x, y) == Cell.EMPTY:
					_gset(x, y, Cell.WATER)

	# The finish chamber at the bottom center; tunnels toward it are
	# plugged like everything else.
	_build_finish_room()
	for c in prev_centers:
		_carve_tunnel(c, Vector2i(W / 2, finish_room.position.y))

	# A couple of buried shafts away from the shelter — useful drops once the
	# crust above them is blown open, but they start below it and end in dirt.
	for i in 2:
		var sx := rng.randi_range(24, W - 8)  # min 24: never through the pens
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


## The homestead: an outhouse on the surface hiding a staircase down into a
## furnished bunker, with animal pens one level below. Layout is random
## every match: room order shuffles and widths vary (always >= 5 cells).
## Every divider has a doorway — nothing is sealed off. Carved directly so
## the crust guard doesn't apply.
func _build_bunker() -> void:
	bunker_rooms = {}
	var top := 24
	var room_h := 6
	# The homestead spawns on a random side of the map with jitter, so the
	# outhouse is somewhere new every match (rng is seeded per run).
	var bx := rng.randi_range(3, 8)
	if rng.randf() < 0.5:
		bx = rng.randi_range(58, 61)
	outhouse_cell = Vector2i(bx + 1, SURFACE_ROW)

	# Stair landing first (the staircase must land in it), then the living
	# rooms in a random order with random widths.
	var stairs_w := rng.randi_range(7, 8)
	bunker_rooms["stairs"] = Rect2i(bx, top, stairs_w, room_h)
	var cur_x := bx + stairs_w + 1
	var order: Array[String] = ["kitchen", "bedroom", "bathroom"]
	order.shuffle()
	for room_name in order:
		var w := rng.randi_range(5, 8)
		bunker_rooms[room_name] = Rect2i(cur_x, top, w, room_h)
		cur_x += w + 1

	# Pens one level below, under the near half of the bunker.
	var pen_top := top + 7
	var pen_x := maxi(bx - rng.randi_range(0, 2), 3)
	if bx > 40:
		pen_x = bx + 1  # right-side homestead: pens stay clear of the shelter
	var pens: Array[String] = ["chicken_pen", "pig_pen"]
	pens.shuffle()
	var pw1 := rng.randi_range(5, 8)
	var pw2 := rng.randi_range(5, 8)
	bunker_rooms[pens[0]] = Rect2i(pen_x, pen_top, pw1, room_h)
	bunker_rooms[pens[1]] = Rect2i(pen_x + pw1 + 1, pen_top, pw2, room_h)

	# Stone framing: solid ground within one cell of a room becomes stone,
	# so the bunker reads as built, not dug. Never fills carved space.
	for room_name in bunker_rooms:
		var r: Rect2i = bunker_rooms[room_name]
		var g := r.grow(1)
		for y in range(g.position.y, g.end.y):
			for x in range(g.position.x, g.end.x):
				var cv := _gget(x, y)
				if cv != Cell.BEDROCK and cv != Cell.EMPTY and cv != Cell.WATER:
					_gset(x, y, Cell.STONE)
	# Carve the room interiors.
	for room_name in bunker_rooms:
		var r: Rect2i = bunker_rooms[room_name]
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				if _gget(x, y) != Cell.BEDROCK:
					_gset(x, y, Cell.EMPTY)

	# Doorways through every INTERIOR divider (not the outer wall): 3 tall
	# at floor level, so nothing is ever sealed off.
	var walls: Array[int] = [bx + stairs_w]
	for i in order.size() - 1:
		var r: Rect2i = bunker_rooms[order[i]]
		walls.append(r.end.x)
	for wall_x in walls:
		for y in range(top + 3, top + room_h):
			if _gget(wall_x, y) != Cell.BEDROCK:
				_gset(wall_x, y, Cell.EMPTY)

	# Staircase from the outhouse down to the landing (1-cell steps).
	for step in 6:
		var sx := outhouse_cell.x + step
		for dy in 3:
			_gset(sx, SURFACE_ROW + step + dy, Cell.EMPTY)

	# Hole in the landing floor down into the pens, plus climb-out steps at
	# the pens' right edge (players can jump them, critters can't).
	var stairs_r: Rect2i = bunker_rooms["stairs"]
	var pen2_r: Rect2i = bunker_rooms[pens[1]]
	var hole_x := clampi(stairs_r.position.x + 2, pen_x + 1, pen2_r.end.x - 3)
	for hx in range(hole_x, hole_x + 2):
		_gset(hx, top + room_h, Cell.EMPTY)
	var step_x := pen2_r.end.x - 1
	_gset(step_x, pen_top + 4, Cell.STONE)
	_gset(step_x, pen_top + 5, Cell.STONE)
	_gset(step_x - 1, pen_top + 5, Cell.STONE)
	# Fence wall between the pens: hop-over gap at the top.
	var fence_x := pen_x + pw1
	for y in range(pen_top + 2, pen_top + room_h):
		_gset(fence_x, y, Cell.STONE)

	# Protect the whole complex from random generation: caves, shafts and
	# tunnels must never open pits into (or under) the bunker.
	var gmin := Vector2i(1000000, SURFACE_ROW)
	var gmax := Vector2i(-1000000, 0)
	for guard_name in bunker_rooms:
		var gr: Rect2i = bunker_rooms[guard_name]
		gmin.x = mini(gmin.x, gr.position.x)
		gmax.x = maxi(gmax.x, gr.end.x)
		gmax.y = maxi(gmax.y, gr.end.y)
	_gen_guard = Rect2i(gmin.x - 2, SURFACE_ROW,
		(gmax.x - gmin.x) + 4, (gmax.y - SURFACE_ROW) + 3)

	# The well: a hand pump on the far side of the outhouse, a pipe straight
	# down (drawn by the props layer), and a wide underground reservoir.
	var px := maxi(outhouse_cell.x - 4, 2)
	pump_cell = Vector2i(px, SURFACE_ROW)
	reservoir_rect = Rect2i(maxi(px - 6, 2), 46, 13, 3)
	for y in range(reservoir_rect.position.y, reservoir_rect.end.y):
		for x in range(reservoir_rect.position.x, reservoir_rect.end.x):
			if _gget(x, y) != Cell.BEDROCK:
				_gset(x, y, Cell.WATER)
	# The guard also shields the well system from random generation.
	_gen_guard = _gen_guard.merge(reservoir_rect.grow(2))


## The finish chamber: a 5x5 checkered room at the bottom center, floored
## by bedrock. Reaching it IS winning the depth race.
func _build_finish_room() -> void:
	var cx := W / 2
	finish_room = Rect2i(cx - 2, H - 9, 5, 5)
	for y in range(finish_room.position.y, finish_room.end.y):
		for x in range(finish_room.position.x, finish_room.end.x):
			if _gget(x, y) != Cell.BEDROCK:
				_gset(x, y, Cell.EMPTY)


## Which stratum a row belongs to, with 5 rows of dithered blending at each
## boundary (10/30/50/70/90% of the lower material) instead of hard lines.
func _stratum_at(y: int) -> int:
	var bands := [
		[CLAY_TOP, Cell.DIRT, Cell.CLAY],
		[STONE_TOP, Cell.CLAY, Cell.STONE],
		[DEEP_TOP, Cell.STONE, Cell.DEEP],
	]
	for band: Array in bands:
		var b: int = band[0]
		if y < b - 2:
			continue
		if y <= b + 2:
			var lower_chance := float(y - b + 2) * 0.2 + 0.1
			return int(band[2]) if rng.randf() < lower_chance else int(band[1])
	if y >= DEEP_TOP:
		return Cell.DEEP
	if y >= STONE_TOP:
		return Cell.STONE
	if y >= CLAY_TOP:
		return Cell.CLAY
	return Cell.DIRT


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
	# ...and never undermines the bunker: no pits or caves give way there.
	if _gen_guard.has_point(Vector2i(x, y)):
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
				Cell.WATER:
					t = Tile.WATER if _gget(x, y - 1) == Cell.WATER else Tile.WATER_TOP
				Cell.CLAY:
					t = Tile.CLAY_DARK if rng.randf() < 0.35 else Tile.CLAY
				Cell.STONE:
					t = Tile.STONE_DARK if rng.randf() < 0.35 else Tile.STONE
				Cell.DEEP:
					t = Tile.DEEP_DARK if rng.randf() < 0.35 else Tile.DEEP
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


# ------------------------------------------------------------------ water ---

func _process(delta: float) -> void:
	if client_mode:
		return
	_water_acc += delta
	if _water_acc >= WATER_TICK:
		_water_acc = 0.0
		_tick_water()


## Flowing-water cellular step. Each drop: falls into air below; slides
## down open ledges; if stacked on water it spills sideways to flatten; on
## a solid floor it keeps flowing in its remembered direction while BOTH
## sides are open, and settles once it touches a wall or other water.
## Settled water is perfectly still and costs no bandwidth.
func _tick_water() -> void:
	var moves := []
	var new_transit := {}
	# Bottom-up scan: lower water settles first, columns compact naturally.
	for idx in range(_grid.size() - W - 1, W, -1):
		if _grid[idx] != Cell.WATER:
			continue
		var x := idx % W
		var y := idx / W
		var below := _gget(x, y + 1)
		var la := _gget(x - 1, y) == Cell.EMPTY
		var ra := _gget(x + 1, y) == Cell.EMPTY
		var d := int(_flow_dir.get(idx, 0))
		var to := -1
		if below == Cell.EMPTY:
			to = idx + W
		else:
			var dl := la and _gget(x - 1, y + 1) == Cell.EMPTY
			var dr := ra and _gget(x + 1, y + 1) == Cell.EMPTY
			if dl or dr:
				# A downhill ledge: slide diagonally, keeping our heading
				# when it's still open.
				if dl and dr:
					if d == 0:
						d = 1 if rng.randf() < 0.5 else -1
				elif dl:
					d = -1
				else:
					d = 1
				to = idx + W + d
			elif below == Cell.WATER and (la or ra):
				# Stacked on water: spill sideways to flatten the pool.
				if la and ra:
					if d == 0:
						d = 1 if rng.randf() < 0.5 else -1
				elif la:
					d = -1
				else:
					d = 1
				to = idx + d
			elif la and ra:
				# Solid floor, open on both sides: keep flowing until we
				# find a wall, a hole, or other water.
				if d == 0:
					d = 1 if rng.randf() < 0.5 else -1
				to = idx + d
			else:
				# Bottom filled and at least one side backed by wall or
				# water: this drop is home.
				_flow_dir.erase(idx)
				continue
		_flow_dir.erase(idx)
		var trail: Dictionary = _drop_trail.get(idx, {})
		_drop_trail.erase(idx)
		_grid[idx] = Cell.EMPTY
		erase_cell(Vector2i(x, y))
		_paint_water_cell(x, y + 1)  # the cell under us may surface
		if trail.has(to) or trail.size() > 48:
			# Been here before: it's looping with nowhere left to settle.
			# The drop evaporates.
			moves.append([idx, -1])
			continue
		trail[idx] = true
		_drop_trail[to] = trail
		if d != 0:
			_flow_dir[to] = d
		_grid[to] = Cell.WATER
		new_transit[to] = true
		erase_cell(Vector2i(to % W, to / W))  # in flight: droplet, not a tile
		moves.append([idx, to])
		if moves.size() >= WATER_MAX_MOVES:
			break
	var eq := []
	if moves.size() < WATER_MAX_MOVES:
		_equalize_bodies(eq)
	_settle_transit(new_transit)
	if not moves.is_empty() or not eq.is_empty():
		water_moved.emit(moves, eq)
	queue_redraw()


## Cells that were flying last tick but didn't move this tick have landed:
## give them their block tile back and forget their trails.
func _settle_transit(new_transit: Dictionary) -> void:
	for tkey in _transit:
		var i := int(tkey)
		if new_transit.has(i):
			continue
		_drop_trail.erase(i)
		if _grid[i] == Cell.WATER:
			_paint_water_cell(i % W, i / W)
			_paint_water_cell(i % W, i / W + 1)
	_transit = new_transit


## Communicating vessels: each connected body of water acts as ONE entity.
## A few cells per tick shift from its highest surface column to its lowest
## fillable one, so pools converge smoothly to a level surface, U-bends
## equalize both arms, and a split basin becomes two independent bodies.
func _equalize_bodies(moves: Array) -> void:
	var seen := {}
	for start in range(W, _grid.size() - W):
		if _grid[start] != Cell.WATER or seen.has(start):
			continue
		# Flood the body, remembering the top water cell of every column.
		var tops := {}
		var stack: Array[int] = [start]
		seen[start] = true
		while not stack.is_empty():
			var i: int = stack.pop_back()
			var cx := i % W
			var cy := i / W
			if not tops.has(cx) or cy < int(tops[cx]):
				tops[cx] = cy
			for nb: int in [i - 1, i + 1, i - W, i + W]:
				if nb >= 0 and nb < _grid.size() and not seen.has(nb) \
						and _grid[nb] == Cell.WATER:
					seen[nb] = true
					stack.append(nb)
		if tops.size() < 2:
			continue
		for k in 6:
			var hi_x := -1
			var hi_y := 1000000
			var lo_x := -1
			var lo_y := -1000000
			for cxv in tops:
				var cx2 := int(cxv)
				var ty := int(tops[cxv])
				if ty < hi_y:
					hi_y = ty
					hi_x = cx2
				if ty > lo_y and _gget(cx2, ty - 1) == Cell.EMPTY:
					lo_y = ty
					lo_x = cx2
			if hi_x < 0 or lo_x < 0 or hi_x == lo_x or hi_y >= lo_y - 1:
				break
			var src := hi_y * W + hi_x
			var dst := (lo_y - 1) * W + lo_x
			_grid[src] = Cell.EMPTY
			_grid[dst] = Cell.WATER
			erase_cell(Vector2i(hi_x, hi_y))
			_flow_dir.erase(src)
			_repaint_water_around(src, dst)
			moves.append([src, dst])
			if _gget(hi_x, hi_y + 1) == Cell.WATER:
				tops[hi_x] = hi_y + 1
			else:
				tops.erase(hi_x)
			tops[lo_x] = lo_y - 1
			if moves.size() >= WATER_MAX_MOVES:
				return


## Client mirror of _tick_water: replay the host's flow verbatim, drawing
## traveling drops as droplets and settled shifts as tiles.
func apply_water_moves(moves: Array, eq: Array = []) -> void:
	var new_transit := {}
	for mv in moves:
		var pair: Array = mv
		if pair.size() < 2:
			continue
		var f := int(pair[0])
		var t := int(pair[1])
		if f >= 0 and f < _grid.size():
			_grid[f] = Cell.EMPTY
			erase_cell(Vector2i(f % W, f / W))
			_paint_water_cell(f % W, f / W + 1)
		if t >= 0 and t < _grid.size():
			_grid[t] = Cell.WATER
			new_transit[t] = true
			erase_cell(Vector2i(t % W, t / W))
	for mv in eq:
		var pair: Array = mv
		if pair.size() < 2:
			continue
		var f := int(pair[0])
		var t := int(pair[1])
		if f >= 0 and f < _grid.size():
			_grid[f] = Cell.EMPTY
			erase_cell(Vector2i(f % W, f / W))
		if t >= 0 and t < _grid.size():
			_grid[t] = Cell.WATER
			_repaint_water_around(f, t)
	_settle_transit(new_transit)
	queue_redraw()


## Traveling water renders as droplet particles instead of blocks.
func _draw() -> void:
	for tkey in _transit:
		var i := int(tkey)
		if i < 0 or i >= _grid.size() or _grid[i] != Cell.WATER:
			continue
		var p := Vector2((i % W) * TILE + TILE * 0.5, (i / W) * TILE + TILE * 0.5)
		draw_circle(p, 5.0, WATER_COLOR)
		draw_circle(p + Vector2(-1.6, -1.6), 1.7, Color(0.8, 0.92, 1.0, 0.5))


## Repaint a moved drop and its vertical neighbors: covered water uses the
## full tile, surface water the partial one (visible waterline).
func _repaint_water_around(from_idx: int, to_idx: int) -> void:
	_paint_water_cell(to_idx % W, to_idx / W)
	_paint_water_cell(to_idx % W, to_idx / W + 1)
	_paint_water_cell(from_idx % W, from_idx / W + 1)


func _paint_water_cell(x: int, y: int) -> void:
	if _gget(x, y) != Cell.WATER:
		return
	var t := Tile.WATER if _gget(x, y - 1) == Cell.WATER else Tile.WATER_TOP
	set_cell(Vector2i(x, y), _src_id, Vector2i(t, 0))


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
	var out: Array[Vector2] = []
	for i in n:
		out.append(surface_spawn(i))
	return out


## A spawn point above the grass for the given slot (columns spread out from
## the middle, cycling if there are more players than columns).
func surface_spawn(i: int) -> Vector2:
	var cx := W / 2
	var cols := [cx - 6, cx - 3, cx + 3, cx + 6, cx - 9, cx + 9, cx - 12, cx + 12]
	var c: int = cols[i % cols.size()]
	return Vector2((c + 0.5) * TILE, SURFACE_ROW * TILE - 20.0)


func shelter_spawn() -> Vector2:
	return Vector2((W / 2 + 0.5) * TILE, (SHELTER_TOP + SHELTER_H) * TILE - 16.0)


## A rare few of the dead-end pockets get an armor chest, resting on the
## pocket floor.
func chest_positions() -> Array[Vector2]:
	var cells: Array[Vector2i] = chest_cells.duplicate()
	cells.shuffle()
	var count := rng.randi_range(3, 5)
	var out: Array[Vector2] = []
	for c: Vector2i in cells:
		if out.size() >= count:
			break
		var y: int = c.y
		while y < H - 2 and _gget(c.x, y + 1) == Cell.EMPTY:
			y += 1
		out.append(Vector2((c.x + 0.5) * TILE, (y + 1) * TILE - 8.0))
	return out


## The finish chamber interior in world px — entering it wins the race.
func finish_line_rect() -> Rect2:
	return Rect2(finish_room.position.x * TILE, finish_room.position.y * TILE,
		finish_room.size.x * TILE, finish_room.size.y * TILE)


## Public read access to the cell grid (Cell enum), used by bot navigation.
func cell(x: int, y: int) -> int:
	return _gget(x, y)


## True when the world-space point sits in groundwater.
func is_water(world_pos: Vector2) -> bool:
	var c := local_to_map(to_local(world_pos))
	return _gget(c.x, c.y) == Cell.WATER


# -------------------------------------------------------------------- grid ---

func _gget(x: int, y: int) -> int:
	if x < 0 or x >= W or y < 0 or y >= H:
		return Cell.BEDROCK
	return _grid[y * W + x]


func _gset(x: int, y: int, v: int) -> void:
	if x >= 0 and x < W and y >= 0 and y < H:
		_grid[y * W + x] = v
