class_name WaterSpray
extends Node2D
## Cosmetic water squirt for bathroom fixtures (toilet, shower): a cone of
## droplets that falls under gravity and fades out. Purely visual — no sound,
## unlike scripts/dust_puff.gd's "splat" companions. Self-frees.

## Direction of the cone. Vector2.UP for a toilet squirt, Vector2.DOWN for a
## shower head.
var dir := Vector2.UP
var amount := 12
## Half-angle of the cone, in radians.
var spread := 0.6
var speed := 180.0

var _age := 0.0
const _LIFE := 0.9
const _FADE_START := 0.5


func _ready() -> void:
	z_index = 7
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.emitting = true
	p.amount = amount
	p.lifetime = _LIFE
	p.explosiveness = 1.0
	p.direction = dir
	p.spread = rad_to_deg(spread)
	p.gravity = Vector2(0, 420)
	p.initial_velocity_min = speed * 0.55
	p.initial_velocity_max = speed
	p.scale_amount_min = 1.2
	p.scale_amount_max = 2.2
	p.color = Color("7fd4ff")
	p.color.a = 0.85
	add_child(p)


func _process(delta: float) -> void:
	_age += delta
	if _age > _LIFE:
		queue_free()
	elif _age > _FADE_START:
		modulate.a = 1.0 - (_age - _FADE_START) / (_LIFE - _FADE_START)
