class_name BotController
extends Node
## Drives one remote-controlled Player like a (mean) human: dodges bombs by
## their real blast radius, kicks fresh bombs away (or at you), grabs armor
## chests, and greedily descends through the deepest nearby opening.

const THREAT_FUSE := 1.6
const KICK_FUSE_MIN := 0.55
const REPLAN_INTERVAL := 0.35
const SCAN_COLS := 22

var player: Player
var terrain: Terrain

var _replan := 0.0
var _target_x := 0.0
var _stuck_time := 0.0


func _physics_process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	if not player.alive:
		player.remote_axis = 0.0
		player.remote_jump = false
		player.remote_kick = false
		return

	var pos := player.global_position
	var axis := 0.0
	var jump := false
	var kick := false

	# Threat scan every frame: nearest bomb whose blast would reach us soon.
	var threat: Bomb = null
	var tdist := 1e9
	for b in get_tree().get_nodes_in_group(&"bombs"):
		var bomb := b as Bomb
		if bomb == null:
			continue
		var d := pos.distance_to(bomb.global_position)
		var danger: float = Bomb.BLAST_RADIUS * bomb._blast_mult * Settings.blast_scale + 30.0
		if bomb.fuse < THREAT_FUSE and d < danger and d < tdist:
			threat = bomb
			tdist = d

	if threat:
		if tdist < 34.0 and threat.fuse > KICK_FUSE_MIN:
			# Close and still fresh: face it and punt it away.
			axis = signf(threat.global_position.x - pos.x)
			if axis == 0.0:
				axis = 1.0
			kick = true
		else:
			axis = -signf(threat.global_position.x - pos.x)
			if axis == 0.0:
				axis = 1.0 if randf() < 0.5 else -1.0
			jump = player.is_on_floor() and randf() < 0.1
	else:
		_replan -= delta
		if _replan <= 0.0:
			_replan = REPLAN_INTERVAL
			_plan(pos)
		var dx := _target_x - pos.x
		axis = clampf(dx / 24.0, -1.0, 1.0)
		if absf(dx) < 8.0:
			axis = 0.0
		# Pushing into a wall without moving: hop.
		if absf(player.velocity.x) < 10.0 and absf(axis) > 0.5:
			_stuck_time += delta
		else:
			_stuck_time = 0.0
		jump = _stuck_time > 0.15 and player.is_on_floor()

	player.remote_axis = axis
	player.remote_jump = jump
	player.remote_kick = kick


func _plan(pos: Vector2) -> void:
	# Armor greed: detour to a nearby chest at or below our level.
	if not player.armor:
		var best_chest: Node2D = null
		var best_d := 260.0
		for ch in get_tree().get_nodes_in_group(&"chests"):
			var node := ch as Node2D
			if node == null:
				continue
			var d := pos.distance_to(node.global_position)
			if d < best_d and node.global_position.y >= pos.y - 40.0:
				best_d = d
				best_chest = node
		if best_chest:
			_target_x = best_chest.global_position.x
			return

	# Descend: head for the column with the deepest reachable floor nearby.
	var my_col := int(pos.x / Terrain.TILE)
	var my_row := int(pos.y / Terrain.TILE)
	var best_col := my_col
	var best_depth := _floor_row(my_col, my_row)
	for dc in range(-SCAN_COLS, SCAN_COLS + 1):
		var col := my_col + dc
		if col < 3 or col > Terrain.W - 4:
			continue
		var fr := _floor_row(col, my_row)
		if fr > best_depth or (fr == best_depth and absi(col - my_col) < absi(best_col - my_col)):
			best_depth = fr
			best_col = col
	_target_x = (best_col + 0.5) * Terrain.TILE + randf_range(-4.0, 4.0)


## First solid row at or below from_row in this column (how deep you'd get).
func _floor_row(col: int, from_row: int) -> int:
	var r := maxi(from_row, 0)
	while r < Terrain.H - 1 and terrain.cell(col, r + 1) == Terrain.Cell.EMPTY:
		r += 1
	return r
