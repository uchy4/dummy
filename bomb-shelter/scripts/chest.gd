class_name Chest
extends Area2D
## A rare trunk found at cavern dead ends. Walking into it grants body armor:
## one-time protection from a lethal blast. Unshielded explosions destroy
## unopened chests.

func _ready() -> void:
	add_to_group(&"chests")
	z_index = 4
	collision_layer = 0
	collision_mask = 2
	var cs := CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	rs.size = Vector2(22, 16)
	cs.shape = rs
	add_child(cs)
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	var p := body as Player
	if p == null or not p.alive or p.armor:
		return
	p.give_armor()
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
	draw_rect(Rect2(-10, -8, 20, 16), Color.BLACK)              # outline
	draw_rect(Rect2(-9, -1, 18, 8), Color("6d4c2f"))            # base
	draw_rect(Rect2(-9, -7, 18, 6), Color("8a6238"))            # lid
	draw_rect(Rect2(-9, -2, 18, 2), Color("caa64a"))            # gold band
	draw_rect(Rect2(-2, -3, 4, 5), Color("e8c35c"))             # latch
	draw_rect(Rect2(-1, -2, 2, 2), Color("4a3517"))             # keyhole
