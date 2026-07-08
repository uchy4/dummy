class_name Chest
extends Area2D
## A sturdy construction crate found at cavern dead ends. Walking into it
## hands out a fresh hard hat (one-time protection from a lethal blast).
## Unshielded explosions destroy unopened crates.

## Puppet: display-only mirror on a LAN-join client (host handles pickups).
var puppet := false


func _ready() -> void:
	add_to_group(&"chests")
	z_index = 4
	collision_layer = 0
	if puppet:
		collision_mask = 0
		monitoring = false
		return
	collision_mask = 2
	var cs := CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	rs.size = Vector2(22, 16)
	cs.shape = rs
	add_child(cs)
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	# Duck-typed on purpose: casting to Player here would chain into a
	# class-loading cycle (Bomb -> Chest -> Player -> Bomb).
	if not body.is_in_group(&"players"):
		return
	if not body.get(&"alive") or body.get(&"armor"):
		return
	body.call(&"give_armor")
	get_tree().call_group(&"sfx", &"play_pickup", global_position)
	_poof()


func blast_destroy() -> void:
	_poof()


func _poof() -> void:
	var d := DustPuff.new()
	d.amount = 6
	d.position = global_position
	get_parent().add_child.call_deferred(d)
	queue_free()


func _draw() -> void:
	# Safety-orange construction crate: hazard stripes, steel rails, bolts.
	draw_rect(Rect2(-11, -8, 22, 16), Color.BLACK)              # outline
	draw_rect(Rect2(-10, -7, 20, 14), Color("e8892b"))          # body
	for i in 3:
		var sx := -9.0 + i * 6.0
		draw_colored_polygon(PackedVector2Array([
			Vector2(sx, 5.0), Vector2(sx + 3.0, 5.0),
			Vector2(sx + 7.0, -5.0), Vector2(sx + 4.0, -5.0)]), Color("26262b"))
	draw_rect(Rect2(-10, -7, 20, 2.2), Color("f2a54a"))         # top rail
	draw_rect(Rect2(-10, 4.8, 20, 2.2), Color("c9741f"))        # bottom rail
	for cpos: Vector2 in [Vector2(-8, -4.6), Vector2(8, -4.6),
			Vector2(-8, 4.6), Vector2(8, 4.6)]:
		draw_circle(cpos, 1.3, Color("2f2f35"))                 # corner bolts
