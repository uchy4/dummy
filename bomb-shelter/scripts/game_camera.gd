class_name GameCamera
extends Camera2D
## Frames every living player at once (party-game style): zooms out as they
## spread apart, clamped so the whole map always fits. Screen shake via trauma.

const MIN_ZOOM := 0.36
const MAX_ZOOM := 2.4
const MARGIN := 240.0

var map_rect := Rect2()
var trauma := 0.0


func _ready() -> void:
	add_to_group(&"camera")
	make_current()


func add_trauma(amount: float) -> void:
	trauma = minf(trauma + amount, 1.0)


func _physics_process(delta: float) -> void:
	var targets: Array[Vector2] = []
	for p in get_tree().get_nodes_in_group(&"players"):
		var pl := p as Player
		if pl and pl.alive:
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
