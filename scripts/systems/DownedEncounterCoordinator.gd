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

# active sessions: target_instance_id -> session dict
var _sessions: Dictionary = {}

# session shape:
# {
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

	# Try to reuse existing session or create a new one
	var session: Dictionary
	if _sessions.has(target_id):
		session = _sessions[target_id]
		# If the session is stale (ignore_until has passed for SPARE), clear it out
		if session["resolved_at"] > 0.0 and session["verdict"] == Verdict.SPARE and RunClock.now() > session["ignore_until"]:
			_sessions.erase(target_id)
			session = _create_session(target, faction_id, group_id, enemy_uid, enemy)
			_sessions[target_id] = session
		else:
			# Ensure the querying enemy is a participant if in range and matches context
			if not session["participant_uids"].has(enemy_uid):
				session["participant_uids"].append(enemy_uid)
	else:
		session = _create_session(target, faction_id, group_id, enemy_uid, enemy)
		_sessions[target_id] = session

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

func _create_session(target: Node, faction_id: String, group_id: String, triggering_enemy_uid: String, triggering_enemy: Node) -> Dictionary:
	var session: Dictionary = {
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

	# Gather nearby participants
	if triggering_enemy != null and triggering_enemy.is_inside_tree():
		var my_chunk_opt: Variant = null
		if EnemyRegistry != null and EnemyRegistry.has_method("world_to_chunk"):
			my_chunk_opt = EnemyRegistry.world_to_chunk(triggering_enemy.global_position)

		var nearby_enemies: Array[Node2D] = []
		if my_chunk_opt != null:
			var my_chunk: Vector2i = my_chunk_opt
			nearby_enemies = EnemyRegistry.get_bucket_neighborhood(my_chunk)
		else:
			# Fallback if registry not available, though less efficient
			nearby_enemies = []
			for node in triggering_enemy.get_tree().get_nodes_in_group("enemy"):
				if node is Node2D:
					nearby_enemies.append(node)

		var target_pos: Vector2 = target.global_position
		for e in nearby_enemies:
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

			if e_faction_id != faction_id and e_group_id != group_id:
				continue

			if e.global_position.distance_to(target_pos) <= encounter_radius:
				var e_uid: String = ""
				if e.has_method("get_enemy_uid"):
					e_uid = e.call("get_enemy_uid")
				elif "entity_uid" in e:
					e_uid = String(e.get("entity_uid"))
				if e_uid == "":
					e_uid = str(e.get_instance_id())

				if not session["participant_uids"].has(e_uid):
					session["participant_uids"].append(e_uid)

	# Ensure triggering enemy is always included
	if not session["participant_uids"].has(triggering_enemy_uid):
		session["participant_uids"].append(triggering_enemy_uid)

	# Sort for deterministic executor selection
	session["participant_uids"].sort()

	return session

func _resolve_verdict(session: Dictionary, faction_id: String) -> void:
	var hostility_modifier: float = 0.0
	if FactionRelationService != null and FactionRelationService.has_method("get_finish_modifier"):
		hostility_modifier = float(FactionRelationService.get_finish_modifier(faction_id, hostility_finish_bonus_max))

	var context_modifier: float = _get_context_modifier(session)
	var finish_chance: float = clampf(base_finish_chance + hostility_modifier + context_modifier, min_finish_chance, max_finish_chance)

	var roll: float = randf()
	if roll < finish_chance:
		session["verdict"] = Verdict.FINISH
		# Deterministic selection: first in sorted list of participants
		if session["participant_uids"].size() > 0:
			session["executor_uid"] = session["participant_uids"][0]
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
	_sessions.erase(target_id)

func notify_target_revived(target: Node) -> void:
	# Since AIComponent caches _ignore_player_until, we can safely clear the session
	# when the player revives to ensure the next downed event starts fresh.
	if target == null:
		return
	var target_id := target.get_instance_id()
	_sessions.erase(target_id)

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
