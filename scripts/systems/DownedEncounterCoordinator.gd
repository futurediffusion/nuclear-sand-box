extends Node


enum Verdict {
	NONE,
	SPARE,
	FINISH
}

@export var base_finish_chance: float = 0.30
@export var min_finish_chance: float = 0.05
@export var max_finish_chance: float = 0.95
@export var hostility_finish_bonus_max: float = 0.40
@export var spare_ignore_seconds: float = 4.0
@export var spare_safe_radius: float = 180.0
@export var finish_perimeter_radius: float = 120.0
@export var encounter_radius: float = 220.0
@export var engagement_memory_seconds: float = 5.0
@export var max_participant_distance: float = 480.0

# active sessions: encounter_key -> session dict
var _sessions: Dictionary = {}

## Cuando > RunClock.now(), todos los encuentros resuelven SPARE (sin remate).
## Usar force_spare_for() tras eventos como abrir un barril de facción.
var _force_spare_until: float = 0.0

func force_spare_for(duration: float) -> void:
	_force_spare_until = RunClock.now() + duration

# session shape:
# {
#     "encounter_key": String,
#     "target_id": int,
#     "target_ref": WeakRef,
#     "group_id": String,
#     "faction_id": String,
#     "participant_uids": Array[String],
#     "verdict": int,
#     "executor_uid": String,
#     "created_at": float,
#     "resolved_at": float,
#     "ignore_until": float,
#     "safe_radius": float
# }

func _extract_faction_id(node: Node) -> String:
	if node.has_method("get_faction_id"):
		return node.call("get_faction_id")
	elif "faction_id" in node:
		return String(node.get("faction_id"))
	return ""

func _extract_group_id(node: Node) -> String:
	if node.has_method("get_group_id"):
		return node.call("get_group_id")
	elif "group_id" in node:
		return String(node.get("group_id"))
	return ""

func _extract_enemy_uid(node: Node) -> String:
	var uid: String = ""
	if node.has_method("get_enemy_uid"):
		uid = node.call("get_enemy_uid")
	elif "entity_uid" in node:
		uid = String(node.get("entity_uid"))

	if uid == "":
		uid = str(node.get_instance_id())
	return uid

func _is_enemy_uid_in_session(enemy_uid: String, session: Dictionary) -> bool:
	if session.has("participant_uids"):
		return session["participant_uids"].has(enemy_uid)
	return false

func get_policy_for_enemy(enemy: Node, target: Node) -> Dictionary:
	var empty_policy: Dictionary = {
		"active": false,
		"verdict": Verdict.NONE,
		"executor_uid": "",
		"ignore_until": 0.0,
		"safe_radius": 0.0
	}

	if enemy == null or target == null or not is_instance_valid(target) or not is_instance_valid(enemy):
		return empty_policy

	var is_target_downed: bool = false
	if target.has_method("is_downed"):
		is_target_downed = target.call("is_downed")
	elif "is_downed" in target:
		is_target_downed = target.get("is_downed")

	if not is_target_downed:
		return empty_policy

	var faction_id := _extract_faction_id(enemy)
	var group_id := _extract_group_id(enemy)
	var enemy_uid := _extract_enemy_uid(enemy)

	var encounter_key := _make_encounter_key(target, faction_id, group_id)
	var session: Dictionary

	if _sessions.has(encounter_key):
		session = _sessions[encounter_key]
	else:
		session = _create_session(encounter_key, target, faction_id, group_id)
		if session.is_empty():
			return empty_policy
		_sessions[encounter_key] = session

	if not _is_enemy_uid_in_session(enemy_uid, session):
		return empty_policy

	# If unresolved, roll verdict
	if session["verdict"] == Verdict.NONE:
		_resolve_verdict(session, faction_id)

	return {
		"active": true,
		"verdict": session["verdict"],
		"executor_uid": session["executor_uid"],
		"ignore_until": session["ignore_until"],
		"safe_radius": session["safe_radius"]
	}

func _make_encounter_key(target: Node, faction_id: String, group_id: String) -> String:
	var target_id := target.get_instance_id()
	var group_id_or_fallback := group_id if group_id != "" else faction_id
	return "%s|%s|%s" % [str(target_id), faction_id, group_id_or_fallback]

func _get_session_for_enemy_and_target(enemy: Node, target: Node) -> Variant:
	if enemy == null or target == null:
		return null

	var faction_id := _extract_faction_id(enemy)
	var group_id := _extract_group_id(enemy)

	var key := _make_encounter_key(target, faction_id, group_id)
	return _sessions.get(key, null)

func _create_session(encounter_key: String, target: Node, faction_id: String, group_id: String) -> Dictionary:
	# Gather participants strictly from AggroTrackerService
	var valid_participants := _gather_participants(target, faction_id, group_id)

	if valid_participants.is_empty():
		return {}

	var session: Dictionary = {
		"encounter_key": encounter_key,
		"target_id": target.get_instance_id(),
		"target_ref": weakref(target),
		"group_id": group_id,
		"faction_id": faction_id,
		"participant_uids": valid_participants,
		"verdict": Verdict.NONE,
		"executor_uid": "",
		"created_at": RunClock.now(),
		"resolved_at": 0.0,
		"ignore_until": 0.0,
		"safe_radius": spare_safe_radius
	}

	return session

func _gather_participants(target: Node, faction_id: String, group_id: String) -> Array[String]:
	var valid_uids: Array[String] = []

	if AggroTrackerService != null and AggroTrackerService.has_method("get_recent_attackers"):
		var recent_attackers: Array[Node] = AggroTrackerService.get_recent_attackers(target, engagement_memory_seconds)
		var target_pos: Vector2 = (target as Node2D).global_position

		for e in recent_attackers:
			if e == null or not is_instance_valid(e) or e.is_queued_for_deletion():
				continue

			var e_faction_id := _extract_faction_id(e)
			var e_group_id := _extract_group_id(e)

			if e_faction_id != faction_id:
				continue

			if group_id != "" and e_group_id != group_id:
				continue

			var dist: float = (e as Node2D).global_position.distance_to(target_pos)
			if dist > max_participant_distance:
				continue

			var e_uid := _extract_enemy_uid(e)
			if not valid_uids.has(e_uid):
				valid_uids.append(e_uid)

	valid_uids.sort()
	return valid_uids

func _resolve_verdict(session: Dictionary, faction_id: String) -> void:
	# Forzar SPARE si hay un evento activo (e.g. barril abierto — lección, no ejecución)
	if RunClock.now() < _force_spare_until:
		session["verdict"]      = Verdict.SPARE
		session["ignore_until"] = RunClock.now() + spare_ignore_seconds
		session["resolved_at"]  = RunClock.now()
		return

	var hostility_modifier: float = \
		float(FactionHostilityManager.get_hostility_level(faction_id)) / 10.0 \
		* hostility_finish_bonus_max

	var context_modifier: float = _get_context_modifier(session)
	var finish_chance: float = clampf(base_finish_chance + hostility_modifier + context_modifier, min_finish_chance, max_finish_chance)

	var roll: float = randf()
	if roll < finish_chance:
		session["verdict"] = Verdict.FINISH
		# Deterministic executor selection: hash of key mod participant count
		if session["participant_uids"].size() > 0:
			var idx: int = int(abs(hash(session["encounter_key"]))) % session["participant_uids"].size()
			session["executor_uid"] = session["participant_uids"][idx]
	else:
		session["verdict"] = Verdict.SPARE
		session["ignore_until"] = RunClock.now() + spare_ignore_seconds

	session["resolved_at"] = RunClock.now()

func _get_context_modifier(session: Dictionary) -> float:
	# Future expansion point
	return 0.0

func clear_target_session(target: Node) -> void:
	if target == null:
		return
	var target_id := target.get_instance_id()
	var keys_to_erase: Array[String] = []
	for k in _sessions.keys():
		var s: Dictionary = _sessions[k]
		if int(s.get("target_id", -1)) == target_id:
			keys_to_erase.append(String(k))
	for k in keys_to_erase:
		_sessions.erase(k)

func notify_target_revived(target: Node) -> void:
	# AIComponent caches _ignore_target_until. We clear the session
	# when the target revives to ensure the next downed event starts fresh.
	clear_target_session(target)

func notify_target_died_final(target: Node) -> void:
	clear_target_session(target)

func can_enemy_finish_target(enemy: Node, target: Node) -> bool:
	var policy := get_policy_for_enemy(enemy, target)
	if not bool(policy.get("active", false)):
		return false

	var enemy_uid := _extract_enemy_uid(enemy)

	return int(policy.get("verdict", Verdict.NONE)) == Verdict.FINISH and String(policy.get("executor_uid", "")) == enemy_uid
