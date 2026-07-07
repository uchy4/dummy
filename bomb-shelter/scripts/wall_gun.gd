class_name WallGun
extends Node2D
## A rifle mounted on the arsenal room's back wall. It never breaks — a
## nearby blast just sets it off, and it sprays 2-4 stray Bullets (see
## scripts/bullet.gd) over the following moment. Because it survives, later
## blasts can set it misfiring again.
##
## Usage: `position` is the muzzle mount point; the rifle art is drawn
## pointing along +x from there, with a small wall-mount bracket behind it
## (-x side).
##   var g := WallGun.new(); g.position = Vector2(wx, wy); add_child(g)

## Streamed to web viewers as [x, y, kind, rotation].
var prop_kind := 14

const FIRE_WINDOW := 0.4  ## seconds over which a misfire's rounds go off

var _rounds_left := 0
var _fire_accum := 0.0
var _fire_interval := 0.1


func _ready() -> void:
	add_to_group(&"props")
	add_to_group(&"chests")  # blast loop calls blast_destroy() on this group
	z_index = 3


func _process(delta: float) -> void:
	if _rounds_left <= 0:
		return
	_fire_accum -= delta
	if _fire_accum <= 0.0:
		_fire_one()
		_rounds_left -= 1
		_fire_accum = _fire_interval


## Called by the blast loop for group "chests" nodes it reaches unblocked.
## Deliberately does NOT free/disable the gun — it can misfire repeatedly.
func blast_destroy() -> void:
	var n := randi_range(2, 4)
	_rounds_left += n
	_fire_interval = FIRE_WINDOW / float(n)
	_fire_accum = 0.0


func _fire_one() -> void:
	var side := -1.0 if randf() < 0.5 else 1.0
	var dir := Vector2(side, 0.0).rotated(randf_range(-0.5, 0.5))
	var b := Bullet.new()
	b.global_position = global_position
	b.velocity = dir * 620.0
	b.rotation = dir.angle()
	get_parent().add_child(b)
	get_tree().call_group(&"sfx", &"play_shot", global_position)


func _draw() -> void:
	draw_rect(Rect2(-7.0, -3.5, 6.0, 7.0).grow(1.0), Color.BLACK)     # mount bracket
	draw_rect(Rect2(-7.0, -3.5, 6.0, 7.0), Color("454049"))
	draw_rect(Rect2(-2.0, -2.0, 22.0, 4.0).grow(1.0), Color.BLACK)    # barrel + stock outline
	draw_rect(Rect2(10.0, -2.0, 10.0, 4.0), Color("2e2e34"))          # dark barrel
	draw_rect(Rect2(-2.0, -2.5, 12.0, 5.0), Color("6d4c2f"))          # wooden stock
	draw_rect(Rect2(3.0, 2.0, 2.0, 3.0), Color("2e2e34"))             # trigger guard nub
