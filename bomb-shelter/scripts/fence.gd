class_name Fence
extends StaticBody2D
## A wooden fence section on the surface animal strip: solid to critters and
## players (they hop over or smash through it). Same kicked()/blast_destroy()
## pattern as scripts/fixture.gd, but instead of just reacting it breaks
## apart into tumbling Plank debris (see BunkerProps.Plank) and disappears.
##
## Usage: `position` is the CENTER, ground-line convention — to stand it at
## world y `ground_y` (the grass line), set position.y = ground_y - 11.0
## (the collision shape is ~4x22, so the post pokes up out of the ground).
##   var f := Fence.new(); f.position = Vector2(cx, ground_y - 11.0)
##   add_child(f)

## Streamed to web viewers as [x, y, kind, rotation].
var prop_kind := 8

var _dead := false


func _ready() -> void:
	add_to_group(&"props")
	add_to_group(&"fixtures")  # kicks in range call kicked()
	add_to_group(&"chests")    # blasts in range call blast_destroy()
	z_index = 3
	collision_layer = 1  # solid like terrain: critters/players collide with it
	collision_mask = 0

	var cs := CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	rs.size = Vector2(4, 22)
	cs.shape = rs
	add_child(cs)


## Called by the lead's kick loop for group "fixtures" nodes in range.
func kicked(_dir := Vector2.ZERO) -> void:
	_break()


## Called by the blast loop for group "chests" nodes it reaches unblocked.
func blast_destroy() -> void:
	_break()


func _break() -> void:
	if _dead:
		return
	_dead = true
	if NetHub.has_viewers():  # fx kind 11 = plank debris burst
		NetHub.broadcast({"t": "fx", "k": 11,
			"x": int(global_position.x), "y": int(global_position.y)})
	for i in 3:
		var plank := BunkerProps.Plank.new()
		plank.size = Vector2(randf_range(6.0, 12.0), 3.0)
		plank.position = global_position \
			+ Vector2(randf_range(-6.0, 6.0), randf_range(-10.0, 4.0))
		plank.rotation = randf_range(-0.6, 0.6)
		plank.linear_velocity = Vector2(randf_range(-160.0, 160.0),
			randf_range(-260.0, -60.0))
		plank.angular_velocity = randf_range(-8.0, 8.0)
		get_parent().add_child(plank)
	queue_free()


func _draw() -> void:
	# post
	draw_rect(Rect2(-2.0, -11.0, 4.0, 22.0).grow(1.0), Color.BLACK)
	draw_rect(Rect2(-2.0, -11.0, 4.0, 22.0), Color("8a6238"))
	# two horizontal rails sticking out either side of the post
	for ry in [-4.0, 4.0]:
		draw_rect(Rect2(-10.0, ry - 1.5, 20.0, 3.0).grow(1.0), Color.BLACK)
		draw_rect(Rect2(-10.0, ry - 1.5, 20.0, 3.0), Color("5e3d22"))
