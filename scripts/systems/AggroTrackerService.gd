extends Node

# tracking internal data:
# _engagements[target_id] = Dictionary[enemy_instance_id -> { "enemy_ref": WeakRef, "target_ref": WeakRef, "timestamp": float }]
var _engagements: Dictionary = {}

func register_engagement(enemy: Node, target: Node) -> void:
	if enemy == null or target == null or not is_instance_valid(enemy) or not is_instance_valid(target):
		return

	var target_id := target.get_instance_id()
	var enemy_id := enemy.get_instance_id()

	if not _engagements.has(target_id):
		_engagements[target_id] = {}

	_engagements[target_id][enemy_id] = {
		"enemy_ref": weakref(enemy),
		"target_ref": weakref(target),
		"timestamp": RunClock.now()
	}

func clear_enemy(enemy: Node) -> void:
	if enemy == null:
		return
	var enemy_id := enemy.get_instance_id()

	for target_id in _engagements.keys():
		var target_dict: Dictionary = _engagements[target_id]
		if target_dict.has(enemy_id):
			target_dict.erase(enemy_id)

		if target_dict.is_empty():
			_engagements.erase(target_id)

func clear_target(target: Node) -> void:
	if target == null:
		return
	var target_id := target.get_instance_id()
	_engagements.erase(target_id)

func get_recent_attackers(target: Node, max_age_seconds: float = 5.0) -> Array[Node]:
	var result: Array[Node] = []
	if target == null or not is_instance_valid(target):
		return result

	var target_id := target.get_instance_id()
	if not _engagements.has(target_id):
		return result

	var current_time := RunClock.now()
	var target_dict: Dictionary = _engagements[target_id]
	var to_erase: Array[int] = []

	for enemy_id in target_dict.keys():
		var data: Dictionary = target_dict[enemy_id]
		var enemy_ref: WeakRef = data.get("enemy_ref")
		var timestamp: float = data.get("timestamp", 0.0)

		if enemy_ref == null or enemy_ref.get_ref() == null or not is_instance_valid(enemy_ref.get_ref()):
			to_erase.append(enemy_id)
			continue

		if current_time - timestamp <= max_age_seconds:
			result.append(enemy_ref.get_ref() as Node)

	for enemy_id in to_erase:
		target_dict.erase(enemy_id)

	if target_dict.is_empty():
		_engagements.erase(target_id)

	return result

func was_enemy_recently_engaged_with(enemy: Node, target: Node, max_age_seconds: float = 5.0) -> bool:
	if enemy == null or target == null or not is_instance_valid(enemy) or not is_instance_valid(target):
		return false

	var target_id := target.get_instance_id()
	var enemy_id := enemy.get_instance_id()

	if not _engagements.has(target_id):
		return false

	var target_dict: Dictionary = _engagements[target_id]
	if not target_dict.has(enemy_id):
		return false

	var data: Dictionary = target_dict[enemy_id]
	var enemy_ref: WeakRef = data.get("enemy_ref")
	var timestamp: float = data.get("timestamp", 0.0)

	if enemy_ref == null or enemy_ref.get_ref() == null or not is_instance_valid(enemy_ref.get_ref()):
		target_dict.erase(enemy_id)
		if target_dict.is_empty():
			_engagements.erase(target_id)
		return false

	return (RunClock.now() - timestamp) <= max_age_seconds
