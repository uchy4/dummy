class_name GameCamera
extends Camera2D
## Frames every living player at once (party-game style): zooms out as they
## spread apart, clamped so the whole map always fits. Screen shake via trauma.

const MIN_ZOOM := 0.36
const MAX_ZOOM := 2.4
const MARGIN := 240.0

var map_rect := Rect2()
var trauma := 0.0
## In follow mode (Settings.camera_follow) the camera tracks this one player
## instead of framing the whole group. Falls back to the first living player.
var focus_target: Player = null
## While non-empty the camera ignores players and holds this rect fitted to
## the screen — the pre-match lounge frames the whole finish hall with it.
var hold_rect := Rect2()


func _ready() -> void:
	add_to_group(&"camera")
	make_current()


func add_trauma(amount: float) -> void:
	trauma = minf(trauma + amount, 1.0)


func _physics_process(delta: float) -> void:
	if hold_rect.size.x > 0.0:
		var hvp := get_viewport_rect().size
		var hfit := minf(hvp.x / hold_rect.size.x, hvp.y / hold_rect.size.y)
		zoom = zoom.lerp(Vector2.ONE * hfit, 1.0 - exp(-6.0 * delta))
		global_position = global_position.lerp(hold_rect.get_center(),
			1.0 - exp(-6.0 * delta))
		trauma = maxf(trauma - 2.0 * delta, 0.0)
		offset = Vector2.ZERO
		return
	var living: Array[Player] = []
	for p in get_tree().get_nodes_in_group(&"players"):
		var pl := p as Player
		if pl and pl.alive:
			living.append(pl)

	var targets: Array[Vector2] = []
	if Settings.camera_follow:
		# Follow one player (parity with the web view). Prefer the assigned
		# focus target; otherwise the first living player.
		var who: Player = focus_target if (focus_target and focus_target.alive) else null
		if who == null and not living.is_empty():
			who = living[0]
		if who:
			targets.append(who.global_position)
	else:
		for pl in living:
			targets.append(pl.global_position)

	if not targets.is_empty():
		var bbox := Rect2(targets[0], Vector2.ZERO)
		for t in targets:
			bbox = bbox.expand(t)
		bbox = bbox.grow(MARGIN)

		var vp := get_viewport_rect().size
		var fit := minf(vp.x / bbox.size.x, vp.y / bbox.size.y)
		var tz := clampf(fit * Settings.zoom_scale, MIN_ZOOM, MAX_ZOOM)
		zoom = zoom.lerp(Vector2.ONE * tz, 1.0 - exp(-4.0 * delta))

		var half := vp / zoom / 2.0
		var target := bbox.get_center()
		if map_rect.size.x > half.x * 2.0:
			target.x = clampf(target.x, map_rect.position.x + half.x, map_rect.end.x - half.x)
		else:
			target.x = map_rect.get_center().x
		target.y = minf(target.y, map_rect.end.y - half.y)
		global_position = global_position.lerp(target, 1.0 - exp(-5.0 * delta))

	trauma = maxf(trauma - 2.0 * delta, 0.0)
	var shake := trauma * trauma * 16.0
	offset = Vector2(randf_range(-shake, shake), randf_range(-shake, shake))
