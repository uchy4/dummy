class_name Player
extends CharacterBody2D
## One local player. Platformer movement (coyote time + jump buffer), can push
## bombs around, dies to close unshielded blasts and respawns in the shelter.

const SPEED := 230.0
const ACCEL := 1900.0
const JUMP_VELOCITY := -430.0
const MAX_FALL := 900.0
const PUSH_FORCE := 380.0
const PLAYER_SHOVE := 900.0
const RESPAWN_TIME := 3.0
const INVULN_TIME := 1.5
const KICK_RANGE := 30.0
const KICK_COOLDOWN := 0.35
const IMPACT_STUN_SPEED := 230.0  ## relative speed along the normal to stun on impact
const IMPACT_KNOCKBACK := 200.0
const IMPACT_STUN_GRACE := 0.3  ## no re-stun this soon after an impact stun

var index := 0
var player_color := Color.WHITE
var color2 := Color.WHITE  ## second stripe color; equals player_color when solid
var display_name := "P?"
var alive := true
## Deepest point reached while alive (bigger y = lower). When everyone
## dies, the deepest player takes the match.
var deepest_y := -100000.0
## The hard hat: everyone spawns wearing one. It eats one lethal blast and
## flies off; construction crates hand out replacements.
var armor := true
var deaths := 0
var respawn_left := 0.0
var respawn_point := Vector2.ZERO

## Web-joined players are driven by NetHub state instead of InputMap actions.
var remote := false
var remote_axis := 0.0
var remote_jump := false
var remote_kick := false

## One-shot directional kick queued by gestures / web clients; consumed on
## the next physics tick. ZERO = nothing queued.
var _queued_kick := Vector2.ZERO
var _queued_kick_power := 1.0

## Puppet: a display-only mirror on a LAN-join client. No physics, no input —
## position and state come from host snapshots; drawing and the 3D layer work
## as usual.
var puppet := false
var puppet_on_floor := true
var puppet_stunned := false  ## host says this puppet is ragdoll-stunned

## Client prediction hold: while the host owns this body's motion (dead,
## or riding a stun ragdoll), the local simulation pauses and the client
## lerps us along the snapshot stream instead.
var remote_hold := false

## Ragdoll-stun: seconds left before the player gets back up. Set via
## apply_stun()/apply_impact_stun(); input is ignored while it's positive.
var stun_left := 0.0
## While stunned, the body is a real physics ragdoll launched with our
## velocity; the player rides its torso and stands up where it lands.
var _stun_ragdoll: Ragdoll = null
var _ragdoll_time := 0.0  ## total time down — hard-capped at 3 seconds

var world_bounds := Rect2(-100000, -100000, 200000, 200000)

var _invuln_left := 0.0
var _coyote := 0.0
var _jump_buffer := 0.0
var _walk_phase := 0.0
var _swing := 0.0
var _prev_jump_held := false
var _prev_kick_held := false
var _kick_cd := 0.0
var _facing := 1
var airborne := false
var _was_on_floor := true
var _fall_speed := 0.0
var _step_sign := 0
var _dizzy_phase := 0.0  ## orbit angle for the stunned dizzy-stars doodle
## Kick pose timer: the leading leg snaps out toward the facing direction
## for a beat. Streamed to clients as snapshot flag index 7; puppets set
## puppet_kicking from it instead.
var kick_anim := 0.0
var puppet_kicking := false
var _impact_stun_cd := 0.0  ## grace so the slide-loop and bomb contacts don't double-stun
var _a_left: StringName
var _a_right: StringName
var _a_jump: StringName
var _a_kick: StringName
var _shape: CollisionShape2D
var _terrain: Terrain  ## cached for water queries

var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")


func setup(i: int, color: Color) -> void:
	index = i
	player_color = color
	color2 = color
	display_name = "P%d" % (i + 1)
	_a_left = StringName("p%d_left" % (i + 1))
	_a_right = StringName("p%d_right" % (i + 1))
	_a_jump = StringName("p%d_jump" % (i + 1))
	_a_kick = StringName("p%d_kick" % (i + 1))


func setup_remote(i: int, p_name: String, color: Color, second := Color.TRANSPARENT) -> void:
	index = i
	remote = true
	display_name = p_name
	player_color = color
	color2 = color if second == Color.TRANSPARENT else second


func set_color(c: Color) -> void:
	set_colors(c, c)


func set_colors(c: Color, c2: Color) -> void:
	player_color = c
	color2 = c2
	queue_redraw()


func is_striped() -> bool:
	return not player_color.is_equal_approx(color2)


func _ready() -> void:
	add_to_group(&"players")
	z_index = 5
	if puppet:
		collision_layer = 0
		collision_mask = 0
		return
	collision_layer = 2
	collision_mask = 1 | 2 | 4  # terrain, other players, bombs
	floor_snap_length = 6.0
	_shape = CollisionShape2D.new()
	var cap := CapsuleShape2D.new()
	cap.radius = 7.0
	cap.height = 26.0
	_shape.shape = cap
	add_child(_shape)


## True when standing on ground; snapshot-driven for puppets.
func on_ground() -> bool:
	return puppet_on_floor if puppet else is_on_floor()


var _was_in_water := false
var _wake_cd := 0.0


func _ripple(power: float) -> void:
	get_tree().call_group(&"terrain", &"add_ripple",
		global_position + Vector2(0, 8.0), power)


## Stair assist: walking into a ledge up to one tile tall climbs it without
## a jump — any 1-block-per-1-block staircase (a 45-degree slope in block
## terms) is simply walkable. Taller faces still need a hop.
func _try_step_up(dir: float) -> void:
	if Settings.step_climb <= 0.5:
		return  # auto-climb disabled (Quick Settings slider)
	if absf(dir) < 0.2 or not is_on_floor():
		return
	var fwd := Vector2(signf(dir) * 5.0, 0)
	if not test_move(global_transform, fwd):
		return  # path ahead is clear: nothing to climb
	var up := Vector2(0, -(Settings.step_climb + 2.0))
	if test_move(global_transform, up):
		return  # ceiling right overhead: no room to step
	if test_move(global_transform.translated(up), fwd):
		return  # still a wall at step height: taller than the climb limit
	global_position += up + fwd * 0.5
	velocity.y = 0.0


func _physics_process(delta: float) -> void:
	if puppet:
		return
	if remote_hold:
		queue_redraw()
		return
	if not alive:
		if not Settings.one_life:
			respawn_left -= delta
			if respawn_left <= 0.0:
				_respawn()
		return

	if _invuln_left > 0.0:
		_invuln_left -= delta
		modulate.a = 0.4 + 0.6 * absf(sin(_invuln_left * 18.0))
		if _invuln_left <= 0.0:
			modulate.a = 1.0

	_impact_stun_cd -= delta
	kick_anim = maxf(kick_anim - delta, 0.0)

	var was_stunned := stun_left > 0.0
	if was_stunned:
		stun_left -= delta
		_ragdoll_time += delta
		if stun_left <= 0.0:
			# Don't get up mid-air — but never stay down forever either:
			# a nearly-motionless body counts as landed (micro-jitters on a
			# prop, wedged in a corner), and 3s of ragdoll is the hard cap.
			var rag_ok := _stun_ragdoll != null and is_instance_valid(_stun_ragdoll)
			var still_flying := rag_ok and not _stun_ragdoll.torso_grounded() \
				and _stun_ragdoll.torso_speed() > 18.0 \
				and _ragdoll_time < 3.0
			if still_flying:
				stun_left = 0.05
			else:
				stun_left = 0.0
				rotation = 0.0
				_clear_stun_ragdoll(true)

	var dir := 0.0
	var jump_released := false
	if not was_stunned:
		var jump_held := remote_jump if remote else Input.is_action_pressed(_a_jump)
		var jump_pressed := jump_held and not _prev_jump_held
		jump_released = not jump_held and _prev_jump_held
		_prev_jump_held = jump_held
		dir = remote_axis if remote else Input.get_axis(_a_left, _a_right)
		if absf(dir) > 0.2:
			_facing = 1 if dir > 0.0 else -1

		_kick_cd -= delta
		var kick_held := remote_kick if remote else Input.is_action_pressed(_a_kick)
		if kick_held and not _prev_kick_held and _kick_cd <= 0.0:
			_kick_cd = KICK_COOLDOWN
			_do_kick_dir(Vector2(_facing, -1).normalized(), 1.0)
		_prev_kick_held = kick_held
		if _queued_kick != Vector2.ZERO:
			if _kick_cd <= 0.0:
				_kick_cd = KICK_COOLDOWN
				_do_kick_dir(_queued_kick, _queued_kick_power)
			_queued_kick = Vector2.ZERO

		# Groundwater: you bob at the surface instead of sinking — submerged
		# you float up, feet-wet you settle, and jumping paddles you out.
		var head_water := _water_at(Vector2(0, -8))
		var feet_water := _water_at(Vector2(0, 10))
		# The surface rolls when we interact with it: a splash ripple on the
		# way in (scaled by impact speed), a small wake while swimming.
		if feet_water and not _was_in_water:
			_ripple(0.4 + minf(absf(velocity.y) / 300.0, 1.2))
		elif feet_water and absf(velocity.x) > 40.0:
			_wake_cd -= delta
			if _wake_cd <= 0.0:
				_wake_cd = 0.2
				_ripple(0.5)
		_was_in_water = feet_water
		if head_water:
			velocity.y = move_toward(velocity.y, -110.0, 2200.0 * delta)
		elif feet_water:
			velocity.y = move_toward(velocity.y, 35.0, 1500.0 * delta)
		else:
			velocity.y = minf(velocity.y + gravity * delta, MAX_FALL)
		_coyote = 0.15 if (is_on_floor() or feet_water) else _coyote - delta
		_jump_buffer = 0.1 if jump_pressed else _jump_buffer - delta

		if _jump_buffer > 0.0 and _coyote > 0.0:
			velocity.y = JUMP_VELOCITY * (0.7 if feet_water else 1.0)
			_jump_buffer = 0.0
			_coyote = 0.0
			get_tree().call_group(&"sfx", &"play_jump", global_position)
			_puff(4)
		if jump_released and velocity.y < 0.0:
			velocity.y *= 0.55  # variable jump height

		var swim_speed := SPEED * (0.65 if feet_water else 1.0)
		velocity.x = move_toward(velocity.x, dir * swim_speed, ACCEL * delta)
	else:
		# Stunned: the body is a tumbling physics ragdoll — ride its torso so
		# the camera, snapshots, and blasts all track where it's flung.
		if _stun_ragdoll != null and is_instance_valid(_stun_ragdoll):
			global_position = _stun_ragdoll.torso_pos()
			velocity = Vector2.ZERO
		else:
			velocity.y = minf(velocity.y + gravity * delta, MAX_FALL)
			if is_on_floor():
				velocity.x = move_toward(velocity.x, 0.0, 600.0 * delta)

	_fall_speed = velocity.y
	move_and_slide()
	if not was_stunned:
		_try_step_up(dir)

	# Landing: was airborne, now grounded, was falling with real speed.
	if is_on_floor() and not _was_on_floor and _fall_speed > 220.0:
		get_tree().call_group(&"sfx", &"play_land", global_position)
		_puff(8)
	_was_on_floor = is_on_floor()

	# Limb swing: legs/arms pump while walking; airborne uses a fixed jump pose.
	airborne = not is_on_floor()
	var swing_target := 0.0
	if not was_stunned and not airborne and absf(velocity.x) > 20.0:
		_walk_phase += velocity.x * delta * 0.055
		swing_target = sin(_walk_phase) * 0.6
		# A crunch each time a foot plants: the swing reverses direction at
		# its extremes, which is when the leading foot hits the ground.
		var sgn := 1 if cos(_walk_phase) >= 0.0 else -1
		if sgn != _step_sign:
			_step_sign = sgn
			get_tree().call_group(&"sfx", &"play_step", global_position)
	_swing = lerpf(_swing, swing_target, 0.35)

	if stun_left > 0.0 and _stun_ragdoll == null:
		# Fallback tilt for a stun without a ragdoll (shouldn't happen on
		# the host; puppets get theirs from client_main).
		_dizzy_phase += delta * 6.0
		if is_on_floor():
			var dir_sign: float = signf(velocity.x) if absf(velocity.x) > 5.0 else float(_facing)
			rotation = 1.1 * dir_sign
		else:
			rotation += delta * 3.0
	queue_redraw()

	# Shove bombs and other players we walk into; a fast bomb impact (a
	# falling bomb landing on someone, not a gentle roll-into) also
	# ragdoll-stuns us.
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var rb := c.get_collider() as RigidBody2D
		if rb:
			var bomb := rb as Bomb
			if bomb and bomb.carrier == null \
					and not (bomb.kicker == self and bomb.kicker_grace > 0.0):
				var rel_speed := absf((velocity - bomb.linear_velocity).dot(c.get_normal()))
				if rel_speed > IMPACT_STUN_SPEED:
					apply_impact_stun(c.get_normal())
			rb.apply_central_impulse(-c.get_normal() * PUSH_FORCE * delta)
			continue
		var other := c.get_collider() as Player
		if other and other.alive:
			other.velocity.x += -c.get_normal().x * PLAYER_SHOVE * delta
			continue
		# Running into livestock bumps it out of the way.
		var cr := c.get_collider() as Critter
		if cr and cr.alive:
			cr.velocity += -c.get_normal() * PLAYER_SHOVE * 0.6 * delta

	# Depth record (in-bounds only): the tie-breaker when nobody survives.
	if world_bounds.has_point(global_position):
		deepest_y = maxf(deepest_y, global_position.y)
	else:
		# Failsafe: anyone who escapes the map dies.
		die()


func _water_at(offset: Vector2) -> bool:
	if _terrain == null:
		_terrain = get_tree().get_first_node_in_group(&"terrain") as Terrain
		if _terrain == null:
			return false
	return _terrain.is_water(global_position + offset)


## Queue a directional kick with a 0.2..1.0 power scale (charged gesture
## kicks and web clients use this; the classic kick button stays 45 degrees
## at full power).
func queue_kick(dir: Vector2, power: float) -> void:
	_queued_kick = dir.normalized() if dir.length_squared() > 0.001 \
		else Vector2(_facing, -1).normalized()
	_queued_kick_power = clampf(power, 0.2, 1.0)


## Punt nearby bombs (and, more gently, players) in the given direction.
## A sticky bomb glued to us always launches, whatever the range.
func _do_kick_dir(dir: Vector2, power: float) -> void:
	if absf(dir.x) > 0.2:
		_facing = 1 if dir.x > 0.0 else -1
	kick_anim = 0.25
	queue_redraw()
	var center := global_position + Vector2(_facing * 10.0, 0.0)
	var hit := false
	for b in get_tree().get_nodes_in_group(&"bombs"):
		var bomb := b as Bomb
		if bomb == null:
			continue
		if bomb.carrier == self:
			bomb.kicked_by(self)
			bomb.launch(dir * Settings.kick_bomb_power * power)
			hit = true
			continue
		if center.distance_to(bomb.global_position) <= KICK_RANGE + bomb._body_radius:
			bomb.kicked_by(self)
			if bomb.carrier != null:
				bomb.launch(dir * Settings.kick_bomb_power * power)
			else:
				bomb.linear_velocity = dir * Settings.kick_bomb_power * power
				bomb.angular_velocity = _facing * 8.0
			hit = true
	for p in get_tree().get_nodes_in_group(&"players"):
		var other := p as Player
		if other and other != self and other.alive \
				and center.distance_to(other.global_position) <= KICK_RANGE + 8.0:
			other.velocity += dir * Settings.kick_player_power * power
			other._coyote = 0.0
			other.apply_stun(Settings.stun_time)  # kicks ragdoll players too
			hit = true
	# Furniture flies, critters get punted, fixtures (toilet/shower) react.
	for n in get_tree().get_nodes_in_group(&"props"):
		var node := n as Node2D
		if node == null or center.distance_to(node.global_position) > KICK_RANGE + 12.0:
			continue
		var rb := node as RigidBody2D
		if rb != null:
			rb.linear_velocity = dir * Settings.kick_bomb_power * power * 0.8
			rb.angular_velocity = _facing * 6.0
			hit = true
		elif node.has_method(&"shove"):
			node.call(&"shove", dir * Settings.kick_player_power * power)
			hit = true
	for f in get_tree().get_nodes_in_group(&"fixtures"):
		var fx := f as Node2D
		if fx and fx.has_method(&"kicked") \
				and center.distance_to(fx.global_position) <= KICK_RANGE + 12.0:
			fx.call(&"kicked", dir)
			hit = true
	get_tree().call_group(&"sfx", &"play_kick", global_position)
	if hit:
		_puff(3)


func give_armor() -> void:
	armor = true
	queue_redraw()


## Ragdoll-stun the player for `duration` seconds (blast survival, an armor
## save, or a bomb impact). No-op once dead or for a non-positive duration;
## never shortens stun time already in progress. The body becomes a real
## ragdoll flung with the current velocity (so call this AFTER the kick is
## applied); the player gets up wherever it tumbles to.
func apply_stun(duration: float) -> void:
	if duration <= 0.0 or not alive:
		return
	stun_left = maxf(stun_left, duration)
	if puppet or _stun_ragdoll != null:
		return
	_ragdoll_time = 0.0
	_stun_ragdoll = Ragdoll.new()
	_stun_ragdoll.hat = armor  # still wearing the hard hat? ragdoll wears it too
	_stun_ragdoll.persist = true
	_stun_ragdoll.color = player_color
	_stun_ragdoll.color2 = color2
	_stun_ragdoll.impulse = velocity.limit_length(700.0)
	_stun_ragdoll.position = global_position
	get_parent().add_child.call_deferred(_stun_ragdoll)
	hide()
	_shape.set_deferred(&"disabled", true)


## Tear down the stun ragdoll. A living player reappears at the body's
## resting spot with a little get-up hop; a dead one leaves it for die().
func _clear_stun_ragdoll(recover: bool) -> void:
	if _stun_ragdoll != null:
		if is_instance_valid(_stun_ragdoll):
			if recover:
				global_position = _stun_ragdoll.torso_pos() + Vector2(0, -6)
				reset_physics_interpolation()
			_stun_ragdoll.queue_free()
		_stun_ragdoll = null
	if alive:
		show()
		_shape.set_deferred(&"disabled", false)
		if recover:
			velocity = Vector2(0, -140.0)  # get-up hop
			_puff(4)


## Bomb-impact stun plus a small shove in `dir` (away from the bomb).
## Grace-gated so the player's own slide-collision loop and the bomb's
## contact-monitor can't both fire for the same hit.
func apply_impact_stun(dir: Vector2) -> void:
	if not alive or _impact_stun_cd > 0.0:
		return
	_impact_stun_cd = IMPACT_STUN_GRACE
	# Knockback first: apply_stun launches the ragdoll with our velocity.
	velocity += dir * IMPACT_KNOCKBACK + Vector2(0, -120.0)
	apply_stun(Settings.stun_time)


func take_blast(kick: Vector2, lethal: bool) -> void:
	if not alive:
		return
	if lethal and _invuln_left <= 0.0:
		if armor:
			# The hard hat eats the blast and flies off — hurled but alive,
			# briefly untouchable. Crates hand out new hats.
			armor = false
			var hat := BunkerProps.Plank.new()
			hat.size = Vector2(11, 4)
			hat.col = Color("f5c518")
			hat.position = global_position + Vector2(0, -16)
			hat.rotation = randf_range(-0.4, 0.4)
			hat.linear_velocity = Vector2(randf_range(-130.0, 130.0), -290.0)
			hat.angular_velocity = randf_range(-9.0, 9.0)
			get_parent().add_child(hat)
			_invuln_left = 1.2
			velocity += kick
			_coyote = 0.0
			apply_stun(Settings.stun_time)
			get_tree().call_group(&"sfx", &"play_armor_break", global_position)
			queue_redraw()
			return
		die(kick)
		return
	velocity += kick
	_coyote = 0.0
	apply_stun(Settings.stun_time)


## Move the player somewhere safe without a death penalty (Quick Settings
## "reset" button). A dead player respawns almost immediately instead.
func teleport_to(pos: Vector2) -> void:
	if not alive and Settings.one_life:
		return  # the dead stay dead in elimination mode
	_clear_stun_ragdoll(false)
	global_position = pos
	reset_physics_interpolation()
	velocity = Vector2.ZERO
	stun_left = 0.0
	rotation = 0.0
	_invuln_left = INVULN_TIME
	if not alive:
		respawn_left = minf(respawn_left, 0.1)


func die(kick := Vector2.ZERO) -> void:
	if not alive:
		return
	alive = false
	armor = false
	deaths += 1
	respawn_left = RESPAWN_TIME
	velocity = Vector2.ZERO
	stun_left = 0.0
	rotation = 0.0
	_clear_stun_ragdoll(false)  # the death ragdoll takes over from here
	hide()
	_shape.set_deferred("disabled", true)
	get_tree().call_group(&"sfx", &"play_splat", global_position)

	var rd := Ragdoll.new()
	rd.color = player_color
	rd.color2 = color2
	rd.impulse = kick.limit_length(700.0) if kick != Vector2.ZERO else Vector2(0, -220)
	rd.position = global_position
	get_parent().add_child.call_deferred(rd)


func _respawn() -> void:
	_clear_stun_ragdoll(false)
	global_position = respawn_point
	reset_physics_interpolation()
	velocity = Vector2.ZERO
	stun_left = 0.0
	rotation = 0.0
	alive = true
	armor = true  # fresh spawn, fresh hard hat
	_invuln_left = INVULN_TIME
	show()
	_shape.set_deferred("disabled", false)


func _puff(amount: int) -> void:
	var d := DustPuff.new()
	d.amount = amount
	d.position = global_position + Vector2(0, 12)
	get_parent().add_child.call_deferred(d)


## Draws one capsule limb of the shared figure onto `ci` at origin `o`.
## f (=facing) mirrors the whole pose horizontally when the figure turns.
static func _fig_limb(ci: CanvasItem, o: Vector2, anchor: Vector2, angle: float,
		length: float, col: Color, f: float) -> void:
	ci.draw_set_transform(o + Vector2(anchor.x * f, anchor.y), angle * f, Vector2.ONE)
	ci.draw_rect(Rect2(-3, -1, 6, length + 2), Color.BLACK)  # outline
	ci.draw_circle(Vector2(0, 0), 3.0, Color.BLACK)          # rounded caps
	ci.draw_circle(Vector2(0, length + 1), 3.0, Color.BLACK)
	ci.draw_rect(Rect2(-2, 0, 4, length), col)
	ci.draw_circle(Vector2(0, 0.5), 2.0, col)
	ci.draw_circle(Vector2(0, length + 0.5), 2.0, col)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## A flat-bottomed dome (round top, straight chord across the bottom).
static func _fig_dome(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 9:
		var t := PI * i / 8.0
		pts.append(c + Vector2(cos(t) * r, -sin(t) * r))
	ci.draw_colored_polygon(pts, col)


## The ONE source of truth for the player figure: limbs, fused dome head,
## torso, stripes, hard hat and eyes. Player._draw and the podium ceremony
## both render through this, so celebration dolls can never drift from the
## live in-game model again.
static func draw_figure(ci: CanvasItem, o: Vector2, c1: Color, c2: Color,
		striped: bool, hat: bool, f: float, r_arm: float, l_arm: float,
		r_leg: float, l_leg: float, leg_x: float, l_leg_len: float,
		kick_top: bool) -> void:
	var arm_c := c1.darkened(0.15)
	var leg_c := c1.darkened(0.35)
	# Back arm and both legs, behind the torso.
	_fig_limb(ci, o, Vector2(5, -6), r_arm, 10, arm_c.darkened(0.2), f)
	_fig_limb(ci, o, Vector2(leg_x, 2), r_leg, 12, leg_c.darkened(0.2), f)
	if not kick_top:
		_fig_limb(ci, o, Vector2(-leg_x, 2), l_leg, l_leg_len, leg_c, f)
	# Torso with a fused round-top head, black silhouette first. The head
	# is the BODY color with a flat bottom melting into the torso — the
	# figure reads like a bullet in its casing.
	ci.draw_circle(o + Vector2(0, -8), 6.9, Color.BLACK)
	ci.draw_rect(Rect2(o.x - 7, o.y - 8, 14, 12), Color.BLACK)
	ci.draw_circle(o + Vector2(0, -8), 5.9, c1)
	ci.draw_rect(Rect2(o.x - 6, o.y - 7, 12, 10), c1)
	if striped:
		ci.draw_rect(Rect2(o.x - 6, o.y - 5, 12, 2.5), c2)
		ci.draw_rect(Rect2(o.x - 6, o.y - 0.5, 12, 2.5), c2)
	if hat:
		# The safety-yellow hard hat: a flat-bottomed dome capping the head
		# (no brim — nothing covers the eyes). A lethal blast knocks it off.
		_fig_dome(ci, o + Vector2(0, -12.4), 5.4, Color.BLACK)
		_fig_dome(ci, o + Vector2(0, -12.2), 4.8, Color("f5c518"))
	var fx := f * 1.0
	ci.draw_rect(Rect2(o.x - 3 + fx, o.y - 12, 2, 3), Color.WHITE)
	ci.draw_rect(Rect2(o.x + 1 + fx, o.y - 12, 2, 3), Color.WHITE)
	ci.draw_rect(Rect2(o.x - 2.5 + fx, o.y - 11, 1, 1.5), Color.BLACK)
	ci.draw_rect(Rect2(o.x + 1.5 + fx, o.y - 11, 1, 1.5), Color.BLACK)
	# Front arm drawn over the torso.
	_fig_limb(ci, o, Vector2(-5, -6), l_arm, 10, arm_c, f)
	if kick_top:  # the kicking leg tops the whole stack
		_fig_limb(ci, o, Vector2(-leg_x, 2), l_leg, l_leg_len, leg_c, f)



func _draw() -> void:
	var f := float(_facing)
	# Poses defined facing-right; _limb mirrors them by f when facing left.
	var r_arm: float
	var l_arm: float
	var r_leg: float
	var l_leg: float
	var leg_x := 3.0
	var l_leg_len := 12.0
	var stunned := stun_left > 0.0 or puppet_stunned
	# The kicking leg draws OVER the torso and arms so it's never hidden.
	var kick_pose := (kick_anim > 0.0 or puppet_kicking) and not stunned
	if stunned:
		# Ragdoll tumble: limbs splayed at odd angles (overrides airborne pose).
		r_arm = -2.0
		l_arm = 1.4
		r_leg = -0.9
		l_leg = 0.5
		leg_x = 2.0
	elif kick_anim > 0.0 or puppet_kicking:
		# Kick: BOTH legs read clearly — the support leg planted straight
		# down, the kicking leg fully extended out horizontal toward the
		# facing side (and a touch longer), arms counter-swinging.
		r_arm = -0.6
		l_arm = 0.6
		r_leg = 0.0
		l_leg = -0.79  # 45 degrees forward
		l_leg_len = 14.0
		leg_x = 3.0
	elif airborne:
		# Jump: arms up in a Y, feet together and straight.
		r_arm = -2.5
		l_arm = 2.5
		r_leg = 0.0
		l_leg = 0.0
		leg_x = 1.5
	else:
		# Walk cycle: arms and legs swing opposite each other.
		r_arm = _swing
		l_arm = -_swing
		r_leg = -_swing
		l_leg = _swing
	draw_figure(self, Vector2.ZERO, player_color, color2, is_striped(), armor,
		f, r_arm, l_arm, r_leg, l_leg, leg_x, l_leg_len, kick_pose)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if stunned:
		# Dizzy stars orbiting above the head.
		var head := Vector2(0, -22)
		draw_circle(head + Vector2(cos(_dizzy_phase) * 6.0, sin(_dizzy_phase) * 2.0 - 2.0),
			1.6, Color.WHITE)
		draw_circle(head + Vector2(cos(_dizzy_phase + PI) * 6.0, sin(_dizzy_phase + PI) * 2.0 - 2.0),
			1.6, Color.WHITE)
