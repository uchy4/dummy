class_name DustPuff
extends Node2D
## Small one-shot dirt puff for jumps and landings. Frees itself.

var amount := 6

var _age := 0.0


func _ready() -> void:
	z_index = 7
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.emitting = true
	p.amount = amount
	p.lifetime = 0.45
	p.explosiveness = 1.0
	p.direction = Vector2.UP
	p.spread = 65.0
	p.gravity = Vector2(0, 260)
	p.initial_velocity_min = 40.0
	p.initial_velocity_max = 110.0
	p.scale_amount_min = 1.5
	p.scale_amount_max = 3.0
	p.color = Color(0.62, 0.5, 0.36, 0.8)
	add_child(p)


func _process(delta: float) -> void:
	_age += delta
	if _age > 0.9:
		queue_free()
