class_name Hud
extends CanvasLayer
## All UI, built in code: player status rows, match timer, center messages,
## controls help, and the winner overlay.

signal restart_requested
signal settings_pressed
signal reset_players_pressed
signal player_color_changed(index: int, color: Color)

var _rows: Array[Label] = []
var _rows_box: VBoxContainer
var _timer: Label
var _center: Label
var _overlay: ColorRect
var _win_title: Label
var _win_sub: Label
var _settings: PanelContainer
var _qr_overlay: Control
var _qr_texture: TextureRect
var _qr_url: Label
var _touch := false
var _upd_btn: Button
var _podium: PodiumView


func setup(colors: Array[Color], touch := false) -> void:
	layer = 10
	_touch = touch

	_rows_box = VBoxContainer.new()
	_rows_box.position = Vector2(14, 12)
	add_child(_rows_box)
	for c in colors:
		add_player_row(c)

	_timer = _make_label(18, Color.WHITE)
	_timer.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_timer.offset_left = -180
	_timer.offset_right = -14
	_timer.offset_top = 12
	_timer.offset_bottom = 40
	_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_timer)

	_center = _make_label(28, Color.WHITE)
	_center.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_center.offset_left = -420
	_center.offset_right = 420
	_center.offset_top = 70
	_center.offset_bottom = 120
	_center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_center)

	var help := _make_label(14, Color(1, 1, 1, 0.85))
	help.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	help.offset_top = -56
	help.offset_bottom = -8
	help.offset_left = 10
	help.offset_right = -10
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if touch:
		help.text = "Drag = move  •  ▲ = jump  •  KICK: tap = quick kick, hold + pull = aimed charge  •  ⇄ swaps sides"
	else:
		help.text = "P1 A/D W S-kick    P2 arrows ↓-kick    P3 J/L I K-kick    P4 F/H T G-kick    R restart    Esc settings\nKick bombs into tunnels — every route dead-ends until a blast opens it. Dirt blocks blasts: shelter!"
	add_child(help)

	_overlay = ColorRect.new()
	_overlay.color = Color(0, 0, 0, 0.55)
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.visible = false
	_overlay.gui_input.connect(_on_overlay_input)
	add_child(_overlay)

	var center_box := CenterContainer.new()
	center_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center_box)
	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	center_box.add_child(vbox)
	_win_title = _make_label(48, Color.WHITE)
	_win_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_win_title)
	_win_sub = _make_label(20, Color(1, 1, 1, 0.9))
	_win_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_win_sub)

	var gear := Button.new()
	gear.text = "⚙ settings"
	gear.focus_mode = Control.FOCUS_NONE
	gear.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	gear.offset_left = -180
	gear.offset_right = -14
	gear.offset_top = 44
	gear.offset_bottom = 76
	gear.pressed.connect(func() -> void: settings_pressed.emit())
	add_child(gear)
	_build_settings_panel()

	if touch:
		_build_touch_controls()


func add_player_row(color: Color) -> void:
	var l := _make_label(18, color)
	_rows_box.add_child(l)
	_rows.append(l)


func set_row_color(i: int, color: Color) -> void:
	if i < _rows.size():
		_rows[i].add_theme_color_override(&"font_color", color)


func set_player_status(i: int, text: String) -> void:
	if i < _rows.size():
		_rows[i].text = text


func set_timer(t: float) -> void:
	_timer.text = "%d:%04.1f" % [int(t) / 60, fmod(t, 60.0)]


func set_center(text: String) -> void:
	_center.text = text
	_center.visible = not text.is_empty()


func show_winner(winner_name: String, color: Color, time: float,
		reason := "Reached the finish line") -> void:
	_win_title.text = "%s WINS!" % winner_name.to_upper()
	_win_title.add_theme_color_override(&"font_color", color)
	var again := "tap anywhere for a rematch" if _touch else "press Enter for a rematch"
	_win_sub.text = "%s in %d:%04.1f  —  %s" \
		% [reason, int(time) / 60, fmod(time, 60.0), again]
	_overlay.visible = true


## End-of-match ceremony: 1st/2nd/3rd on a checkered podium, ranked by
## depth, jumping and waving. entries: [{n, c, c2, d}] sorted best-first.
func show_podium(entries: Array[Dictionary], time: float, reason: String) -> void:
	if _podium == null:
		_podium = PodiumView.new()
		var vbox := _win_title.get_parent()
		vbox.add_child(_podium)
		vbox.move_child(_podium, _win_title.get_index() + 1)
	_podium.entries.assign(entries.slice(0, 3))
	if entries.is_empty():
		_win_title.text = "NOBODY WINS"
		_win_title.add_theme_color_override(&"font_color", Color(0.8, 0.8, 0.8))
	else:
		var w: Dictionary = entries[0]
		_win_title.text = "%s WINS!" % str(w.n).to_upper()
		_win_title.add_theme_color_override(&"font_color", w.c)
	var again := "tap anywhere for a rematch" if _touch else "press Enter for a rematch"
	_win_sub.text = "%s  —  %d:%04.1f  —  %s" \
		% [reason, int(time) / 60, fmod(time, 60.0), again]
	_overlay.visible = true


## The animated podium: checkered stage, gold/silver/bronze steps, winners
## jumping and waving their arms. Runs while the tree is paused (the HUD
## lives under Main, which is PROCESS_MODE_ALWAYS).
class PodiumView:
	extends Control
	var entries: Array[Dictionary] = []
	var _t := 0.0

	func _ready() -> void:
		custom_minimum_size = Vector2(400, 235)

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var sq := 20.0
		for r in int(ceil(size.y / sq)):
			for c in int(ceil(size.x / sq)):
				var col := Color(0.9, 0.9, 0.9) if (r + c) % 2 == 0 \
					else Color(0.1, 0.1, 0.1)
				draw_rect(Rect2(c * sq, r * sq, sq, minf(sq, size.y - r * sq)), col)
		var base := size.y - 16.0
		var step_w := 96.0
		var mid := size.x / 2.0
		var font := ThemeDB.fallback_font
		var defs: Array[Dictionary] = [
			{"slot": 1, "x": mid - step_w * 1.5, "h": 52.0},
			{"slot": 0, "x": mid - step_w * 0.5, "h": 80.0},
			{"slot": 2, "x": mid + step_w * 0.5, "h": 34.0},
		]
		var step_cols: Array[Color] = [
			Color("c9a227"), Color("b7bec9"), Color("a06a3d"),
		]
		for d: Dictionary in defs:
			var slot: int = d.slot
			var x: float = d.x
			var h: float = d.h
			draw_rect(Rect2(x + 2, base - h + 2, step_w - 4, h), Color(0, 0, 0, 0.6))
			draw_rect(Rect2(x + 4, base - h + 4, step_w - 8, h - 4), step_cols[slot])
			if font != null:
				draw_string(font, Vector2(x, base - h + 28), str(slot + 1),
					HORIZONTAL_ALIGNMENT_CENTER, step_w, 24, Color(0, 0, 0, 0.65))
			if slot >= entries.size():
				continue
			var e: Dictionary = entries[slot]
			var jump := absf(sin(_t * 4.0 + slot * 0.9)) * (15.0 if slot == 0 else 9.0)
			_guy(Vector2(x + step_w / 2.0, base - h - 15.0 - jump), e.c, e.c2, slot)
			if font != null:
				draw_string(font, Vector2(x - 16, base + 14),
					"%s  · %d deep" % [str(e.n), int(e.d)],
					HORIZONTAL_ALIGNMENT_CENTER, step_w + 32, 13, Color.WHITE)

	func _guy(at: Vector2, c1v: Variant, c2v: Variant, i: int) -> void:
		var c1: Color = c1v
		var c2: Color = c2v
		var wave := sin(_t * 9.0 + i * 1.7) * 0.45
		# Arms thrown up, waving.
		for s: float in [-1.0, 1.0]:
			draw_set_transform(at + Vector2(6.0 * s, -6.0), (-2.35 + wave) * s, Vector2.ONE)
			draw_rect(Rect2(-2, -1, 4, 13), Color.BLACK)
			draw_rect(Rect2(-1.5, 0, 3, 11), c1.darkened(0.18))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_rect(Rect2(at.x - 5, at.y + 3, 4, 12), c1.darkened(0.4))
		draw_rect(Rect2(at.x + 1, at.y + 3, 4, 12), c1.darkened(0.4))
		draw_rect(Rect2(at.x - 7, at.y - 8, 14, 13), Color.BLACK)
		draw_rect(Rect2(at.x - 6, at.y - 7, 12, 11), c1)
		if not c1.is_equal_approx(c2):
			draw_rect(Rect2(at.x - 6, at.y - 4.5, 12, 2.5), c2)
			draw_rect(Rect2(at.x - 6, at.y, 12, 2.5), c2)
		draw_rect(Rect2(at.x - 5, at.y - 17, 10, 9), c1.lightened(0.35))
		draw_rect(Rect2(at.x - 6, at.y - 19, 12, 4), c1.lightened(0.15))
		draw_rect(Rect2(at.x - 3, at.y - 14, 2, 3), Color.WHITE)
		draw_rect(Rect2(at.x + 1, at.y - 14, 2, 3), Color.WHITE)


func _on_overlay_input(ev: InputEvent) -> void:
	if (ev is InputEventMouseButton or ev is InputEventScreenTouch) and ev.is_pressed():
		restart_requested.emit()


func show_settings(open: bool) -> void:
	_settings.visible = open


# The Quick Settings panel: live gameplay tuning while the game is paused.
# Values write straight into Settings statics, so they apply the moment you
# resume and survive rematches.
func _build_settings_panel() -> void:
	_settings = PanelContainer.new()
	_settings.set_anchors_preset(Control.PRESET_CENTER)
	_settings.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_settings.grow_vertical = Control.GROW_DIRECTION_BOTH
	_settings.visible = false
	add_child(_settings)

	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 20)
	_settings.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override(&"separation", 8)
	margin.add_child(vbox)

	var title := _make_label(22, Color.WHITE)
	title.text = "QUICK SETTINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var cam_follow := CheckBox.new()
	cam_follow.text = "Camera follows one player (else whole group)"
	cam_follow.button_pressed = Settings.camera_follow
	cam_follow.focus_mode = Control.FOCUS_NONE
	cam_follow.toggled.connect(func(on: bool) -> void: Settings.camera_follow = on)
	vbox.add_child(cam_follow)

	var one_life := CheckBox.new()
	one_life.text = "One life — elimination (last standing wins)"
	one_life.button_pressed = Settings.one_life
	one_life.focus_mode = Control.FOCUS_NONE
	one_life.toggled.connect(func(on: bool) -> void: Settings.one_life = on)
	vbox.add_child(one_life)

	var duds := CheckBox.new()
	duds.text = "10% duds (fizzle out; blasts can set them off)"
	duds.button_pressed = Settings.duds_enabled
	duds.focus_mode = Control.FOCUS_NONE
	duds.toggled.connect(func(on: bool) -> void: Settings.duds_enabled = on)
	vbox.add_child(duds)

	if not (OS.has_feature("mode2d") or OS.has_feature("mode3d")):
		# Flavor APKs are locked to their renderer; only dev builds can switch.
		var mode3d := CheckBox.new()
		mode3d.text = "2.5D graphics (applies on restart, R)"
		mode3d.button_pressed = Settings.mode_3d
		mode3d.focus_mode = Control.FOCUS_NONE
		mode3d.toggled.connect(func(on: bool) -> void: Settings.mode_3d = on)
		vbox.add_child(mode3d)

	_add_slider(vbox, "Bots — hard AI (applies on restart, R)", 0.0, 4.0, 1.0,
		float(Settings.bot_count),
		func(v: float) -> void: Settings.bot_count = int(v))
	_add_slider(vbox, "Bombs per drop (at max difficulty)", 1.0, 6.0, 1.0,
		float(Settings.bombs_per_drop),
		func(v: float) -> void: Settings.bombs_per_drop = int(v))
	_add_slider(vbox, "Seconds between drops (start)", 0.6, 6.0, 0.1,
		Settings.drop_interval,
		func(v: float) -> void: Settings.drop_interval = v)
	_add_slider(vbox, "Ramp-up time to max (seconds)", 30.0, 300.0, 5.0,
		Settings.ramp_time,
		func(v: float) -> void: Settings.ramp_time = v)
	_add_slider(vbox, "Camera zoom", 0.6, 2.2, 0.05,
		Settings.zoom_scale,
		func(v: float) -> void: Settings.zoom_scale = v)
	_add_slider(vbox, "Blast size", 0.5, 2.5, 0.05,
		Settings.blast_scale,
		func(v: float) -> void: Settings.blast_scale = v)
	_add_slider(vbox, "Bomb kick power", 100.0, 900.0, 10.0,
		Settings.kick_bomb_power,
		func(v: float) -> void: Settings.kick_bomb_power = v)
	_add_slider(vbox, "Player kick power", 0.0, 700.0, 10.0,
		Settings.kick_player_power,
		func(v: float) -> void: Settings.kick_player_power = v)
	_add_slider(vbox, "Stun time (seconds)", 0.0, 3.0, 0.1,
		Settings.stun_time,
		func(v: float) -> void: Settings.stun_time = v)

	if _touch:
		var side_cb := CheckBox.new()
		side_cb.text = "Touch buttons on the LEFT side"
		side_cb.button_pressed = Settings.touch_buttons_left
		side_cb.focus_mode = Control.FOCUS_NONE
		side_cb.toggled.connect(func(on: bool) -> void: Settings.touch_buttons_left = on)
		vbox.add_child(side_cb)

	var types_label := _make_label(15, Color(1, 1, 1, 0.9))
	types_label.text = "Bomb types in the mix:"
	vbox.add_child(types_label)
	var type_names := ["Normal", "Big (huge blast)", "Cluster (splits)", "Bouncy",
		"Sticky (kick it!)", "Shockwave (5x launch)",
		"Drill (digs 5 deep)", "Anvil (blasts down)"]
	var grid := GridContainer.new()
	grid.columns = 2
	vbox.add_child(grid)
	for i in type_names.size():
		var cb := CheckBox.new()
		cb.text = type_names[i]
		cb.button_pressed = Settings.type_enabled[i]
		cb.focus_mode = Control.FOCUS_NONE
		cb.toggled.connect(func(on: bool) -> void: Settings.type_enabled[i] = on)
		grid.add_child(cb)

	var colors_label := _make_label(15, Color(1, 1, 1, 0.9))
	colors_label.text = "Player colors:"
	vbox.add_child(colors_label)
	var colors_row := HBoxContainer.new()
	colors_row.add_theme_constant_override(&"separation", 10)
	vbox.add_child(colors_row)
	for i in Settings.player_colors.size():
		var box := VBoxContainer.new()
		var tag := _make_label(13, Color(1, 1, 1, 0.8))
		tag.text = "P%d" % (i + 1)
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(tag)
		var picker := ColorPickerButton.new()
		picker.color = Settings.player_colors[i]
		picker.custom_minimum_size = Vector2(52, 34)
		picker.focus_mode = Control.FOCUS_NONE
		picker.color_changed.connect(func(c: Color) -> void: player_color_changed.emit(i, c))
		box.add_child(picker)
		colors_row.add_child(box)

	# In-place update button: only shows when the launch check found a newer
	# CI build. Same signing key, so Android installs it over this build.
	# Method connection to the autoload — a lambda would outlive this HUD
	# and crash poking the freed button after a restart.
	_upd_btn = Button.new()
	_upd_btn.visible = Updater.update_available()
	if _upd_btn.visible:
		_upd_btn.text = "⬇ Update available — install build %d" % Updater.latest_build
	_upd_btn.focus_mode = Control.FOCUS_NONE
	_upd_btn.modulate = Color("b9f6ca")
	_upd_btn.pressed.connect(func() -> void: Updater.launch_update())
	Updater.update_found.connect(_on_update_found)
	vbox.add_child(_upd_btn)
	if BuildInfo.BUILD > 0:
		var ver := _make_label(12, Color(1, 1, 1, 0.5))
		ver.text = "this device: build %d" % BuildInfo.BUILD
		vbox.add_child(ver)

	var reset := Button.new()
	reset.text = "Reset players to shelter"
	reset.focus_mode = Control.FOCUS_NONE
	reset.pressed.connect(func() -> void: reset_players_pressed.emit())
	vbox.add_child(reset)

	var qr := Button.new()
	qr.text = "Show web-join QR  (friends join from their phone)"
	qr.focus_mode = Control.FOCUS_NONE
	qr.pressed.connect(_show_qr)
	vbox.add_child(qr)

	var online := Button.new()
	online.text = "🌐 Host ONLINE room  (friends in other cities)"
	online.focus_mode = Control.FOCUS_NONE
	online.pressed.connect(_show_online)
	vbox.add_child(online)

	var resume := Button.new()
	resume.text = "Resume"
	resume.focus_mode = Control.FOCUS_NONE
	resume.pressed.connect(func() -> void: settings_pressed.emit())
	vbox.add_child(resume)


# Fullscreen QR overlay: scan with a phone on the same Wi-Fi to open the
# controller page and join the match.
func _show_qr() -> void:
	if _qr_overlay == null:
		_build_qr_overlay()
	var url: String = NetHub.join_url()
	_qr_texture.texture = ImageTexture.create_from_image(Qr.make_image(url))
	_qr_url.text = url + "\n(phone must be on the same Wi-Fi)"
	_qr_overlay.visible = true


## Internet room via the relay: opens (or reuses) the room and shows the
## code + link + QR that friends anywhere can use from a browser.
func _show_online() -> void:
	if _qr_overlay == null:
		_build_qr_overlay()
	if NetHub.RELAY_HOST.is_empty():
		_qr_texture.texture = null
		_qr_url.text = "Online rooms need the relay deployed:\nsee bomb-shelter/relay/README.md"
		_qr_overlay.visible = true
		return
	NetHub.start_relay()
	if NetHub.relay_code.is_empty():
		_qr_texture.texture = null
		_qr_url.text = "opening online room…"
	else:
		_on_relay_ready(NetHub.relay_code)
	_qr_overlay.visible = true
	if not NetHub.relay_ready.is_connected(_on_relay_ready):
		NetHub.relay_ready.connect(_on_relay_ready)


func _on_relay_ready(code: String) -> void:
	if _qr_overlay == null or _qr_url == null:
		return
	var url: String = NetHub.relay_page_url()
	_qr_texture.texture = ImageTexture.create_from_image(Qr.make_image(url))
	_qr_url.text = "ROOM CODE: %s\n%s\n(anyone, anywhere — send them the link)" % [code, url]


func _build_qr_overlay() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.8)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_qr_overlay = dim

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override(&"separation", 12)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(vbox)

	var title := _make_label(26, Color.WHITE)
	title.text = "SCAN TO JOIN"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var frame := PanelContainer.new()
	vbox.add_child(frame)
	_qr_texture = TextureRect.new()
	_qr_texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_qr_texture.custom_minimum_size = Vector2(300, 300)
	_qr_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_qr_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	frame.add_child(_qr_texture)

	_qr_url = _make_label(18, Color(1, 1, 1, 0.9))
	_qr_url.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_qr_url)

	var close := Button.new()
	close.text = "Close"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func() -> void: _qr_overlay.visible = false)
	vbox.add_child(close)


func _add_slider(parent: Control, text: String, mn: float, mx: float,
		step: float, value: float, setter: Callable) -> void:
	var row_label := _make_label(15, Color(1, 1, 1, 0.9))
	parent.add_child(row_label)
	var s := HSlider.new()
	s.min_value = mn
	s.max_value = mx
	s.step = step
	s.custom_minimum_size = Vector2(340, 24)
	s.focus_mode = Control.FOCUS_NONE
	var update := func(v: float) -> void:
		row_label.text = "%s:  %s" % [text, String.num(v, 2)]
		setter.call(v)
	s.value_changed.connect(update)
	s.value = value
	update.call(value)
	parent.add_child(s)


# Touch controls: an invisible joystick that appears under the thumb, quick
# tap = jump, press your character + swipe = charged directional kick. Axis
# and jump feed the same P1 input actions the keyboard uses, so the player
# script needs no changes; charged kicks go straight to queue_kick().
func _build_touch_controls() -> void:
	var g := TouchGestures.new()
	g.char_screen = _local_char_screen
	g.axis_changed.connect(_on_gesture_axis)
	g.jump_tapped.connect(_on_gesture_jump)
	g.kick_charged.connect(_on_gesture_kick)
	g.jump_down.connect(func() -> void: Input.action_press(&"p1_jump"))
	g.jump_up.connect(func() -> void: Input.action_release(&"p1_jump"))
	add_child(g)


## Screen position of the local touch player (P1), or INF when unavailable.
func _local_char_screen() -> Vector2:
	var p := _local_touch_player()
	if p == null:
		return Vector2.INF
	return p.get_global_transform_with_canvas().origin


func _on_update_found(b: int) -> void:
	if is_instance_valid(_upd_btn):
		_upd_btn.text = "⬇ Update available — install build %d" % b
		_upd_btn.visible = true


func _local_touch_player() -> Player:
	for n in get_tree().get_nodes_in_group(&"players"):
		var p := n as Player
		if p and p.index == 0 and not p.puppet and not p.remote and p.alive:
			return p
	return null


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
	var p := _local_touch_player()
	if p:
		p.queue_kick(dir, power)


static func circle_tex(radius: int, color: Color) -> ImageTexture:
	var s := radius * 2
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in s:
		for x in s:
			var d := Vector2(x - radius + 0.5, y - radius + 0.5).length()
			if d <= radius - 4.0:
				img.set_pixel(x, y, color)
			elif d <= radius:
				img.set_pixel(x, y, Color(color.r, color.g, color.b, minf(color.a + 0.3, 1.0)))
	return ImageTexture.create_from_image(img)


func _make_label(size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", color)
	l.add_theme_color_override(&"font_outline_color", Color.BLACK)
	l.add_theme_constant_override(&"outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
