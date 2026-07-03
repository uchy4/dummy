class_name Bomb
extends RigidBody2D
## A falling bomb with a visible fuse ticker. When the fuse runs out it carves
## a hole in the terrain, kicks and kills nearby unshielded players, and
## propels + ignites nearby bombs (chain reactions). Dirt blocks the blast, so
## the shelter and tunnels actually protect you.
##
## Types: NORMAL; BIG (heavy, huge blast, longer fuse); CLUSTER (splits into
## bomblets); BOUNCY (ricochets around). Blast sizes scale with
## Settings.blast_scale, tunable in-game.

enum Type { NORMAL, BIG, CLUSTER, BOUNCY }

const BLAST_RADIUS := 80.0
const CARVE_RADIUS := 66.0
const KILL_RADIUS := 48.0
const BOMB_IMPULSE := 300.0
const PLAYER_KNOCKBACK := 430.0
const BOMBLET_COUNT := 3

var type := Type.NORMAL
var is_bomblet := false
var fuse := 4.0
var terrain: Terrain

var _body_radius := 9.0
var _blast_mult := 1.0
var _body_color := Color(0.13, 0.13, 0.16)
var _exploded := false
var _label: Label


func _ready() -> void:
	add_to_group(&"bombs")
	z_index = 6
	can_sleep = false
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
	physics_material_override = pm

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
	fuse = minf(fuse, new_fuse)


func _process(_delta: float) -> void:
	# Keep the ticker upright and above the (rolling) bomb.
	_label.rotation = -rotation
	_label.position = Vector2(-22, -_body_radius - 33.0).rotated(-rotation)
	_label.text = "%.1f" % maxf(fuse, 0.0)
	if fuse < 1.2:
		_label.add_theme_color_override(&"font_color",
			Color.RED if fmod(fuse * 5.0, 1.0) < 0.5 else Color.WHITE)
	elif fuse < 2.5:
		_label.add_theme_color_override(&"font_color", Color.ORANGE)
	queue_redraw()


func _physics_process(delta: float) -> void:
	if _exploded:
		return
	fuse -= delta
	if fuse <= 0.0:
		_explode()


func _explode() -> void:
	_exploded = true
	var blast := BLAST_RADIUS * _blast_mult * Settings.blast_scale
	var kill := KILL_RADIUS * _blast_mult * Settings.blast_scale
	var carve := CARVE_RADIUS * _blast_mult * Settings.blast_scale
	var space := get_world_2d().direct_space_state

	for p in get_tree().get_nodes_in_group(&"players"):
		var pl := p as Player
		if pl == null or not pl.alive:
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
		pl.take_blast(kick, d <= kill and not blocked)

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
		bomb.apply_central_impulse(dir * BOMB_IMPULSE * (0.5 + falloff) * bomb.mass)
		bomb.ignite(randf_range(0.25, 0.7))  # its death sets their fuse off

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
		_blast_mult * Settings.blast_scale)
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
	if fuse < 1.2:
		flash = 0.55 if fmod(maxf(fuse, 0.0) * 5.0, 1.0) < 0.5 else 0.0
	var body := _body_color.lerp(Color(1, 0.35, 0.2), flash)
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
	draw_rect(Rect2(-2.5, -_body_radius - 4, 5, 5), Color(0.35, 0.32, 0.3))
	draw_circle(Vector2(0, -_body_radius - 5), 1.8, Color(1.0, 0.7, 0.2))
