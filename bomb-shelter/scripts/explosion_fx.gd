class_name ExplosionFx
extends Node2D
## One-shot explosion visual: expanding flash ring + debris particles.
## Frees itself when done.

const FLASH_LIFE := 0.35
const LIFE := 0.9

var radius := 66.0

var _age := 0.0


func _ready() -> void:
	z_index = 20
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.emitting = true
	p.amount = 28
	p.lifetime = 0.65
	p.explosiveness = 1.0
	p.direction = Vector2.UP
	p.spread = 180.0
	p.gravity = Vector2(0, 620)
	p.initial_velocity_min = 110.0
	p.initial_velocity_max = 340.0
	p.scale_amount_min = 2.0
	p.scale_amount_max = 5.0
	p.color = Color(1.0, 0.62, 0.18)
	add_child(p)


func _process(delta: float) -> void:
	_age += delta
	queue_redraw()
	if _age >= LIFE:
		queue_free()


func _draw() -> void:
	var t := clampf(_age / FLASH_LIFE, 0.0, 1.0)
	if t >= 1.0:
		return
	var r := lerpf(radius * 0.45, radius * 1.2, ease(t, 0.4))
	draw_circle(Vector2.ZERO, r, Color(1, 0.9, 0.55, 0.85 * (1.0 - t)))
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(1, 0.45, 0.1, 1.0 - t), 4.0)
