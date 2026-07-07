class_name Bullet
extends CharacterBody2D
## A stray rifle round from a misfiring WallGun (scripts/wall_gun.gd):
## ricochets off terrain a few times, ragdolls the first player it grazes via
## Player.apply_impact_stun(), then fizzles out.
##
## Usage: the spawner sets `velocity` (world px/sec, e.g. `dir * 620.0`) and
## `global_position` before adding this to the tree, e.g.:
##   var b := Bullet.new(); b.global_position = muzzle; b.velocity = dir * 620.0
##   parent.add_child(b)

## Streamed to web viewers as [x, y, kind, rotation].
var prop_kind := 15

const MAX_RICOCHETS := 3
const MAX_LIFE := 1.8
const HIT_RADIUS := 11.0
const BOUNCE_DAMPING := 0.85

var _bounces := 0
var _age := 0.0


func _ready() -> void:
	add_to_group(&"props")
	z_index = 4
	collision_layer = 0
	collision_mask = 1  # terrain only; player hits are proximity-checked below

	var cs := CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	rs.size = Vector2(3, 2)
	cs.shape = rs
	add_child(cs)
	rotation = velocity.angle()


func _physics_process(delta: float) -> void:
	_age += delta
	if _age > MAX_LIFE:
		queue_free()
		return

	# Proximity hit check: puppets/bots and hosted players all share the
	# "players" group, so this behaves the same everywhere.
	for n in get_tree().get_nodes_in_group(&"players"):
		var p := n as Player
		if p == null or p.puppet or not p.alive:
			continue
		if global_position.distance_to(p.global_position) < HIT_RADIUS:
			p.apply_impact_stun(velocity.normalized())
			queue_free()
			return

	var col := move_and_collide(velocity * delta)
	if col != null:
		velocity = velocity.bounce(col.get_normal()) * BOUNCE_DAMPING
		_bounces += 1
		if _bounces >= MAX_RICOCHETS:
			queue_free()
			return
	rotation = velocity.angle()
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(-3.0, -1.0, 6.0, 2.0), Color("ffd54f"))
	draw_rect(Rect2(-1.0, -0.5, 2.0, 1.0), Color.WHITE)
