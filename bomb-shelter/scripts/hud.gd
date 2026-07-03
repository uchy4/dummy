class_name Hud
extends CanvasLayer
## All UI, built in code: player status rows, match timer, center messages,
## controls help, and the winner overlay.

signal restart_requested

var _rows: Array[Label] = []
var _timer: Label
var _center: Label
var _overlay: ColorRect
var _win_title: Label
var _win_sub: Label
var _touch := false
var _touch_buttons: Array[TouchScreenButton] = []


func setup(count: int, colors: Array[Color], touch := false) -> void:
	layer = 10
	_touch = touch

	var rows := VBoxContainer.new()
	rows.position = Vector2(14, 12)
	add_child(rows)
	for i in count:
		var l := _make_label(18, colors[i])
		rows.add_child(l)
		_rows.append(l)

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
		help.text = "Push bombs into tunnels — every route dead-ends until a blast opens it. Dirt blocks blasts: shelter!"
	else:
		help.text = "P1 A/D + W    P2 arrows    P3 J/L + I    P4 F/H + T (or numpad 4/6/8)    R restart\nPush bombs into tunnels — every route dead-ends until a blast opens it. Dirt blocks blasts: shelter!"
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

	if touch:
		_build_touch_controls()


func set_player_status(i: int, text: String) -> void:
	_rows[i].text = text


func set_timer(t: float) -> void:
	_timer.text = "%d:%04.1f" % [int(t) / 60, fmod(t, 60.0)]


func set_center(text: String) -> void:
	_center.text = text
	_center.visible = not text.is_empty()


func show_winner(index: int, color: Color, time: float) -> void:
	_win_title.text = "PLAYER %d WINS!" % (index + 1)
	_win_title.add_theme_color_override(&"font_color", color)
	var again := "tap anywhere for a rematch" if _touch else "press Enter for a rematch"
	_win_sub.text = "Reached the finish line in %d:%04.1f  —  %s" \
		% [int(time) / 60, fmod(time, 60.0), again]
	_overlay.visible = true


func _on_overlay_input(ev: InputEvent) -> void:
	if (ev is InputEventMouseButton or ev is InputEventScreenTouch) and ev.is_pressed():
		restart_requested.emit()


# On-screen controls for touch devices: left/right under the left thumb,
# jump under the right. TouchScreenButton fires the same input actions the
# keyboard uses, so the player script needs no changes.
func _build_touch_controls() -> void:
	for cfg: Array in [[&"p1_left", "<"], [&"p1_right", ">"], [&"p1_jump", "^"]]:
		var b := TouchScreenButton.new()
		b.action = cfg[0]
		b.texture_normal = _circle_tex(64, Color(1, 1, 1, 0.22))
		b.texture_pressed = _circle_tex(64, Color(1, 1, 1, 0.45))
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
		add_child(b)
		_touch_buttons.append(b)
	_layout_touch()
	get_viewport().size_changed.connect(_layout_touch)


func _layout_touch() -> void:
	var vs := get_viewport().get_visible_rect().size
	_touch_buttons[0].position = Vector2(36, vs.y - 170)
	_touch_buttons[1].position = Vector2(204, vs.y - 170)
	_touch_buttons[2].position = Vector2(vs.x - 170, vs.y - 170)


func _circle_tex(radius: int, color: Color) -> ImageTexture:
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
