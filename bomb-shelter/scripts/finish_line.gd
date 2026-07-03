class_name FinishLine
extends Node2D
## Checkered gold finish strip drawn at the bottom of the finish hall.

var rect := Rect2()


func _ready() -> void:
	z_index = -5
	var label := Label.new()
	label.text = "F I N I S H"
	label.add_theme_font_size_override(&"font_size", 22)
	label.add_theme_color_override(&"font_color", Color("ffd54f"))
	label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	label.add_theme_constant_override(&"outline_size", 5)
	label.size = Vector2(200, 30)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = rect.get_center() - Vector2(100, 60)
	add_child(label)


func _draw() -> void:
	var check := 8.0
	var cols := ceili(rect.size.x / check)
	for i in cols:
		var w := minf(check, rect.end.x - (rect.position.x + i * check))
		var c := Color("ffd54f") if i % 2 == 0 else Color("1a1a1a")
		draw_rect(Rect2(rect.position.x + i * check, rect.position.y, w, rect.size.y), c)
	draw_rect(rect.grow(1.0), Color("ffb300"), false, 2.0)
