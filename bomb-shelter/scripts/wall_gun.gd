class_name WallGun
extends Node2D
## A rifle mounted on the arsenal room's back wall. A nearby blast blows it
## clean OFF the wall: it becomes a tumbling FallenGun rigid body that
## misfires 2-4 stray Bullets (see scripts/bullet.gd) as it flies, and later
## blasts can toss it around and set it misfiring again wherever it landed.
##
## Usage: `position` is the muzzle mount point; the rifle art is drawn
## pointing along +x from there, with a small wall-mount bracket behind it
## (-x side).
##   var g := WallGun.new(); g.position = Vector2(wx, wy); add_child(g)

## Streamed to web viewers as [x, y, kind, rotation].
var prop_kind := 14

const FIRE_WINDOW := 0.4  ## seconds over which a misfire's rounds go off


func _ready() -> void:
	add_to_group(&"props")
	add_to_group(&"chests")  # blast loop calls blast_destroy() on this group
	z_index = 3


## Called by the blast loop for group "chests" nodes it reaches unblocked.
## The mount gives way: the rifle flies off, firing wildly.
func blast_destroy() -> void:
	var g := FallenGun.new()
	g.position = global_position
	g.rotation = randf_range(-0.4, 0.4)
	g.linear_velocity = Vector2(randf_range(-150.0, 150.0), randf_range(-230.0, -90.0))
	g.angular_velocity = randf_range(-7.0, 7.0)
	g.queue_misfire()
	get_parent().add_child(g)
	queue_free()


func _draw() -> void:
	WallGun.draw_rifle(self)


## Shared rifle art (mount bracket + barrel + stock), used by both the
## mounted gun and its fallen twin so nothing changes visually mid-flight.
static func draw_rifle(on: CanvasItem) -> void:
	on.draw_rect(Rect2(-7.0, -3.5, 6.0, 7.0).grow(1.0), Color.BLACK)     # mount bracket
	on.draw_rect(Rect2(-7.0, -3.5, 6.0, 7.0), Color("454049"))
	on.draw_rect(Rect2(-2.0, -2.0, 22.0, 4.0).grow(1.0), Color.BLACK)    # barrel + stock outline
	on.draw_rect(Rect2(10.0, -2.0, 10.0, 4.0), Color("2e2e34"))          # dark barrel
	on.draw_rect(Rect2(-2.0, -2.5, 12.0, 5.0), Color("6d4c2f"))          # wooden stock
	on.draw_rect(Rect2(3.0, 2.0, 2.0, 3.0), Color("2e2e34"))             # trigger guard nub


## A rifle knocked off its mount: a physical prop that tumbles off terrain,
## gets tossed by later blasts (ragdoll_parts) and misfires again every time
## one reaches it (chests). Bullets leave along wherever the barrel points.
class FallenGun:
	extends RigidBody2D

	## Streamed to web viewers as [x, y, kind, rotation] — same rifle.
	var prop_kind := 14

	var _rounds_left := 0
	var _fire_accum := 0.0
	var _fire_interval := 0.1

	func _ready() -> void:
		add_to_group(&"props")
		add_to_group(&"chests")         # blasts re-trigger misfires
		add_to_group(&"ragdoll_parts")  # ...and toss it around
		z_index = 3
		mass = 0.9
		collision_layer = 4
		collision_mask = 1 | 4
		var pm := PhysicsMaterial.new()
		pm.bounce = 0.3
		pm.friction = 0.7
		physics_material_override = pm
		var cs := CollisionShape2D.new()
		var rs := RectangleShape2D.new()
		rs.size = Vector2(22, 6)
		cs.shape = rs
		cs.position = Vector2(7, 0)
		add_child(cs)

	func _process(delta: float) -> void:
		if _rounds_left <= 0:
			return
		_fire_accum -= delta
		if _fire_accum <= 0.0:
			_fire_one()
			_rounds_left -= 1
			_fire_accum = _fire_interval

	func queue_misfire() -> void:
		var n := randi_range(2, 4)
		_rounds_left += n
		_fire_interval = WallGun.FIRE_WINDOW / float(n)
		_fire_accum = 0.05

	func blast_destroy() -> void:
		queue_misfire()

	func _fire_one() -> void:
		var dir := Vector2.RIGHT.rotated(global_rotation + randf_range(-0.25, 0.25))
		if randf() < 0.5:
			dir = -dir
		var b := Bullet.new()
		b.global_position = global_position + dir * 12.0
		b.velocity = dir * 620.0
		b.rotation = dir.angle()
		get_parent().add_child(b)
		get_tree().call_group(&"sfx", &"play_shot", global_position)
		apply_central_impulse(-dir * 40.0)  # a little recoil kick

	func _draw() -> void:
		WallGun.draw_rifle(self)
