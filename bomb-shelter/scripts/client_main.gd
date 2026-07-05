class_name ClientMain
extends Node2D
## Native LAN-join client. Connects to a host's WebSocket (same protocol the
## web page uses) and mirrors the match with puppet Players/Bombs/Chests on a
## client-mode Terrain — so both the 2D renderer and the KayKit 2.5D layer
## work unchanged. Sends this player's input back to the host.

var world: Node2D
var terrain: Terrain
var camera: GameCamera
var ws := WebSocketPeer.new()
var joined := false
var my_index := -1

var players: Array[Player] = []
var bombs: Array[Bomb] = []
var chests: Array[Node2D] = []
var _ptargets: Array[Vector2] = []
var _plast: Array[Vector2] = []
var _btargets: Array[Vector2] = []
var _finish: FinishLine

var _status: Label
var _win_label: Label
var _hud: CanvasLayer
var _touch_buttons: Array[TouchScreenButton] = []
var _sent_a := 0
var _sent_j := false
var _sent_k := false


func _ready() -> void:
	if OS.has_feature("mode3d"):
		Settings.mode_3d = true
	elif OS.has_feature("mode2d"):
		Settings.mode_3d = false

	world = Node2D.new()
	world.name = "World"
	add_child(world)

	terrain = Terrain.new()
	terrain.client_mode = true
	world.add_child(terrain)
	_build_backdrops()

	add_child(Sfx.new())

	camera = GameCamera.new()
	var wr := terrain.world_rect()
	camera.map_rect = wr.grow_individual(40, 500, 40, 0)
	camera.position = Vector2(wr.get_center().x, terrain.surface_y() - 60.0)
	camera.zoom = Vector2(0.8, 0.8)
	world.add_child(camera)

	_build_hud()

	if Settings.mode_3d:
		world.visible = false
		var v3 := Visual3D.new()
		v3.terrain = terrain
		add_child(v3)

	var err := ws.connect_to_url("ws://%s:%d" % [Settings.join_ip, Settings.join_ws_port])
	if err != OK:
		_leave("Could not connect")


func _process(delta: float) -> void:
	ws.poll()
	match ws.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not joined:
				joined = true
				ws.send_text(JSON.stringify({
					"t": "join", "n": Settings.join_name, "c": "#ff8f2e",
				}))
			while ws.get_available_packet_count() > 0:
				var msg: Variant = JSON.parse_string(ws.get_packet().get_string_from_utf8())
				if msg is Dictionary:
					_handle(msg)
			_send_inputs()
		WebSocketPeer.STATE_CLOSED:
			_leave("Disconnected from host")
			return

	if Input.is_action_just_pressed(&"settings"):
		_leave("")
		return

	_animate_puppets(delta)


func _animate_puppets(delta: float) -> void:
	var k := 1.0 - exp(-14.0 * delta)
	for i in players.size():
		var p := players[i]
		if not is_instance_valid(p):
			continue
		var target := _ptargets[i]
		if p.global_position.distance_to(target) > 150.0:
			p.global_position = target
		else:
			p.global_position = p.global_position.lerp(target, k)
		var vx := (target.x - _plast[i].x) * 15.0
		var vy := (target.y - _plast[i].y) * 15.0
		p.velocity = Vector2(vx, vy)
		p.puppet_on_floor = absf(vy) < 30.0
		if absf(vx) > 20.0:
			p._facing = 1 if vx > 0.0 else -1
		var swing_target := 0.0
		if absf(vx) > 20.0 and p.puppet_on_floor:
			p._walk_phase += vx * delta * 0.055
			swing_target = sin(p._walk_phase) * 0.6
		elif not p.puppet_on_floor:
			swing_target = 0.35
		p._swing = lerpf(p._swing, swing_target, 0.35)
		p.queue_redraw()
	for i in bombs.size():
		var b := bombs[i]
		if not is_instance_valid(b):
			continue
		if b.global_position.distance_to(_btargets[i]) > 120.0:
			b.global_position = _btargets[i]
		else:
			b.global_position = b.global_position.lerp(_btargets[i], k)


func _send_inputs() -> void:
	var axis := Input.get_axis(&"p1_left", &"p1_right")
	var a := 0
	if axis < -0.3:
		a = -1
	elif axis > 0.3:
		a = 1
	var j := Input.is_action_pressed(&"p1_jump")
	var kk := Input.is_action_pressed(&"p1_kick")
	if a != _sent_a or j != _sent_j or kk != _sent_k:
		_sent_a = a
		_sent_j = j
		_sent_k = kk
		ws.send_text(JSON.stringify({"t": "i", "a": a, "j": 1 if j else 0, "k": 1 if kk else 0}))


func _handle(m: Dictionary) -> void:
	match str(m.get("t", "")):
		"init":
			terrain.load_from_string(str(m.get("grid", "")))
			_clear_entities()
			_win_label.get_parent().visible = false
			if _finish:
				_finish.queue_free()
			_finish = FinishLine.new()
			_finish.rect = Rect2(3 * Terrain.TILE, float(m.get("fin", 0)),
				(Terrain.W - 6) * Terrain.TILE, 14)
			world.add_child(_finish)
			_status.text = ""
		"roster":
			_apply_roster(m.get("p", []))
		"you":
			my_index = int(m.get("i", -1))
		"s":
			_apply_snapshot(m)
		"carve":
			var pos := Vector2(float(m.get("x", 0)), float(m.get("y", 0)))
			var r := float(m.get("r", 60))
			terrain.carve_circle(pos, r)
			get_tree().call_group(&"sfx", &"play_explosion", pos, r / 66.0, 0)
			get_tree().call_group(&"camera", &"add_trauma", 0.3)
			if not Settings.mode_3d:
				var fx := ExplosionFx.new()
				fx.radius = r
				fx.position = pos
				world.add_child(fx)
		"win":
			_win_label.text = "%s WINS!" % str(m.get("n", "?")).to_upper()
			_win_label.add_theme_color_override(&"font_color",
				Color.from_string("#" + str(m.get("c", "ffffff")), Color.WHITE))
			_win_label.get_parent().visible = true
			get_tree().call_group(&"sfx", &"play_fanfare", Vector2.ZERO)


func _apply_roster(list: Array) -> void:
	while players.size() > list.size():
		var extra: Player = players.pop_back()
		_ptargets.pop_back()
		_plast.pop_back()
		if is_instance_valid(extra):
			extra.queue_free()
	while players.size() < list.size():
		var p := Player.new()
		p.puppet = true
		p.name = "Puppet%d" % players.size()
		p.setup_remote(players.size(), "?", Color.WHITE)
		world.add_child(p)
		players.append(p)
		_ptargets.append(Vector2.ZERO)
		_plast.append(Vector2.ZERO)
	for i in list.size():
		var entry: Dictionary = list[i]
		var c1 := Color.from_string("#" + str(entry.get("c", "ffffff")), Color.WHITE)
		var c2 := Color.from_string("#" + str(entry.get("c2", "")), c1)
		players[i].set_colors(c1, c2)
		players[i].display_name = str(entry.get("n", "?"))


func _apply_snapshot(m: Dictionary) -> void:
	var ps: Array = m.get("p", [])
	for i in mini(ps.size(), players.size()):
		var arr: Array = ps[i]
		_plast[i] = _ptargets[i]
		_ptargets[i] = Vector2(float(arr[0]), float(arr[1]))
		var p := players[i]
		var was := p.alive
		p.alive = int(arr[2]) == 1
		p.visible = p.alive
		if arr.size() > 5:
			p.armor = int(arr[5]) == 1
		if was and not p.alive:
			var rd := Ragdoll.new()
			rd.color = p.player_color
			rd.color2 = p.color2
			rd.position = _ptargets[i]
			world.add_child(rd)
			get_tree().call_group(&"sfx", &"play_splat", _ptargets[i])
		if i == my_index:
			if not p.alive:
				_status.text = "ELIMINATED — spectating" if int(arr[3]) < 0 \
					else "respawn in %.1f" % (float(arr[3]) / 10.0)
			else:
				_status.text = ""

	var bs: Array = m.get("b", [])
	while bombs.size() > bs.size():
		var extra: Bomb = bombs.pop_back()
		_btargets.pop_back()
		if is_instance_valid(extra):
			extra.queue_free()
	for i in bs.size():
		var arr: Array = bs[i]
		var btype := int(arr[2])
		var brad := float(arr[4])
		if i < bombs.size() and (int(bombs[i].type) != btype
				or absf(bombs[i]._body_radius - brad) > 1.0):
			bombs[i].queue_free()
			bombs[i] = _make_puppet_bomb(btype, brad, Vector2(float(arr[0]), float(arr[1])))
			_btargets[i] = bombs[i].position
		elif i >= bombs.size():
			bombs.append(_make_puppet_bomb(btype, brad, Vector2(float(arr[0]), float(arr[1]))))
			_btargets.append(bombs[i].position)
		_btargets[i] = Vector2(float(arr[0]), float(arr[1]))
		bombs[i].fuse = float(arr[3]) / 10.0

	var cs: Array = m.get("c", [])
	while chests.size() > cs.size():
		var extra: Node2D = chests.pop_back()
		if is_instance_valid(extra):
			extra.queue_free()
	while chests.size() < cs.size():
		var ch := Chest.new()
		ch.puppet = true
		world.add_child(ch)
		chests.append(ch)
	for i in cs.size():
		var arr: Array = cs[i]
		chests[i].position = Vector2(float(arr[0]), float(arr[1]))


func _make_puppet_bomb(btype: int, brad: float, pos: Vector2) -> Bomb:
	var b := Bomb.new()
	b.puppet = true
	b.type = btype as Bomb.Type
	b.is_bomblet = btype == Bomb.Type.CLUSTER and brad < 7.0
	b.position = pos
	world.add_child(b)
	return b


func _clear_entities() -> void:
	for p in players:
		if is_instance_valid(p):
			p.queue_free()
	for b in bombs:
		if is_instance_valid(b):
			b.queue_free()
	for ch in chests:
		if is_instance_valid(ch):
			ch.queue_free()
	players.clear()
	bombs.clear()
	chests.clear()
	_ptargets.clear()
	_plast.clear()
	_btargets.clear()


func _leave(_reason: String) -> void:
	get_tree().change_scene_to_file("res://scenes/menu.tscn")


func _build_backdrops() -> void:
	var wr := terrain.world_rect()
	var sky := ColorRect.new()
	sky.color = Color("8ecae6")
	sky.position = Vector2(wr.position.x - 400, -900)
	sky.size = Vector2(wr.size.x + 800, wr.size.y + 900)
	sky.z_index = -20
	world.add_child(sky)
	var cave := ColorRect.new()
	cave.color = Color("17100a")
	cave.position = Vector2(wr.position.x, terrain.surface_y())
	cave.size = Vector2(wr.size.x, wr.size.y - terrain.surface_y())
	cave.z_index = -15
	world.add_child(cave)


func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.layer = 10
	add_child(_hud)

	_status = Label.new()
	_status.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_status.offset_left = -300
	_status.offset_right = 300
	_status.offset_top = 60
	_status.offset_bottom = 100
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override(&"font_size", 22)
	_status.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_status.add_theme_constant_override(&"outline_size", 5)
	_status.text = "connecting to %s…" % Settings.join_ip
	_hud.add_child(_status)

	var leave := Button.new()
	leave.text = "Leave"
	leave.focus_mode = Control.FOCUS_NONE
	leave.position = Vector2(10, 10)
	leave.pressed.connect(func() -> void: _leave(""))
	_hud.add_child(leave)

	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.55)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.visible = false
	_hud.add_child(overlay)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	_win_label = Label.new()
	_win_label.add_theme_font_size_override(&"font_size", 44)
	_win_label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_win_label.add_theme_constant_override(&"outline_size", 6)
	center.add_child(_win_label)

	if DisplayServer.is_touchscreen_available():
		# Must match the host HUD's construction exactly: the textures anchor
		# the hit shape (no texture = tap area offset from the visuals).
		for cfg: Array in [[&"p1_left", "<"], [&"p1_right", ">"], [&"p1_jump", "^"], [&"p1_kick", "K"]]:
			var b := TouchScreenButton.new()
			b.action = cfg[0]
			b.texture_normal = Hud.circle_tex(64, Color(1, 1, 1, 0.22))
			b.texture_pressed = Hud.circle_tex(64, Color(1, 1, 1, 0.45))
			var shape := CircleShape2D.new()
			shape.radius = 74.0
			b.shape = shape
			b.passby_press = true
			var l := Label.new()
			l.text = cfg[1]
			l.size = Vector2(128, 128)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			l.add_theme_font_size_override(&"font_size", 52)
			l.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.8))
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.add_child(l)
			_hud.add_child(b)
			_touch_buttons.append(b)
		_layout_touch()
		get_viewport().size_changed.connect(_layout_touch)


func _layout_touch() -> void:
	if _touch_buttons.size() < 4:
		return
	var vs := get_viewport().get_visible_rect().size
	_touch_buttons[0].position = Vector2(36, vs.y - 170)
	_touch_buttons[1].position = Vector2(204, vs.y - 170)
	_touch_buttons[2].position = Vector2(vs.x - 170, vs.y - 170)
	_touch_buttons[3].position = Vector2(vs.x - 318, vs.y - 170)
