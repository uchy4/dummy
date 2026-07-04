class_name Visual3D
extends Node3D
## The 2.5D presentation layer. The 2D simulation (physics, bots, web join)
## keeps running untouched with its canvas hidden; this node mirrors the
## world in 3D using the KayKit packs: MultiMesh block terrain, character
## models per player, bomb spheres, chest and finish-line blocks, and a 3D
## camera that follows the existing 2D camera's framing.

const UNIT := 16.0            # 2D pixels per 3D unit (one tile = one block)
const CHAR_HEIGHT := 1.75     # target character height in units
const TERRAIN_REBUILD_CD := 0.15

var terrain: Terrain

var _cam: Camera3D
var _terrain_mm: Array[MultiMesh] = []
var _terrain_dirty := true
var _terrain_cd := 0.0
var _char_visuals := {}   # Player -> Node3D
var _bomb_visuals := {}   # Bomb -> Node3D
var _chest_visuals := {}  # chest -> Node3D
var _part_visuals := {}   # ragdoll part -> MeshInstance3D
var _char_meshes: Array[PackedScene] = []
var _wood_mesh: Mesh
var _time := 0.0


static func map3(p: Vector2) -> Vector3:
	return Vector3(p.x / UNIT, -p.y / UNIT, 0.0)


func _ready() -> void:
	_build_environment()
	_build_camera()
	_build_terrain_meshes()
	_build_finish_line()
	for path in KayKitPaths.CHARACTERS:
		_char_meshes.append(load(path) as PackedScene)
	_wood_mesh = _mesh_from_scene(KayKitPaths.BLOCK_WOOD)
	terrain.carved.connect(_on_carved)


func _process(delta: float) -> void:
	_time += delta
	_terrain_cd -= delta
	if _terrain_dirty and _terrain_cd <= 0.0:
		_terrain_dirty = false
		_terrain_cd = TERRAIN_REBUILD_CD
		_rebuild_terrain()
	_sync_camera()
	_sync_players(delta)
	_sync_bombs()
	_sync_chests()
	_sync_ragdolls()


# ------------------------------------------------------------ environment ---

func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("4a9cd6")
	sky_mat.sky_horizon_color = Color("a8d8ea")
	sky_mat.ground_bottom_color = Color("2a1c10")
	sky_mat.ground_horizon_color = Color("6b4a2c")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	# Plain color ambient: reliable on the compatibility renderer.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.78, 0.85)
	env.ambient_light_energy = 0.8
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 28, 0)
	sun.shadow_enabled = true
	sun.light_energy = 1.15
	add_child(sun)

	# Dark cave backdrop behind the blocks so carved tunnels read as depth.
	var back := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(Terrain.W + 40.0, Terrain.H + 40.0)
	back.mesh = quad
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color("17100a")
	back.material_override = m
	back.position = Vector3(Terrain.W / 2.0, -Terrain.H / 2.0, -0.9)
	add_child(back)


func _build_camera() -> void:
	_cam = Camera3D.new()
	_cam.fov = 35.0
	_cam.near = 0.5
	_cam.far = 500.0
	add_child(_cam)
	_cam.current = true
	_cam.position = Vector3(Terrain.W / 2.0, -Terrain.SURFACE_ROW + 2.0, 60.0)


func _sync_camera() -> void:
	var cams := get_tree().get_nodes_in_group(&"camera")
	if cams.is_empty():
		return
	var cam2d := cams[0] as Camera2D
	if cam2d == null:
		return
	var center := map3(cam2d.get_screen_center_position())
	var zoom: float = cam2d.zoom.x
	var half_h_units: float = get_viewport().get_visible_rect().size.y / zoom / UNIT / 2.0
	var dist := half_h_units / tan(deg_to_rad(_cam.fov) / 2.0)
	dist = clampf(dist, 8.0, 220.0)
	_cam.position = center + Vector3(0.0, 2.0, dist)
	_cam.look_at(center)


# ---------------------------------------------------------------- terrain ---

func _build_terrain_meshes() -> void:
	var paths: Array[String] = [
		KayKitPaths.BLOCK_GRASS, KayKitPaths.BLOCK_DIRT,
		KayKitPaths.BLOCK_DIRT_DARK, KayKitPaths.BLOCK_BEDROCK,
	]
	for path in paths:
		var mesh := _mesh_from_scene(path)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		_terrain_mm.append(mm)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		add_child(mmi)


## Visual index for a cell: 0 grass, 1 dirt, 2 dark dirt, 3 bedrock.
func _cell_visual(c: int, x: int, y: int) -> int:
	match c:
		Terrain.Cell.GRASS:
			return 0
		Terrain.Cell.BEDROCK:
			return 3
		_:
			# Deterministic per-cell variety, darker with depth (mirrors 2D).
			var h := absi((x * 73856093) ^ (y * 19349663)) % 100
			var dark_chance := int(remap(float(y), float(Terrain.SURFACE_ROW), float(Terrain.H), 10.0, 55.0))
			return 2 if h < dark_chance else 1


func _block_transform(mesh: Mesh, x: int, y: int) -> Transform3D:
	var aabb := mesh.get_aabb()
	var s := 1.0 / maxf(maxf(aabb.size.x, aabb.size.y), maxf(aabb.size.z, 0.001))
	var basis := Basis.IDENTITY.scaled(Vector3(s, s, s))
	var center := (aabb.position + aabb.size / 2.0) * s
	var origin := Vector3(x + 0.5, -(y + 0.5), 0.0) - center
	return Transform3D(basis, origin)


func _rebuild_terrain() -> void:
	var lists: Array = [[], [], [], []]
	for y in Terrain.H:
		for x in Terrain.W:
			var c := terrain.cell(x, y)
			if c == Terrain.Cell.EMPTY:
				continue
			var t := _cell_visual(c, x, y)
			(lists[t] as Array).append(Vector2i(x, y))
	for i in 4:
		var cells: Array = lists[i]
		var mm := _terrain_mm[i]
		if mm.mesh == null:
			continue
		mm.instance_count = cells.size()
		for k in cells.size():
			var cell: Vector2i = cells[k]
			mm.set_instance_transform(k, _block_transform(mm.mesh, cell.x, cell.y))


func _on_carved(pos: Vector2, radius: float) -> void:
	_terrain_dirty = true
	_spawn_blast_fx(map3(pos), radius / UNIT)


func _build_finish_line() -> void:
	var mesh := _mesh_from_scene(KayKitPaths.BLOCK_GOLD)
	if mesh == null:
		return
	var fr := terrain.finish_line_rect()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	var cols := int(fr.size.x / UNIT)
	mm.instance_count = cols
	var row := int(fr.end.y / UNIT) - 1
	var col0 := int(fr.position.x / UNIT)
	for k in cols:
		var tr := _block_transform(mesh, col0 + k, row)
		tr = tr.scaled_local(Vector3(1.0, 0.35, 1.3))
		mm.set_instance_transform(k, tr)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)


# ---------------------------------------------------------------- players ---

func _sync_players(delta: float) -> void:
	var seen := {}
	for node in get_tree().get_nodes_in_group(&"players"):
		var p := node as Player
		if p == null:
			continue
		seen[p] = true
		if not _char_visuals.has(p):
			_char_visuals[p] = _make_char_visual(p)
		var vis: Node3D = _char_visuals[p]
		vis.visible = p.alive and p.visible
		if not p.alive:
			continue
		vis.position = map3(p.global_position)
		var model := vis.get_node("Model") as Node3D
		var target_yaw := PI / 2.0 * float(p._facing)
		model.rotation.y = lerp_angle(model.rotation.y, target_yaw, minf(12.0 * delta, 1.0))
		var moving := absf(p.velocity.x) > 20.0 and p.on_ground()
		var bob := absf(sin(_time * 11.0)) * 0.09 if moving else 0.0
		model.position.y = -CHAR_HEIGHT / 2.0 + bob
		var lean := 0.0
		if moving:
			lean = -0.1 * float(p._facing)
		elif not p.on_ground():
			lean = 0.14 * float(p._facing)
		model.rotation.z = lerpf(model.rotation.z, lean, minf(10.0 * delta, 1.0))
		var armor_ring := vis.get_node("ArmorRing") as Node3D
		armor_ring.visible = p.armor
		(vis.get_node("Ring") as Node3D).rotate_y(delta * 1.5)
	for key in _char_visuals.keys():
		if not seen.has(key) or not is_instance_valid(key):
			(_char_visuals[key] as Node3D).queue_free()
			_char_visuals.erase(key)


func _make_char_visual(p: Player) -> Node3D:
	var root := Node3D.new()
	add_child(root)

	var model := Node3D.new()
	model.name = "Model"
	root.add_child(model)
	var scene := _char_meshes[p.index % _char_meshes.size()]
	if scene != null:
		var inst := scene.instantiate() as Node3D
		var h := _scene_height(inst)
		var s := CHAR_HEIGHT / maxf(h, 0.4)
		inst.scale = Vector3(s, s, s)
		_tint_meshes(inst, Color(1, 1, 1).lerp(p.player_color, 0.35))
		model.add_child(inst)
	model.position.y = -CHAR_HEIGHT / 2.0

	var ring := MeshInstance3D.new()
	ring.name = "Ring"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.42
	torus.outer_radius = 0.58
	ring.mesh = torus
	ring.material_override = _unshaded(p.player_color)
	ring.position.y = -CHAR_HEIGHT / 2.0 + 0.03
	root.add_child(ring)

	var armor_ring := MeshInstance3D.new()
	armor_ring.name = "ArmorRing"
	var torus2 := TorusMesh.new()
	torus2.inner_radius = 0.34
	torus2.outer_radius = 0.44
	armor_ring.mesh = torus2
	armor_ring.material_override = _unshaded(Color(0.85, 0.88, 0.95))
	armor_ring.position.y = 0.15
	armor_ring.visible = false
	root.add_child(armor_ring)

	var label := Label3D.new()
	label.text = p.display_name
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = p.player_color
	label.outline_size = 8
	label.pixel_size = 0.012
	label.position.y = CHAR_HEIGHT / 2.0 + 0.5
	root.add_child(label)
	return root


# ----------------------------------------------------------------- bombs ---

func _sync_bombs() -> void:
	var seen := {}
	for node in get_tree().get_nodes_in_group(&"bombs"):
		var b := node as Bomb
		if b == null:
			continue
		seen[b] = true
		if not _bomb_visuals.has(b):
			_bomb_visuals[b] = _make_bomb_visual(b)
		var vis: Node3D = _bomb_visuals[b]
		vis.position = map3(b.global_position)
		vis.rotation.z = -b.rotation
		var label := vis.get_node("Fuse") as Label3D
		label.text = "%.1f" % maxf(b.fuse, 0.0)
		label.rotation.z = b.rotation  # counter the body spin
		var mat := (vis.get_node("Ball") as MeshInstance3D).material_override as StandardMaterial3D
		if b.fuse < 1.2 and fmod(maxf(b.fuse, 0.0) * 5.0, 1.0) < 0.5:
			mat.emission_enabled = true
			mat.emission = Color(1.0, 0.25, 0.1)
			label.modulate = Color.RED
		else:
			mat.emission_enabled = false
			label.modulate = Color.WHITE
	for key in _bomb_visuals.keys():
		if not seen.has(key) or not is_instance_valid(key):
			(_bomb_visuals[key] as Node3D).queue_free()
			_bomb_visuals.erase(key)


func _make_bomb_visual(b: Bomb) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	var ball := MeshInstance3D.new()
	ball.name = "Ball"
	var sphere := SphereMesh.new()
	var r: float = b._body_radius / UNIT
	sphere.radius = r
	sphere.height = r * 2.0
	ball.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = b._body_color
	mat.roughness = 0.4
	ball.material_override = mat
	root.add_child(ball)
	var cap := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.06
	cyl.bottom_radius = 0.09
	cyl.height = 0.22
	cap.mesh = cyl
	cap.material_override = _unshaded(Color(0.9, 0.7, 0.25))
	cap.position.y = r + 0.06
	root.add_child(cap)
	var label := Label3D.new()
	label.name = "Fuse"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.outline_size = 8
	label.pixel_size = 0.014
	label.position.y = r + 0.55
	root.add_child(label)
	return root


# --------------------------------------------------------- chests/ragdolls ---

func _sync_chests() -> void:
	var seen := {}
	for node in get_tree().get_nodes_in_group(&"chests"):
		var ch := node as Node2D
		if ch == null:
			continue
		seen[ch] = true
		if not _chest_visuals.has(ch):
			var vis := MeshInstance3D.new()
			vis.mesh = _wood_mesh
			if _wood_mesh != null:
				var aabb := _wood_mesh.get_aabb()
				var s := 1.0 / maxf(aabb.size.x, 0.001)
				vis.scale = Vector3(s * 1.1, s * 0.75, s * 0.85)
			add_child(vis)
			var band := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(1.15, 0.16, 0.9)
			band.mesh = box
			band.material_override = _unshaded(Color("e8c35c"))
			vis.add_child(band)
			_chest_visuals[ch] = vis
		(_chest_visuals[ch] as Node3D).position = map3(ch.global_position)
	for key in _chest_visuals.keys():
		if not seen.has(key) or not is_instance_valid(key):
			(_chest_visuals[key] as Node3D).queue_free()
			_chest_visuals.erase(key)


func _sync_ragdolls() -> void:
	var seen := {}
	for node in get_tree().get_nodes_in_group(&"ragdoll_parts"):
		var part := node as RigidBody2D
		if part == null:
			continue
		seen[part] = true
		if not _part_visuals.has(part):
			var mi := MeshInstance3D.new()
			var box := BoxMesh.new()
			var size := Vector3(0.4, 0.6, 0.3)
			var col := Color.WHITE
			for child in part.get_children():
				var shape := child as CollisionShape2D
				if shape and shape.shape is RectangleShape2D:
					var rs: Vector2 = (shape.shape as RectangleShape2D).size
					size = Vector3(rs.x / UNIT, rs.y / UNIT, 0.3)
				var poly := child as Polygon2D
				if poly:
					col = poly.color  # last polygon wins: the tinted one
			box.size = size
			mi.mesh = box
			var m := StandardMaterial3D.new()
			m.albedo_color = col
			mi.material_override = m
			add_child(mi)
			_part_visuals[part] = mi
		var vis: MeshInstance3D = _part_visuals[part]
		vis.position = map3(part.global_position)
		vis.rotation.z = -part.rotation
		var rag := part.get_parent() as Node2D
		if rag:
			vis.transparency = 1.0 - rag.modulate.a
	for key in _part_visuals.keys():
		if not seen.has(key) or not is_instance_valid(key):
			(_part_visuals[key] as Node3D).queue_free()
			_part_visuals.erase(key)


# -------------------------------------------------------------------- fx ---

func _spawn_blast_fx(pos: Vector3, radius: float) -> void:
	var light := OmniLight3D.new()
	light.position = pos + Vector3(0, 0, 1.5)
	light.light_color = Color(1.0, 0.6, 0.25)
	light.light_energy = 6.0
	light.omni_range = radius * 4.0
	add_child(light)
	var tw := light.create_tween()
	tw.tween_property(light, "light_energy", 0.0, 0.45)
	tw.tween_callback(light.queue_free)

	var parts := CPUParticles3D.new()
	parts.position = pos
	parts.one_shot = true
	parts.emitting = true
	parts.amount = 24
	parts.lifetime = 0.7
	parts.explosiveness = 1.0
	parts.direction = Vector3.UP
	parts.spread = 70.0
	parts.gravity = Vector3(0, -14, 0)
	parts.initial_velocity_min = 4.0
	parts.initial_velocity_max = 10.0
	parts.scale_amount_min = 0.12
	parts.scale_amount_max = 0.3
	parts.mesh = BoxMesh.new()
	(parts.mesh as BoxMesh).size = Vector3(0.2, 0.2, 0.2)
	parts.color = Color(0.9, 0.55, 0.2)
	add_child(parts)
	var tw2 := parts.create_tween()
	tw2.tween_interval(1.2)
	tw2.tween_callback(parts.queue_free)


# ----------------------------------------------------------------- helpers ---

func _mesh_from_scene(path: String) -> Mesh:
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var inst := packed.instantiate()
	var mi := _find_mesh_instance(inst)
	var mesh: Mesh = mi.mesh if mi != null else null
	inst.free()
	return mesh


func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _find_mesh_instance(child)
		if found != null:
			return found
	return null


func _scene_height(node: Node) -> float:
	var h := 0.0
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var mi := n as MeshInstance3D
		if mi != null and mi.mesh != null:
			h = maxf(h, mi.mesh.get_aabb().end.y)
		for child in n.get_children():
			stack.append(child)
	return h


func _tint_meshes(node: Node, color: Color) -> void:
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var mi := n as MeshInstance3D
		if mi != null and mi.mesh != null:
			for i in mi.mesh.get_surface_count():
				var mat := mi.get_active_material(i)
				var base := mat as BaseMaterial3D
				if base != null:
					var dup := base.duplicate() as BaseMaterial3D
					dup.albedo_color = dup.albedo_color * color
					mi.set_surface_override_material(i, dup)
		for child in n.get_children():
			stack.append(child)


func _unshaded(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	return m
