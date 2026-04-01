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
var _last_raid_time_by_group: Dictionary = {}        # group_id → RunClock.now()
var _last_wall_probe_time_by_group: Dictionary = {}  # group_id → RunClock.now()


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


func enqueue_light_raid(faction_id: String, group_id: String, leader_id: String,
		base_center: Vector2, base_id: String) -> void:
	var intent: Dictionary = {
		"faction_id":  faction_id,
		"group_id":    group_id,
		"leader_id":   leader_id,
		"base_center": base_center,
		"base_id":     base_id,
		"raid_type":   "light",
		"created_at":  RunClock.now(),
	}
	_intents.append(intent)
	if group_id != "":
		_last_raid_time_by_group[group_id] = RunClock.now()
	Debug.log("raid", "[RQ] light raid enqueued — group=%s base=%s center=%s" % [
		group_id, base_id, str(base_center)])


func enqueue_wall_probe(faction_id: String, group_id: String, leader_id: String,
		base_center: Vector2, base_id: String, probe_squad_size: int) -> void:
	var intent: Dictionary = {
		"faction_id":       faction_id,
		"group_id":         group_id,
		"leader_id":        leader_id,
		"base_center":      base_center,
		"base_id":          base_id,
		"raid_type":        "wall_probe",
		"probe_squad_size": probe_squad_size,
		"created_at":       RunClock.now(),
	}
	_intents.append(intent)
	if group_id != "":
		_last_raid_time_by_group[group_id]       = RunClock.now()
		_last_wall_probe_time_by_group[group_id] = RunClock.now()
	Debug.log("raid", "[RQ] wall probe enqueued — group=%s base=%s squad=%d" % [
		group_id, base_id, probe_squad_size])


func enqueue_structure_assault(faction_id: String, group_id: String, leader_id: String,
		base_center: Vector2, base_id: String, squad_size: int) -> void:
	var intent: Dictionary = {
		"faction_id":       faction_id,
		"group_id":         group_id,
		"leader_id":        leader_id,
		"base_center":      base_center,
		"base_id":          base_id,
		"raid_type":        "structure_assault",
		"probe_squad_size": squad_size,
		"created_at":       RunClock.now(),
	}
	_intents.append(intent)
	if group_id != "":
		_last_raid_time_by_group[group_id]       = RunClock.now()
		_last_wall_probe_time_by_group[group_id] = RunClock.now()
	Debug.log("raid", "[RQ] structure assault enqueued — group=%s squad=%d center=%s" % [
		group_id, squad_size, str(base_center)])


func get_last_wall_probe_time(group_id: String) -> float:
	return float(_last_wall_probe_time_by_group.get(group_id, 0.0))


## Owner-read helper: cooldown restante para raids (light/full/shared).
func get_raid_cooldown_remaining(group_id: String, cooldown: float) -> float:
	var cd: float = maxf(0.0, cooldown)
	if cd <= 0.0:
		return 0.0
	var elapsed: float = RunClock.now() - get_last_raid_time(group_id)
	return maxf(0.0, cd - elapsed)


## Owner-read helper: cooldown restante para probes de pared.
func get_wall_probe_cooldown_remaining(group_id: String, cooldown: float) -> float:
	var cd: float = maxf(0.0, cooldown)
	if cd <= 0.0:
		return 0.0
	var elapsed: float = RunClock.now() - get_last_wall_probe_time(group_id)
	return maxf(0.0, cd - elapsed)


func has_pending_for_group(group_id: String) -> bool:
	for i in _intents:
		if String(i.get("group_id", "")) == group_id:
			return true
	return false


func has_structure_assault_for_group(group_id: String) -> bool:
	for i in _intents:
		if String(i.get("group_id", "")) == group_id \
				and String(i.get("raid_type", "")) == "structure_assault":
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
	_last_wall_probe_time_by_group.clear()
