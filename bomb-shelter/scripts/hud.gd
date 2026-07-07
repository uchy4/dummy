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
		help.text = "Drag = move   •   tap = jump (2nd finger too)   •   swipe 2nd finger (or from your player) = charged kick"
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

	var types_label := _make_label(15, Color(1, 1, 1, 0.9))
	types_label.text = "Bomb types in the mix:"
	vbox.add_child(types_label)
	var type_names := ["Normal", "Big (huge blast)", "Cluster (splits)", "Bouncy",
		"Sticky (kick it!)"]
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
	var upd := Button.new()
	upd.visible = Updater.update_available()
	if upd.visible:
		upd.text = "⬇ Update available — install build %d" % Updater.latest_build
	upd.focus_mode = Control.FOCUS_NONE
	upd.modulate = Color("b9f6ca")
	upd.pressed.connect(func() -> void: Updater.launch_update())
	Updater.update_found.connect(func(b: int) -> void:
		upd.text = "⬇ Update available — install build %d" % b
		upd.visible = true)
	vbox.add_child(upd)
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
	add_child(g)


## Screen position of the local touch player (P1), or INF when unavailable.
func _local_char_screen() -> Vector2:
	var p := _local_touch_player()
	if p == null:
		return Vector2.INF
	return p.get_global_transform_with_canvas().origin


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
