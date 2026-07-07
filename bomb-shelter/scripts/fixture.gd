class_name Fixture
extends StaticBody2D
## Static bathroom fixtures: toilet and shower. Solid (collision_layer = 1,
## like terrain) so players/bombs can stand on or bump them, but they react
## to being kicked or caught in a blast — see scripts/chest.gd for why
## joining group "chests" is what makes the blast loop call blast_destroy()
## on them, and scripts/water_spray.gd for the squirt effect.
##
## Usage: set `kind` before adding to the tree, e.g.:
##   var t := Fixture.new(); t.kind = Fixture.Kind.TOILET; add_child(t)
## `position` is the fixture's CENTER (toilet 16x18, shower 6x26) — to stand
## it on a floor at world y `floor_y`, set position.y = floor_y - h/2.
## The lead's kick loop should call `kicked()` on group "fixtures" members in
## range; the blast loop already calls `blast_destroy()` on group "chests".

enum Kind { TOILET, SHOWER, PUMP }

var kind := Kind.TOILET
## Streamed to web viewers as [x, y, kind, rotation]; kept in sync with `kind`.
var prop_kind := 4

const SHOWER_ON_TIME := 6.0
const SHOWER_INTERVAL := 0.25
const SHOWER_DRIBBLE_INTERVAL := 0.8

var _squirt_count := 0
var _cracked := false

var _shower_timer := -1.0  # seconds remaining while running; < 0 = off
var _shower_accum := 0.0
var _dribbling := false    # permanent post-blast trickle (shower only)
var _dribble_accum := 0.0

## PUMP: the well pipe's bottom (world y), set by BunkerProps. Once busted,
## the whole pipe leaks — sprays burst out along its full length forever.
var pipe_bottom_y := 0.0
var _busted := false
var _leak_accum := 0.0


func _ready() -> void:
	match kind:
		Kind.TOILET:
			prop_kind = 4
		Kind.SHOWER:
			prop_kind = 5
		Kind.PUMP:
			prop_kind = 10
	add_to_group(&"props")
	add_to_group(&"fixtures")
	add_to_group(&"chests")  # blast loop calls blast_destroy() on this group
	z_index = 3
	collision_layer = 1
	collision_mask = 0

	var cs := CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	match kind:
		Kind.TOILET:
			rs.size = Vector2(16, 18)
		Kind.SHOWER:
			rs.size = Vector2(6, 26)
		Kind.PUMP:
			rs.size = Vector2(10, 20)
	cs.shape = rs
	add_child(cs)


func _process(delta: float) -> void:
	if kind == Kind.PUMP:
		if _busted and pipe_bottom_y > global_position.y:
			_leak_accum += delta
			if _leak_accum >= 0.3:
				_leak_accum = 0.0
				_pipe_leak()
		return
	if kind != Kind.SHOWER:
		return
	if _shower_timer >= 0.0:
		_shower_timer -= delta
		_shower_accum += delta
		if _shower_accum >= SHOWER_INTERVAL:
			_shower_accum = 0.0
			_spray_down()
		if _shower_timer < 0.0:
			queue_redraw()
	elif _dribbling:
		_dribble_accum += delta
		if _dribble_accum >= SHOWER_DRIBBLE_INTERVAL:
			_dribble_accum = 0.0
			_spray_down(0.5)


## Public hook the lead's kick loop calls for group "fixtures" nodes in range.
func kicked() -> void:
	match kind:
		Kind.TOILET:
			_squirt()
		Kind.PUMP:
			# A kick busts the well: spout gushes and the pipe springs
			# leaks all the way down to the reservoir, permanently.
			_pump_squirt()
			_busted = true
			queue_redraw()
		Kind.SHOWER:
			if _shower_timer >= 0.0:
				_shower_timer = -1.0
			else:
				_shower_timer = SHOWER_ON_TIME
				_shower_accum = 0.0
			queue_redraw()


## Called automatically by the blast loop for every node in group "chests".
func blast_destroy() -> void:
	match kind:
		Kind.TOILET:
			_squirt()
		Kind.PUMP:
			_pump_squirt(2.0)
			_busted = true
			queue_redraw()
		Kind.SHOWER:
			_spray_down(1.6)
			_dribbling = true


## The well pump gushes from its spout when kicked.
func _pump_squirt(mult := 1.0) -> void:
	var spray := WaterSpray.new()
	spray.dir = Vector2(-0.55, -0.85).normalized()
	spray.amount = int(16 * mult)
	spray.spread = 0.45
	spray.speed = 210.0 * mult
	spray.global_position = global_position + Vector2(-6, -5)
	get_parent().add_child.call_deferred(spray)


## A busted well leaks from a random point along its buried pipe.
func _pipe_leak() -> void:
	var spray := WaterSpray.new()
	var ly := lerpf(global_position.y + 10.0, pipe_bottom_y, randf())
	var side := 1.0 if randf() < 0.5 else -1.0
	spray.dir = Vector2(side, randf_range(-0.4, 0.1)).normalized()
	spray.amount = 6
	spray.spread = 0.35
	spray.speed = randf_range(90.0, 150.0)
	spray.global_position = Vector2(global_position.x, ly)
	get_parent().add_child.call_deferred(spray)


func _squirt() -> void:
	_squirt_count += 1
	if _squirt_count >= 3:
		_cracked = true
	var spray := WaterSpray.new()
	spray.dir = Vector2(randf_range(-0.3, 0.3), -1.0).normalized()
	spray.amount = 14
	spray.spread = 0.5
	spray.speed = 200.0
	spray.global_position = global_position + Vector2(0, -8)
	get_parent().add_child.call_deferred(spray)
	queue_redraw()


func _spray_down(mult := 1.0) -> void:
	var spray := WaterSpray.new()
	spray.dir = Vector2.DOWN
	spray.amount = int(14 * mult)
	spray.spread = 0.35
	spray.speed = 160.0 * mult
	spray.global_position = global_position + Vector2(0, -11)  # shower head
	get_parent().add_child.call_deferred(spray)


func _draw() -> void:
	match kind:
		Kind.TOILET:
			_draw_toilet()
		Kind.SHOWER:
			_draw_shower()
		Kind.PUMP:
			_draw_pump()


func _draw_pump() -> void:
	draw_rect(Rect2(-4, -10, 8, 20), Color.BLACK)                # outline
	draw_rect(Rect2(-3, -9, 6, 18), Color("3e6b4f"))             # cast body
	draw_rect(Rect2(-8, -7, 6, 3), Color("2f523c"))              # spout
	draw_rect(Rect2(-8, -4, 2.5, 2), Color("2f523c"))            # spout lip
	if _busted:
		# Drooped handle + a crack down the casting.
		draw_line(Vector2(2, -9), Vector2(8, -5), Color("263e2e"), 2.5)
		draw_circle(Vector2(8, -5), 1.6, Color("263e2e"))
		draw_line(Vector2(-1, -8), Vector2(1.5, 6), Color("1a2a20"), 1.3)
	else:
		draw_line(Vector2(2, -9), Vector2(8, -13), Color("263e2e"), 2.5)  # handle
		draw_circle(Vector2(8, -13), 1.6, Color("263e2e"))
	draw_rect(Rect2(-6, 9, 12, 2), Color("54381f"))              # base plank


func _draw_toilet() -> void:
	var tint := Color(0.85, 0.85, 0.85) if _cracked else Color.WHITE
	draw_rect(Rect2(-9, -9, 18, 20), Color.BLACK)              # outline
	draw_rect(Rect2(-7, 2, 14, 7), Color("d8d8d8") * tint)     # base
	draw_rect(Rect2(-8, -3, 16, 8), Color("f2f2f2") * tint)    # bowl
	draw_rect(Rect2(-8, -9, 16, 6), Color("ffffff") * tint)    # tank
	draw_rect(Rect2(-8, -4, 16, 1.5), Color("c9c9c9"))         # seat line
	if _cracked:
		draw_line(Vector2(-4, -8), Vector2(3, 5), Color("555555"), 1.2)


func _draw_shower() -> void:
	draw_rect(Rect2(-3, -13, 6, 26), Color.BLACK)              # outline
	draw_rect(Rect2(-2, -12, 4, 24), Color("9e9e9e"))          # pole
	draw_rect(Rect2(-6, -13, 12, 4), Color("757575"))          # head
	var on := _shower_timer >= 0.0
	draw_rect(Rect2(1, -1, 3, 3), Color("42a5f5") if on else Color("616161"))  # handle
