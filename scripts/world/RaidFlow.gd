class_name RaidFlow
extends Node

# Raid lifecycle orchestrator for player-base assaults.
# Jobs are consumed from RaidQueue and translated into group movement dispatches.

const ATTACK_RADIUS: float = 450.0
const APPROACH_TIMEOUT: float = 90.0
const ATTACK_DURATION: float = 60.0
const MAX_RAID_DURATION: float = 150.0
const WALL_ASSAULT_INTERVAL: float = 6.0
const WALL_SEARCH_RADIUS: float = 600.0
const PLACEABLE_SEARCH_RADIUS: float = 700.0
const STRUCTURE_ASSAULT_GLOBAL_SEARCH_RADIUS: float = 12000.0
const STRUCTURE_ASSAULT_ENABLE_GLOBAL_WALL_FALLBACK: bool = true

const LIGHT_ATTACK_DURATION: float = 30.0
const LIGHT_MAX_DURATION: float = 75.0

const STRUCTURE_APPROACH_TIMEOUT: float = 180.0
const STRUCTURE_ATTACK_DURATION: float = 120.0
const STRUCTURE_MAX_DURATION: float = 360.0
const STRUCTURE_APPROACH_DISPATCH_INTERVAL: float = 2.2
const DISPATCH_JITTER_RATIO: float = 0.16
const STRUCTURE_NO_TARGET_NEAR_RADIUS: float = 260.0
const STRUCTURE_NO_TARGET_NEAR_RADIUS_SQ: float = STRUCTURE_NO_TARGET_NEAR_RADIUS * STRUCTURE_NO_TARGET_NEAR_RADIUS
const STRUCTURE_TARGET_STABILITY_EPSILON: float = 56.0
const STRUCTURE_TARGET_STABILITY_EPSILON_SQ: float = STRUCTURE_TARGET_STABILITY_EPSILON * STRUCTURE_TARGET_STABILITY_EPSILON

const INVALID_TARGET: Vector2 = Vector2(-1.0, -1.0)

var _npc_simulator: NpcSimulator = null
var _find_wall: Callable = Callable()
var _find_workbench: Callable = Callable()
var _find_storage: Callable = Callable()
var _find_placeable: Callable = Callable()
var _dispatch_group_to_target: Callable = Callable()

var _active_jobs: Dictionary = {}  # group_id -> job


func setup(ctx: Dictionary) -> void:
	_npc_simulator = ctx.get("npc_simulator")
	_dispatch_group_to_target = ctx.get("dispatch_group_to_target_cb", Callable())
	set_process(false)


func set_wall_query(cb: Callable) -> void:
	_find_wall = cb


func set_workbench_query(cb: Callable) -> void:
	_find_workbench = cb


func set_storage_query(cb: Callable) -> void:
	_find_storage = cb


func set_placeable_query(cb: Callable) -> void:
	_find_placeable = cb


func process_flow() -> void:
	_abort_invalid_jobs()
	_consume_raid_queue()
	_consume_memory_assault_intents()
	_tick_jobs()


func _consume_raid_queue() -> void:
	for gid in BanditGroupMemory.get_all_group_ids():
		if _has_active_job(gid):
			continue
		var g: Dictionary = BanditGroupMemory.get_group(gid)
		var intent_ok: bool = String(g.get("current_group_intent", "")) == "raiding"
		var force_consume: bool = RaidQueue.has_structure_assault_for_group(gid)
		if not intent_ok and not force_consume:
			continue
		var intents: Array = RaidQueue.consume_for_group(gid)
		if intents.is_empty():
			continue
		var chosen: Dictionary = _pick_intent_to_execute(intents)
		if chosen.is_empty():
			continue
		var raid_type: String = String(chosen.get("raid_type", "full"))
		if raid_type == "structure_assault":
			var base_center: Vector2 = chosen.get("base_center", INVALID_TARGET) as Vector2
			var reason: String = String(chosen.get("trigger", "raid_queue"))
			var squad_size: int = int(chosen.get("probe_squad_size", -1))
			BanditGroupMemory.publish_assault_target_intent(
				gid,
				base_center,
				base_center,
				"%s:squad=%d" % [reason, squad_size],
				BanditTuning.structure_assault_active_ttl(),
				BanditGroupMemory.ASSAULT_INTENT_SOURCE_RAID_QUEUE
			)
		_create_job(gid, chosen)


func _consume_memory_assault_intents() -> void:
	for gid in BanditGroupMemory.get_all_group_ids():
		if _has_active_job(gid):
			continue
		var intent: Dictionary = BanditGroupMemory.get_assault_target_intent(gid)
		if intent.is_empty():
			continue
		_create_job(gid, _job_from_assault_intent(gid, intent))


func _job_from_assault_intent(gid: String, intent: Dictionary) -> Dictionary:
	var g: Dictionary = BanditGroupMemory.get_group(gid)
	return {
		"raid_type": "structure_assault",
		"faction_id": String(g.get("faction_id", "")),
		"leader_id": String(g.get("leader_id", "")),
		"base_center": intent.get("anchor", INVALID_TARGET) as Vector2,
		"probe_squad_size": -1,
		"trigger": String(intent.get("reason", "assault_intent")),
	}


func _pick_intent_to_execute(intents: Array) -> Dictionary:
	if intents.is_empty():
		return {}
	var chosen: Dictionary = intents[0] as Dictionary
	var best_score: int = _raid_type_priority(String(chosen.get("raid_type", "full")))
	var best_created_at: float = float(chosen.get("created_at", 0.0))
	for raw_intent in intents:
		if not (raw_intent is Dictionary):
			continue
		var intent: Dictionary = raw_intent as Dictionary
		var raid_type: String = String(intent.get("raid_type", "full"))
		var score: int = _raid_type_priority(raid_type)
		var created_at: float = float(intent.get("created_at", 0.0))
		if score > best_score or (score == best_score and created_at >= best_created_at):
			chosen = intent
			best_score = score
			best_created_at = created_at
	return chosen


func _raid_type_priority(raid_type: String) -> int:
	match raid_type:
		"structure_assault":
			return 4
		"full":
			return 3
		"light":
			return 2
		"wall_probe":
			return 1
		_:
			return 0


func _create_job(gid: String, intent: Dictionary) -> void:
	var raid_type: String = String(intent.get("raid_type", "full"))
	var raw_squad_size: int = int(intent.get("probe_squad_size", -1))
	_active_jobs[gid] = {
		"group_id": gid,
		"faction_id": String(intent.get("faction_id", "")),
		"leader_id": String(intent.get("leader_id", "")),
		"base_center": intent.get("base_center", Vector2.ZERO) as Vector2,
		"raid_type": raid_type,
		"probe_squad_size": raw_squad_size,
		"stage": "approaching",
		"started_at": RunClock.now(),
		"attack_started_at": 0.0,
		"wall_assault_next_at": 0.0,
		"approach_next_at": 0.0,
		"last_dispatched_target": INVALID_TARGET,
		"no_target_since": 0.0,
	}
	Debug.log("raid", "[RF] job created group=%s type=%s base=%s squad=%d" % [
		gid, raid_type, str(intent.get("base_center", Vector2.ZERO)), raw_squad_size
	])
	if raid_type == "structure_assault":
		BanditGroupMemory.mark_structure_assault_active(gid, BanditTuning.structure_assault_active_ttl())


func _tick_jobs() -> void:
	var done_ids: Array[String] = []
	for gid in _active_jobs.keys():
		var job: Dictionary = _active_jobs[gid] as Dictionary
		var raid_type: String = String(job.get("raid_type", "full"))
		match String(job.get("stage", "")):
			"approaching":
				if _tick_approaching(job, gid):
					done_ids.append(gid)
			"attacking":
				match raid_type:
					"light":
						_tick_placeable_assault(job, gid)
					"wall_probe":
						_tick_wall_probe_assault(job, gid)
					"structure_assault":
						_tick_structure_assault(job, gid)
					_:
						_tick_wall_assault(job, gid)
				if _tick_attacking(job, gid):
					done_ids.append(gid)
	for gid in done_ids:
		_finish_raid(gid, "retreat")


func _tick_approaching(job: Dictionary, gid: String) -> bool:
	var total: float = RunClock.now() - float(job.get("started_at", RunClock.now()))
	if total >= _max_total_for_job(job):
		return true

	var now: float = RunClock.now()
	var base_center: Vector2 = job.get("base_center", Vector2.ZERO) as Vector2
	if String(job.get("raid_type", "")) == "structure_assault":
		var intent_contract: Dictionary = BanditGroupMemory.get_assault_target_intent(gid)
		var intent_anchor: Vector2 = intent_contract.get("anchor", INVALID_TARGET) as Vector2
		var intent_target: Vector2 = intent_contract.get("target_pos", INVALID_TARGET) as Vector2
		if _is_valid_target(intent_anchor):
			base_center = intent_anchor
			job["base_center"] = intent_anchor
		var approach_target: Vector2 = intent_target if _is_valid_target(intent_target) else base_center
		if _is_valid_target(approach_target) and now >= float(job.get("approach_next_at", 0.0)):
			var requested: int = int(job.get("probe_squad_size", -1))
			if requested == 0:
				requested = -1
			var redirected: int = _dispatch_group(gid, approach_target, requested)
			if redirected > 0:
				job["last_dispatched_target"] = approach_target
			job["approach_next_at"] = _next_dispatch_at(gid, STRUCTURE_APPROACH_DISPATCH_INTERVAL)
			Debug.log("raid", "[RF] structure approach dispatch group=%s target=%s redirected=%d" % [
				gid, str(approach_target), redirected
			])

	var leader_id: String = String(job.get("leader_id", ""))
	var close_enough: bool = false

	if leader_id != "" and _npc_simulator != null:
		var leader_node = _npc_simulator.get_enemy_node(leader_id)
		if leader_node != null:
			close_enough = (leader_node as Node2D).global_position.distance_to(base_center) <= ATTACK_RADIUS

	var timed_out: bool = total >= _approach_timeout_for_job(job)
	if close_enough or timed_out:
		job["stage"] = "attacking"
		job["attack_started_at"] = RunClock.now()
		job["wall_assault_next_at"] = now
		Debug.log("raid", "[RF] stage=attacking group=%s close=%s timeout=%s" % [
			gid, str(close_enough), str(timed_out)
		])
	return false


func _tick_wall_assault(job: Dictionary, gid: String) -> void:
	if RunClock.now() < float(job.get("wall_assault_next_at", 0.0)):
		return
	var faction_id: String = String(job.get("faction_id", ""))
	if faction_id != "":
		var profile: FactionBehaviorProfile = FactionHostilityManager.get_behavior_profile(faction_id)
		if not profile.can_damage_walls:
			return

	var anchor: Vector2 = job.get("base_center", Vector2.ZERO) as Vector2
	var target_pos: Vector2 = _resolve_structure_target(anchor, true, true)
	if not _is_valid_target(target_pos):
		return

	var redirected: int = _dispatch_group(gid, target_pos, -1)
	job["base_center"] = target_pos
	job["wall_assault_next_at"] = _next_dispatch_at(gid, WALL_ASSAULT_INTERVAL)
	if redirected > 0:
		Debug.log("raid", "[RF] full assault group=%s target=%s redirected=%d/ALL" % [
			gid, str(target_pos), redirected
		])


func _tick_placeable_assault(job: Dictionary, gid: String) -> void:
	if RunClock.now() < float(job.get("wall_assault_next_at", 0.0)):
		return
	var faction_id: String = String(job.get("faction_id", ""))
	var profile: FactionBehaviorProfile = FactionHostilityManager.get_behavior_profile(faction_id)
	if not profile.can_damage_workbenches:
		return

	var anchor: Vector2 = job.get("base_center", Vector2.ZERO) as Vector2
	var target_pos: Vector2 = INVALID_TARGET
	var wall_chance: float = clampf((profile.hostility_level - 6) * 0.20 + 0.05, 0.0, 1.0)

	if _find_wall.is_valid() and randf() < wall_chance:
		target_pos = _find_wall.call(anchor, WALL_SEARCH_RADIUS) as Vector2

	if not _is_valid_target(target_pos):
		target_pos = _resolve_structure_target(anchor, false, true)
	if not _is_valid_target(target_pos) and _find_wall.is_valid():
		target_pos = _find_wall.call(anchor, WALL_SEARCH_RADIUS) as Vector2
	if not _is_valid_target(target_pos):
		return

	var redirected: int = _dispatch_group(gid, target_pos, -1)
	job["base_center"] = target_pos
	job["wall_assault_next_at"] = _next_dispatch_at(gid, WALL_ASSAULT_INTERVAL)
	if redirected > 0:
		Debug.log("raid", "[RF] light assault group=%s target=%s redirected=%d/ALL wall_chance=%.0f%%" % [
			gid, str(target_pos), redirected, wall_chance * 100.0
		])


func _tick_structure_assault(job: Dictionary, gid: String) -> void:
	BanditGroupMemory.mark_structure_assault_active(gid, BanditTuning.structure_assault_active_ttl())
	if RunClock.now() < float(job.get("wall_assault_next_at", 0.0)):
		return

	var now: float = RunClock.now()
	var intent_contract: Dictionary = BanditGroupMemory.get_assault_target_intent(gid)
	var anchor: Vector2 = job.get("base_center", Vector2.ZERO) as Vector2
	if not intent_contract.is_empty():
		var intent_anchor: Vector2 = intent_contract.get("anchor", INVALID_TARGET) as Vector2
		if _is_valid_target(intent_anchor):
			anchor = intent_anchor
			job["base_center"] = intent_anchor
	# Resolver siempre contra estructuras vivas: esto encadena automáticamente al siguiente
	# wall cuando el actual cae, y renueva el intent (TTL corto = heartbeat).
	var target_pos: Vector2 = _resolve_structure_target(anchor, true, true)
	if not _is_valid_target(target_pos):
		if STRUCTURE_ASSAULT_ENABLE_GLOBAL_WALL_FALLBACK and _find_wall.is_valid():
			target_pos = _find_wall.call(anchor, STRUCTURE_ASSAULT_GLOBAL_SEARCH_RADIUS) as Vector2
		# Fallback: buscar cerca de la última posición registrada en el intent
		# por si el anchor se desplazó y hay walls en otro cluster cercano.
		var intent_target: Vector2 = intent_contract.get("target_pos", INVALID_TARGET) as Vector2
		if _is_valid_target(intent_target) \
				and intent_target.distance_squared_to(anchor) > STRUCTURE_TARGET_STABILITY_EPSILON_SQ:
			target_pos = _resolve_structure_target(intent_target, true, true)
			if not _is_valid_target(target_pos) and STRUCTURE_ASSAULT_ENABLE_GLOBAL_WALL_FALLBACK and _find_wall.is_valid():
				target_pos = _find_wall.call(intent_target, STRUCTURE_ASSAULT_GLOBAL_SEARCH_RADIUS) as Vector2
		# Último recurso: usar intent.target_pos directamente.
		# Cubre casos donde los query callables no están disponibles (e.g. setup parcial).
		if not _is_valid_target(target_pos) and _is_valid_target(intent_target):
			target_pos = intent_target
	if not _is_valid_target(target_pos):
		var near_assault_area: bool = _is_group_near_assault_area(gid, anchor)
		if float(job.get("no_target_since", 0.0)) <= 0.0:
			job["no_target_since"] = now
			Debug.log("raid", "[RF] structure_assault_no_target_started group=%s anchor=%s near=%s" % [
				gid, str(anchor), str(near_assault_area)
			])
		var no_target_elapsed: float = now - float(job.get("no_target_since", now))
		if near_assault_area and no_target_elapsed >= BanditTuning.structure_no_target_close_grace():
			job["_finish_reason"] = "no_targets_close_fast"
			BanditGroupMemory.clear_structure_assault_active(gid)
			Debug.log("raid", "[RF] structure_assault_finished_fast group=%s elapsed=%.2fs anchor=%s" % [
				gid, no_target_elapsed, str(anchor)
			])
			Debug.log("raid", "[RF] structure_assault_active_released group=%s reason=no_targets_close_fast" % gid)
		job["wall_assault_next_at"] = _next_dispatch_at(gid, BanditTuning.wall_probe_wall_interval())
		return

	if float(job.get("no_target_since", 0.0)) > 0.0:
		Debug.log("raid", "[RF] structure_assault_no_target_cleared group=%s target=%s" % [gid, str(target_pos)])
	job["no_target_since"] = 0.0
	# Mantener intent y contexto BWC sincronizados con el wall vivo actual.
	# Esto renueva el TTL corto del intent (heartbeat) y propaga el target a los NPCs.
	BanditGroupMemory.refresh_assault_target_pos(gid, anchor, target_pos, BanditTuning.structure_assault_active_ttl())
	BanditGroupMemory.record_interest(gid, target_pos, "structure_assault_target")
	var requested: int = int(job.get("probe_squad_size", -1))
	if requested == 0:
		requested = -1
	var last_dispatched: Vector2 = job.get("last_dispatched_target", INVALID_TARGET) as Vector2
	var target_shifted_significantly: bool = (not _is_valid_target(last_dispatched)) \
		or last_dispatched.distance_squared_to(target_pos) > STRUCTURE_TARGET_STABILITY_EPSILON_SQ
	if not target_shifted_significantly:
		job["wall_assault_next_at"] = _next_dispatch_at(gid, BanditTuning.wall_probe_wall_interval())
		Debug.log("placement_react", "[RF] structure assault skip redispatch group=%s stable_target=%s" % [
			gid, str(target_pos)
		])
		return
	var redirected: int = _dispatch_group(gid, target_pos, requested)
	job["base_center"] = target_pos
	if redirected > 0:
		job["last_dispatched_target"] = target_pos
	job["wall_assault_next_at"] = _next_dispatch_at(gid, BanditTuning.wall_probe_wall_interval())
	if redirected > 0:
		var req_text: String = "ALL" if requested <= 0 else str(requested)
		Debug.log("raid", "[RF] structure assault group=%s target=%s redirected=%d/%s" % [
			gid, str(target_pos), redirected, req_text
		])
	else:
		Debug.log("placement_react", "[RF] structure assault group=%s waiting for live members" % gid)


func _tick_wall_probe_assault(job: Dictionary, gid: String) -> void:
	if not _find_wall.is_valid():
		return
	if RunClock.now() < float(job.get("wall_assault_next_at", 0.0)):
		return

	var anchor: Vector2 = job.get("base_center", Vector2.ZERO) as Vector2
	var wall_pos: Vector2 = _find_wall.call(anchor, WALL_SEARCH_RADIUS) as Vector2
	if not _is_valid_target(wall_pos):
		return

	var squad_size: int = maxi(1, int(job.get("probe_squad_size", 1)))
	var redirected: int = _dispatch_group(gid, wall_pos, squad_size)
	job["base_center"] = wall_pos
	job["wall_assault_next_at"] = _next_dispatch_at(gid, BanditTuning.wall_probe_wall_interval())
	if redirected > 0:
		Debug.log("raid", "[RF] wall probe group=%s wall=%s redirected=%d/%d" % [
			gid, str(wall_pos), redirected, squad_size
		])


func _next_dispatch_at(group_id: String, interval: float) -> float:
	var clamped_interval: float = maxf(0.05, interval)
	var h: int = absi(hash(group_id))
	var phase: float = float(h % 997) / 997.0
	var jitter: float = clamped_interval * DISPATCH_JITTER_RATIO * phase
	return RunClock.now() + clamped_interval + jitter


func _tick_attacking(job: Dictionary, gid: String) -> bool:
	var raid_type: String = String(job.get("raid_type", "full"))
	if raid_type == "structure_assault":
		var finish_reason: String = _structure_assault_finish_reason(job)
		if finish_reason != "":
			job["_finish_reason"] = finish_reason
			Debug.log("raid", "[RF] structure assault done group=%s reason=%s" % [gid, finish_reason])
			return true
		return false

	var attack_elapsed: float = RunClock.now() - float(job.get("attack_started_at", RunClock.now()))
	var total_elapsed: float = RunClock.now() - float(job.get("started_at", RunClock.now()))
	var max_attack: float = _attack_duration_for_job(job)
	var max_total: float = _max_total_for_job(job)
	if attack_elapsed >= max_attack or total_elapsed >= max_total:
		Debug.log("raid", "[RF] attack done group=%s type=%s attack_t=%.0f total_t=%.0f" % [
			gid, raid_type, attack_elapsed, total_elapsed
		])
		return true
	return false


func _structure_assault_finish_reason(job: Dictionary) -> String:
	var preset_reason: String = String(job.get("_finish_reason", ""))
	if preset_reason != "":
		return preset_reason
	var now: float = RunClock.now()
	var total_elapsed: float = now - float(job.get("started_at", now))
	if total_elapsed >= BanditTuning.structure_assault_max_total_safety():
		return "safety_cap"
	var no_target_since: float = float(job.get("no_target_since", 0.0))
	if no_target_since <= 0.0:
		return ""
	if now - no_target_since >= BanditTuning.structure_no_target_grace():
		return "no_targets_grace"
	return ""


func _abort_invalid_jobs() -> void:
	var abort_ids: Array[String] = []
	for gid in _active_jobs.keys():
		var job: Dictionary = _active_jobs[gid] as Dictionary
		var total: float = RunClock.now() - float(job.get("started_at", RunClock.now()))
		if total >= _max_total_for_job(job):
			if String(job.get("raid_type", "")) == "structure_assault":
				job["_finish_reason"] = "safety_cap"
			abort_ids.append(gid)
			continue

		var g: Dictionary = BanditGroupMemory.get_group(gid)
		if g.is_empty():
			abort_ids.append(gid)
			continue

		var raid_type: String = String(job.get("raid_type", ""))
		if raid_type != "structure_assault":
			var leader_id: String = String(g.get("leader_id", ""))
			if leader_id == "":
				abort_ids.append(gid)
				continue
			if _npc_simulator != null and _npc_simulator.get_enemy_node(leader_id) == null:
				abort_ids.append(gid)
	for gid in abort_ids:
		_finish_raid(gid, "abort")


func _finish_raid(gid: String, reason: String) -> void:
	if not _active_jobs.has(gid):
		return
	var job: Dictionary = _active_jobs[gid] as Dictionary
	_active_jobs.erase(gid)
	var raid_type: String = String(job.get("raid_type", "full"))
	var resolved_reason: String = reason
	var finish_reason: String = String(job.get("_finish_reason", ""))
	if finish_reason != "":
		resolved_reason = finish_reason
	if raid_type == "structure_assault":
		BanditGroupMemory.clear_structure_assault_active(gid)
		BanditGroupMemory.clear_assault_target_intent(gid)
		Debug.log("raid", "[RF] structure_assault_active_released group=%s reason=%s" % [gid, resolved_reason])

	var social_cd: float
	match raid_type:
		"full":
			social_cd = 18.0
		"light":
			social_cd = 10.0
		"wall_probe":
			social_cd = 6.0
		"structure_assault":
			social_cd = 6.0
		_:
			social_cd = 10.0
	BanditGroupMemory.push_social_cooldown(gid, social_cd)
	BanditGroupMemory.update_intent(gid, "idle")

	var faction_id: String = String(job.get("faction_id", ""))
	if faction_id != "":
		FactionHostilityManager.add_hostility(faction_id, 0.0, "raid_executed", {
			"group_id": gid,
			"entity_id": gid + ":raid",
		})
	Debug.log("raid", "[RF] raid finished group=%s type=%s reason=%s" % [gid, raid_type, resolved_reason])


func _is_group_near_assault_area(gid: String, anchor: Vector2) -> bool:
	if not _is_valid_target(anchor):
		return false
	if _npc_simulator == null:
		return false
	var g: Dictionary = BanditGroupMemory.get_group(gid)
	if g.is_empty():
		return false
	var member_ids: Array = g.get("member_ids", [])
	for raw_mid in member_ids:
		var member_id: String = String(raw_mid)
		if member_id == "":
			continue
		var node = _npc_simulator.get_enemy_node(member_id)
		if node == null or not (node is Node2D):
			continue
		var pos: Vector2 = (node as Node2D).global_position
		if pos.distance_squared_to(anchor) <= STRUCTURE_NO_TARGET_NEAR_RADIUS_SQ:
			return true
	return false


func _has_active_job(gid: String) -> bool:
	return _active_jobs.has(gid)


func _dispatch_group(gid: String, target_pos: Vector2, squad_size: int = -1) -> int:
	if not _is_valid_target(target_pos):
		return 0
	if _dispatch_group_to_target.is_valid():
		return int(_dispatch_group_to_target.call(gid, target_pos, squad_size))

	if _npc_simulator == null:
		return 0
	var cap: int = squad_size if squad_size > 0 else 999999
	var redirected: int = 0
	var g: Dictionary = BanditGroupMemory.get_group(gid)
	var member_ids: Array = g.get("member_ids", [])
	for raw_mid in member_ids:
		if redirected >= cap:
			break
		var node = _npc_simulator.get_enemy_node(String(raw_mid))
		if node == null:
			continue
		var bwb = node.get_node_or_null("WorldBehavior")
		if bwb == null or not bwb.has_method("enter_wall_assault"):
			continue
		bwb.call("enter_wall_assault", target_pos)
		redirected += 1
	return redirected


func _resolve_structure_target(anchor_pos: Vector2, allow_walls: bool, prefer_storage: bool,
		search_radius_scale: float = 1.0) -> Vector2:
	var target_pos: Vector2 = INVALID_TARGET
	var placeable_radius: float = PLACEABLE_SEARCH_RADIUS * maxf(0.1, search_radius_scale)
	var wall_radius: float = WALL_SEARCH_RADIUS * maxf(0.1, search_radius_scale)
	if prefer_storage and _find_storage.is_valid():
		target_pos = _find_storage.call(anchor_pos, placeable_radius) as Vector2
		if _is_valid_target(target_pos):
			return target_pos

	if _find_placeable.is_valid():
		target_pos = _find_placeable.call(anchor_pos, placeable_radius) as Vector2
		if _is_valid_target(target_pos):
			return target_pos

	if _find_workbench.is_valid():
		target_pos = _find_workbench.call(anchor_pos, placeable_radius) as Vector2
		if _is_valid_target(target_pos):
			return target_pos

	if allow_walls and _find_wall.is_valid():
		target_pos = _find_wall.call(anchor_pos, wall_radius) as Vector2
		if _is_valid_target(target_pos):
			return target_pos

	return INVALID_TARGET


func _is_valid_target(pos: Vector2) -> bool:
	return pos.is_finite() and not pos.is_equal_approx(INVALID_TARGET)


func _attack_duration_for_job(job: Dictionary) -> float:
	match String(job.get("raid_type", "full")):
		"light":
			return LIGHT_ATTACK_DURATION
		"wall_probe":
			return BanditTuning.wall_probe_attack_duration()
		"structure_assault":
			return STRUCTURE_ATTACK_DURATION
		_:
			return ATTACK_DURATION


func _max_total_for_job(job: Dictionary) -> float:
	match String(job.get("raid_type", "full")):
		"light":
			return LIGHT_MAX_DURATION
		"wall_probe":
			return BanditTuning.wall_probe_max_duration()
		"structure_assault":
			return BanditTuning.structure_assault_max_total_safety()
		_:
			return MAX_RAID_DURATION


func _approach_timeout_for_job(job: Dictionary) -> float:
	match String(job.get("raid_type", "full")):
		"structure_assault":
			return STRUCTURE_APPROACH_TIMEOUT
		_:
			return APPROACH_TIMEOUT
