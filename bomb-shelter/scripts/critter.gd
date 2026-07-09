class_name Critter
extends CharacterBody2D
## Wandering livestock: chickens and pigs. A kick sends them tumbling (they
## keep their shape — the body rocks side to side while the legs flail —
## and get back up); a close bomb blast kills them outright, same rules as
## players.
##
## Usage: set `kind` (and optionally `home`) before adding to the tree, e.g.:
##   var c := Critter.new(); c.kind = Critter.Kind.CHICKEN
##   c.home = pen_rect_world_px; add_child(c)
## `position` is the critter's CENTER (chicken 10x9, pig 32x20 — pigs draw
## at double scale) — to stand it on a floor at world y `floor_y`, set
## position.y = floor_y - h/2. They are CharacterBody2D; the lead's kick
## loop and blast handling call `shove(vel)` on group "props" members.

enum Kind { CHICKEN, PIG }

var kind := Kind.CHICKEN
## Streamed to web viewers as [x, y, kind, rotation]; kept in sync with `kind`.
var prop_kind := 6
## Home pen, in world px. Wanderers softly prefer staying inside it but don't
## pathfind back once flung far out — set by the spawner (BunkerProps).
var home := Rect2()

enum _Intent { IDLE, WALK_LEFT, WALK_RIGHT }

const MAX_FALL := 900.0
const CHICKEN_SPEED := 40.0
const PIG_SPEED := 30.0

var alive := true
var _stun_left := 0.0
var _flail := 0.0  # tumble phase: body rock + leg flailing
var _shape_node: CollisionShape2D

var _gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")
var _facing := 1
var _intent := _Intent.IDLE
var _intent_left := 0.0
var _flutter_left := 0.0  # chicken: short hop, reduced gravity while > 0
var _hop_cooldown := 0.0  # pig: cadence gate on little hops
var _wing_phase := 0.0


func _ready() -> void:
	prop_kind = 6 if kind == Kind.CHICKEN else 7
	add_to_group(&"props")
	z_index = 3
	collision_layer = 4  # on the same physical plane: players bump into them
	collision_mask = 1   # they walk on terrain (shoves come from the bumper)
	floor_snap_length = 6.0

	_shape_node = CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	rs.size = Vector2(10, 9) if kind == Kind.CHICKEN else Vector2(32, 20)
	_shape_node.shape = rs
	add_child(_shape_node)
	_pick_intent()


func _physics_process(delta: float) -> void:
	if not alive:
		return
	if _stun_left > 0.0:
		# Tumbling: the body keeps its shape and just rocks side to side
		# (never capsizes) while the legs flail; plain gravity applies.
		_stun_left -= delta
		_flail += delta * 16.0
		velocity.y = minf(velocity.y + _gravity * delta, MAX_FALL)
		velocity.x = move_toward(velocity.x, 0.0, 80.0 * delta)
		move_and_slide()
		rotation = sin(_flail * 0.9) * 0.45
		if _stun_left <= 0.0:
			rotation = 0.0
			velocity = Vector2.ZERO
		queue_redraw()
		return
	var fall_mult := 0.35 if _flutter_left > 0.0 else 1.0
	velocity.y = minf(velocity.y + _gravity * fall_mult * delta, MAX_FALL)

	_intent_left -= delta
	if _intent_left <= 0.0:
		_pick_intent()

	var speed := CHICKEN_SPEED if kind == Kind.CHICKEN else PIG_SPEED
	match _intent:
		_Intent.WALK_LEFT:
			velocity.x = -speed
		_Intent.WALK_RIGHT:
			velocity.x = speed
		_:
			velocity.x = move_toward(velocity.x, 0.0, speed * 4.0 * delta)

	# Soft home preference: only kicks in once outside the pen horizontally —
	# no pathfinding back once flung far away, that's fine (and funny).
	if home.size != Vector2.ZERO:
		if global_position.x < home.position.x:
			velocity.x = speed
		elif global_position.x > home.end.x:
			velocity.x = -speed

	if velocity.x > 1.0:
		_facing = 1
	elif velocity.x < -1.0:
		_facing = -1

	if kind == Kind.CHICKEN:
		_update_flutter(delta)
	else:
		_update_hop(delta)

	move_and_slide()
	if is_on_wall():
		_intent = _Intent.WALK_RIGHT if _intent == _Intent.WALK_LEFT else _Intent.WALK_LEFT

	queue_redraw()


func _pick_intent() -> void:
	_intent_left = randf_range(0.8, 2.0)
	var roll := randf()
	if roll < 0.35:
		_intent = _Intent.IDLE
	elif roll < 0.67:
		_intent = _Intent.WALK_LEFT
	else:
		_intent = _Intent.WALK_RIGHT

	if kind == Kind.CHICKEN and _flutter_left <= 0.0 and randf() < 0.25:
		_flutter_left = 0.5
		velocity.y = -110.0
	elif kind == Kind.PIG and _hop_cooldown <= 0.0 and randf() < 0.2:
		_hop_cooldown = 1.2
		velocity.y = -90.0


func _update_flutter(delta: float) -> void:
	if _flutter_left > 0.0:
		_flutter_left -= delta
		_wing_phase += delta * 22.0
	else:
		_wing_phase = 0.0


func _update_hop(delta: float) -> void:
	_hop_cooldown = maxf(_hop_cooldown - delta, 0.0)


## Public shove hook: kicks and blast knockback land here. A real wallop
## sends the animal tumbling — it flails and gets back up where it lands.
func shove(vel: Vector2) -> void:
	if not alive:
		return
	if vel.length() > 140.0:
		die(vel)  # a real kick ragdolls them: tossed, tumbling, fading
	else:
		velocity += vel


## Blast handler, same rules as players: lethal range kills, otherwise the
## concussion just launches them into a tumble.
func blast_hit(kick: Vector2, lethal: bool) -> void:
	if not alive:
		return
	if lethal:
		die(kick)
	else:
		shove(kick)


func die(kick: Vector2) -> void:
	if not alive:
		return
	alive = false
	if NetHub.has_viewers():  # fx kind 12 = critter death burst
		NetHub.broadcast({"t": "fx", "k": 12, "x": int(global_position.x),
			"y": int(global_position.y),
			"c": "h" if kind == Kind.CHICKEN else "p"})
	# The corpse keeps the animal's shape: same art, tumbling and fading.
	var corpse := Corpse.new()
	corpse.chicken = kind == Kind.CHICKEN
	corpse.face = _facing
	corpse.vel = (velocity + kick).limit_length(600.0) + Vector2(0, -80.0)
	corpse.position = global_position
	get_parent().add_child.call_deferred(corpse)
	get_tree().call_group(&"sfx", &"play_splat", global_position)
	queue_free()


func _draw() -> void:
	# One mirror transform for the whole body: each animal's art is
	# authored facing right at its true size (no scaling — outlines stay thin).
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(float(_facing), 1.0))
	var lk := _flail if _stun_left > 0.0 else 0.0
	if kind == Kind.CHICKEN:
		var wing := sin(_wing_phase) * 0.9 if _flutter_left > 0.0 else 0.15
		if _stun_left > 0.0:
			wing = sin(_flail * 2.0) * 1.1  # panicked flapping mid-tumble
		Critter.draw_chicken_art(self, wing, lk)
	else:
		Critter.draw_pig_art(self, lk)


## Chicken art (authored facing right, origin at body center). `leg_kick`
## > 0 makes the legs flail (tumble/corpse); 0 stands them normally.
static func draw_chicken_art(ci: CanvasItem, wing_ang: float, leg_kick: float) -> void:
	ci.draw_rect(Rect2(-6, -8, 12, 10), Color.BLACK)               # outline
	ci.draw_rect(Rect2(-5, -7, 10, 8), Color("f5f5f0"))            # body
	ci.draw_rect(Rect2(3.0, -9.5, 4.0, 2.5), Color("f5f5f0"))      # head bump
	ci.draw_rect(Rect2(6.0, -8.5, 2.5, 1.5), Color("ffb300"))      # beak
	ci.draw_rect(Rect2(3.5, -10.5, 2.0, 1.5), Color("e53935"))     # comb
	var k1 := sin(leg_kick) * 2.0 if leg_kick > 0.0 else 0.0
	var k2 := cos(leg_kick * 1.3) * 2.0 if leg_kick > 0.0 else 0.0
	ci.draw_rect(Rect2(-2.5 + k1, 1.0, 1.4, 3.0), Color("ffb300"))  # legs
	ci.draw_rect(Rect2(1.1 + k2, 1.0, 1.4, 3.0), Color("ffb300"))
	var tip := Vector2(-6.0, -2.0).rotated(wing_ang)
	ci.draw_line(Vector2(-2.0, -3.0), Vector2(-2.0, -3.0) + tip, Color("e0e0d8"), 2.5)


## Pig art authored at its real (double) size with a thin 1px outline —
## not a scaled-up small sprite with a fat border.
static func draw_pig_art(ci: CanvasItem, leg_kick: float) -> void:
	ci.draw_rect(Rect2(-17, -13, 34, 23), Color.BLACK)             # outline
	ci.draw_rect(Rect2(-16, -12, 32, 21), Color("f4a7b9"))         # body
	ci.draw_rect(Rect2(12.0, -10.0, 10.0, 12.0), Color("f4a7b9"))  # snout base
	ci.draw_rect(Rect2(17.0, -6.0, 5.0, 6.0), Color("d97b95"))     # snout tip
	ci.draw_rect(Rect2(8.0, -15.0, 6.0, 5.0), Color("e792a8"))     # ear
	var k1 := sin(leg_kick) * 5.0 if leg_kick > 0.0 else 0.0
	var k2 := cos(leg_kick * 1.3) * 5.0 if leg_kick > 0.0 else 0.0
	ci.draw_rect(Rect2(-10.0 + k1, 8.0, 6.0, 6.0), Color("d97b95"))  # legs
	ci.draw_rect(Rect2(4.0 + k2, 8.0, 6.0, 6.0), Color("d97b95"))
	ci.draw_arc(Vector2(-18.0, -4.0), 4.0, 0.0, TAU * 0.75, 10, Color("d97b95"), 1.6)  # curly tail
	ci.draw_arc(Vector2(-20.0, -7.0), 2.8, 0.0, TAU * 0.75, 8, Color("d97b95"), 1.3)


## A dead critter: the SAME body art, flung and tumbling (rocking, legs
## flailing — never balled up into ragdoll parts), fading out. No collision;
## purely cosmetic, so it isn't streamed (web plays fx kind 12 instead).
class Corpse:
	extends Node2D
	var chicken := true
	var face := 1
	var vel := Vector2.ZERO
	var _t := 0.0
	var _flail := 0.0

	func _ready() -> void:
		z_index = 3

	func _process(delta: float) -> void:
		_t += delta
		_flail += delta * 15.0
		vel.y += 900.0 * delta
		position += vel * delta
		rotation = sin(_flail * 0.7) * 0.6
		modulate.a = clampf(1.0 - _t / 1.2, 0.0, 1.0)
		if _t > 1.2:
			queue_free()
		queue_redraw()

	func _draw() -> void:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(float(face), 1.0))
		if chicken:
			Critter.draw_chicken_art(self, sin(_flail * 2.0) * 1.1, _flail)
		else:
			Critter.draw_pig_art(self, _flail)
