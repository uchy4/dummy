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
	{"left": [KEY_A], "right": [KEY_D], "jump": [KEY_W], "kick": [KEY_S]},
	{"left": [KEY_LEFT], "right": [KEY_RIGHT], "jump": [KEY_UP], "kick": [KEY_DOWN]},
	{"left": [KEY_J], "right": [KEY_L], "jump": [KEY_I], "kick": [KEY_K]},
	{"left": [KEY_F, KEY_KP_4], "right": [KEY_H, KEY_KP_6],
		"jump": [KEY_T, KEY_KP_8], "kick": [KEY_G, KEY_KP_5]},
]

@export_range(2, 4) var num_players := 4

var game_over := false
var settings_open := false
var elapsed := 0.0
var touch := false

var world: Node2D
var terrain: Terrain
var hud: Hud
var camera: GameCamera
var players: Array[Player] = []
var web_players := {}  # NetHub client id -> Player
var _bounds := Rect2()
var _roster_dirty := true
var _snap_tick := 0
var _center_msg := ""  ## mirrored to web viewers so they see the countdown

## The all-dead ending is declared after a short delay so the final death's
## ragdoll gets to tumble before the world freezes.
const WIN_DELAY := 1.8
var _win_timer := -1.0


func _enter_tree() -> void:
	register_actions()


func _ready() -> void:
	# Main + HUD keep processing while the tree is paused (win screen);
	# everything inside World freezes.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Flavor APKs lock the renderer: the 2D and 3D builds install side by side.
	if OS.has_feature("mode3d"):
		Settings.mode_3d = true
	elif OS.has_feature("mode2d"):
		Settings.mode_3d = false
	NetHub.advertising = true  # hosting: discoverable on the local network
	# CI smoke forces the touch path so gesture/button code errors surface
	# headless — a real touchscreen isn't available on the runner.
	touch = DisplayServer.is_touchscreen_available() \
		or OS.get_environment("BOMB_SHELTER_SMOKE") == "1"
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
	terrain.water_moved.connect(func(moves: Array, eq: Array) -> void:
		NetHub.broadcast({"t": "w", "m": moves, "q": eq}))
	# Fresh match, fresh map: every web viewer needs the new terrain.
	for id in NetHub.clients:
		if NetHub.clients[id].joined:
			NetHub.clients[id].pending_init = true

	_build_backdrops()

	_build_boundaries()

	if Settings.player_colors.size() < KEYMAPS.size():
		Settings.player_colors = PLAYER_COLORS.duplicate()

	if OS.get_environment("BOMB_SHELTER_SMOKE") == "1":
		Settings.bot_count = maxi(Settings.bot_count, 3)  # CI exercises bot AI
	match OS.get_environment("BOMB_SHELTER_SMOKE_3D"):
		"1":
			Settings.mode_3d = true
		"0":
			Settings.mode_3d = false
	var bot_count := clampi(Settings.bot_count, 0, MAX_PLAYERS - num_players)
	var spawns := terrain.surface_spawns(num_players + bot_count)
	_bounds = terrain.world_rect().grow_individual(80, 900, 80, 300)
	for i in num_players:
		var p := Player.new()
		p.name = "Player%d" % (i + 1)
		p.setup(i, Settings.player_colors[i])
		p.respawn_point = terrain.surface_spawn(i)
		p.world_bounds = _bounds
		p.position = spawns[i]
		world.add_child(p)
		players.append(p)

	for i in bot_count:
		var idx := players.size()
		var free: Array = _color_options()[0]
		var c1 := Color.from_string(free[0], Color.WHITE)
		var c2 := Color.from_string(free[1] if free.size() > 1 else free[0], c1)
		var p := Player.new()
		p.name = "Bot%d" % (i + 1)
		p.setup_remote(idx, "Bot %d" % (i + 1), c1, c2)
		p.respawn_point = terrain.surface_spawn(idx)
		p.world_bounds = _bounds
		p.position = spawns[idx]
		world.add_child(p)
		players.append(p)
		var brain := BotController.new()
		brain.name = "BotBrain%d" % (i + 1)
		brain.player = p
		brain.terrain = terrain
		world.add_child(brain)

	camera = GameCamera.new()
	var wr := terrain.world_rect()
	camera.map_rect = wr.grow_individual(40, 500, 40, 0)
	camera.position = Vector2(wr.get_center().x, terrain.surface_y() - 60.0)
	camera.zoom = Vector2(0.8, 0.8)
	if not players.is_empty():
		camera.focus_target = players[0]  # follow-mode tracks player 1
	world.add_child(camera)

	var spawner := BombSpawner.new()
	spawner.terrain = terrain
	spawner.container = world
	world.add_child(spawner)

	add_child(Sfx.new())

	for pos in terrain.chest_positions():
		var ch := Chest.new()
		ch.position = pos
		world.add_child(ch)

	# The homestead: outhouse, furnished bunker, surface pens, corn, arsenal.
	var props := BunkerProps.new()
	props.terrain = terrain
	world.add_child(props)

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

	if Settings.mode_3d:
		# 2.5D: hide the 2D canvas (the sim keeps running invisibly) and
		# mirror everything with the KayKit 3D presentation layer.
		world.visible = false
		var v3 := Visual3D.new()
		v3.name = "Visual3D"
		v3.terrain = terrain
		v3.process_mode = Node.PROCESS_MODE_PAUSABLE
		add_child(v3)


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
			var suffix := "   HAT" if p.armor else ""
			hud.set_player_status(i, "%s   deaths %d%s" % [p.display_name, p.deaths, suffix])
		elif Settings.one_life:
			hud.set_player_status(i, "%s   OUT" % p.display_name)
		else:
			hud.set_player_status(i, "%s   respawn %.1f" % [p.display_name, maxf(p.respawn_left, 0.0)])

	if Settings.one_life:
		_check_elimination()

	var msg := ""
	if elapsed < GRACE:
		msg = "First bomb in %d — take cover!" % ceili(GRACE - elapsed)
	elif elapsed < GRACE + 6.0:
		msg = "Race to the FINISH line at the bottom!"
	_center_msg = msg
	hud.set_center(msg)


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
	cave.color = Color("2b1a0c")  # warm dark brown, not black
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
	# The checkered chamber is painted by RoomDecor; this is the win sensor.
	var fr := terrain.finish_line_rect()
	var area := Area2D.new()
	area.collision_layer = 0
	area.collision_mask = 2
	var cs := CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	rs.size = fr.size
	cs.shape = rs
	area.position = fr.get_center()
	area.add_child(cs)
	area.body_entered.connect(_on_finish_entered)
	world.add_child(area)


func _on_finish_entered(body: Node2D) -> void:
	var p := body as Player
	if game_over or p == null or not p.alive:
		return
	# Reaching the checkered chamber IS maximum depth: instant podium.
	p.deepest_y += 100000.0
	_finish_match("%s reached the finish chamber!" % p.display_name)


## The race never ends early: a lone survivor keeps digging. The match is
## over only when someone reaches the finish chamber or everyone is dead —
## then the podium ranks everyone by how deep they got. The all-dead path
## waits WIN_DELAY so the final ragdoll finishes flying.
func _check_elimination() -> void:
	if game_over:
		return
	if _win_timer >= 0.0:
		_win_timer -= get_process_delta_time()
		if _win_timer < 0.0:
			_finish_match("Everyone died — deepest digger wins")
		return
	var living := 0
	for p in players:
		if p.alive:
			living += 1
	if living == 0:
		_win_timer = WIN_DELAY


## Match over: rank every player by deepest point reached, fly the camera
## down to the finish hall and let the top three celebrate on its podium
## while the frozen world waits for the rematch tap.
func _finish_match(reason: String) -> void:
	game_over = true
	var ranking := players.duplicate()
	ranking.sort_custom(func(a: Player, b: Player) -> bool:
		return a.deepest_y > b.deepest_y)
	var entries: Array[Dictionary] = []
	for p: Player in ranking:
		entries.append({
			"n": p.display_name, "c": p.player_color, "c2": p.color2,
			"d": maxi(0, int(minf(p.deepest_y, float(Terrain.H * Terrain.TILE))
				/ Terrain.TILE) - Terrain.SURFACE_ROW),
		})
	hud.show_win_banner(entries, elapsed, reason)
	var wire := []
	for e in entries.slice(0, 3):
		wire.append([e.n, (e.c as Color).to_html(false), e.d])
	var win_name: String = entries[0].n if not entries.is_empty() else "Nobody"
	var win_col: String = (entries[0].c as Color).to_html(false) \
		if not entries.is_empty() else "aaaaaa"
	NetHub.broadcast({"t": "win", "n": win_name, "c": win_col, "podium": wire})
	get_tree().call_group(&"sfx", &"play_fanfare", Vector2.ZERO)
	# Cut the camera to the finish hall (the world pauses right after, so it
	# stays put) and stage the ceremony there. Main is PROCESS_MODE_ALWAYS,
	# so the dolls keep jumping while everything else is frozen.
	var fr := terrain.finish_line_rect()
	camera.focus_target = null
	camera.global_position = fr.get_center() + Vector2(0, -6.0)
	camera.zoom = Vector2(2.2, 2.2)
	var cer := Ceremony.new()
	cer.room = fr
	cer.entries.assign(entries.slice(0, 3))
	add_child(cer)
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
		if not c.connected:
			continue
		if c.get("pending_colors", false) \
				and (c.ws as WebSocketPeer).get_ready_state() == WebSocketPeer.STATE_OPEN:
			c.pending_colors = false
			NetHub.send_to(id, _colors_msg())
		if not c.joined:
			continue
		if c.pending_init:
			c.pending_init = false
			# Room list for wallpaper tints: [x, y, w, h, kind]; kinds:
			# 0 stairs 1 kitchen 2 bedroom 3 bathroom 4 arsenal 5 finish.
			var rooms := []
			var kind_of := {"stairs": 0, "kitchen": 1, "bedroom": 2,
				"bathroom": 3, "arsenal": 4}
			for rn in terrain.bunker_rooms:
				var rr: Rect2i = terrain.bunker_rooms[rn]
				rooms.append([rr.position.x, rr.position.y, rr.size.x, rr.size.y,
					int(kind_of.get(rn, 0))])
			var fr := terrain.finish_room
			rooms.append([fr.position.x, fr.position.y, fr.size.x, fr.size.y, 5])
			NetHub.send_to(id, {
				"t": "init", "w": Terrain.W, "h": Terrain.H, "ts": Terrain.TILE,
				"surf": Terrain.SURFACE_ROW, "fin": int(terrain.finish_line_rect().position.y),
				"grid": terrain.grid_string(), "rooms": rooms,
				"pipe": [terrain.pump_cell.x, terrain.pump_cell.y,
					terrain.reservoir_rect.position.y],
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
		NetHub.broadcast_all(_colors_msg())
	_snap_tick += 1
	if _snap_tick % 30 == 0:  # 2 Hz: center message + match timer for web HUDs
		NetHub.broadcast({"t": "hud", "m": _center_msg, "tm": int(elapsed)})
	if _snap_tick % 2 != 0:  # 30 Hz position stream (was 15) - less felt lag
		return
	var ps := []
	for p in players:
		var resp := -1 if Settings.one_life else int(maxf(p.respawn_left, 0.0) * 10.0)
		ps.append([int(p.global_position.x), int(p.global_position.y),
			1 if p.alive else 0, resp, p.deaths,
			1 if p.armor else 0, 1 if p.stun_left > 0.0 else 0,
			1 if p.kick_anim > 0.0 else 0])
	var bs := []
	for b in get_tree().get_nodes_in_group(&"bombs"):
		var bomb := b as Bomb
		if bomb == null:
			continue
		bs.append([int(bomb.global_position.x), int(bomb.global_position.y),
			int(bomb.type), int(maxf(bomb.fuse, 0.0) * 10.0), int(bomb._body_radius),
			1 if bomb.fizzled else 0])
	var cs := []
	for ch in get_tree().get_nodes_in_group(&"chests"):
		if not "prop_kind" in ch:
			cs.append([int(ch.global_position.x), int(ch.global_position.y)])
	# Homestead props (furniture, fixtures, critters, markers) for web view.
	var es := []
	for n in get_tree().get_nodes_in_group(&"props"):
		var node := n as Node2D
		if node == null:
			continue
		var pk: int = node.get(&"prop_kind")
		es.append([int(node.global_position.x), int(node.global_position.y),
			pk, int(node.rotation * 10.0)])
	NetHub.broadcast({"t": "s", "p": ps, "b": bs, "c": cs, "e": es,
		"z": Settings.zoom_scale})


func _pair_key(a: Color, b: Color) -> String:
	return a.to_html(false) + "|" + b.to_html(false)


func _taken_pairs(except: Player = null) -> Dictionary:
	var out := {}
	for p in players:
		if p != except:
			out[_pair_key(p.player_color, p.color2)] = true
	return out


## What joiners can pick: every free solid color, then striped two-color
## combos to keep the tray full as solids run out. Never includes anything
## already worn by a player.
func _color_options() -> Array:
	var taken := _taken_pairs()
	var opts: Array = []
	for c in NetHub.PALETTE:
		if not taken.has(c + "|" + c):
			opts.append([c])
	var n: int = NetHub.PALETTE.size()
	for step in range(1, n):
		for a in range(0, n - step):
			if opts.size() >= 12:
				return opts
			var c1: String = NetHub.PALETTE[a]
			var c2: String = NetHub.PALETTE[a + step]
			if not taken.has(c1 + "|" + c2):
				opts.append([c1, c2])
	return opts


func _colors_msg() -> Dictionary:
	return {"t": "colors", "opts": _color_options()}


func _roster_msg() -> Dictionary:
	var list := []
	for p in players:
		list.append({"n": p.display_name, "c": p.player_color.to_html(false),
			"c2": p.color2.to_html(false)})
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
			# No color sharing: a taken combo falls back to the first free one.
			if _taken_pairs().has(_pair_key(c.color, c.color2)):
				var free: Array = _color_options()[0]
				c.color = Color.from_string(free[0], c.color)
				c.color2 = Color.from_string(free[1] if free.size() > 1 else free[0], c.color)
			var p := Player.new()
			p.name = "WebPlayer%d" % id
			p.setup_remote(players.size(), str(c.name), c.color, c.color2)
			p.respawn_point = terrain.surface_spawn(players.size())  # surface, not the bunker
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
		p.remote_kick = c.kick and c.connected
		if c.connected and c.kick_dir != Vector2.ZERO:
			p.queue_kick(c.kick_dir, c.kick_power)
			c.kick_dir = Vector2.ZERO
		if not p.player_color.is_equal_approx(c.color) or not p.color2.is_equal_approx(c.color2):
			if _taken_pairs(p).has(_pair_key(c.color, c.color2)):
				c.color = p.player_color  # requested combo is in use: reject
				c.color2 = p.color2
			else:
				p.set_colors(c.color, c.color2)
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


static func register_actions() -> void:
	for i in KEYMAPS.size():
		for dir in ["left", "right", "jump", "kick"]:
			_add_action("p%d_%s" % [i + 1, dir], KEYMAPS[i][dir])
	_add_action("restart", [KEY_R])
	_add_action("settings", [KEY_ESCAPE])


static func _add_action(action: String, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)
