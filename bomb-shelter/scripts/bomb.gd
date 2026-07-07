class_name Bomb
extends RigidBody2D
## A falling bomb with a visible fuse ticker. When the fuse runs out it carves
## a hole in the terrain, kicks and kills nearby unshielded players, and
## propels + ignites nearby bombs (chain reactions). Dirt blocks the blast, so
## the shelter and tunnels actually protect you.
##
## Types: NORMAL; BIG (heavy, huge blast, longer fuse); CLUSTER (splits into
## bomblets); BOUNCY (ricochets around); STICKY (glues itself to whoever
## touches it — kick to launch it, or brush another player to pass it on);
## SHOCKWAVE (almost no destructive potency, but launches everything nearby
## with 5x force — a launcher, not an excavator); DRILL (burrows ~5 blocks
## into the ground on landing, then detonates a chamber); ANVIL (its blast
## fires straight DOWN, carving a rectangular column).
## Blast sizes scale with Settings.blast_scale, tunable in-game.

enum Type { NORMAL, BIG, CLUSTER, BOUNCY, STICKY, SHOCKWAVE, DRILL, ANVIL }

const BLAST_RADIUS := 80.0
const CARVE_RADIUS := 66.0
const DRILL_DEPTH := 5.0 * 16.0  ## px burrowed before detonating (~5 blocks)
const DRILL_SPEED := 95.0
const ANVIL_HALF_W := 26.0       ## half-width of the downward blast column
const ANVIL_DEPTH := 7.0 * 16.0  ## how far down the column reaches
const KILL_RADIUS := 48.0
const BOMB_IMPULSE := 300.0
const PLAYER_KNOCKBACK := 430.0
const BOMBLET_COUNT := 3
const IMPACT_STUN_SPEED := 230.0  ## fast enough to ragdoll-stun a player we slam into

var type := Type.NORMAL
var is_bomblet := false
var fuse := 4.0
var terrain: Terrain

## STICKY: the player this bomb is currently glued to (null = loose).
var carrier: Player = null
var _restick_cd := 0.0  ## no re-attach right after being kicked off
var _pass_cd := 0.0     ## brief hand-off cooldown so it can't ping-pong

## The player who most recently kicked this bomb, and how long they stay
## immune to it. A kick must never ragdoll or launch its own kicker.
var kicker: Player = null
var kicker_grace := 0.0

## DRILL: burrowing state — frozen, tunneling straight down, carving as it
## goes; detonates once DRILL_DEPTH has been chewed through.
var _drilling := false
var _drill_left := 0.0
var _drill_carve_acc := 0.0

## Puppet: display-only mirror on a LAN-join client. Frozen, no fuse logic —
## the host streams position and fuse.
var puppet := false

## Duds (Settings.duds_enabled, ~10%): the fuse fizzles out instead of
## detonating — but a nearby blast's concussion re-arms them. Fizzled duds
## stay on the field for good until something sets them off.
var is_dud := false
var fizzled := false

var _body_radius := 9.0
var _blast_mult := 1.0
var _body_color := Color(0.13, 0.13, 0.16)
var _exploded := false
var _prev_vy := 0.0
var _label: Label


func _ready() -> void:
	add_to_group(&"bombs")
	z_index = 6
	can_sleep = false
	if Settings.duds_enabled and not is_bomblet and not puppet and randf() < 0.1:
		is_dud = true
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.25
	pm.friction = 0.9
	mass = 1.4
	match type:
		Type.BIG:
			mass = 3.2
			_body_radius = 13.0
			_blast_mult = 1.6
			_body_color = Color(0.09, 0.09, 0.12)
			fuse += 1.0
		Type.CLUSTER:
			_body_color = Color(0.45, 0.25, 0.09)
			if is_bomblet:
				mass = 0.6
				_body_radius = 5.5
				_blast_mult = 0.5
		Type.BOUNCY:
			mass = 1.1
			_body_color = Color(0.12, 0.36, 0.18)
			pm.bounce = 0.85
			pm.friction = 0.4
		Type.STICKY:
			mass = 1.0
			_body_color = Color(0.5, 0.14, 0.5)
			pm.bounce = 0.05
			pm.friction = 1.0
		Type.SHOCKWAVE:
			mass = 1.2
			_body_color = Color(0.16, 0.32, 0.78)  # deep metallic blue
			pm.bounce = 0.4
		Type.DRILL:
			mass = 2.0
			_body_color = Color(0.38, 0.4, 0.46)  # gunmetal
			pm.bounce = 0.05
			pm.friction = 1.0
		Type.ANVIL:
			mass = 3.4
			_body_color = Color(0.2, 0.21, 0.26)  # cast iron
			pm.bounce = 0.0
			pm.friction = 1.0
	physics_material_override = pm
	if puppet:
		freeze = true
		collision_layer = 0
		collision_mask = 0
	else:
		# Lets us catch the reverse impact-stun case: a fast bomb slamming
		# into a standing player, which never shows up in the player's own
		# slide-collision loop since the player isn't the one moving.
		contact_monitor = true
		max_contacts_reported = 4

	var cs := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = _body_radius
	cs.shape = shape
	add_child(cs)

	_label = Label.new()
	_label.size = Vector2(44, 20)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override(&"font_size", 12 if is_bomblet else 15)
	_label.add_theme_color_override(&"font_color", Color.WHITE)
	_label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_label.add_theme_constant_override(&"outline_size", 5)
	add_child(_label)


func ignite(new_fuse: float) -> void:
	if fizzled:
		# Concussion from a nearby blast re-arms a spent dud.
		fizzled = false
		fuse = new_fuse
		get_tree().call_group(&"sfx", &"play_snap", global_position)
		return
	is_dud = false  # a direct blast always sets the charge off properly
	if new_fuse < fuse - 0.2:
		get_tree().call_group(&"sfx", &"play_snap", global_position)
	fuse = minf(fuse, new_fuse)


## A dud reaching zero: pop of smoke, then it just lies there.
func _fizzle() -> void:
	fizzled = true
	is_dud = false
	get_tree().call_group(&"sfx", &"play_snap", global_position)
	var d := DustPuff.new()
	d.amount = 6
	d.position = global_position
	get_parent().add_child.call_deferred(d)
	queue_redraw()


func _process(_delta: float) -> void:
	# Keep the ticker upright and above the (rolling) bomb.
	_label.rotation = -rotation
	_label.position = Vector2(-22, -_body_radius - 33.0).rotated(-rotation)
	if fizzled:
		_label.text = "DUD"
		_label.add_theme_color_override(&"font_color", Color(0.65, 0.65, 0.65))
		queue_redraw()
		return
	_label.text = "%.1f" % maxf(fuse, 0.0)
	if fuse < 1.2:
		_label.add_theme_color_override(&"font_color",
			Color.RED if fmod(fuse * 5.0, 1.0) < 0.5 else Color.WHITE)
	elif fuse < 2.5:
		_label.add_theme_color_override(&"font_color", Color.ORANGE)
	queue_redraw()


func _physics_process(delta: float) -> void:
	if _exploded or puppet:
		return
	if kicker_grace > 0.0:
		kicker_grace -= delta
	# Groundwater: bombs do sink, just slower — heavy drag, weak gravity.
	if terrain != null and not freeze:
		if terrain.is_water(global_position):
			linear_damp = 3.0
			gravity_scale = 0.4
		else:
			linear_damp = 0.0
			gravity_scale = 1.0
	if type == Type.STICKY:
		_sticky_logic(delta)
	if type == Type.DRILL and not fizzled:
		_drill_logic(delta)
	# A carried sticky bomb has its collision disabled (see _stick_to), but
	# skip explicitly too: riding a carrier must never impact-stun.
	if carrier == null and linear_velocity.length() > IMPACT_STUN_SPEED:
		_check_player_impact()
	# Deflect bounces sideways a little so a bomb never pogos straight up
	# and down in place forever.
	if _prev_vy > 120.0 and linear_velocity.y < -60.0:
		var dev := absf(linear_velocity.y) * randf_range(0.15, 0.45)
		linear_velocity.x += dev * (1.0 if randf() < 0.5 else -1.0)
		angular_velocity += randf_range(-6.0, 6.0)
	_prev_vy = linear_velocity.y

	if fizzled:
		return  # a spent dud lies around until a blast re-arms it (ignite)

	fuse -= delta
	if fuse <= 0.0:
		if is_dud:
			_fizzle()
		else:
			_explode()


## STICKY: glue to whoever brushes it, ride the carrier, and hand off to the
## next player the carrier touches. A kick (Player._do_kick_dir) launches it.
func _sticky_logic(delta: float) -> void:
	_restick_cd -= delta
	_pass_cd -= delta
	if carrier != null and (not is_instance_valid(carrier) or not carrier.alive):
		launch(Vector2(0, -60))  # carrier died: drop free
		return
	if carrier != null:
		# Ride stuck to the carrier's back; fuse keeps ticking.
		global_position = carrier.global_position \
			+ Vector2(-carrier._facing * 9.0, -6.0)
		rotation = 0.0
		if _pass_cd <= 0.0:
			var next := _touching_player(carrier)
			if next != null:
				_stick_to(next)
	elif _restick_cd <= 0.0:
		var pl := _touching_player(null)
		if pl != null:
			_stick_to(pl)


func _stick_to(p: Player) -> void:
	carrier = p
	_pass_cd = 0.35
	freeze = true
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	collision_layer = 0
	collision_mask = 0
	get_tree().call_group(&"sfx", &"play_snap", global_position)


## Detach from the carrier (if any) and fly off with the given velocity.
## Also used by kicks on loose sticky bombs for consistency.
func launch(vel: Vector2) -> void:
	carrier = null
	_restick_cd = 0.4
	freeze = false
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	linear_velocity = vel
	angular_velocity = signf(vel.x) * 8.0


## The player who just kicked this bomb is immune to it briefly — a kick
## must never ragdoll or launch the kicker.
func kicked_by(p: Player) -> void:
	kicker = p
	kicker_grace = 0.6


## DRILL: once the falling body touches ground it locks in place and chews
## straight down, carving a narrow shaft, then detonates at depth.
func _drill_logic(delta: float) -> void:
	if not _drilling:
		if linear_velocity.y < -10.0:
			return  # still on the way up
		var space := get_world_2d().direct_space_state
		var q := PhysicsRayQueryParameters2D.create(global_position,
			global_position + Vector2(0, _body_radius + 5.0), 1)
		if space.intersect_ray(q).is_empty():
			return
		_drilling = true
		_drill_left = DRILL_DEPTH
		freeze = true
		rotation = 0.0
		linear_velocity = Vector2.ZERO
		angular_velocity = 0.0
		collision_layer = 0
		collision_mask = 0
		get_tree().call_group(&"sfx", &"play_snap", global_position)
		return
	var step := DRILL_SPEED * delta
	global_position.y += step
	_drill_left -= step
	_drill_carve_acc += step
	# Carve in chunks, not every frame — keeps the carve stream sane.
	if _drill_carve_acc >= 10.0 and terrain:
		_drill_carve_acc = 0.0
		terrain.carve_circle(global_position + Vector2(0, _body_radius * 0.4),
			_body_radius + 3.0)
	if _drill_left <= 0.0:
		_explode()


## Reverse case for impact-stun: a fast bomb slamming into a standing
## player wouldn't show up in the player's own slide-collision loop (the
## player isn't the one moving), so watch our own contacts instead. The
## player's own apply_impact_stun() grace-gates double hits.
func _check_player_impact() -> void:
	for body in get_colliding_bodies():
		var pl := body as Player
		if pl == null or not pl.alive or pl.puppet:
			continue
		if pl == kicker and kicker_grace > 0.0:
			continue
		var dir := global_position.direction_to(pl.global_position)
		if dir == Vector2.ZERO:
			dir = Vector2.UP
		pl.apply_impact_stun(dir)


func _touching_player(exclude: Player) -> Player:
	for p in get_tree().get_nodes_in_group(&"players"):
		var pl := p as Player
		if pl == null or pl == exclude or not pl.alive or pl.puppet:
			continue
		if global_position.distance_to(pl.global_position) <= _body_radius + 13.0:
			return pl
	return null


func _explode() -> void:
	_exploded = true
	if type == Type.ANVIL:
		_explode_anvil()
		return
	# SHOCKWAVE: barely destructive, but launches everything nearby at 5x
	# force and is never lethal on its own.
	var launch_mult := 5.0 if type == Type.SHOCKWAVE else 1.0
	var lethal_allowed := type != Type.SHOCKWAVE
	var blast := BLAST_RADIUS * _blast_mult * Settings.blast_scale
	var kill := KILL_RADIUS * _blast_mult * Settings.blast_scale
	var carve := CARVE_RADIUS * _blast_mult * Settings.blast_scale \
		* (0.35 if type == Type.SHOCKWAVE else 1.0)
	var space := get_world_2d().direct_space_state

	for p in get_tree().get_nodes_in_group(&"players"):
		var pl := p as Player
		if pl == null or not pl.alive:
			continue
		# A kick must never ragdoll or launch its own kicker.
		if pl == kicker and kicker_grace > 0.0:
			continue
		var d := global_position.distance_to(pl.global_position)
		if d > blast:
			continue
		var blocked := _blocked(space, pl.global_position)
		var dir := global_position.direction_to(pl.global_position)
		if dir == Vector2.ZERO:
			dir = Vector2.UP
		var falloff := 1.0 - d / blast
		var kick := dir * PLAYER_KNOCKBACK * (0.4 + falloff) * (0.25 if blocked else 1.0)
		pl.take_blast(kick * launch_mult, d <= kill and not blocked and lethal_allowed)

	for b in get_tree().get_nodes_in_group(&"bombs"):
		var bomb := b as Bomb
		if bomb == null or bomb == self or bomb._exploded:
			continue
		var d := global_position.distance_to(bomb.global_position)
		if d > blast or _blocked(space, bomb.global_position):
			continue
		var dir := global_position.direction_to(bomb.global_position)
		if dir == Vector2.ZERO:
			dir = Vector2.UP
		var falloff := 1.0 - d / blast
		bomb.apply_central_impulse(dir * BOMB_IMPULSE * launch_mult * (0.5 + falloff) * bomb.mass)
		bomb.ignite(randf_range(0.25, 0.7))  # its death sets their fuse off

	# Blasts toss settled ragdolls around too.
	for rp in get_tree().get_nodes_in_group(&"ragdoll_parts"):
		var part := rp as RigidBody2D
		if part == null or not is_instance_valid(part):
			continue
		var d := global_position.distance_to(part.global_position)
		if d > blast or _blocked(space, part.global_position):
			continue
		var dir := global_position.direction_to(part.global_position)
		if dir == Vector2.ZERO:
			dir = Vector2.UP
		part.apply_central_impulse(
			dir * BOMB_IMPULSE * launch_mult * (0.6 + (1.0 - d / blast)) * part.mass)

	# Critters live and die by the same rules as players: lethal range
	# kills them, the rest of the blast ragdolls them.
	for n in get_tree().get_nodes_in_group(&"props"):
		var node := n as Node2D
		if node == null or not node.has_method(&"shove"):
			continue
		var nd := global_position.distance_to(node.global_position)
		if nd > blast or _blocked(space, node.global_position):
			continue
		var ndir := global_position.direction_to(node.global_position)
		if ndir == Vector2.ZERO:
			ndir = Vector2.UP
		var nkick := ndir * PLAYER_KNOCKBACK * launch_mult * (0.4 + (1.0 - nd / blast))
		if node.has_method(&"blast_hit"):
			node.call(&"blast_hit", nkick, nd <= kill and lethal_allowed)
		else:
			node.call(&"shove", nkick)

	# Untyped on purpose: naming Chest here would create a Bomb -> Chest ->
	# Player -> Bomb class-loading cycle.
	for ch: Node2D in get_tree().get_nodes_in_group(&"chests"):
		if global_position.distance_to(ch.global_position) <= blast \
				and not _blocked(space, ch.global_position):
			ch.call(&"blast_destroy")

	if terrain:
		terrain.carve_circle(global_position, carve)

	if type == Type.CLUSTER and not is_bomblet:
		for i in BOMBLET_COUNT:
			var frag := Bomb.new()
			frag.type = Type.CLUSTER
			frag.is_bomblet = true
			frag.terrain = terrain
			frag.fuse = randf_range(0.9, 1.5)
			frag.position = global_position + Vector2(randf_range(-6, 6), -6)
			frag.linear_velocity = Vector2(randf_range(-170, 170), randf_range(-330, -180))
			get_parent().add_child.call_deferred(frag)

	var fx := ExplosionFx.new()
	fx.radius = carve
	fx.position = global_position
	get_parent().add_child.call_deferred(fx)
	get_tree().call_group(&"camera", &"add_trauma", 0.25 if is_bomblet else 0.45)
	get_tree().call_group(&"sfx", &"play_explosion", global_position,
		_blast_mult * Settings.blast_scale, int(type))
	queue_free()


## ANVIL: the blast fires straight DOWN — everything in a rectangular
## column below the bomb gets slammed, and the column is carved out.
func _explode_anvil() -> void:
	var half_w := ANVIL_HALF_W * Settings.blast_scale
	var depth := ANVIL_DEPTH * Settings.blast_scale
	var rect := Rect2(global_position.x - half_w, global_position.y - 10.0,
		half_w * 2.0, depth + 10.0)

	for p in get_tree().get_nodes_in_group(&"players"):
		var pl := p as Player
		if pl == null or not pl.alive:
			continue
		if pl == kicker and kicker_grace > 0.0:
			continue
		if rect.has_point(pl.global_position):
			var dirx := signf(pl.global_position.x - global_position.x)
			pl.take_blast(Vector2(dirx * 140.0, 520.0), true)

	for b in get_tree().get_nodes_in_group(&"bombs"):
		var bomb := b as Bomb
		if bomb == null or bomb == self or bomb._exploded:
			continue
		if rect.has_point(bomb.global_position):
			bomb.apply_central_impulse(Vector2(0, BOMB_IMPULSE * 1.2) * bomb.mass)
			bomb.ignite(randf_range(0.25, 0.7))

	for rp in get_tree().get_nodes_in_group(&"ragdoll_parts"):
		var part := rp as RigidBody2D
		if part == null or not is_instance_valid(part):
			continue
		if rect.has_point(part.global_position):
			part.apply_central_impulse(Vector2(0, BOMB_IMPULSE * 1.3) * part.mass)

	for ch: Node2D in get_tree().get_nodes_in_group(&"chests"):
		if rect.has_point(ch.global_position):
			ch.call(&"blast_destroy")

	# Carve the column as a stack of overlapping circles.
	if terrain:
		var y := 0.0
		while y <= depth:
			terrain.carve_circle(global_position + Vector2(0, y), half_w + 4.0)
			y += half_w

	var fx := ExplosionFx.new()
	fx.radius = half_w * 2.2
	fx.position = global_position + Vector2(0, depth * 0.3)
	get_parent().add_child.call_deferred(fx)
	get_tree().call_group(&"camera", &"add_trauma", 0.5)
	get_tree().call_group(&"sfx", &"play_explosion", global_position,
		1.3 * Settings.blast_scale, int(Type.BIG))
	queue_free()


## True when solid terrain sits between the bomb and the target — the whole
## point of hiding in the shelter.
func _blocked(space: PhysicsDirectSpaceState2D, target: Vector2) -> bool:
	if global_position.distance_squared_to(target) < 1.0:
		return false
	var q := PhysicsRayQueryParameters2D.create(global_position, target, 1)
	return not space.intersect_ray(q).is_empty()


func _draw() -> void:
	var flash := 0.0
	if fuse < 1.2 and not fizzled:
		flash = 0.55 if fmod(maxf(fuse, 0.0) * 5.0, 1.0) < 0.5 else 0.0
	var body := _body_color.lerp(Color(1, 0.35, 0.2), flash)
	if fizzled:
		body = _body_color.darkened(0.35)
	draw_circle(Vector2.ZERO, _body_radius + 1.5, Color(0, 0, 0, 0.6))
	draw_circle(Vector2.ZERO, _body_radius, body)
	draw_circle(Vector2(-_body_radius * 0.33, -_body_radius * 0.33),
		_body_radius * 0.28, Color(1, 1, 1, 0.22))  # highlight shows rolling
	match type:
		Type.BIG:
			draw_rect(Rect2(-_body_radius, -2.5, _body_radius * 2.0, 5.0),
				Color(0.8, 0.15, 0.1, 0.85))
		Type.CLUSTER:
			if not is_bomblet:
				for a in 3:
					var off := Vector2.RIGHT.rotated(TAU * a / 3.0 + 0.5) * _body_radius * 0.45
					draw_circle(off, 1.8, Color(1, 0.7, 0.3, 0.8))
		Type.STICKY:
			# Goo blobs dripping off the shell.
			var goo := Color(0.85, 0.35, 0.95, 0.9)
			draw_circle(Vector2(-_body_radius * 0.6, _body_radius * 0.45), 2.6, goo)
			draw_circle(Vector2(_body_radius * 0.55, _body_radius * 0.5), 2.2, goo)
			draw_circle(Vector2(0, _body_radius * 0.85), 1.8, goo)
		Type.SHOCKWAVE:
			# Metallic shell: bright silver rim + a specular crescent over
			# the blue body.
			draw_arc(Vector2.ZERO, _body_radius - 1.2, -2.7, -0.5, 16,
				Color(0.9, 0.94, 1.0, 0.95), 2.6)
			draw_arc(Vector2.ZERO, _body_radius - 4.5, 0.5, 2.1, 12,
				Color(0.72, 0.8, 0.95, 0.5), 2.0)
		Type.DRILL:
			# Drill tip pointing down + thread chevrons on the body.
			draw_colored_polygon(PackedVector2Array([
				Vector2(-_body_radius * 0.7, _body_radius * 0.6),
				Vector2(_body_radius * 0.7, _body_radius * 0.6),
				Vector2(0, _body_radius + 7.0),
			]), Color(0.68, 0.7, 0.76))
			for i in 2:
				var yy := -2.0 + i * 4.5
				draw_line(Vector2(-_body_radius * 0.55, yy + 2.0),
					Vector2(_body_radius * 0.55, yy - 2.0), Color(0.6, 0.62, 0.7), 1.6)
		Type.ANVIL:
			# Anvil silhouette: wide cap + narrow waist over the body.
			draw_rect(Rect2(-_body_radius, -_body_radius * 0.75,
				_body_radius * 2.0, 4.0), Color(0.55, 0.57, 0.64))
			draw_rect(Rect2(-3.0, -_body_radius * 0.75 + 4.0, 6.0,
				_body_radius * 0.8), Color(0.42, 0.44, 0.5))
			draw_line(Vector2(-_body_radius * 0.6, _body_radius * 0.55),
				Vector2(_body_radius * 0.6, _body_radius * 0.55),
				Color(0.1, 0.1, 0.13), 2.0)
	draw_rect(Rect2(-2.5, -_body_radius - 4, 5, 5), Color(0.35, 0.32, 0.3))
	draw_circle(Vector2(0, -_body_radius - 5), 1.8, Color(1.0, 0.7, 0.2))
