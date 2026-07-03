class_name Bomb
extends RigidBody2D
## A falling bomb with a visible fuse ticker. When the fuse runs out it carves
## a hole in the terrain, kicks and kills nearby unshielded players, and
## propels + ignites nearby bombs (chain reactions). Dirt blocks the blast, so
## the shelter and tunnels actually protect you.

const BODY_RADIUS := 9.0
const BLAST_RADIUS := 80.0
const CARVE_RADIUS := 66.0
const KILL_RADIUS := 48.0
const BOMB_IMPULSE := 300.0
const PLAYER_KNOCKBACK := 430.0

var fuse := 4.0
var terrain: Terrain

var _exploded := false
var _label: Label


func _ready() -> void:
	add_to_group(&"bombs")
	z_index = 6
	mass = 1.4
	can_sleep = false
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.25
	pm.friction = 0.9
	physics_material_override = pm

	var cs := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = BODY_RADIUS
	cs.shape = shape
	add_child(cs)

	_label = Label.new()
	_label.size = Vector2(44, 20)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override(&"font_size", 15)
	_label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_label.add_theme_constant_override(&"outline_size", 5)
	add_child(_label)


func ignite(new_fuse: float) -> void:
	fuse = minf(fuse, new_fuse)


func _process(_delta: float) -> void:
	# Keep the ticker upright and above the (rolling) bomb.
	_label.rotation = -rotation
	_label.position = Vector2(-22, -42).rotated(-rotation)
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
	var space := get_world_2d().direct_space_state

	for p in get_tree().get_nodes_in_group(&"players"):
		var pl := p as Player
		if pl == null or not pl.alive:
			continue
		var d := global_position.distance_to(pl.global_position)
		if d > BLAST_RADIUS:
			continue
		var blocked := _blocked(space, pl.global_position)
		var dir := global_position.direction_to(pl.global_position)
		if dir == Vector2.ZERO:
			dir = Vector2.UP
		var falloff := 1.0 - d / BLAST_RADIUS
		var kick := dir * PLAYER_KNOCKBACK * (0.4 + falloff) * (0.25 if blocked else 1.0)
		pl.take_blast(kick, d <= KILL_RADIUS and not blocked)

	for b in get_tree().get_nodes_in_group(&"bombs"):
		var bomb := b as Bomb
		if bomb == null or bomb == self or bomb._exploded:
			continue
		var d := global_position.distance_to(bomb.global_position)
		if d > BLAST_RADIUS or _blocked(space, bomb.global_position):
			continue
		var dir := global_position.direction_to(bomb.global_position)
		if dir == Vector2.ZERO:
			dir = Vector2.UP
		var falloff := 1.0 - d / BLAST_RADIUS
		bomb.apply_central_impulse(dir * BOMB_IMPULSE * (0.5 + falloff) * bomb.mass)
		bomb.ignite(randf_range(0.25, 0.7))  # its death sets their fuse off

	if terrain:
		terrain.carve_circle(global_position, CARVE_RADIUS)

	var fx := ExplosionFx.new()
	fx.radius = CARVE_RADIUS
	fx.position = global_position
	get_parent().add_child.call_deferred(fx)
	get_tree().call_group(&"camera", &"add_trauma", 0.45)
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
	var body := Color(0.13, 0.13, 0.16).lerp(Color(1, 0.35, 0.2), flash)
	draw_circle(Vector2.ZERO, BODY_RADIUS + 1.5, Color(0, 0, 0, 0.6))
	draw_circle(Vector2.ZERO, BODY_RADIUS, body)
	draw_circle(Vector2(-3, -3), 2.5, Color(1, 1, 1, 0.22))  # shows rolling
	draw_rect(Rect2(-2.5, -BODY_RADIUS - 4, 5, 5), Color(0.35, 0.32, 0.3))
	draw_circle(Vector2(0, -BODY_RADIUS - 5), 1.8, Color(1.0, 0.7, 0.2))
