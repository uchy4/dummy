class_name CornStalk
extends Node2D
## A single corn stalk in the surface corn field. No collision — players walk
## straight through it — but it sways as they pass close by, and joins the
## same kicked()/blast_destroy() pattern as scripts/fixture.gd so a kick or
## blast uproots it into a flying Plank (see BunkerProps.Plank).
##
## Usage: `position` is the base, at ground level (the grass line); the
## stalk is drawn upward (negative y) from there.
##   var s := CornStalk.new(); s.position = Vector2(cx, ground_y); add_child(s)
##
## The sway lean is written straight to node `rotation` (never draw-transform
## trickery) so the existing "props" web stream — which already sends node
## rotation for every entry — makes stalks sway on the web view for free.

## Streamed to web viewers as [x, y, kind, rotation].
var prop_kind := 13

const SWAY_RANGE_X := 14.0
const SWAY_RANGE_Y := 30.0
const MAX_LEAN := 0.5
const SPRING := 6.0
const BREEZE_AMP := 0.06

var _height := 30.0
var _phase := 0.0
var _lean := 0.0
var _time := 0.0
var _dead := false


func _ready() -> void:
	add_to_group(&"props")
	add_to_group(&"fixtures")  # kicks in range call kicked()
	add_to_group(&"chests")    # blasts in range call blast_destroy()
	z_index = 2
	_height = randf_range(26.0, 34.0)
	_phase = randf_range(0.0, TAU)


func _process(delta: float) -> void:
	_time += delta

	# Closest nearby player pushes a lean; direction follows their motion
	# (falls back to which side of the stalk they're standing on when idle).
	var target := 0.0
	var best_d := SWAY_RANGE_X
	for n in get_tree().get_nodes_in_group(&"players"):
		var p := n as Player
		if p == null or p.puppet or not p.alive:
			continue
		var rel := p.global_position - global_position
		if absf(rel.x) > SWAY_RANGE_X or absf(rel.y) > SWAY_RANGE_Y:
			continue
		if absf(rel.x) >= best_d:
			continue
		best_d = absf(rel.x)
		var push := signf(p.velocity.x)
		if is_zero_approx(push):
			push = signf(rel.x)
		if is_zero_approx(push):
			push = 1.0
		target = push * MAX_LEAN

	_lean = lerpf(_lean, target, SPRING * delta)
	rotation = _lean + sin(_time + _phase) * BREEZE_AMP
	queue_redraw()


## Called by the lead's kick loop for group "fixtures" nodes in range.
func kicked() -> void:
	_uproot()


## Called by the blast loop for group "chests" nodes it reaches unblocked.
func blast_destroy() -> void:
	_uproot()


func _uproot() -> void:
	if _dead:
		return
	_dead = true
	var plank := BunkerProps.Plank.new()
	plank.size = Vector2(3, 20)
	plank.col = Color("3f8f3a")
	plank.position = global_position + Vector2(0, -_height * 0.5)
	plank.rotation = randf_range(-0.4, 0.4)
	plank.linear_velocity = Vector2(randf_range(-60.0, 60.0), randf_range(-260.0, -140.0))
	plank.angular_velocity = randf_range(-6.0, 6.0)
	get_parent().add_child(plank)

	var puff := DustPuff.new()
	puff.amount = 4
	puff.position = global_position
	get_parent().add_child(puff)
	queue_free()


func _draw() -> void:
	var h := _height
	draw_line(Vector2.ZERO, Vector2(0, -h), Color("3f8f3a"), 2.5)
	# leaves: thin triangles either side, staggered up the stalk
	for i in 2:
		var t := 0.4 + float(i) * 0.28
		var side := -1.0 if i == 0 else 1.0
		var base_pt := Vector2(0, -h * t)
		var tip := base_pt + Vector2(side * 9.0, -6.0)
		var mid := base_pt + Vector2(side * 3.0, -2.0)
		draw_colored_polygon(PackedVector2Array([base_pt, mid, tip]), Color("57a84f"))
	# yellow tassel tip
	draw_line(Vector2(0, -h), Vector2(0, -h - 5.0), Color("e8c35c"), 1.6)
