extends Node

# RaidQueue — intents de raid pendientes por grupo.
# Paralelo a ExtortionQueue pero para incursiones a la base del jugador.
# Sin persistencia — los raids son eventos efímeros de runtime.
#
# Intent dict:
# {
#   "faction_id":  String,   # facción que ejecuta el raid
#   "group_id":    String,   # grupo concreto
#   "leader_id":   String,   # líder del grupo
#   "base_center": Vector2,  # centro de la base detectada como objetivo
#   "base_id":     String,   # ID de la base en SettlementIntel
#   "created_at":  float,    # RunClock.now() al crear
# }

var _intents: Array = []
var _last_raid_time_by_group: Dictionary = {}  # group_id → RunClock.now()


func enqueue_raid(faction_id: String, group_id: String, leader_id: String,
		base_center: Vector2, base_id: String) -> void:
	var intent: Dictionary = {
		"faction_id":  faction_id,
		"group_id":    group_id,
		"leader_id":   leader_id,
		"base_center": base_center,
		"base_id":     base_id,
		"created_at":  RunClock.now(),
	}
	_intents.append(intent)
	if group_id != "":
		_last_raid_time_by_group[group_id] = RunClock.now()
	Debug.log("raid", "[RQ] raid enqueued — group=%s base=%s center=%s" % [
		group_id, base_id, str(base_center)])


func has_pending_for_group(group_id: String) -> bool:
	for i in _intents:
		if String(i.get("group_id", "")) == group_id:
			return true
	return false


func consume_for_group(group_id: String) -> Array:
	var result: Array = []
	var remaining: Array = []
	for i in _intents:
		if String(i.get("group_id", "")) == group_id:
			result.append(i)
		else:
			remaining.append(i)
	_intents = remaining
	return result


func get_last_raid_time(group_id: String) -> float:
	return float(_last_raid_time_by_group.get(group_id, 0.0))


func clear_all() -> void:
	_intents.clear()
	_last_raid_time_by_group.clear()
