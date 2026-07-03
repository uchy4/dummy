class_name BombSpawner
extends Node
## Drops bombs from the sky. A short grace period first, then the interval
## ramps down over time. Some bombs aim near a player to keep the pressure on.

const GRACE := 5.0
const SPAWN_Y := -80.0
const AIM_AT_PLAYER_CHANCE := 0.35

var terrain: Terrain
var container: Node2D

var _elapsed := 0.0
var _next_spawn := GRACE


func _physics_process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= _next_spawn:
		_spawn()
		_next_spawn = _elapsed + _interval()


func _interval() -> float:
	return maxf(1.1, 3.4 - _elapsed * 0.022)


func _spawn() -> void:
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
	b.terrain = terrain
	b.fuse = randf_range(3.4, 4.6)
	b.position = Vector2(x, SPAWN_Y)
	container.add_child(b)
