extends Node

var _enemies: Array[WeakRef] = []


func register_enemy(e: Node) -> void:
	if e == null:
		return

	for w in _enemies:
		var obj := w.get_ref()
		if obj == e:
			return

	_enemies.append(weakref(e))


func unregister_enemy(e: Node) -> void:
	if e == null:
		return

	for i in range(_enemies.size() - 1, -1, -1):
		var obj := _enemies[i].get_ref()
		if obj == null or obj == e:
			_enemies.remove_at(i)


func get_live_enemies() -> Array[Node2D]:
	var out: Array[Node2D] = []

	for i in range(_enemies.size() - 1, -1, -1):
		var obj := _enemies[i].get_ref()
		if obj == null:
			_enemies.remove_at(i)
			continue

		if obj is Node2D:
			out.append(obj)

	return out


func count() -> int:
	return get_live_enemies().size()
