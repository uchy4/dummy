class_name Main
extends Node2D
## Game orchestrator: registers per-player input actions, builds the world
## (terrain, backdrops, players, camera, spawner, finish line, HUD) and runs
## the match flow — grace countdown, win detection, pause + rematch.

const GRACE := 5.0
const PLAYER_COLORS: Array[Color] = [
	Color("4fc3f7"), Color("ef5350"), Color("9ccc65"), Color("ffca28"),
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

	_build_backdrops()

	var spawns := terrain.surface_spawns(num_players)
	for i in num_players:
		var p := Player.new()
		p.name = "Player%d" % (i + 1)
		p.setup(i, PLAYER_COLORS[i])
		p.respawn_point = terrain.shelter_spawn()
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

	_build_finish()

	hud = Hud.new()
	add_child(hud)
	hud.setup(num_players, PLAYER_COLORS, touch)
	hud.restart_requested.connect(_on_restart_requested)
	hud.settings_pressed.connect(_toggle_settings)


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
	if settings_open:
		return

	elapsed += delta
	hud.set_timer(elapsed)
	for i in players.size():
		var p := players[i]
		if p.alive:
			hud.set_player_status(i, "P%d   deaths %d" % [i + 1, p.deaths])
		else:
			hud.set_player_status(i, "P%d   respawn %.1f" % [i + 1, maxf(p.respawn_left, 0.0)])

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
	hud.show_winner(p.index, PLAYER_COLORS[p.index], elapsed)
	get_tree().paused = true


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
