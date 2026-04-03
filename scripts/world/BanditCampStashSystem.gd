class_name BanditCampStashSystem
extends Node

## Responsabilidad única: ciclo de vida del cargo de los bandidos y los barriles de campamento.
##
## Cubre:
##   • Spawn y tracking de barriles físicos por grupo (_camp_barrels)
##   • Distribución de deposit_pos a cada behavior (vía callable externo)
##   • Recogida de drops: sweep de órbita y sweep de llegada
##   • Depósito animado de cargo en el barril (con overflow → nuevo barril)
##   • Drop del cargo al suelo cuando el NPC entra en combate
##
## No accede a _behaviors directamente — comunica cambios de barril al caller
## a través del callable update_deposit_pos_cb(group_id, barrel_pos).
##
## Frontera futura:
## no debe absorber memoria social local ni autoridad civil. Si una taberna
## responde a robo/daño, eso irá por otro director; este sistema sigue siendo
## solo logística física de campamento bandido.

const BanditTuningScript := preload("res://scripts/world/BanditTuning.gd")
const CAMP_BARREL_SCENE:  PackedScene = preload("res://scenes/placeables/barrel_world.tscn")
const ITEM_DROP_SCENE:    PackedScene = preload("res://scenes/items/ItemDrop.tscn")
const MethodCapabilityCacheScript := preload("res://scripts/utils/MethodCapabilityCache.gd")

# ---------------------------------------------------------------------------
# Camp layout constants — geometría visual interna, no balance de gameplay.
# Los radios de pickup y timings de animación viven en BanditTuning.
# ---------------------------------------------------------------------------
const BARREL_SPAWN_OFFSET_BASE:  float = 96.0   # px desde home_pos al primer barril (3 tiles)
const BARREL_SPAWN_COLUMN_STEP:  float = 32.0   # px entre barriles adicionales
const KIND_ITEM_DROP: StringName = WorldSpatialIndex.KIND_ITEM_DROP

const CARRY_STACK_BASE_Y:  float = -22.0  # Y del primer item cargado sobre el NPC
const CARRY_STACK_STEP_Y:  float =   8.0  # desplazamiento Y por item adicional en el stack
const DEPOSIT_TARGET_MAX_DIST_SQ: float = 180.0 * 180.0
const DEPOSIT_ZONE_RADIUS: float = 72.0  # NPC dentro de este radio de deposit_pos → depósito automático
const DEPOSIT_ZONE_LOCK_RADIUS: float = 96.0  # lock activo + dentro de esta zona => bypass gate estricto por nodo
const ENABLE_SECONDARY_DEPOSIT_FALLBACK: bool = false
const drops_per_npc_per_tick_max: int = 2
const drops_global_per_pulse_max: int = 18
const COMPACT_DEPOSIT_MANIFEST_THRESHOLD: int = 8
const COMPACT_DEPOSIT_MINIMAL_STACK_THRESHOLD: int = 1
const ENABLE_LEGACY_DETAILED_DEPOSIT_PATH: bool = false
const DROP_PRESSURE_STAGE_HIGH: int = 5
const DROP_PRESSURE_STAGE_COMPACT: int = 6
const PICKUP_SFX_COOLDOWN_MS: int = 100

# group_id (String) -> instance_id (int) del barrel físico (runtime-only, no persisted)
var _camp_barrels: Dictionary = {}
var _pending_deposit_attempts_by_member: Dictionary = {}
var _method_caps: MethodCapabilityCache = MethodCapabilityCacheScript.new()
var deposit_compact_path_hits: int = 0
var _drop_processing_budget_hits: int = 0
var _debug_drop_pulse_id: int = -1
var _debug_pickup_queries_in_pulse: int = 0
var _debug_drop_candidates_total_in_pulse: int = 0
var _debug_budget_hits_in_pulse: int = 0
var _debug_compact_hits_in_pulse: int = 0
var _debug_last_pickup_queries_per_pulse: int = 0
var _debug_last_drop_candidates_total: int = 0
var _debug_last_budget_hits: int = 0
var _debug_last_compact_hits: int = 0
var _debug_sweep_attempts_blocked_by_role_in_pulse: int = 0
var _debug_sweep_attempts_blocked_by_group_cap_in_pulse: int = 0
var _debug_last_sweep_attempts_blocked_by_role: int = 0
var _debug_last_sweep_attempts_blocked_by_group_cap: int = 0
var _debug_drop_pressure_mode: String = "normal"
var _eligible_looters_per_group: Dictionary = {}
var _pickup_sfx_last_ms_by_member: Dictionary = {}
var _pickup_sfx_last_pulse_by_member: Dictionary = {}
var _authorized_assault_looters_by_group: Dictionary = {}

# Callable(group_id: String, barrel_pos: Vector2) -> void
# Implementado por BanditBehaviorLayer para propagar deposit_pos a los behaviors.
var _world_spatial_index: WorldSpatialIndex = null
var _update_deposit_pos_cb: Callable = Callable()
var _log_worker_event_cb: Callable = Callable()
var _is_worker_instrumentation_enabled_cb: Callable = Callable()
var _get_work_tick_cb: Callable = Callable()
var _get_work_cycle_id_cb: Callable = Callable()
var _on_deposit_closed_cb: Callable = Callable()
var _instrumentation_enabled: bool = true


func _fmt_pos(value: Vector2) -> String:
	return "%.2f,%.2f" % [value.x, value.y]


func _is_worker_event_logging_enabled() -> bool:
	if not _instrumentation_enabled:
		return false
	if _is_worker_instrumentation_enabled_cb.is_valid():
		return bool(_is_worker_instrumentation_enabled_cb.call())
	return Debug.is_enabled("bandit_pipeline")


func _current_tick() -> int:
	if _get_work_tick_cb.is_valid():
		return int(_get_work_tick_cb.call())
	return 0


func _current_work_cycle_id(beh: BanditWorldBehavior) -> String:
	if beh == null:
		return ""
	if _get_work_cycle_id_cb.is_valid():
		return String(_get_work_cycle_id_cb.call(beh.member_id))
	return ""


func _emit_worker_event(event_name: String, beh: BanditWorldBehavior,
		used_pos: Vector2, target_id: String, extra := {}) -> void:
	if not _is_worker_event_logging_enabled():
		return
	var payload := {
		"npc_id": beh.member_id if beh != null else "unknown",
		"group_id": beh.group_id if beh != null else "unknown",
		"camp_id": beh.group_id if beh != null else "unknown",
		"position_used": _fmt_pos(used_pos),
		"target_id": target_id,
		"state": str(int(beh.state)) if beh != null else "unknown",
		"tick": _current_tick(),
		"work_cycle_id": _current_work_cycle_id(beh),
	}
	for key in extra.keys():
		payload[key] = extra[key]
	if _log_worker_event_cb.is_valid():
		_log_worker_event_cb.call(event_name, payload)
		return
	var fallback := payload.duplicate()
	fallback["event"] = event_name
	Debug.log("bandit_pipeline", "[CAMP_PIPE] %s" % JSON.stringify(fallback))


func _queue_deposit_attempt(beh: BanditWorldBehavior, cause: String, source: String) -> void:
	if beh == null:
		return
	var member_id: String = beh.member_id
	var queue: Array = _pending_deposit_attempts_by_member.get(member_id, []) as Array
	queue.append({
		"tick": _current_tick(),
		"cause": cause,
		"source": source,
		"cargo": beh.cargo_count,
	})
	while queue.size() > 8:
		queue.pop_front()
	_pending_deposit_attempts_by_member[member_id] = queue


func _clear_deposit_attempt_queue(beh: BanditWorldBehavior) -> void:
	if beh == null:
		return
	_pending_deposit_attempts_by_member.erase(beh.member_id)


func setup(ctx: Dictionary) -> void:
	_world_spatial_index = ctx.get("world_spatial_index", null)
	_update_deposit_pos_cb = ctx.get("update_deposit_pos_cb", Callable())
	_log_worker_event_cb = ctx.get("log_worker_event_cb", Callable())
	_is_worker_instrumentation_enabled_cb = ctx.get("is_worker_instrumentation_enabled_cb", Callable())
	_get_work_tick_cb = ctx.get("get_work_tick_cb", Callable())
	_get_work_cycle_id_cb = ctx.get("get_work_cycle_id_cb", Callable())
	_instrumentation_enabled = bool(ctx.get("worker_instrumentation_enabled", true))


func set_work_context(ctx: Dictionary) -> void:
	_get_work_tick_cb = ctx.get("get_work_tick_cb", _get_work_tick_cb)
	_get_work_cycle_id_cb = ctx.get("get_work_cycle_id_cb", _get_work_cycle_id_cb)
	_on_deposit_closed_cb = ctx.get("on_deposit_closed_cb", _on_deposit_closed_cb)




func _set_deposit_lock(beh: BanditWorldBehavior, spawn_pos: Vector2, event_name: String, extra := {}) -> void:
	if beh == null:
		return
	beh.deposit_lock_active = true
	beh.delivery_lock_active = true
	_emit_worker_event(event_name, beh, spawn_pos, "", extra)


func _clear_deposit_lock(beh: BanditWorldBehavior, spawn_pos: Vector2, event_name: String, extra := {}) -> void:
	if beh == null:
		return
	beh.deposit_lock_active = false
	beh.delivery_lock_active = false
	_emit_worker_event(event_name, beh, spawn_pos, "", extra)

func _force_clear_cargo_after_deposit(beh: BanditWorldBehavior) -> void:
	if beh == null:
		return
	beh.cargo_count = 0
	beh._cargo_manifest.clear()
	beh.deposit_lock_active = false
	beh.delivery_lock_active = false


func _consume_carried_visual_nodes_for_deposit(beh: BanditWorldBehavior,
		chest_pos: Vector2, animate: bool) -> Dictionary:
	var result := {
		"scheduled": 0,
		"freed": 0,
		"missing": 0,
		"sfx": null,
	}
	if beh == null or beh._cargo_manifest.is_empty():
		return result
	_emit_worker_event("deposit_visual_cleanup_started", beh, chest_pos, "", {
		"cargo": beh.cargo_count,
		"animate": animate,
		"manifest_size": beh._cargo_manifest.size(),
	})
	var scene_root: Node = get_tree().current_scene
	var fall_time: float = BanditTuningScript.cargo_fall_time()
	var sfx_stagger: float = BanditTuningScript.cargo_sfx_stagger()
	var cleanup_index: int = 0
	var one_shot_sfx: AudioStream = null
	for entry in beh._cargo_manifest:
		if not (entry is Dictionary):
			continue
		var data := entry as Dictionary
		var node_id: int = int(data.get("node_id", 0))
		if node_id == 0 or not is_instance_id_valid(node_id):
			result["missing"] = int(result.get("missing", 0)) + 1
			_emit_worker_event("deposit_visual_node_missing", beh, chest_pos, "", {
				"reason": "invalid_node_id",
				"node_id": node_id,
			})
			continue
		var obj := instance_from_id(node_id)
		if obj == null or not is_instance_valid(obj) or not (obj is ItemDrop):
			result["missing"] = int(result.get("missing", 0)) + 1
			_emit_worker_event("deposit_visual_node_missing", beh, chest_pos, "", {
				"reason": "missing_or_not_item_drop",
				"node_id": node_id,
			})
			continue
		var drop_node := obj as ItemDrop
		if drop_node.is_queued_for_deletion():
			result["missing"] = int(result.get("missing", 0)) + 1
			_emit_worker_event("deposit_visual_node_missing", beh, chest_pos, "", {
				"reason": "already_queued_for_deletion",
				"node_id": node_id,
			})
			continue
		if one_shot_sfx == null:
			one_shot_sfx = drop_node.get("pickup_sfx") as AudioStream
		if not animate:
			drop_node.queue_free()
			result["freed"] = int(result.get("freed", 0)) + 1
			_emit_worker_event("deposit_visual_node_freed", beh, chest_pos, "", {
				"mode": "instant",
				"node_id": node_id,
			})
			continue
		var carry_pos := drop_node.global_position
		if scene_root != null and drop_node.get_parent() != scene_root:
			drop_node.reparent(scene_root, false)
		drop_node.global_position = carry_pos
		var offset := Vector2(randf_range(-8.0, 8.0), randf_range(-4.0, 4.0))
		var target_pos := chest_pos + offset
		var tw := create_tween()
		tw.tween_property(drop_node, "global_position", target_pos, fall_time) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		var cap_drop := drop_node
		var cap_node_id := node_id
		var cap_pos := chest_pos
		var free_delay := fall_time + float(cleanup_index) * sfx_stagger
		cleanup_index += 1
		result["scheduled"] = int(result.get("scheduled", 0)) + 1
		get_tree().create_timer(free_delay).timeout.connect(func() -> void:
			if not is_instance_valid(cap_drop) or cap_drop.is_queued_for_deletion():
				return
			cap_drop.queue_free()
			_emit_worker_event("deposit_visual_node_freed", beh, cap_pos, "", {
				"mode": "animated",
				"node_id": cap_node_id,
			})
		)
	if one_shot_sfx != null:
		result["sfx"] = one_shot_sfx
	_emit_worker_event("deposit_visual_cleanup_complete", beh, chest_pos, "", {
		"scheduled": int(result.get("scheduled", 0)),
		"freed": int(result.get("freed", 0)),
		"missing": int(result.get("missing", 0)),
		"animate": animate,
	})
	return result


func _is_drop_pressure_stage_6(beh: BanditWorldBehavior) -> bool:
	var snapshot := _get_drop_pressure_snapshot()
	if int(snapshot.get("drop_pressure_stage", 0)) >= DROP_PRESSURE_STAGE_COMPACT:
		return true
	if beh == null or beh.group_id == "":
		return false
	var g: Dictionary = BanditGroupMemory.get_group(beh.group_id)
	if g.is_empty():
		return false
	for key in [
		"drop_pressure_stage",
		"drops_pressure_stage",
		"drop_scan_pressure_stage",
		"drop_pressure_level",
		"drops_pressure_level",
	]:
		if int(g.get(String(key), 0)) >= DROP_PRESSURE_STAGE_COMPACT:
			return true
	return false


func _get_drop_pressure_snapshot() -> Dictionary:
	if LootSystem != null and LootSystem.has_method("get_drop_pressure_snapshot"):
		return LootSystem.get_drop_pressure_snapshot() as Dictionary
	return {}


func _is_drop_pressure_high_or_worse() -> bool:
	var snapshot := _get_drop_pressure_snapshot()
	return int(snapshot.get("drop_pressure_stage", 0)) >= DROP_PRESSURE_STAGE_HIGH


func _pickup_budget_scale() -> float:
	var snapshot := _get_drop_pressure_snapshot()
	var scale: float = float(snapshot.get("pickup_budget_scale", 1.0))
	return clampf(scale, 0.35, 1.0)


func _assault_pickup_group_looter_cap() -> int:
	return maxi(BanditTuningScript.assault_pickup_group_looter_cap(), 1)


func _assault_pickup_scavenger_only() -> bool:
	return BanditTuningScript.assault_pickup_scavenger_only()


func _assault_pickup_rotation_interval_ticks() -> int:
	return maxi(BanditTuningScript.assault_pickup_rotation_interval_ticks(), 1)


func _normalize_group_pickup_mode(beh: BanditWorldBehavior) -> String:
	if beh == null:
		return "normal"
	var g: Dictionary = BanditGroupMemory.get_group(beh.group_id)
	var mode: String = String(g.get("current_group_intent", "idle"))
	if BanditGroupMemory.is_structure_assault_active(beh.group_id) \
			or mode == "raiding" \
			or mode == "hunting" \
			or mode == "alerted":
		return "assault"
	if mode == "retreating" or mode == "depositing":
		return "retreat"
	return "normal"


func _is_strike_or_cover_unit(beh: BanditWorldBehavior) -> bool:
	if beh == null:
		return false
	if beh.state == NpcWorldBehavior.State.FOLLOW_LEADER \
			or beh.state == NpcWorldBehavior.State.EXTORT_APPROACH \
			or beh.state == NpcWorldBehavior.State.EXTORT_RETREAT:
		return true
	if BanditGroupMemory.is_structure_assault_active(beh.group_id):
		return true
	return false


func _is_assault_pickup_task_active(beh: BanditWorldBehavior) -> bool:
	if beh == null:
		return false
	if beh.state == NpcWorldBehavior.State.LOOT_APPROACH:
		return true
	return beh.pending_collect_id != 0 or beh.cargo_count > 0


func _resolve_authorized_assault_looters(group_id: String, looter_cap: int) -> Dictionary:
	if group_id == "":
		return {}
	var now_tick: int = _current_tick()
	var cap: int = maxi(looter_cap, 1)
	var persisted: Dictionary = _authorized_assault_looters_by_group.get(group_id, {}) as Dictionary
	var members_source: Array = (BanditGroupMemory.get_group(group_id).get("member_ids", []) as Array)
	var candidates: Array[String] = []
	for raw_member_id in members_source:
		var member_id: String = String(raw_member_id)
		if member_id != "":
			candidates.append(member_id)
	candidates.sort()
	var chosen: Array[String] = []
	var prev_allowed: Array = persisted.get("member_ids", []) as Array
	for raw_prev in prev_allowed:
		var prev_id: String = String(raw_prev)
		if candidates.has(prev_id) and chosen.size() < cap:
			chosen.append(prev_id)
	var cursor: int = int(persisted.get("cursor", 0))
	var interval_ticks: int = _assault_pickup_rotation_interval_ticks()
	var refresh_due: bool = persisted.is_empty() \
			or now_tick >= int(persisted.get("next_refresh_tick", 0))
	if refresh_due and candidates.size() > 0 and chosen.size() < cap:
		var start_idx: int = posmod(cursor, candidates.size())
		var idx: int = start_idx
		var visited: int = 0
		while visited < candidates.size() and chosen.size() < cap:
			var candidate_id: String = candidates[idx]
			if not chosen.has(candidate_id):
				chosen.append(candidate_id)
			idx = (idx + 1) % candidates.size()
			visited += 1
		cursor = idx
	var resolved := {
		"member_ids": chosen,
		"cursor": cursor,
		"next_refresh_tick": now_tick + interval_ticks,
	}
	_authorized_assault_looters_by_group[group_id] = resolved
	return resolved


func _is_sweep_eligible(beh: BanditWorldBehavior, query_ctx: Dictionary) -> Dictionary:
	var fallback := {
		"eligible": false,
		"blocked_by": "invalid_behavior",
		"mode": "normal",
		"eligible_count": 0,
	}
	if beh == null:
		return fallback
	var mode: String = _normalize_group_pickup_mode(beh)
	var result := {
		"eligible": true,
		"blocked_by": "",
		"mode": mode,
		"eligible_count": 0,
	}
	if mode != "assault":
		result["eligible_count"] = 0
		return result
	if beh.role == "bodyguard" or beh.role == "leader" or _is_strike_or_cover_unit(beh):
		result["eligible"] = false
		result["blocked_by"] = "role"
		return result
	var scavenger_only: bool = _assault_pickup_scavenger_only()
	if scavenger_only and beh.role != "scavenger":
		result["eligible"] = false
		result["blocked_by"] = "role"
		return result
	if _is_assault_pickup_task_active(beh):
		result["eligible_count"] = 1
		return result
	var looter_cap: int = maxi(int(query_ctx.get("assault_pickup_group_looter_cap", _assault_pickup_group_looter_cap())), 1)
	var authorized: Dictionary = _resolve_authorized_assault_looters(beh.group_id, looter_cap)
	var allowed_ids: Array = authorized.get("member_ids", []) as Array
	result["eligible_count"] = allowed_ids.size()
	if allowed_ids.has(beh.member_id):
		return result
	result["eligible"] = false
	result["blocked_by"] = "group_cap"
	return result


func begin_drop_pulse(pulse_id: int, drop_pressure_mode: String = "normal") -> void:
	if pulse_id != _debug_drop_pulse_id:
		_debug_last_pickup_queries_per_pulse = _debug_pickup_queries_in_pulse
		_debug_last_drop_candidates_total = _debug_drop_candidates_total_in_pulse
		_debug_last_budget_hits = _debug_budget_hits_in_pulse
		_debug_last_compact_hits = _debug_compact_hits_in_pulse
		_debug_last_sweep_attempts_blocked_by_role = _debug_sweep_attempts_blocked_by_role_in_pulse
		_debug_last_sweep_attempts_blocked_by_group_cap = _debug_sweep_attempts_blocked_by_group_cap_in_pulse
		_debug_drop_pulse_id = pulse_id
		_debug_pickup_queries_in_pulse = 0
		_debug_drop_candidates_total_in_pulse = 0
		_debug_budget_hits_in_pulse = 0
		_debug_compact_hits_in_pulse = 0
		_debug_sweep_attempts_blocked_by_role_in_pulse = 0
		_debug_sweep_attempts_blocked_by_group_cap_in_pulse = 0
		_eligible_looters_per_group.clear()
	_debug_drop_pressure_mode = drop_pressure_mode


func get_debug_snapshot() -> Dictionary:
	var pickup_queries_per_pulse: int = _debug_pickup_queries_in_pulse
	var candidates_total: int = _debug_drop_candidates_total_in_pulse
	var budget_hits: int = _debug_budget_hits_in_pulse
	var compact_hits: int = _debug_compact_hits_in_pulse
	if pickup_queries_per_pulse <= 0 and _debug_last_pickup_queries_per_pulse > 0:
		pickup_queries_per_pulse = _debug_last_pickup_queries_per_pulse
		candidates_total = _debug_last_drop_candidates_total
	if budget_hits <= 0 and _debug_last_budget_hits > 0:
		budget_hits = _debug_last_budget_hits
	if compact_hits <= 0 and _debug_last_compact_hits > 0:
		compact_hits = _debug_last_compact_hits
	var blocked_by_role: int = _debug_sweep_attempts_blocked_by_role_in_pulse
	var blocked_by_group_cap: int = _debug_sweep_attempts_blocked_by_group_cap_in_pulse
	if blocked_by_role <= 0 and _debug_last_sweep_attempts_blocked_by_role > 0:
		blocked_by_role = _debug_last_sweep_attempts_blocked_by_role
	if blocked_by_group_cap <= 0 and _debug_last_sweep_attempts_blocked_by_group_cap > 0:
		blocked_by_group_cap = _debug_last_sweep_attempts_blocked_by_group_cap
	return {
		"drop_pulse_id": _debug_drop_pulse_id,
		"pickup_queries_per_pulse": pickup_queries_per_pulse,
		"average_drop_candidates_per_query": float(candidates_total) / float(maxi(pickup_queries_per_pulse, 1)),
		"drop_processing_budget_hits": budget_hits,
		"deposit_compact_path_hits": compact_hits,
		"drop_pressure_mode": _debug_drop_pressure_mode,
		"drop_processing_budget_hits_total": _drop_processing_budget_hits,
		"deposit_compact_path_hits_total": deposit_compact_path_hits,
		"eligible_looters_per_group": _eligible_looters_per_group.duplicate(true),
		"sweep_attempts_blocked_by_role": blocked_by_role,
		"sweep_attempts_blocked_by_group_cap": blocked_by_group_cap,
		"assault_pickup_group_looter_cap": _assault_pickup_group_looter_cap(),
		"assault_pickup_scavenger_only": _assault_pickup_scavenger_only(),
		"assault_pickup_rotation_interval_ticks": _assault_pickup_rotation_interval_ticks(),
	}


func _insert_into_group_barrels(beh: BanditWorldBehavior, spawn_pos: Vector2, target_source: String,
		chest: Node, item_id: String, amount: int) -> Dictionary:
	var result := {
		"inserted": 0,
		"source": target_source,
	}
	if chest != null:
		var inserted := int(chest.call("try_insert_item", item_id, amount))
		if inserted > 0:
			result["inserted"] = inserted
			result["source"] = target_source
			return result
	if beh.group_id != "":
		for gid in _camp_barrels.keys():
			if not String(gid).begins_with(beh.group_id) or String(gid) == beh.group_id:
				continue
			var bid: int = int(_camp_barrels[gid])
			if bid == 0 or not is_instance_id_valid(bid):
				continue
			var bn2 := instance_from_id(bid) as Node
			if bn2 == null or not is_instance_valid(bn2) \
					or not _method_caps.has_method_cached(bn2, &"try_insert_item"):
				continue
			var ins2 := int(bn2.call("try_insert_item", item_id, amount))
			if ins2 > 0:
				_camp_barrels[beh.group_id] = bid
				_notify_deposit_pos(beh.group_id, (bn2 as Node2D).global_position)
				result["inserted"] = ins2
				result["source"] = "extra_barrel_retarget"
				return result
		var col: int = 0
		for gid in _camp_barrels:
			if String(gid).begins_with(beh.group_id):
				col += 1
		var new_barrel := _spawn_camp_barrel(spawn_pos, col)
		if new_barrel != null:
			var nrid: int = new_barrel.get_instance_id()
			_camp_barrels[beh.group_id + "_extra_%d" % col] = nrid
			_camp_barrels[beh.group_id] = nrid
			_notify_deposit_pos(beh.group_id, (new_barrel as Node2D).global_position)
			var inserted_new: int = int(new_barrel.call("try_insert_item", item_id, amount))
			result["inserted"] = inserted_new
			result["source"] = "extra_barrel_spawn"
			return result
	result["inserted"] = 0
	return result


func _close_deposit(beh: BanditWorldBehavior, spawn_pos: Vector2,
		target_source: String, outcome: String) -> void:
	if beh == null:
		return
	var had_cargo: bool = beh.cargo_count > 0 or not beh._cargo_manifest.is_empty()
	_force_clear_cargo_after_deposit(beh)
	_clear_deposit_lock(beh, spawn_pos, "deposit_lock_cleared_success", {"outcome": outcome})
	beh.on_deposit_complete()
	_clear_deposit_attempt_queue(beh)
	_emit_worker_event("deposit_closed", beh, spawn_pos, "", {
		"source": target_source,
		"outcome": outcome,
		"had_cargo": had_cargo,
	})
	if _on_deposit_closed_cb.is_valid():
		_on_deposit_closed_cb.call(beh, spawn_pos, outcome, had_cargo)


# ---------------------------------------------------------------------------
# API pública — llamada por BanditBehaviorLayer en cada tick
# ---------------------------------------------------------------------------

## Garantiza que cada grupo activo tiene un barril vivo; spawna si es necesario.
func ensure_barrels() -> void:
	for group_id in BanditGroupMemory.get_all_group_ids():
		var barrel_id: int = int(_camp_barrels.get(group_id, 0))
		if barrel_id != 0 and is_instance_id_valid(barrel_id):
			var existing := instance_from_id(barrel_id) as Node
			if existing != null and is_instance_valid(existing) \
					and not existing.is_queued_for_deletion():
				_notify_deposit_pos(group_id, (existing as Node2D).global_position)
				continue
		var g: Dictionary = BanditGroupMemory.get_group(group_id)
		if (g.get("member_ids", []) as Array).is_empty():
			continue
		var home: Vector2 = g.get("home_world_pos", Vector2.ZERO)
		var barrel := _spawn_camp_barrel(home, 0)
		if barrel != null:
			_camp_barrels[group_id] = barrel.get_instance_id()
			_notify_deposit_pos(group_id, (barrel as Node2D).global_position)


## Recoge drops en radio de órbita (desde el centro del recurso).
func sweep_collect_orbit(beh: BanditWorldBehavior, enemy_node: Node,
		orbit_center: Vector2, query_budget_ctx: Dictionary = {}) -> void:
	_sweep(beh, enemy_node, orbit_center, BanditTuningScript.orbit_collect_radius_sq(), query_budget_ctx)


## Recoge todos los drops cercanos al llegar a un drop objetivo.
func sweep_collect_arrive(beh: BanditWorldBehavior, enemy_node: Node,
		arrive_pos: Vector2, query_budget_ctx: Dictionary = {}) -> void:
	_sweep(beh, enemy_node, arrive_pos, BanditTuningScript.loot_arrive_collect_radius_sq(), query_budget_ctx)


## Deposita el cargo en el barril del campamento (animación de caída + inserción).
func handle_cargo_deposit(beh: BanditWorldBehavior, enemy_node: Node) -> void:
	# Proximity deposit zone: trigger without requiring exact arrival if the NPC
	# is within DEPOSIT_ZONE_RADIUS of their assigned deposit slot while returning.
	if not beh._just_arrived_home_with_cargo and beh.cargo_count > 0 \
			and beh.deposit_pos != Vector2.ZERO \
			and (beh.state == NpcWorldBehavior.State.RETURN_HOME \
				or beh.state == NpcWorldBehavior.State.IDLE_AT_HOME):
		var _node2d := enemy_node as Node2D
		if _node2d != null and is_instance_valid(_node2d) \
				and _node2d.global_position.distance_to(beh.deposit_pos) <= DEPOSIT_ZONE_RADIUS:
			beh._just_arrived_home_with_cargo = true
	if not beh._just_arrived_home_with_cargo:
		return
	beh._just_arrived_home_with_cargo = false

	var spawn_pos: Vector2 = beh.home_pos
	if enemy_node != null and is_instance_valid(enemy_node):
		spawn_pos = (enemy_node as Node2D).global_position
	_set_deposit_lock(beh, spawn_pos, "deposit_lock_activated", {"reason": "deposit_attempt_begin", "cargo": beh.cargo_count})
	_emit_worker_event("delivery_lock_activated", beh, spawn_pos, "", {
		"reason": "deposit_attempt_begin",
		"cargo": beh.cargo_count,
	})

	if beh.cargo_count > 0 and beh._cargo_manifest.is_empty():
		Debug.log("bandit_ai",
				"[CampStashHook] deposit_attempt_abort npc=%s cause=manifest_empty_with_cargo cargo=%d" % [
			beh.member_id,
			beh.cargo_count,
		])
		_close_deposit(beh, spawn_pos, "manifest_guard", "manifest_empty_abort")
		return

	var in_delivery_zone: bool = beh.deposit_pos != Vector2.ZERO \
			and spawn_pos.distance_to(beh.deposit_pos) <= DEPOSIT_ZONE_LOCK_RADIUS
	var lock_bypass: bool = beh.delivery_lock_active and in_delivery_zone
	var resolution := _resolve_deposit_target(beh.group_id, spawn_pos, lock_bypass)
	var chest: Node = resolution.get("node", null) as Node
	var target_source: String = String(resolution.get("source", "none"))
	var missing_cause: String = String(resolution.get("missing_cause", "none"))
	var should_spawn_fallback: bool = bool(resolution.get("allow_spawn_fallback", true))
	if chest == null and should_spawn_fallback:
		var fallback_barrel := _spawn_camp_barrel(spawn_pos - Vector2(36.0, 0.0), 0)
		if fallback_barrel != null:
			chest = fallback_barrel
			target_source = "spawned_fallback_barrel"
			missing_cause = "none"
			if beh.group_id != "":
				_camp_barrels[beh.group_id] = fallback_barrel.get_instance_id()
				_notify_deposit_pos(beh.group_id, fallback_barrel.global_position)
		else:
			missing_cause = "spawn_fallback_failed"

	_emit_worker_event("deposit_attempt", beh, spawn_pos, "", {
		"cargo": beh.cargo_count,
		"source": target_source,
	})
	if chest == null:
		_emit_worker_event("deposit_target_missing", beh, spawn_pos, "", {
			"cause": missing_cause,
		})
		_emit_worker_event("deposit_retry", beh, spawn_pos, "", {
			"cause": missing_cause,
			"source": target_source,
		})
		_queue_deposit_attempt(beh, missing_cause, target_source)
		_set_deposit_lock(beh, spawn_pos, "deposit_lock_retry", {"cause": missing_cause, "source": target_source})
		_emit_worker_event("cargo_not_returning", beh, spawn_pos, "", {
			"reason": "deposit_target_unavailable",
			"cause": missing_cause,
			"attempt_queue_size": int((_pending_deposit_attempts_by_member.get(beh.member_id, []) as Array).size()),
		})
		beh._just_arrived_home_with_cargo = true
		beh.force_return_home()
		return

	var land_target: Vector2 = spawn_pos
	if chest != null and chest is Node2D:
		land_target = (chest as Node2D).global_position

	var fall_time:   float = BanditTuningScript.cargo_fall_time()
	var sfx_stagger: float = BanditTuningScript.cargo_sfx_stagger()
	var has_competition: bool = _is_drop_pressure_stage_6(beh) or _is_drop_pressure_high_or_worse()
	var is_minimal_manifest: bool = beh._cargo_manifest.size() <= COMPACT_DEPOSIT_MINIMAL_STACK_THRESHOLD
	var compact_mode: bool = true
	if ENABLE_LEGACY_DETAILED_DEPOSIT_PATH:
		compact_mode = has_competition \
				or beh._cargo_manifest.size() > COMPACT_DEPOSIT_MANIFEST_THRESHOLD \
				or not is_minimal_manifest
	if compact_mode:
		deposit_compact_path_hits += 1
		_debug_compact_hits_in_pulse += 1
		var batches: Dictionary = {}
		for i in beh._cargo_manifest.size():
			var entry: Dictionary = beh._cargo_manifest[i]
			var item_id: String = String(entry.get("item_id", ""))
			var amount: int = int(entry.get("amount", 1))
			if item_id == "" or amount <= 0:
				continue
			batches[item_id] = int(batches.get(item_id, 0)) + amount
		var fallback_batches: Array = []
		var inserted_any: bool = false
		var inserted_total: int = 0
		for item_id in batches.keys():
			var packed_amount: int = int(batches.get(item_id, 0))
			if packed_amount <= 0:
				continue
			var ins_res := _insert_into_group_barrels(beh, spawn_pos, target_source, chest, String(item_id), packed_amount)
			var inserted: int = int(ins_res.get("inserted", 0))
			var source_used: String = String(ins_res.get("source", target_source))
			if inserted > 0:
				inserted_any = true
				inserted_total += inserted
			var leftover: int = maxi(0, packed_amount - inserted)
			if leftover > 0:
				fallback_batches.append({
					"item_id": String(item_id),
					"amount": leftover,
					"source": source_used,
				})
		var unresolved_fallback: bool = false
		var fallback_dropped_any: bool = false
		for fallback_entry in fallback_batches:
			var fallback_item_id: String = String(fallback_entry.get("item_id", ""))
			var fallback_amount: int = int(fallback_entry.get("amount", 0))
			if fallback_item_id == "" or fallback_amount <= 0:
				continue
			var fallback_drop: ItemDrop = null
			if ITEM_DROP_SCENE != null:
				fallback_drop = ITEM_DROP_SCENE.instantiate() as ItemDrop
				if fallback_drop == null:
					unresolved_fallback = true
					_emit_worker_event("cargo_not_returning", beh, spawn_pos, fallback_item_id, {
						"reason": "deposit_blocked",
						"cause": "stash_full",
						"source": String(fallback_entry.get("source", target_source)),
					})
					_set_deposit_lock(beh, spawn_pos, "deposit_lock_blocked", {"cause": "stash_full"})
					continue
			fallback_drop.item_id = fallback_item_id
			fallback_drop.amount = fallback_amount
			get_tree().current_scene.add_child(fallback_drop)
			fallback_drop.global_position = land_target + Vector2(randf_range(-8.0, 8.0), randf_range(-4.0, 4.0))
			fallback_drop.set_deferred("collision_layer", 4)
			fallback_drop.set_deferred("monitoring", true)
			fallback_drop.set_process(true)
			fallback_drop.add_to_group("item_drop")
			fallback_dropped_any = true
			_emit_worker_event("cargo_not_returning", beh, spawn_pos, fallback_item_id, {
				"reason": "deposit_blocked",
				"cause": "stash_full",
				"source": String(fallback_entry.get("source", target_source)),
			})
		var has_visualized_resolution: bool = inserted_any or fallback_dropped_any
		if not has_visualized_resolution or unresolved_fallback:
			_emit_worker_event("deposit_retry", beh, spawn_pos, "", {
				"cause": "compact_unresolved",
				"source": target_source,
				"inserted_total": inserted_total,
				"fallback_batches": fallback_batches.size(),
				"unresolved_fallback": unresolved_fallback,
			})
			_set_deposit_lock(beh, spawn_pos, "deposit_lock_retry", {
				"cause": "compact_unresolved",
				"source": target_source,
			})
			beh._just_arrived_home_with_cargo = true
			beh.force_return_home()
			return
		var visual_cleanup := _consume_carried_visual_nodes_for_deposit(beh, land_target, true)
		var one_shot_sfx: AudioStream = visual_cleanup.get("sfx", null) as AudioStream
		if one_shot_sfx != null:
			AudioSystem.play_2d(one_shot_sfx, spawn_pos, null, &"SFX")
		_force_clear_cargo_after_deposit(beh)
		if inserted_any:
			_emit_worker_event("deposit_success_logical", beh, spawn_pos, "", {
				"inserted_total": inserted_total,
				"source": target_source,
			})
			_emit_worker_event("deposit_success", beh, spawn_pos, "", {
				"amount": inserted_total,
				"source": target_source,
			})
		_emit_worker_event("deposit_success_visual", beh, spawn_pos, "", {
			"scheduled": int(visual_cleanup.get("scheduled", 0)),
			"freed": int(visual_cleanup.get("freed", 0)),
			"missing": int(visual_cleanup.get("missing", 0)),
		})
		_clear_deposit_attempt_queue(beh)
		Debug.log("bandit_ai", "[CampStash] cargo depositado id=%s pos=%s chest=%s compact=true" % [
			beh.member_id, str(spawn_pos), str(chest != null)])
		_close_deposit(beh, spawn_pos, target_source, "deposit_closed")
		return

	if not ENABLE_LEGACY_DETAILED_DEPOSIT_PATH:
		_close_deposit(beh, spawn_pos, target_source, "deposit_closed")
		Debug.log("bandit_ai", "[CampStash] cargo depositado id=%s pos=%s chest=%s compact=forced" % [
			beh.member_id, str(spawn_pos), str(chest != null)])
		return

	for i in beh._cargo_manifest.size():
		var entry:      Dictionary  = beh._cargo_manifest[i]
		var node_id:    int         = int(entry.get("node_id",    0))
		var item_id:    String      = String(entry.get("item_id", ""))
		var amount:     int         = int(entry.get("amount",     1))
		var orig_layer: int         = int(entry.get("orig_layer", 4))
		var offset      := Vector2(randf_range(-8.0, 8.0), randf_range(-4.0, 4.0))
		var ground_pos  := land_target + offset

		# Obtener o re-spawnar el nodo del drop
		var drop_node: ItemDrop = null
		if node_id != 0 and is_instance_id_valid(node_id):
			var obj := instance_from_id(node_id)
			if obj != null and is_instance_valid(obj) \
					and not (obj as Node).is_queued_for_deletion():
				drop_node = obj as ItemDrop

		if drop_node == null:
			if item_id == "" or amount <= 0 or ITEM_DROP_SCENE == null:
				continue
			drop_node = ITEM_DROP_SCENE.instantiate() as ItemDrop
			if drop_node == null:
				continue
			drop_node.item_id = item_id
			drop_node.amount  = amount
			get_tree().current_scene.add_child(drop_node)
			drop_node.global_position = spawn_pos + Vector2(0.0, CARRY_STACK_BASE_Y - i * CARRY_STACK_STEP_Y)

		# Reparentar a la escena manteniendo la posición elevada del carry
		var carry_pos := drop_node.global_position
		if drop_node.get_parent() != get_tree().current_scene:
			drop_node.reparent(get_tree().current_scene, false)
		drop_node.global_position = carry_pos

		# Caída animada hacia el barril/suelo
		var tw := create_tween()
		tw.tween_property(drop_node, "global_position", ground_pos, fall_time) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

		var cap_drop     := drop_node
		var cap_item_id  := item_id
		var cap_amount   := amount
		var cap_sfx: AudioStream = drop_node.get("pickup_sfx") as AudioStream
		var cap_group_id := beh.group_id

		if chest != null:
			var deposit_delay := fall_time + i * sfx_stagger
			get_tree().create_timer(deposit_delay).timeout.connect(func() -> void:
				if not is_instance_valid(cap_drop) or cap_drop.is_queued_for_deletion():
					return
				var inserted := int(chest.call("try_insert_item", cap_item_id, cap_amount))
				if inserted > 0:
					_force_clear_cargo_after_deposit(beh)
					_emit_worker_event("deposit_success", beh, spawn_pos, cap_item_id, {
						"amount": inserted,
						"source": target_source,
					})
					_clear_deposit_attempt_queue(beh)
					if cap_sfx != null:
						AudioSystem.play_2d(cap_sfx, spawn_pos, null, &"SFX")
					cap_drop.queue_free()
					return
				# Barril lleno — buscar extras del grupo primero
				if cap_group_id != "":
					var found_space := false
					for gid in _camp_barrels.keys():
						if not String(gid).begins_with(cap_group_id) or String(gid) == cap_group_id:
							continue
						var bid: int = int(_camp_barrels[gid])
						if bid == 0 or not is_instance_id_valid(bid):
							continue
						var bn2 := instance_from_id(bid) as Node
						if bn2 == null or not is_instance_valid(bn2) \
								or not _method_caps.has_method_cached(bn2, &"try_insert_item"):
							continue
						var ins2 := int(bn2.call("try_insert_item", cap_item_id, cap_amount))
						if ins2 > 0:
							_force_clear_cargo_after_deposit(beh)
							_emit_worker_event("deposit_success", beh, spawn_pos, cap_item_id, {
								"amount": ins2,
								"source": "extra_barrel_retarget",
							})
							_camp_barrels[cap_group_id] = bid
							_notify_deposit_pos(cap_group_id, (bn2 as Node2D).global_position)
							if cap_sfx != null:
								AudioSystem.play_2d(cap_sfx, spawn_pos, null, &"SFX")
							cap_drop.queue_free()
							_clear_deposit_attempt_queue(beh)
							found_space = true
							break
					if not found_space:
						var col: int = 0
						for gid in _camp_barrels:
							if String(gid).begins_with(cap_group_id):
								col += 1
						var new_barrel := _spawn_camp_barrel(spawn_pos, col)
						if new_barrel != null:
							var nrid: int = new_barrel.get_instance_id()
							_camp_barrels[cap_group_id + "_extra_%d" % col] = nrid
							_camp_barrels[cap_group_id] = nrid
							_notify_deposit_pos(cap_group_id, (new_barrel as Node2D).global_position)
							var inserted_new: int = int(new_barrel.call("try_insert_item", cap_item_id, cap_amount))
							if inserted_new > 0:
								_force_clear_cargo_after_deposit(beh)
								_emit_worker_event("deposit_success", beh, spawn_pos, cap_item_id, {
									"amount": inserted_new,
									"source": "extra_barrel_spawn",
								})
							if cap_sfx != null:
								AudioSystem.play_2d(cap_sfx, spawn_pos, null, &"SFX")
							cap_drop.queue_free()
							_clear_deposit_attempt_queue(beh)
							return
				# Sin espacio en ningún barril — dejar en el suelo
				_emit_worker_event("cargo_not_returning", beh, spawn_pos, cap_item_id, {
					"reason": "deposit_blocked",
					"cause": "stash_full",
					"source": target_source,
				})
				_set_deposit_lock(beh, spawn_pos, "deposit_lock_blocked", {"cause": "stash_full"})
				cap_drop.add_to_group("item_drop")
				cap_drop.set_deferred("collision_layer", orig_layer)
				cap_drop.set_deferred("monitoring",      true)
				cap_drop.set_process(true)
			)
		else:
			# Sin barril — spawnear uno nuevo en la posición de depósito
			var cap_group_id2 := beh.group_id
			var cap_deposit   := land_target
			get_tree().create_timer(fall_time).timeout.connect(func() -> void:
				if not is_instance_valid(cap_drop) or cap_drop.is_queued_for_deletion():
					return
				var new_barrel := _spawn_camp_barrel(cap_deposit - Vector2(36.0, 0.0), 0)
				if new_barrel != null and cap_group_id2 != "":
					_camp_barrels[cap_group_id2] = new_barrel.get_instance_id()
					_notify_deposit_pos(cap_group_id2, new_barrel.global_position)
				if new_barrel != null:
					var inserted_fallback: int = int(new_barrel.call("try_insert_item", cap_item_id, cap_amount))
					if inserted_fallback > 0:
						_force_clear_cargo_after_deposit(beh)
						_emit_worker_event("deposit_success", beh, spawn_pos, cap_item_id, {
							"amount": inserted_fallback,
							"source": "spawned_new_barrel",
						})
					if cap_sfx != null:
						AudioSystem.play_2d(cap_sfx, cap_deposit, null, &"SFX")
					cap_drop.queue_free()
					_clear_deposit_attempt_queue(beh)
				else:
					_emit_worker_event("cargo_not_returning", beh, spawn_pos, cap_item_id, {
						"reason": "deposit_blocked",
						"cause": "spawn_fallback_failed",
						"source": target_source,
					})
					_set_deposit_lock(beh, spawn_pos, "deposit_lock_blocked", {"cause": "spawn_fallback_failed"})
					cap_drop.add_to_group("item_drop")
					cap_drop.set_deferred("collision_layer", orig_layer)
					cap_drop.set_deferred("monitoring",      true)
					cap_drop.set_process(true)
			)

	_close_deposit(beh, spawn_pos, target_source, "deposit_closed")
	Debug.log("bandit_ai", "[CampStash] cargo depositado id=%s pos=%s chest=%s" % [
		beh.member_id, str(spawn_pos), str(chest != null)])


## Appends inventory-style entries into bandit carry, respecting cargo capacity.
## entries format: [{item_id: String, amount: int}]
## Returns {added: int, taken: Array[Dictionary], leftovers: Array[Dictionary]}.
func append_manifest_entries(beh: BanditWorldBehavior, entries: Array) -> Dictionary:
	var result := {
		"added": 0,
		"taken": [],
		"leftovers": [],
	}
	if beh == null or entries.is_empty():
		return result

	var remaining_capacity: int = maxi(0, beh.cargo_capacity - beh.cargo_count)
	if remaining_capacity <= 0:
		for raw_entry in entries:
			if not (raw_entry is Dictionary):
				continue
			var e: Dictionary = raw_entry as Dictionary
			var item_id: String = String(e.get("item_id", "")).strip_edges()
			var amount: int = int(e.get("amount", 0))
			if item_id == "" or amount <= 0:
				continue
			(result["leftovers"] as Array).append({"item_id": item_id, "amount": amount})
		return result

	var taken: Array = []
	var leftovers: Array = []
	var added: int = 0
	for raw_entry in entries:
		if not (raw_entry is Dictionary):
			continue
		var entry: Dictionary = raw_entry as Dictionary
		var item_id: String = String(entry.get("item_id", "")).strip_edges()
		var amount: int = int(entry.get("amount", 0))
		if item_id == "" or amount <= 0:
			continue

		var take_amount: int = mini(amount, remaining_capacity)
		if take_amount > 0:
			beh._cargo_manifest.append({
				"item_id": item_id,
				"amount": take_amount,
				"node_id": 0,
			})
			beh.cargo_count += take_amount
			remaining_capacity -= take_amount
			added += take_amount
			taken.append({"item_id": item_id, "amount": take_amount})

		var leftover_amount: int = amount - take_amount
		if leftover_amount > 0:
			leftovers.append({"item_id": item_id, "amount": leftover_amount})

		if remaining_capacity <= 0:
			continue

	result["added"] = added
	result["taken"] = taken
	result["leftovers"] = leftovers
	return result


## Suelta todo el cargo al suelo cuando el NPC entra en combate.
func drop_carry_on_aggro(beh: BanditWorldBehavior, enemy_node: Node) -> void:
	var drop_pos: Vector2 = beh.home_pos
	if enemy_node != null and is_instance_valid(enemy_node):
		drop_pos = (enemy_node as Node2D).global_position

	for entry in beh._cargo_manifest:
		var node_id: int    = int(entry.get("node_id",    0))
		var orig_layer: int = int(entry.get("orig_layer", 4))
		var throw_dir := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 0.2)).normalized()

		if node_id != 0 and is_instance_id_valid(node_id):
			var drop_node := instance_from_id(node_id) as ItemDrop
			if drop_node != null and is_instance_valid(drop_node) \
					and not drop_node.is_queued_for_deletion():
				if drop_node.is_in_group("item_drop"):
					continue
				drop_node.reparent(get_tree().current_scene, false)
				drop_node.add_to_group("item_drop")
				drop_node.set_deferred("collision_layer", orig_layer)
				drop_node.set_deferred("monitoring",      true)
				drop_node.set_process(true)
				drop_node.throw_from(drop_pos, throw_dir, randf_range(55.0, 110.0))
				continue

		# Fallback: el nodo no sobrevivió — spawnear uno nuevo
		var item_id := String(entry.get("item_id", ""))
		var amount  := int(entry.get("amount", 1))
		if item_id == "" or amount <= 0 or ITEM_DROP_SCENE == null:
			continue
		var drop := ITEM_DROP_SCENE.instantiate() as ItemDrop
		if drop == null:
			continue
		drop.item_id = item_id
		drop.amount  = amount
		get_tree().current_scene.add_child(drop)
		drop.throw_from(drop_pos, throw_dir, randf_range(55.0, 110.0))

	beh._cargo_manifest.clear()
	beh.cargo_count                   = 0
	beh._just_arrived_home_with_cargo = false
	beh.delivery_lock_active          = false
	_clear_deposit_lock(beh, drop_pos, "deposit_lock_cleared_drop_on_aggro")
	_clear_deposit_attempt_queue(beh)
	Debug.log("bandit_ai", "[CampStash] carry soltado al entrar en combate id=%s" % beh.member_id)


# ---------------------------------------------------------------------------
# Privado — sweep y collection
# ---------------------------------------------------------------------------

func _resolve_enemy_pos(enemy_node: Node) -> Vector2:
	var node2d := enemy_node as Node2D
	return node2d.global_position if node2d != null else Vector2.ZERO


func _get_global_processed(global_budget_ctx: Dictionary) -> int:
	return int(global_budget_ctx.get("processed", 0))


func _get_npc_processed(npc_budget_ctx: Dictionary) -> int:
	return int(npc_budget_ctx.get("processed", 0))


func _get_npc_max(query_ctx: Dictionary, npc_budget_ctx: Dictionary) -> int:
	return maxi(int(query_ctx.get("drops_per_npc_per_tick_max", npc_budget_ctx.get("max", drops_per_npc_per_tick_max))), 0)


func _get_global_max(query_ctx: Dictionary, global_budget_ctx: Dictionary) -> int:
	return maxi(int(query_ctx.get("drops_global_per_pulse_max", global_budget_ctx.get("max", drops_global_per_pulse_max))), 0)


func _is_global_budget_hit(query_ctx: Dictionary) -> bool:
	var global_budget_ctx: Dictionary = query_ctx.get("drops_global_counter_ctx", {}) as Dictionary
	if global_budget_ctx.is_empty():
		return false
	var global_max: int = _get_global_max(query_ctx, global_budget_ctx)
	if global_max <= 0:
		return false
	return _get_global_processed(global_budget_ctx) >= global_max


func _is_npc_budget_hit(query_ctx: Dictionary) -> bool:
	var npc_budget_ctx: Dictionary = query_ctx.get("drops_npc_counter_ctx", {}) as Dictionary
	if npc_budget_ctx.is_empty():
		return false
	var npc_max: int = _get_npc_max(query_ctx, npc_budget_ctx)
	if npc_max <= 0:
		return false
	return _get_npc_processed(npc_budget_ctx) >= npc_max


func _mark_budget_hit(beh: BanditWorldBehavior, check_pos: Vector2, query_ctx: Dictionary,
		scope: String, local_processed: int, local_max: int) -> void:
	_drop_processing_budget_hits += 1
	_debug_budget_hits_in_pulse += 1
	var global_budget_ctx: Dictionary = query_ctx.get("drops_global_counter_ctx", {}) as Dictionary
	_emit_worker_event("drop_budget_hit", beh, check_pos, str(beh.pending_collect_id), {
		"scope": scope,
		"stage": String(query_ctx.get("stage", "drop_collect")),
		"local_processed": local_processed,
		"local_max": local_max,
		"global_processed": _get_global_processed(global_budget_ctx),
		"global_max": _get_global_max(query_ctx, global_budget_ctx),
		"has_pending_collect": beh.pending_collect_id != 0,
	})


func _consume_pickup_budget(query_ctx: Dictionary) -> void:
	var global_budget_ctx: Dictionary = query_ctx.get("drops_global_counter_ctx", {}) as Dictionary
	if not global_budget_ctx.is_empty():
		global_budget_ctx["processed"] = _get_global_processed(global_budget_ctx) + 1
	var npc_budget_ctx: Dictionary = query_ctx.get("drops_npc_counter_ctx", {}) as Dictionary
	if not npc_budget_ctx.is_empty():
		npc_budget_ctx["processed"] = _get_npc_processed(npc_budget_ctx) + 1


func _sweep(beh: BanditWorldBehavior, enemy_node: Node,
		check_pos: Vector2, radius_sq: float, query_budget_ctx: Dictionary = {}) -> void:
	if beh.is_cargo_full():
		return
	var actor_pos: Vector2 = _resolve_enemy_pos(enemy_node)
	var query_radius: float = sqrt(maxf(radius_sq, 0.0))
	var budget_scale: float = _pickup_budget_scale()
	var query_ctx: Dictionary = {
		"intent": "idle",
		"stage": "drop_collect",
		"max_candidates_eval": 32,
		"drops_per_npc_per_tick_max": maxi(1, int(floor(float(drops_per_npc_per_tick_max) * budget_scale))),
		"drops_global_per_pulse_max": maxi(1, int(floor(float(drops_global_per_pulse_max) * budget_scale))),
	}
	for key in query_budget_ctx.keys():
		query_ctx[key] = query_budget_ctx[key]
	var eligibility: Dictionary = _is_sweep_eligible(beh, query_ctx)
	var mode: String = String(eligibility.get("mode", "normal"))
	if mode == "assault":
		var group_key: String = beh.group_id if beh.group_id != "" else "_ungrouped"
		_eligible_looters_per_group[group_key] = int(eligibility.get("eligible_count", 0))
	if not bool(eligibility.get("eligible", true)):
		var blocked_by: String = String(eligibility.get("blocked_by", "role"))
		if blocked_by == "group_cap":
			_debug_sweep_attempts_blocked_by_group_cap_in_pulse += 1
		else:
			_debug_sweep_attempts_blocked_by_role_in_pulse += 1
		_emit_worker_event("pickup_sweep_blocked", beh, check_pos, "", {
			"blocked_by": blocked_by,
			"group_pickup_mode": mode,
			"group_looter_cap": int(query_ctx.get("assault_pickup_group_looter_cap", _assault_pickup_group_looter_cap())),
			"scavenger_only": _assault_pickup_scavenger_only(),
		})
		return
	var npc_budget_ctx: Dictionary = query_ctx.get("drops_npc_counter_ctx", {}) as Dictionary
	var local_budget_max: int = _get_npc_max(query_ctx, npc_budget_ctx)
	var local_processed: int = _get_npc_processed(npc_budget_ctx)
	if _is_global_budget_hit(query_ctx):
		_mark_budget_hit(beh, check_pos, query_ctx, "global", local_processed, local_budget_max)
		return
	if _is_npc_budget_hit(query_ctx):
		_mark_budget_hit(beh, check_pos, query_ctx, "npc", local_processed, local_budget_max)
		return
	var max_candidates_eval: int = maxi(int(query_ctx.get("max_candidates_eval", 0)), 0)
	var candidates := _world_spatial_index.get_runtime_nodes_near(
		KIND_ITEM_DROP,
		check_pos,
		query_radius,
		query_ctx
	)
	var candidate_nodes: Array[Node2D] = []
	for raw_drop in candidates:
		var drop_node := raw_drop as Node2D
		if drop_node == null or not is_instance_valid(drop_node) \
				or drop_node.is_queued_for_deletion():
			continue
		if not drop_node.is_in_group("item_drop"):
			continue
		candidate_nodes.append(drop_node)
		if max_candidates_eval > 0 and candidate_nodes.size() >= max_candidates_eval:
			break
	_debug_pickup_queries_in_pulse += 1
	_debug_drop_candidates_total_in_pulse += candidate_nodes.size()
	var found_candidate: bool = false
	var collected_in_sweep: int = 0
	var representative_sfx: AudioStream = null
	var representative_pos: Vector2 = actor_pos
	for drop_node in candidate_nodes:
		if beh.is_cargo_full():
			break
		if _is_global_budget_hit(query_ctx):
			_mark_budget_hit(beh, check_pos, query_ctx, "global", local_processed, local_budget_max)
			break
		if _is_npc_budget_hit(query_ctx):
			_mark_budget_hit(beh, check_pos, query_ctx, "npc", local_processed, local_budget_max)
			break
		if actor_pos.distance_squared_to(drop_node.global_position) > radius_sq:
			continue
		found_candidate = true
		_consume_pickup_budget(query_ctx)
		local_processed += 1
		beh.pending_collect_id = drop_node.get_instance_id()
		_emit_worker_event("drop_detected", beh, check_pos, str(beh.pending_collect_id), {
			"drop_pos": _fmt_pos(drop_node.global_position),
			"radius_sq": snappedf(radius_sq, 0.01),
		})
		var collect_result: Dictionary = _handle_collection(beh, enemy_node)
		if bool(collect_result.get("collected", false)):
			collected_in_sweep += 1
			if representative_sfx == null:
				representative_sfx = collect_result.get("sfx_stream", null) as AudioStream
				representative_pos = collect_result.get("sfx_pos", representative_pos) as Vector2
	if collected_in_sweep > 0:
		_play_pickup_sfx_aggregated(beh, representative_sfx, representative_pos)
	if not found_candidate:
		_emit_worker_event("pickup_candidates_empty", beh, check_pos, "", {
			"radius_sq": snappedf(radius_sq, 0.01),
			"candidate_count": candidate_nodes.size(),
			"query_radius": snappedf(query_radius, 0.01),
		})


func _play_pickup_sfx_aggregated(beh: BanditWorldBehavior, sfx_stream: AudioStream, sfx_pos: Vector2) -> void:
	if beh == null:
		return
	var member_id: String = beh.member_id
	var pulse_id: int = _debug_drop_pulse_id
	if int(_pickup_sfx_last_pulse_by_member.get(member_id, -1)) == pulse_id:
		return
	var now_ms: int = Time.get_ticks_msec()
	var last_ms: int = int(_pickup_sfx_last_ms_by_member.get(member_id, -PICKUP_SFX_COOLDOWN_MS))
	if now_ms - last_ms < PICKUP_SFX_COOLDOWN_MS:
		return
	var stream_to_play: AudioStream = sfx_stream if sfx_stream != null else AudioSystem.default_pickup_sfx
	AudioSystem.play_2d(stream_to_play, sfx_pos, null, &"SFX")
	_pickup_sfx_last_ms_by_member[member_id] = now_ms
	_pickup_sfx_last_pulse_by_member[member_id] = pulse_id


func _handle_collection(beh: BanditWorldBehavior, enemy_node: Node) -> Dictionary:
	var drop_id: int = beh.pending_collect_id
	beh.pending_collect_id = 0

	if drop_id == 0 or not is_instance_id_valid(drop_id):
		_emit_worker_event("drop_not_visible", beh, _resolve_enemy_pos(enemy_node), str(drop_id), {
			"reason": "invalid_instance_id",
		})
		return {"collected": false}
	_emit_worker_event("drop_pickup_attempt", beh, _resolve_enemy_pos(enemy_node), str(drop_id), {
		"cargo": "%d/%d" % [beh.cargo_count, beh.cargo_capacity],
	})
	var drop_obj: Object = instance_from_id(drop_id)
	if drop_obj == null or not is_instance_valid(drop_obj):
		_emit_worker_event("drop_not_visible", beh, _resolve_enemy_pos(enemy_node), str(drop_id), {
			"reason": "drop_object_missing",
		})
		return {"collected": false}
	var drop_node: Node2D = drop_obj as Node2D
	if drop_node == null or drop_node.is_queued_for_deletion():
		_emit_worker_event("drop_not_visible", beh, _resolve_enemy_pos(enemy_node), str(drop_id), {
			"reason": "drop_node_deleted",
		})
		return {"collected": false}

	var collected_amount: int = int(drop_node.get("amount") if drop_node.get("amount") != null else 1)
	var item_id: String       = String(drop_node.get("item_id") if drop_node.get("item_id") != null else "")
	var drop_pos: Vector2     = drop_node.global_position
	var pickup_sfx            = drop_node.get("pickup_sfx")
	var sfx_stream: AudioStream = pickup_sfx if pickup_sfx is AudioStream else AudioSystem.default_pickup_sfx

	var carried: bool = false
	if enemy_node != null and is_instance_valid(enemy_node):
		var orig_layer: int = drop_node.collision_layer
		drop_node.remove_from_group("item_drop")
		drop_node.set_deferred("monitoring",      false)
		drop_node.set_deferred("collision_layer", 0)
		drop_node.set_process(false)
		var stack_offset := Vector2(0.0, CARRY_STACK_BASE_Y - beh._cargo_manifest.size() * CARRY_STACK_STEP_Y)
		drop_node.reparent(enemy_node, false)
		drop_node.position = stack_offset
		beh._cargo_manifest.append({
			"item_id":    item_id,
			"amount":     collected_amount,
			"node_id":    drop_node.get_instance_id(),
			"orig_layer": orig_layer,
		})
		carried = true

	if not carried:
		drop_node.queue_free()
		if item_id != "":
			beh._cargo_manifest.append({"item_id": item_id, "amount": collected_amount, "node_id": 0})

	var prev: int = beh.cargo_count
	beh.cargo_count = mini(beh.cargo_count + collected_amount, beh.cargo_capacity)
	_emit_worker_event("drop_pickup_success", beh, drop_pos, str(drop_id), {
		"item_id": item_id,
		"amount": collected_amount,
		"cargo_before": prev,
		"cargo_after": beh.cargo_count,
	})
	Debug.log("bandit_ai", "[CampStash] collected %s×%d id=%s cargo=%d→%d/%d" % [
		item_id, collected_amount, beh.member_id, prev, beh.cargo_count, beh.cargo_capacity])
	return {
		"collected": true,
		"sfx_stream": sfx_stream,
		"sfx_pos": drop_pos,
	}


# ---------------------------------------------------------------------------
# Privado — barrel spawn
# ---------------------------------------------------------------------------

func _spawn_camp_barrel(home_pos: Vector2, column: int = 0) -> Node:
	if CAMP_BARREL_SCENE == null:
		push_warning("[CampStash] CAMP_BARREL_SCENE not loaded")
		return null
	var barrel := CAMP_BARREL_SCENE.instantiate()
	get_tree().current_scene.add_child(barrel)
	barrel.global_position = home_pos + Vector2(BARREL_SPAWN_OFFSET_BASE + column * BARREL_SPAWN_COLUMN_STEP, 0.0)
	Debug.log("camp_stash", "[CampStash] spawned camp barrel at=%s col=%d" % [str(home_pos), column])
	return barrel


func _notify_deposit_pos(group_id: String, barrel_pos: Vector2) -> void:
	if _update_deposit_pos_cb.is_valid():
		_update_deposit_pos_cb.call(group_id, barrel_pos)


func _resolve_deposit_target(group_id: String, near_pos: Vector2, bypass_range_gate: bool = false) -> Dictionary:
	var result := {
		"node": null,
		"source": "none",
		"missing_cause": "none",
		"allow_spawn_fallback": true,
	}
	# 1) Primario: barril asignado al grupo (con un reintento inmediato).
	if group_id != "":
		for _attempt in 2:
			var barrel_id: int = int(_camp_barrels.get(group_id, 0))
			if barrel_id == 0:
				result["missing_cause"] = "group_barrel_id_missing"
			elif not is_instance_id_valid(barrel_id):
				result["missing_cause"] = "group_barrel_instance_invalid"
			else:
				var barrel := instance_from_id(barrel_id) as Node
				if barrel == null or not is_instance_valid(barrel) or barrel.is_queued_for_deletion():
					result["missing_cause"] = "group_barrel_deleted"
				elif not _method_caps.has_method_cached(barrel, &"try_insert_item"):
					result["missing_cause"] = "group_barrel_no_insert_method"
				elif not bypass_range_gate and barrel is Node2D and near_pos.distance_squared_to(
						(barrel as Node2D).global_position) > DEPOSIT_TARGET_MAX_DIST_SQ:
					result["missing_cause"] = "pathing_or_out_of_range"
				else:
					result["node"] = barrel
					result["source"] = "group_barrel"
					result["missing_cause"] = "none"
					return result

		# 2) Fallback principal: otro barril válido del mismo grupo.
		var best_fallback: Node = null
		var best_dist_sq: float = INF
		for gid in _camp_barrels.keys():
			var gid_str: String = String(gid)
			if not gid_str.begins_with(group_id):
				continue
			var extra_id: int = int(_camp_barrels.get(gid_str, 0))
			if extra_id == 0 or not is_instance_id_valid(extra_id):
				continue
			var extra := instance_from_id(extra_id) as Node
			if extra == null or not is_instance_valid(extra) or extra.is_queued_for_deletion():
				continue
			if not _method_caps.has_method_cached(extra, &"try_insert_item"):
				continue
			var dist_sq: float = 0.0
			if extra is Node2D:
				dist_sq = near_pos.distance_squared_to((extra as Node2D).global_position)
			if dist_sq < best_dist_sq:
				best_dist_sq = dist_sq
				best_fallback = extra
		if best_fallback != null:
			result["node"] = best_fallback
			result["source"] = "group_barrel_fallback"
			result["missing_cause"] = "none"
			result["allow_spawn_fallback"] = false
			return result

	if String(result["missing_cause"]) == "none":
		result["missing_cause"] = "group_barrel_unresolved"
	return result
