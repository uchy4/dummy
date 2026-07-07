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

var _status: Label
var _win_label: Label
var _hud: CanvasLayer
var _decor: RoomDecor
var _ceremony: Ceremony
var _game_over := false
var _sent_a := 0.0
var _snap_dt := 0.033
var _last_snap_ms := 0
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

	# Follow-mode tracks this device's own player, matching the web view.
	if camera and not _game_over and my_index >= 0 and my_index < players.size():
		camera.focus_target = players[my_index]
	_animate_puppets(delta)


func _animate_puppets(delta: float) -> void:
	var k := 1.0 - exp(-14.0 * delta)
	for i in players.size():
		var p := players[i]
		if not is_instance_valid(p):
			continue
		if i == my_index and not p.puppet and not p.remote_hold:
			continue  # locally simulated: it moves and animates itself
		var target := _ptargets[i]
		if p.global_position.distance_to(target) > 150.0:
			p.global_position = target
		else:
			p.global_position = p.global_position.lerp(target, k)
		var vx := (target.x - _plast[i].x) * 15.0
		var vy := (target.y - _plast[i].y) * 15.0
		p.velocity = Vector2(vx, vy)
		p.puppet_on_floor = absf(vy) < 30.0
		p.airborne = not p.puppet_on_floor
		if absf(vx) > 20.0:
			p._facing = 1 if vx > 0.0 else -1
		var swing_target := 0.0
		if not p.puppet_stunned and absf(vx) > 20.0 and p.puppet_on_floor:
			p._walk_phase += vx * delta * 0.055
			swing_target = sin(p._walk_phase) * 0.6
		p._swing = lerpf(p._swing, swing_target, 0.35)
		if p.puppet_stunned:
			p._dizzy_phase += delta * 6.0
			if p.puppet_on_floor:
				var dir_sign: float = 1.0 if vx >= 0.0 else -1.0
				p.rotation = 1.1 * dir_sign
			else:
				p.rotation += delta * 3.0
		else:
			p.rotation = 0.0
		p.queue_redraw()
	# Bombs are physics-simulated locally now — no lerp needed.


func _send_inputs() -> void:
	# Analog: keyboard gives -1/0/1, the touch joystick anything in between.
	var a := snappedf(Input.get_axis(&"p1_left", &"p1_right"), 0.01)
	if absf(a) < 0.08:
		a = 0.0
	var j := Input.is_action_pressed(&"p1_jump")
	var kk := Input.is_action_pressed(&"p1_kick")
	if kk and not _sent_k:
		_predict_kick(Vector2.ZERO, 1.0)  # classic kick: instant local feedback
	if a != _sent_a or j != _sent_j or kk != _sent_k:
		_sent_a = a
		_sent_j = j
		_sent_k = kk
		ws.send_text(JSON.stringify({"t": "i", "a": a, "j": 1 if j else 0, "k": 1 if kk else 0}))


func _handle(m: Dictionary) -> void:
	match str(m.get("t", "")):
		"init":
			terrain.load_from_string(str(m.get("grid", "")))
			_apply_rooms(m.get("rooms", []))
			_clear_entities()
			_win_label.get_parent().visible = false
			_status.text = ""
			_game_over = false
			if _ceremony != null and is_instance_valid(_ceremony):
				_ceremony.queue_free()
			_ceremony = null
			if camera:  # fresh match: release the ceremony shot
				camera.set_physics_process(true)
				camera.zoom = Vector2(0.8, 0.8)
				camera.position = Vector2(terrain.world_rect().get_center().x,
					terrain.surface_y() - 60.0)
		"roster":
			_apply_roster(m.get("p", []))
		"you":
			my_index = int(m.get("i", -1))
		"s":
			_apply_snapshot(m)
		"w":
			terrain.apply_water_moves(m.get("m", []), m.get("q", []))
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
		"fx":
			# Only the water-surface ripple (17) is replayed here — other fx
			# kinds are re-derived locally from the snapshot stream.
			if int(m.get("k", -1)) == 17:
				terrain.add_ripple(Vector2(float(m.get("x", 0)), float(m.get("y", 0))),
					float(m.get("p", 0.5)))
		"win":
			_win_label.text = "%s WINS!" % str(m.get("n", "?")).to_upper()
			_win_label.add_theme_color_override(&"font_color",
				Color.from_string("#" + str(m.get("c", "ffffff")), Color.WHITE))
			_win_label.get_parent().visible = true
			get_tree().call_group(&"sfx", &"play_fanfare", Vector2.ZERO)
			_show_ceremony(m.get("podium", []))


## Feed the host's room list into the client terrain so RoomDecor paints
## the same furnished backgrounds (and the finish hall) the host sees.
## Wire kinds: 0 stairs 1 kitchen 2 bedroom 3 bathroom 4 arsenal 5 finish.
func _apply_rooms(rooms: Array) -> void:
	var names: Array[String] = ["stairs", "kitchen", "bedroom", "bathroom", "arsenal"]
	terrain.bunker_rooms = {}
	terrain.finish_room = Rect2i()
	for rm in rooms:
		var ra: Array = rm
		if ra.size() < 5:
			continue
		var rect := Rect2i(int(ra[0]), int(ra[1]), int(ra[2]), int(ra[3]))
		var kind := int(ra[4])
		if kind == 5:
			terrain.finish_room = rect
		elif kind >= 0 and kind < names.size():
			terrain.bunker_rooms[names[kind]] = rect
	# Fresh decor per match (also drops the old map's blast scorch).
	if _decor != null and is_instance_valid(_decor):
		_decor.queue_free()
	_decor = null
	if not terrain.bunker_rooms.is_empty():
		_decor = RoomDecor.new()
		_decor.terrain = terrain
		world.add_child(_decor)


## Mirror the host's ending: cut the camera into the finish hall and stage
## the podium ceremony from the win message's top-three list.
func _show_ceremony(podium: Array) -> void:
	_game_over = true
	if terrain.finish_room.size.x <= 0:
		return
	var fr := terrain.finish_line_rect()
	if camera:
		camera.set_physics_process(false)  # hold the shot on the hall
		camera.global_position = fr.get_center() + Vector2(0, -6.0)
		camera.zoom = Vector2(2.2, 2.2)
	_ceremony = Ceremony.new()
	_ceremony.room = fr
	var entries: Array[Dictionary] = []
	for e in podium:
		var ea: Array = e
		if ea.size() < 3:
			continue
		var c := Color.from_string("#" + str(ea[1]), Color.WHITE)
		entries.append({"n": str(ea[0]), "c": c, "c2": c, "d": int(ea[2])})
	_ceremony.entries = entries
	world.add_child(_ceremony)


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
	var now_ms := Time.get_ticks_msec()
	if _last_snap_ms > 0:
		_snap_dt = clampf(float(now_ms - _last_snap_ms) / 1000.0, 0.016, 0.12)
	_last_snap_ms = now_ms
	_ensure_local_player()
	var ps: Array = m.get("p", [])
	for i in mini(ps.size(), players.size()):
		var arr: Array = ps[i]
		_plast[i] = _ptargets[i]
		_ptargets[i] = Vector2(float(arr[0]), float(arr[1]))
		var p := players[i]
		if i == my_index and not p.puppet:
			_reconcile_local(p, arr)
			continue
		var was := p.alive
		p.alive = int(arr[2]) == 1
		p.visible = p.alive
		if arr.size() > 5:
			p.armor = int(arr[5]) == 1
		if arr.size() > 6:
			var stun_flag: int = arr[6]
			p.puppet_stunned = stun_flag == 1
		else:
			p.puppet_stunned = false
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
		# Locally-simulated bombs: derive velocity from successive snapshot
		# positions, correct drift, and let the physics engine roll them at
		# 60fps between corrections.
		var nt := Vector2(float(arr[0]), float(arr[1]))
		var bb := bombs[i]
		var vel := (nt - _btargets[i]) / _snap_dt
		if vel.length() > 900.0:
			vel = vel.normalized() * 900.0
		bb.linear_velocity = vel
		var berr := nt - bb.global_position
		if berr.length() > 70.0:
			bb.global_position = nt
			bb.reset_physics_interpolation()
		else:
			bb.global_position += berr * 0.3
		_btargets[i] = nt
		bb.fuse = float(arr[3]) / 10.0
		if arr.size() > 5:
			var fz: int = arr[5]
			bb.fizzled = fz == 1

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
	b.sim_puppet = true  # real local physics, host-corrected
	b.terrain = terrain
	b.type = btype as Bomb.Type
	b.is_bomblet = btype == Bomb.Type.CLUSTER and brad < 7.0
	b.position = pos
	world.add_child(b)
	return b


## Swap this device's roster puppet for a real, locally-simulated Player:
## input applies instantly with full native movement feel (coyote time,
## water, everything) and the host stream just reconciles — the same
## treatment the web client already has.
func _ensure_local_player() -> void:
	if my_index < 0 or my_index >= players.size():
		return
	var pup := players[my_index]
	if not is_instance_valid(pup) or not pup.puppet:
		return
	var lp := Player.new()
	lp.name = "LocalPlayer"
	lp.setup(0, pup.player_color)  # drives from the p1_* input actions
	lp.set_colors(pup.player_color, pup.color2)
	lp.display_name = pup.display_name
	lp.world_bounds = Rect2(-100000, -100000, 200000, 200000)  # host decides deaths
	lp.position = pup.position
	world.add_child(lp)
	pup.queue_free()
	players[my_index] = lp
	if camera:
		camera.focus_target = lp


## Reconcile the locally-simulated player against the host snapshot.
func _reconcile_local(p: Player, arr: Array) -> void:
	var target := Vector2(float(arr[0]), float(arr[1]))
	var was := p.alive
	var alive_now := int(arr[2]) == 1
	if arr.size() > 5:
		p.armor = int(arr[5]) == 1
	var stunned := arr.size() > 6 and int(arr[6]) == 1
	var had_hold := p.remote_hold
	p.alive = alive_now
	p.visible = alive_now
	p.puppet_stunned = stunned
	p.remote_hold = (not alive_now) or stunned
	if was and not alive_now:
		var rd := Ragdoll.new()
		rd.color = p.player_color
		rd.color2 = p.color2
		rd.position = target
		world.add_child(rd)
		get_tree().call_group(&"sfx", &"play_splat", target)
	if not alive_now:
		_status.text = "ELIMINATED — spectating" if int(arr[3]) < 0 \
			else "respawn in %.1f" % (float(arr[3]) / 10.0)
	else:
		_status.text = ""
	if p.remote_hold:
		return  # _animate_puppets lerps us along the host stream
	if had_hold:
		# Just got back control (respawn / stun over): resume from host truth.
		p.global_position = target
		p.velocity = Vector2.ZERO
		p.rotation = 0.0
		p.reset_physics_interpolation()
		return
	var err := target - p.global_position
	if err.length() > 90.0:
		p.global_position = target
		p.velocity = Vector2.ZERO
		p.reset_physics_interpolation()
	else:
		p.global_position += err * 0.22


## Local kick feedback: fling nearby simulated bombs the moment we kick —
## the host snapshot corrects any difference a beat later.
func _predict_kick(dir: Vector2, power: float) -> void:
	if my_index < 0 or my_index >= players.size():
		return
	var p := players[my_index]
	if not is_instance_valid(p) or p.puppet or p.remote_hold:
		return
	var fdir := dir
	if fdir == Vector2.ZERO:
		fdir = Vector2(float(p._facing), -1).normalized()
	var center := p.global_position + Vector2(float(p._facing) * 10.0, 0)
	for b in bombs:
		if is_instance_valid(b) \
				and center.distance_to(b.global_position) <= 30.0 + b._body_radius:
			b.linear_velocity = fdir * Settings.kick_bomb_power * power


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
	cave.color = Color("2b1a0c")  # match the host backdrop (and scorch color)
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

	# Nearly-clear overlay + top banner, so the in-world podium ceremony in
	# the finish hall stays visible underneath.
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.12)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.visible = false
	_hud.add_child(overlay)
	_win_label = Label.new()
	_win_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_win_label.offset_left = -360
	_win_label.offset_right = 360
	_win_label.offset_top = 100
	_win_label.offset_bottom = 160
	_win_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_win_label.add_theme_font_size_override(&"font_size", 40)
	_win_label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_win_label.add_theme_constant_override(&"outline_size", 6)
	overlay.add_child(_win_label)

	if DisplayServer.is_touchscreen_available():
		# Same gesture controls as the host: invisible thumb joystick + tap
		# jump feed the P1 actions (picked up by _send_inputs); a charged
		# kick goes straight to the host as a "k" message.
		var g := TouchGestures.new()
		g.char_screen = _my_char_screen
		g.axis_changed.connect(_on_gesture_axis)
		g.jump_tapped.connect(_on_gesture_jump)
		g.kick_charged.connect(_on_gesture_kick)
		g.jump_down.connect(func() -> void: Input.action_press(&"p1_jump"))
		g.jump_up.connect(func() -> void: Input.action_release(&"p1_jump"))
		_hud.add_child(g)


## Screen position of my own puppet, or INF when not spawned/alive.
func _my_char_screen() -> Vector2:
	if my_index < 0 or my_index >= players.size():
		return Vector2.INF
	var p := players[my_index]
	if not is_instance_valid(p) or not p.visible:
		return Vector2.INF
	return p.get_global_transform_with_canvas().origin


func _on_gesture_axis(v: float) -> void:
	Input.action_release(&"p1_left")
	Input.action_release(&"p1_right")
	if v > 0.0:
		Input.action_press(&"p1_right", v)
	elif v < 0.0:
		Input.action_press(&"p1_left", -v)


func _on_gesture_jump() -> void:
	Input.action_press(&"p1_jump")
	get_tree().create_timer(0.12).timeout.connect(
		func() -> void: Input.action_release(&"p1_jump"))


func _on_gesture_kick(dir: Vector2, power: float) -> void:
	var d := dir
	if d == Vector2.ZERO:
		# Double-tap "use facing" kick: aim it with our puppet's facing.
		var f := 1.0
		if my_index >= 0 and my_index < players.size() \
				and is_instance_valid(players[my_index]):
			f = float(players[my_index]._facing)
		d = Vector2(f, -1).normalized()
	if ws and ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.send_text(JSON.stringify({"t": "k",
			"dx": snappedf(d.x, 0.01), "dy": snappedf(d.y, 0.01),
			"p": snappedf(power, 0.01)}))
	_predict_kick(d, power)
