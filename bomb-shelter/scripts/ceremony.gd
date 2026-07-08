class_name Ceremony
extends Node2D
## End-of-match celebration inside the finish hall: the top three players'
## dolls jump and wave on the real in-world podium (drawn by RoomDecor)
## while confetti falls. Added under Main (PROCESS_MODE_ALWAYS) so it keeps
## animating after the world pauses.

## Best-first: [{n: String, c: Color, c2: Color, d: int}], up to 3 used.
var entries: Array[Dictionary] = []
## The finish room in world px (terrain.finish_line_rect()).
var room := Rect2()

var _t := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 20


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var steps := RoomDecor.podium_steps(room)
	var font := ThemeDB.fallback_font
	# Confetti: deterministic per-fleck paths, wrapping down the room.
	var flecks: Array[Color] = [Color("ef5350"), Color("ffca28"), Color("9ccc65"),
		Color("64b5f6"), Color("ba68c8")]
	for i in 26:
		var h := hash(i * 7349)
		var fx := room.position.x + 6.0 + float(h % 1000) / 1000.0 * (room.size.x - 12.0)
		var fy := room.position.y + fmod(float((h >> 10) % 1000) / 1000.0 * room.size.y
			+ _t * (16.0 + float(i % 5) * 5.0), room.size.y - 6.0)
		var sway := sin(_t * 3.0 + float(i)) * 2.5
		draw_rect(Rect2(fx + sway, fy, 2.2, 1.4), flecks[i % flecks.size()])
	for i in mini(entries.size(), steps.size()):
		var s: Rect2 = steps[i]
		var e: Dictionary = entries[i]
		var jump := absf(sin(_t * 4.0 + i * 0.9)) * (8.0 if i == 0 else 5.0)
		_guy(Vector2(s.get_center().x, s.position.y - 14.0 - jump), e.c, e.c2, i)
		if font != null:
			draw_string(font, Vector2(s.position.x - 14.0, s.position.y - 34.0),
				str(e.n), HORIZONTAL_ALIGNMENT_CENTER, s.size.x + 28.0, 8, Color.WHITE)
			draw_string(font, Vector2(s.position.x - 14.0, s.get_center().y + 3.0),
				"%d deep" % int(e.d), HORIZONTAL_ALIGNMENT_CENTER, s.size.x + 28.0, 7,
				Color(0, 0, 0, 0.7))


## A mini player doll with arms thrown up, waving — same proportions as the
## live Player art so the winners are recognizable.
func _guy(at: Vector2, c1v: Variant, c2v: Variant, i: int) -> void:
	var c1: Color = c1v
	var c2: Color = c2v
	var wave := sin(_t * 9.0 + i * 1.7) * 0.45
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
	draw_circle(at + Vector2(0, -9), 5.7, c1)
	draw_circle(at + Vector2(0, -13.6), 4.4, Color("f5c518"))
	draw_rect(Rect2(at.x - 6, at.y - 13.8, 12, 1.6), Color("e3b214"))
	draw_rect(Rect2(at.x - 3, at.y - 14, 2, 3), Color.WHITE)
	draw_rect(Rect2(at.x + 1, at.y - 14, 2, 3), Color.WHITE)
