extends Node
class_name DownedEncounterCoordinator

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

	var target_id := target.get_instance_id()

	var faction_id: String = ""
	if enemy.has_method("get_faction_id"):
		faction_id = enemy.call("get_faction_id")
	elif "faction_id" in enemy:
		faction_id = String(enemy.get("faction_id"))

	var group_id: String = ""
	if enemy.has_method("get_group_id"):
		group_id = enemy.call("get_group_id")
	elif "group_id" in enemy:
		group_id = String(enemy.get("group_id"))

	var enemy_uid: String = ""
	if enemy.has_method("get_enemy_uid"):
		enemy_uid = enemy.call("get_enemy_uid")
	elif "entity_uid" in enemy:
		enemy_uid = String(enemy.get("entity_uid"))

	if enemy_uid == "":
		enemy_uid = str(enemy.get_instance_id())

	var encounter_key := _make_encounter_key(target, faction_id, group_id)
	var session: Dictionary

	if _sessions.has(encounter_key):
		session = _sessions[encounter_key]

		# Only add the querying enemy if they are not already a participant,
		# and they actually pass the strict aggro/context checks.
		if not session["participant_uids"].has(enemy_uid):
			var valid_participants := _gather_participants(target, faction_id, group_id)
			if valid_participants.has(enemy_uid):
				session["participant_uids"].append(enemy_uid)
				session["participant_uids"].sort()
	else:
		session = _create_session(encounter_key, target, faction_id, group_id, enemy_uid, enemy)
		_sessions[encounter_key] = session

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

	var faction_id: String = ""
	if enemy.has_method("get_faction_id"):
		faction_id = enemy.call("get_faction_id")
	elif "faction_id" in enemy:
		faction_id = String(enemy.get("faction_id"))

	var group_id: String = ""
	if enemy.has_method("get_group_id"):
		group_id = enemy.call("get_group_id")
	elif "group_id" in enemy:
		group_id = String(enemy.get("group_id"))

	var key := _make_encounter_key(target, faction_id, group_id)
	return _sessions.get(key, null)

func _create_session(encounter_key: String, target: Node, faction_id: String, group_id: String, triggering_enemy_uid: String, triggering_enemy: Node) -> Dictionary:
	var session: Dictionary = {
		"encounter_key": encounter_key,
		"target_id": target.get_instance_id(),
		"target_ref": weakref(target),
		"group_id": group_id,
		"faction_id": faction_id,
		"participant_uids": [],
		"verdict": Verdict.NONE,
		"executor_uid": "",
		"created_at": RunClock.now(),
		"resolved_at": 0.0,
		"ignore_until": 0.0,
		"safe_radius": spare_safe_radius
	}

	# Gather participants using strictly AggroTrackerService
	var valid_participants := _gather_participants(target, faction_id, group_id)

	for uid in valid_participants:
		if not session["participant_uids"].has(uid):
			session["participant_uids"].append(uid)

	# Sort for deterministic executor selection
	session["participant_uids"].sort()

	return session

func _gather_participants(target: Node, faction_id: String, group_id: String) -> Array[String]:
	var valid_uids: Array[String] = []

	if AggroTrackerService != null and AggroTrackerService.has_method("get_recent_attackers"):
		var recent_attackers: Array[Node] = AggroTrackerService.get_recent_attackers(target, engagement_memory_seconds)
		var target_pos: Vector2 = target.global_position

		for e in recent_attackers:
			if e == null or not is_instance_valid(e) or e.is_queued_for_deletion():
				continue

			var e_faction_id: String = ""
			if e.has_method("get_faction_id"):
				e_faction_id = e.call("get_faction_id")
			elif "faction_id" in e:
				e_faction_id = String(e.get("faction_id"))

			var e_group_id: String = ""
			if e.has_method("get_group_id"):
				e_group_id = e.call("get_group_id")
			elif "group_id" in e:
				e_group_id = String(e.get("group_id"))

			if e_faction_id != faction_id:
				continue

			if group_id != "" and e_group_id != group_id:
				continue

			var dist := e.global_position.distance_to(target_pos)
			if dist > max_participant_distance:
				continue

			var e_uid: String = ""
			if e.has_method("get_enemy_uid"):
				e_uid = e.call("get_enemy_uid")
			elif "entity_uid" in e:
				e_uid = String(e.get("entity_uid"))
			if e_uid == "":
				e_uid = str(e.get_instance_id())

			if not valid_uids.has(e_uid):
				valid_uids.append(e_uid)

	return valid_uids

func _resolve_verdict(session: Dictionary, faction_id: String) -> void:
	var hostility_modifier: float = 0.0
	if FactionRelationService != null and FactionRelationService.has_method("get_finish_modifier"):
		hostility_modifier = float(FactionRelationService.get_finish_modifier(faction_id, hostility_finish_bonus_max))

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

	var enemy_uid: String = ""
	if enemy.has_method("get_enemy_uid"):
		enemy_uid = enemy.call("get_enemy_uid")
	elif "entity_uid" in enemy:
		enemy_uid = String(enemy.get("entity_uid"))
	if enemy_uid == "":
		enemy_uid = str(enemy.get_instance_id())

	return int(policy.get("verdict", Verdict.NONE)) == Verdict.FINISH and String(policy.get("executor_uid", "")) == enemy_uid
