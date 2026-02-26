extends Node

var _enemies: Array[WeakRef] = []
var _cleanup_timer: float = 0.0
const CLEANUP_INTERVAL: float = 5.0


func register_enemy(e: Node) -> void:
	if e == null:
		return

	for w: WeakRef in _enemies:
		var obj: Object = w.get_ref()
		if obj == e:
			return

	_enemies.append(weakref(e))


func unregister_enemy(e: Node) -> void:
	if e == null:
		return

	for i: int in range(_enemies.size() - 1, -1, -1):
		var obj: Object = _enemies[i].get_ref()
		if obj == null or obj == e:
			_enemies.remove_at(i)


func get_live_enemies() -> Array[Node2D]:
	var out: Array[Node2D] = []

	for i: int in range(_enemies.size() - 1, -1, -1):
		var obj: Object = _enemies[i].get_ref()
		if obj == null:
			_enemies.remove_at(i)
			continue

		var enemy: Node2D = obj as Node2D
		if enemy != null:
			out.append(enemy)

	return out


func count() -> int:
	return get_live_enemies().size()


func _process(delta: float) -> void:
	_cleanup_timer += delta
	if _cleanup_timer >= CLEANUP_INTERVAL:
		_cleanup_timer = 0.0
		get_live_enemies()  # fuerza limpieza de refs muertas
