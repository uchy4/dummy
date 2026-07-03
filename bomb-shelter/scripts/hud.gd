class_name Hud
extends CanvasLayer
## All UI, built in code: player status rows, match timer, center messages,
## controls help, and the winner overlay.

var _rows: Array[Label] = []
var _timer: Label
var _center: Label
var _overlay: ColorRect
var _win_title: Label
var _win_sub: Label


func setup(count: int, colors: Array[Color]) -> void:
	layer = 10

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
	help.text = "P1 A/D + W    P2 arrows    P3 J/L + I    P4 F/H + T (or numpad 4/6/8)    R restart\nPush bombs into tunnels — every route dead-ends until a blast opens it. Dirt blocks blasts: shelter!"
	add_child(help)

	_overlay = ColorRect.new()
	_overlay.color = Color(0, 0, 0, 0.55)
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.visible = false
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
	_win_sub.text = "Reached the shelter finish line in %d:%04.1f  —  press Enter for a rematch" \
		% [int(time) / 60, fmod(time, 60.0)]
	_overlay.visible = true


func _make_label(size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", color)
	l.add_theme_color_override(&"font_outline_color", Color.BLACK)
	l.add_theme_constant_override(&"outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
