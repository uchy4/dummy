class_name BombSpawner
extends Node
## Drops waves of bombs from the sky. A short grace period first, then the
## interval ramps down over time. Wave size, pacing, and which bomb types are
## in the pool all come from Settings (tunable in-game). Some bombs aim near a
## player to keep the pressure on.

const GRACE := 5.0
const SPAWN_Y := -80.0
const AIM_AT_PLAYER_CHANCE := 0.35
const MAX_LIVE_BOMBS := 90

var terrain: Terrain
var container: Node2D

var _elapsed := 0.0
var _next_spawn := GRACE


func _physics_process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= _next_spawn:
		_spawn_wave()
		_next_spawn = _elapsed + _interval()


## 0 at match start, 1 once ramp_time has elapsed: the difficulty dial.
func _difficulty() -> float:
	return clampf((_elapsed - GRACE) / maxf(Settings.ramp_time, 1.0), 0.0, 1.0)


func _interval() -> float:
	var floor_interval := maxf(0.5, Settings.drop_interval * 0.18)
	return lerpf(Settings.drop_interval, floor_interval, _difficulty())


func _spawn_wave() -> void:
	# Fizzled duds stay on the field forever — don't let them eat the
	# live-bomb budget or the bombardment would slowly starve.
	var live := 0
	for b in get_tree().get_nodes_in_group(&"bombs"):
		var bomb := b as Bomb
		if bomb and not bomb.fizzled:
			live += 1
	var count := maxi(1, roundi(lerpf(1.0, float(Settings.bombs_per_drop), _difficulty())))
	for i in count:
		if live + i >= MAX_LIVE_BOMBS:
			return
		_spawn_one(i)


func _spawn_one(index: int) -> void:
	var min_x := 3.0 * Terrain.TILE
	var max_x := (Terrain.W - 3.0) * Terrain.TILE
	var x := randf_range(min_x, max_x)

	if randf() < AIM_AT_PLAYER_CHANCE:
		var alive: Array[Node] = []
		for p in get_tree().get_nodes_in_group(&"players"):
			if p is Player and (p as Player).alive:
				alive.append(p)
		if not alive.is_empty():
			var target := alive.pick_random() as Player
			x = clampf(target.global_position.x + randf_range(-90.0, 90.0), min_x, max_x)

	var b := Bomb.new()
	b.type = _pick_type()
	b.terrain = terrain
	b.fuse = randf_range(3.4, 4.6)
	# Stagger wave members vertically so they don't spawn overlapping.
	b.position = Vector2(x, SPAWN_Y - index * 40.0)
	container.add_child(b)


func _pick_type() -> Bomb.Type:
	var pool: Array[int] = []
	for t in Settings.type_enabled.size():
		if Settings.type_enabled[t]:
			pool.append(t)
	if pool.is_empty():
		return Bomb.Type.NORMAL
	return pool.pick_random() as Bomb.Type
