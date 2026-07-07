class_name TouchGestures
extends Control
## Invisible touch controls. Touch-and-drag anywhere summons a joystick under
## the thumb (horizontal drag = move axis), a quick tap jumps, and pressing on
## your own character then swiping away winds up a charged directional kick,
## with a power bar over the character and a dotted trajectory preview.
##
## Emits signals only — the host HUD injects P1 input actions from them and
## the LAN client forwards them over the wire, so both share this node.

signal axis_changed(value: float)
signal jump_tapped
signal kick_charged(dir: Vector2, power: float)

const TAP_TIME := 0.22       ## max seconds for a touch to count as a tap
const TAP_SLOP := 14.0       ## max px of travel for a tap
const DEAD_ZONE := 8.0       ## joystick px before the axis engages
const AXIS_RANGE := 46.0     ## px of drag for a full-speed axis
const CHAR_GRAB := 60.0      ## px around the character that starts a kick
const FULL_CHARGE := 95.0    ## swipe px for a 100% power kick
const MIN_POWER := 0.25

## Returns the local character's screen position, or Vector2.INF when there
## isn't one (dead, not spawned). Supplied by the owner.
var char_screen: Callable = func() -> Vector2: return Vector2.INF
## Launch speed (px/s) at full charge — drives the trajectory preview.
var kick_speed: Callable = func() -> float: return Settings.kick_bomb_power

var _move_idx := -1
var _move_origin := Vector2.ZERO
var _move_pos := Vector2.ZERO
var _move_ms := 0
var _kick_idx := -1
var _kick_origin := Vector2.ZERO
var _kick_pos := Vector2.ZERO
var _kick_ms := 0
## Second finger while the joystick is held: tap = jump, swipe = charged
## kick — so you can jump and kick without stopping.
var _gest_idx := -1
var _gest_origin := Vector2.ZERO
var _gest_pos := Vector2.ZERO
var _gest_ms := 0
var _axis := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	if _move_idx != -1 or _kick_idx != -1 or _gest_idx != -1:
		queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_touch_down(t.index, t.position)
		else:
			_touch_up(t.index)
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		_touch_move(d.index, d.position)


func _touch_down(idx: int, pos: Vector2) -> void:
	var cs: Vector2 = char_screen.call()
	if _kick_idx == -1 and _gest_idx == -1 \
			and cs != Vector2.INF and pos.distance_to(cs) <= CHAR_GRAB:
		_kick_idx = idx
		_kick_origin = pos
		_kick_pos = pos
		_kick_ms = Time.get_ticks_msec()
		return
	if _move_idx == -1:
		_move_idx = idx
		_move_origin = pos
		_move_pos = pos
		_move_ms = Time.get_ticks_msec()
		return
	if _gest_idx == -1:
		_gest_idx = idx
		_gest_origin = pos
		_gest_pos = pos
		_gest_ms = Time.get_ticks_msec()


func _touch_move(idx: int, pos: Vector2) -> void:
	if idx == _move_idx:
		_move_pos = pos
		var dx := pos.x - _move_origin.x
		var v := 0.0 if absf(dx) < DEAD_ZONE else clampf(dx / AXIS_RANGE, -1.0, 1.0)
		if v != _axis:
			_axis = v
			axis_changed.emit(v)
	elif idx == _kick_idx:
		_kick_pos = pos
	elif idx == _gest_idx:
		_gest_pos = pos


func _touch_up(idx: int) -> void:
	if idx == _move_idx:
		var quick := Time.get_ticks_msec() - _move_ms < TAP_TIME * 1000.0 \
			and _move_pos.distance_to(_move_origin) < TAP_SLOP
		_move_idx = -1
		if _axis != 0.0:
			_axis = 0.0
			axis_changed.emit(0.0)
		if quick:
			jump_tapped.emit()
		queue_redraw()
	elif idx == _kick_idx:
		var d := _kick_pos - _kick_origin
		var quick := Time.get_ticks_msec() - _kick_ms < TAP_TIME * 1000.0
		_kick_idx = -1
		_end_tap_or_kick(d, quick)
	elif idx == _gest_idx:
		var d := _gest_pos - _gest_origin
		var quick := Time.get_ticks_msec() - _gest_ms < TAP_TIME * 1000.0
		_gest_idx = -1
		_end_tap_or_kick(d, quick)


## Shared release logic for the on-character press and the second finger:
## a short tap jumps, a swipe fires a charged kick along the swipe.
func _end_tap_or_kick(d: Vector2, quick: bool) -> void:
	if d.length() < TAP_SLOP:
		if quick:
			jump_tapped.emit()
	else:
		kick_charged.emit(d.normalized(),
			clampf(d.length() / FULL_CHARGE, MIN_POWER, 1.0))
	queue_redraw()


func _draw() -> void:
	# Joystick: ring at the touch origin, knob clamped to the axis range.
	if _move_idx != -1:
		draw_arc(_move_origin, 40.0, 0.0, TAU, 40, Color(1, 1, 1, 0.5), 2.0, true)
		var knob_x := clampf(_move_pos.x - _move_origin.x, -40.0, 40.0)
		draw_circle(_move_origin + Vector2(knob_x, 0), 20.0, Color(1, 1, 1, 0.3))
	# Kick charge: power bar over the character + dotted trajectory preview
	# (from the on-character press or the second finger, whichever is live).
	if _kick_idx != -1 or _gest_idx != -1:
		var d := _kick_pos - _kick_origin if _kick_idx != -1 \
			else _gest_pos - _gest_origin
		if d.length() < TAP_SLOP:
			return
		var cs: Vector2 = char_screen.call()
		if cs == Vector2.INF:
			return
		var power := clampf(d.length() / FULL_CHARGE, MIN_POWER, 1.0)
		draw_rect(Rect2(cs.x - 26, cs.y - 56, 52, 9), Color(0, 0, 0, 0.55))
		var bar := Color(0.61, 0.8, 0.4)
		if power > 0.8:
			bar = Color(1.0, 0.32, 0.32)
		elif power > 0.5:
			bar = Color(1.0, 0.79, 0.16)
		draw_rect(Rect2(cs.x - 24, cs.y - 54, 48.0 * power, 5), bar)
		# The camera canvas transform is translate+scale only, so a world
		# trajectory maps to the screen with a single scale factor.
		var scl: float = get_viewport().get_canvas_transform().get_scale().x
		var dir := d.normalized()
		var speed: float = kick_speed.call()
		var v := dir * speed * power
		for i in range(1, 10):
			var t := i * 0.055
			var p := cs + (v * t + Vector2(0, 490.0 * t * t)) * scl
			draw_circle(p, 2.2, Color(1, 1, 1, clampf(0.85 - i * 0.08, 0.0, 1.0)))
