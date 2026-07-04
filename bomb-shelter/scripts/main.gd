class_name Main
extends Node2D
## Game orchestrator: registers per-player input actions, builds the world
## (terrain, backdrops, players, camera, spawner, finish line, HUD) and runs
## the match flow — grace countdown, win detection, pause + rematch.

const GRACE := 5.0
const MAX_PLAYERS := 8
# P1 is purple: the old light blue vanished against the sky.
const PLAYER_COLORS: Array[Color] = [
	Color("9575ff"), Color("ef5350"), Color("9ccc65"), Color("ffca28"),
]
const KEYMAPS: Array[Dictionary] = [
	{"left": [KEY_A], "right": [KEY_D], "jump": [KEY_W]},
	{"left": [KEY_LEFT], "right": [KEY_RIGHT], "jump": [KEY_UP]},
	{"left": [KEY_J], "right": [KEY_L], "jump": [KEY_I]},
	{"left": [KEY_F, KEY_KP_4], "right": [KEY_H, KEY_KP_6], "jump": [KEY_T, KEY_KP_8]},
]

@export_range(2, 4) var num_players := 4

var game_over := false
var settings_open := false
var elapsed := 0.0
var touch := false

var world: Node2D
var terrain: Terrain
var hud: Hud
var players: Array[Player] = []
var web_players := {}  # NetHub client id -> Player
var _bounds := Rect2()
var _roster_dirty := true
var _snap_tick := 0


func _enter_tree() -> void:
	_register_actions()


func _ready() -> void:
	# Main + HUD keep processing while the tree is paused (win screen);
	# everything inside World freezes.
	process_mode = Node.PROCESS_MODE_ALWAYS
	touch = DisplayServer.is_touchscreen_available()
	if touch:
		num_players = 1  # phone: one player racing the bombs, on-screen buttons
	world = Node2D.new()
	world.name = "World"
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)

	terrain = Terrain.new()
	terrain.name = "Terrain"
	world.add_child(terrain)  # generates in _ready
	terrain.carved.connect(_on_carved)
	# Fresh match, fresh map: every web viewer needs the new terrain.
	for id in NetHub.clients:
		if NetHub.clients[id].joined:
			NetHub.clients[id].pending_init = true

	_build_backdrops()

	_build_boundaries()

	if Settings.player_colors.size() < KEYMAPS.size():
		Settings.player_colors = PLAYER_COLORS.duplicate()

	var spawns := terrain.surface_spawns(num_players)
	_bounds = terrain.world_rect().grow_individual(80, 900, 80, 300)
	for i in num_players:
		var p := Player.new()
		p.name = "Player%d" % (i + 1)
		p.setup(i, Settings.player_colors[i])
		p.respawn_point = _shelter_slot(i)
		p.world_bounds = _bounds
		p.position = spawns[i]
		world.add_child(p)
		players.append(p)

	var camera := GameCamera.new()
	var wr := terrain.world_rect()
	camera.map_rect = wr.grow_individual(40, 500, 40, 0)
	camera.position = Vector2(wr.get_center().x, terrain.surface_y() - 60.0)
	camera.zoom = Vector2(0.8, 0.8)
	world.add_child(camera)

	var spawner := BombSpawner.new()
	spawner.terrain = terrain
	spawner.container = world
	world.add_child(spawner)

	add_child(Sfx.new())

	_build_finish()

	hud = Hud.new()
	add_child(hud)
	var hud_colors: Array[Color] = []
	for p in players:
		hud_colors.append(p.player_color)
	hud.setup(hud_colors, touch)
	hud.restart_requested.connect(_on_restart_requested)
	hud.settings_pressed.connect(_toggle_settings)
	hud.reset_players_pressed.connect(_reset_players)
	hud.player_color_changed.connect(_on_player_color_changed)


func _process(delta: float) -> void:
	if game_over:
		if Input.is_action_just_pressed(&"ui_accept") or Input.is_action_just_pressed(&"restart"):
			_restart()
		return
	if Input.is_action_just_pressed(&"settings"):
		_toggle_settings()
	if Input.is_action_just_pressed(&"restart"):
		_restart()
		return
	_sync_web_players()
	_net_service()
	if settings_open:
		return

	elapsed += delta
	hud.set_timer(elapsed)
	for i in players.size():
		var p := players[i]
		if p.alive:
			hud.set_player_status(i, "%s   deaths %d" % [p.display_name, p.deaths])
		else:
			hud.set_player_status(i, "%s   respawn %.1f" % [p.display_name, maxf(p.respawn_left, 0.0)])

	if elapsed < GRACE:
		hud.set_center("First bomb in %d — take cover!" % ceili(GRACE - elapsed))
	elif elapsed < GRACE + 6.0:
		hud.set_center("Race to the FINISH line at the bottom!")
	else:
		hud.set_center("")


func _build_backdrops() -> void:
	var wr := terrain.world_rect()
	var sky := ColorRect.new()
	sky.color = Color("8ecae6")
	sky.position = Vector2(wr.position.x - 400, -900)
	sky.size = Vector2(wr.size.x + 800, wr.size.y + 900)
	sky.z_index = -20
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	world.add_child(sky)

	var cave := ColorRect.new()
	cave.color = Color("17100a")
	cave.position = Vector2(wr.position.x, terrain.surface_y())
	cave.size = Vector2(wr.size.x, wr.size.y - terrain.surface_y())
	cave.z_index = -15
	cave.mouse_filter = Control.MOUSE_FILTER_IGNORE
	world.add_child(cave)


# Invisible walls over the bedrock edge columns, reaching far above the
# surface — the visible pillars stop a jump, these stop everything else.
func _build_boundaries() -> void:
	var wr := terrain.world_rect()
	for x: float in [Terrain.TILE, wr.size.x - Terrain.TILE]:
		var wall := StaticBody2D.new()
		wall.collision_layer = 1
		wall.collision_mask = 0
		var cs := CollisionShape2D.new()
		var rs := RectangleShape2D.new()
		rs.size = Vector2(2 * Terrain.TILE, 1400)
		cs.shape = rs
		wall.position = Vector2(x, terrain.surface_y() - 700)
		wall.add_child(cs)
		world.add_child(wall)


# Spread shelter positions out: players collide now, so they can't share one.
func _shelter_slot(i: int) -> Vector2:
	return terrain.shelter_spawn() + Vector2((i - (MAX_PLAYERS - 1) / 2.0) * 24.0, 0)


func _reset_players() -> void:
	for i in players.size():
		players[i].teleport_to(_shelter_slot(i))


func _build_finish() -> void:
	var fr := terrain.finish_line_rect()

	var strip := FinishLine.new()
	strip.rect = fr
	world.add_child(strip)

	var area := Area2D.new()
	area.collision_layer = 0
	area.collision_mask = 2
	var cs := CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	rs.size = fr.size + Vector2(0, 12)  # a bit taller so a running player can't skip it
	cs.shape = rs
	area.position = fr.get_center() - Vector2(0, 6)
	area.add_child(cs)
	area.body_entered.connect(_on_finish_entered)
	world.add_child(area)


func _on_finish_entered(body: Node2D) -> void:
	var p := body as Player
	if game_over or p == null or not p.alive:
		return
	game_over = true
	hud.show_winner(p.display_name, p.player_color, elapsed)
	NetHub.broadcast({"t": "win", "n": p.display_name, "c": p.player_color.to_html(false)})
	get_tree().paused = true


func _on_player_color_changed(i: int, c: Color) -> void:
	if i < players.size():
		players[i].set_color(c)
		hud.set_row_color(i, c)
	if i < Settings.player_colors.size():
		Settings.player_colors[i] = c
	_roster_dirty = true


func _on_carved(pos: Vector2, radius: float) -> void:
	NetHub.broadcast({"t": "carve", "x": int(pos.x), "y": int(pos.y), "r": int(radius)})


# Stream game state to web viewers: init bundle for new/rejoined clients,
# roster on changes, entity snapshots at ~15 Hz.
func _net_service() -> void:
	for id in NetHub.clients:
		var c: Dictionary = NetHub.clients[id]
		if not c.joined or not c.connected:
			continue
		if c.pending_init:
			c.pending_init = false
			NetHub.send_to(id, {
				"t": "init", "w": Terrain.W, "h": Terrain.H, "ts": Terrain.TILE,
				"surf": Terrain.SURFACE_ROW, "fin": int(terrain.finish_line_rect().position.y),
				"grid": terrain.grid_string(),
			})
			NetHub.send_to(id, _roster_msg())
			if web_players.has(id):
				NetHub.send_to(id, {"t": "you", "i": (web_players[id] as Player).index})
			if game_over:
				NetHub.send_to(id, {"t": "win", "n": "someone", "c": "ffffff"})
	if not NetHub.has_viewers():
		return
	if _roster_dirty:
		_roster_dirty = false
		NetHub.broadcast(_roster_msg())
	_snap_tick += 1
	if _snap_tick % 4 != 0:
		return
	var ps := []
	for p in players:
		ps.append([int(p.global_position.x), int(p.global_position.y),
			1 if p.alive else 0, int(maxf(p.respawn_left, 0.0) * 10.0), p.deaths])
	var bs := []
	for b in get_tree().get_nodes_in_group(&"bombs"):
		var bomb := b as Bomb
		if bomb == null:
			continue
		bs.append([int(bomb.global_position.x), int(bomb.global_position.y),
			int(bomb.type), int(maxf(bomb.fuse, 0.0) * 10.0), int(bomb._body_radius)])
	NetHub.broadcast({"t": "s", "p": ps, "b": bs})


func _roster_msg() -> Dictionary:
	var list := []
	for p in players:
		list.append({"n": p.display_name, "c": p.player_color.to_html(false)})
	return {"t": "roster", "p": list}


## Spawn a Player for every joined web controller and feed it live input.
func _sync_web_players() -> void:
	for id in NetHub.clients:
		var c: Dictionary = NetHub.clients[id]
		if not c.joined:
			continue
		if not web_players.has(id):
			if players.size() >= MAX_PLAYERS:
				continue
			var p := Player.new()
			p.name = "WebPlayer%d" % id
			p.setup_remote(players.size(), str(c.name), c.color)
			p.respawn_point = _shelter_slot(players.size())
			p.world_bounds = _bounds
			p.position = p.respawn_point
			world.add_child(p)
			players.append(p)
			web_players[id] = p
			hud.add_player_row(c.color)
			_roster_dirty = true
		var p: Player = web_players[id]
		p.remote_axis = c.axis if c.connected else 0.0
		p.remote_jump = c.jump and c.connected
		if not p.player_color.is_equal_approx(c.color):
			p.set_color(c.color)
			hud.set_row_color(p.index, c.color)
			_roster_dirty = true


func _on_restart_requested() -> void:
	if game_over:
		_restart()


func _toggle_settings() -> void:
	if game_over:
		return
	settings_open = not settings_open
	hud.show_settings(settings_open)
	get_tree().paused = settings_open


func _restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _register_actions() -> void:
	for i in KEYMAPS.size():
		for dir in ["left", "right", "jump"]:
			_add_action("p%d_%s" % [i + 1, dir], KEYMAPS[i][dir])
	_add_action("restart", [KEY_R])
	_add_action("settings", [KEY_ESCAPE])


func _add_action(action: String, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)
