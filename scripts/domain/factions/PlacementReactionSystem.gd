extends RefCounted
class_name PlacementReactionSystem

const BuildingEventDtoScript := preload("res://scripts/domain/contracts/BuildingEventDto.gd")
const DEFAULT_INTENT_LOCK_SECONDS: float = 90.0
const DEFAULT_STRUCT_ASSAULT_SQUAD: int = 3
const DEFAULT_EVENT_MIN_INTERVAL: float = 0.20
const DEFAULT_DEBUG_MAX_EVENTS: int = 96
const DEFAULT_EVENT_DEDUPE_WINDOW: float = 0.35

var _threat_assessment_system: ThreatAssessmentSystem
var _group_intent_system: BanditIntentSystem
var _world_spatial_index: WorldSpatialIndex
var _tile_to_world_cb: Callable
var _nearest_workbench_world_pos_cb: Callable
var _drop_hotspots_provider_cb: Callable
var _enemy_node_provider_cb: Callable

var _domain_event_dispatcher: SandboxDomainEventDispatcher

var _placement_react_last_event_at: float = -9999.0
var _placement_react_pulse_seq: int = 0
var _placement_react_debug_total_events: int = 0
var _placement_react_debug_total_activated_groups: int = 0
var _placement_react_debug_total_intents_published: int = 0
var _placement_react_debug_recent_events: Array[Dictionary] = []
var _placement_react_debug_skipped_duplicate_events: int = 0
var _recent_event_fingerprints: Dictionary = {}

var _default_radius: float = 640.0
var _radius_by_item_id: Dictionary = {}
var _max_groups_per_event: int = 3
var _min_score: float = 0.40
var _high_priority_score: float = 0.72
var _struct_assault_squad_size: int = DEFAULT_STRUCT_ASSAULT_SQUAD
var _high_priority_squad_size_override: int = 4
var _blocking_checks_budget: int = 4
var _lock_min_relevance_delta: float = 0.12
var _lock_min_distance_delta_px: float = 96.0
var _wall_assault_global_mode: bool = true
var _wall_assault_radius: float = 12000.0
var _wall_assault_min_score: float = 0.18
var _event_min_interval: float = DEFAULT_EVENT_MIN_INTERVAL
var _event_dedupe_window: float = DEFAULT_EVENT_DEDUPE_WINDOW
var _intent_lock_seconds: float = DEFAULT_INTENT_LOCK_SECONDS
var _debug_max_events: int = DEFAULT_DEBUG_MAX_EVENTS

func setup(config: Dictionary = {}) -> void:
	_threat_assessment_system = config.get("threat_assessment_system") as ThreatAssessmentSystem
	_group_intent_system = config.get("group_intent_system") as BanditIntentSystem
	_world_spatial_index = config.get("world_spatial_index") as WorldSpatialIndex
	_tile_to_world_cb = config.get("tile_to_world", Callable()) as Callable
	_nearest_workbench_world_pos_cb = config.get("nearest_workbench_world_pos", Callable()) as Callable
	_drop_hotspots_provider_cb = config.get("drop_hotspots_provider", Callable()) as Callable
	_enemy_node_provider_cb = config.get("enemy_node_provider", Callable()) as Callable
	_domain_event_dispatcher = config.get("domain_event_dispatcher", null) as SandboxDomainEventDispatcher
	_default_radius = maxf(0.0, float(config.get("default_radius", _default_radius)))
	_radius_by_item_id = (config.get("radius_by_item_id", {}) as Dictionary).duplicate(true)
	_max_groups_per_event = maxi(1, int(config.get("max_groups_per_event", _max_groups_per_event)))
	_min_score = clampf(float(config.get("min_score", _min_score)), 0.0, 1.0)
	_high_priority_score = clampf(float(config.get("high_priority_score", _high_priority_score)), 0.0, 1.0)
	_struct_assault_squad_size = maxi(1, int(config.get("struct_assault_squad_size", _struct_assault_squad_size)))
	_high_priority_squad_size_override = int(config.get("high_priority_squad_size_override", _high_priority_squad_size_override))
	_blocking_checks_budget = maxi(0, int(config.get("blocking_checks_budget", _blocking_checks_budget)))
	_lock_min_relevance_delta = maxf(0.0, float(config.get("lock_min_relevance_delta", _lock_min_relevance_delta)))
	_lock_min_distance_delta_px = maxf(0.0, float(config.get("lock_min_distance_delta_px", _lock_min_distance_delta_px)))
	_wall_assault_global_mode = bool(config.get("wall_assault_global_mode", _wall_assault_global_mode))
	_wall_assault_radius = maxf(0.0, float(config.get("wall_assault_radius", _wall_assault_radius)))
	_wall_assault_min_score = clampf(float(config.get("wall_assault_min_score", _wall_assault_min_score)), 0.0, 1.0)
	_event_min_interval = maxf(0.0, float(config.get("event_min_interval", _event_min_interval)))
	_event_dedupe_window = maxf(0.0, float(config.get("event_dedupe_window", _event_dedupe_window)))
	_intent_lock_seconds = maxf(0.0, float(config.get("intent_lock_seconds", _intent_lock_seconds)))
	_debug_max_events = maxi(1, int(config.get("debug_max_events", _debug_max_events)))


func handle_building_event(event_data: Dictionary) -> void:
	var normalized: Dictionary = _normalize_building_event(event_data)
	if normalized.is_empty():
		return
	var item_id: String = String(normalized.get("item_id", ""))
	var target_pos: Vector2 = normalized.get("target_position", Vector2.ZERO) as Vector2
	var now: float = RunClock.now()
	if _is_duplicate_event(normalized, now):
		Debug.log("placement_react", "  SUMMARY placement_event skipped_by_interval=%d skipped_by_duplicate=%d skipped_by_lock=%d activated=%d item=%s target=%s" % [
			0, 1, 0, 0, item_id, str(target_pos)
		])
		_record_debug_event(item_id, target_pos, 0, 0, 0, 0, 1)
		return
	if now - _placement_react_last_event_at < _event_min_interval:
		Debug.log("placement_react", "  SUMMARY placement_event skipped_by_interval=%d skipped_by_duplicate=%d skipped_by_lock=%d activated=%d item=%s target=%s" % [
			1, 0, 0, 0, item_id, str(target_pos)
		])
		_record_debug_event(item_id, target_pos, 0, 0, 1, 0, 0)
		return
	_placement_react_last_event_at = now
	_trigger_placement_react(normalized)


func reset_debug_metrics() -> void:
	_placement_react_debug_total_events = 0
	_placement_react_debug_total_activated_groups = 0
	_placement_react_debug_total_intents_published = 0
	_placement_react_debug_skipped_duplicate_events = 0
	_placement_react_debug_recent_events.clear()
	_recent_event_fingerprints.clear()


func get_debug_snapshot() -> Dictionary:
	var avg_dispatches_per_event: float = 0.0
	if _placement_react_debug_total_events > 0:
		avg_dispatches_per_event = float(_placement_react_debug_total_intents_published) / float(_placement_react_debug_total_events)
	return {
		"events_total": _placement_react_debug_total_events,
		"groups_activated_total": _placement_react_debug_total_activated_groups,
		"intents_published_total": _placement_react_debug_total_intents_published,
		"skipped_duplicate_events_total": _placement_react_debug_skipped_duplicate_events,
		"dispatches_per_event_avg": avg_dispatches_per_event,
		"last_event": _placement_react_debug_recent_events.back() if not _placement_react_debug_recent_events.is_empty() else {},
		"recent_events": _placement_react_debug_recent_events.duplicate(true),
	}


func _trigger_placement_react(source_event: Dictionary) -> void:
	var item_id: String = String(source_event.get("item_id", ""))
	var event_type: String = String(source_event.get("event_type", ThreatAssessmentSystem.EVENT_TYPE_PLACEMENT_COMPLETED))
	var source_metadata: Dictionary = source_event.get("metadata", {}) as Dictionary
	var target_pos: Vector2 = source_event.get("target_position", Vector2.ZERO) as Vector2
	var all_ids: Array = BanditGroupMemory.get_all_group_ids()
	var is_wall_assault_event: bool = _is_wall_assault_placement_item(item_id)
	var react_radius: float = _get_placement_react_radius(item_id)
	var react_radius_sq: float = react_radius * react_radius
	var min_score_threshold: float = _wall_assault_min_score if is_wall_assault_event else _min_score
	_placement_react_pulse_seq += 1
	var blocking_query_ctx: Dictionary = {
		"pulse_id": _placement_react_pulse_seq,
		"blocking_checks_budget": 0 if is_wall_assault_event else _blocking_checks_budget,
	}
	Debug.log("placement_react", "--- placement react target=%s groups_total=%d ---" % [
		str(target_pos), all_ids.size()])
	if all_ids.is_empty():
		_record_debug_event(item_id, target_pos, 0, 0, 0, 0)
		Debug.log("placement_react", "  SKIP: no hay grupos registrados en BanditGroupMemory")
		Debug.log("placement_react", "  SUMMARY placement_event skipped_by_interval=%d skipped_by_duplicate=%d skipped_by_lock=%d activated=%d item=%s target=%s" % [
			0, 0, 0, 0, item_id, str(target_pos)
		])
		return
	var groups_evaluated: int = 0
	var groups_eligible: int = 0
	var candidate_groups: Array[Dictionary] = []
	for gid in all_ids:
		var g: Dictionary = BanditGroupMemory.get_group(gid)
		var faction_id: String = String(g.get("faction_id", ""))
		var eradicated: bool = bool(g.get("eradicated", false))
		var members: Array = g.get("member_ids", []) as Array
		if eradicated or members.is_empty():
			continue
		if not _is_group_hostile_for_structure_assault(g):
			Debug.log("placement_react", "  group=%s faction=%s skipped (not hostile for structures)" % [gid, faction_id])
			continue
		var anchor: Dictionary = _get_group_react_anchor(g)
		var anchor_pos: Vector2 = anchor.get("pos", Vector2.ZERO) as Vector2
		var anchor_kind: String = String(anchor.get("kind", "none"))
		if anchor_kind == "none":
			continue
		groups_evaluated += 1
		var dist_sq: float = anchor_pos.distance_squared_to(target_pos)
		if dist_sq > react_radius_sq:
			Debug.log("placement_react", "  group=%s skipped (far) dist=%.1f radius=%.1f anchor=%s" % [gid, sqrt(dist_sq), react_radius, anchor_kind])
			continue
		if not is_wall_assault_event and int(blocking_query_ctx.get("blocking_checks_budget", 0)) <= 0:
			Debug.log("placement_react", "  blocking_checks_budget exhausted pulse=%d groups_evaluated=%d" % [int(blocking_query_ctx.get("pulse_id", -1)), groups_evaluated])
			break
		var score_pack: Dictionary = _score_placement_relevance(item_id, target_pos, anchor_pos, g, react_radius, blocking_query_ctx, is_wall_assault_event)
		groups_eligible += 1
		candidate_groups.append({
			"gid": gid,
			"group_data": g,
			"faction_id": faction_id,
			"anchor_kind": anchor_kind,
			"dist_sq": dist_sq,
			"score_pack": score_pack,
		})
	if candidate_groups.is_empty():
		_record_debug_event(item_id, target_pos, 0, 0, 0, 0)
		Debug.log("placement_react", "  SKIP: no hay grupos cercanos (evaluated=%d eligible=%d radius=%.1f)" % [groups_evaluated, groups_eligible, react_radius])
		Debug.log("placement_react", "  SUMMARY placement_event skipped_by_interval=%d skipped_by_duplicate=%d skipped_by_lock=%d activated=%d item=%s target=%s" % [0, 0, 0, 0, item_id, str(target_pos)])
		return
	candidate_groups.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_pack: Dictionary = a.get("score_pack", {}) as Dictionary
		var b_pack: Dictionary = b.get("score_pack", {}) as Dictionary
		var a_score: float = float(a_pack.get("score", 0.0))
		var b_score: float = float(b_pack.get("score", 0.0))
		if is_equal_approx(a_score, b_score):
			return float(a.get("dist_sq", INF)) < float(b.get("dist_sq", INF))
		return a_score > b_score
	)
	if _threat_assessment_system == null or _group_intent_system == null:
		return
	var assessment: Dictionary = _threat_assessment_system.assess_building_event(
		{
			"type": event_type,
			"item_id": item_id,
			"target_position": target_pos,
			"tile_pos": source_event.get("tile_pos", Vector2i.ZERO),
			"metadata": source_metadata.merged({
				"is_wall_assault_event": is_wall_assault_event,
				"react_radius": react_radius,
			}, true),
		},
		{
			"group_candidates": candidate_groups,
			"min_group_score": min_score_threshold,
			"max_groups": _max_groups_per_event,
		}
	)
	Debug.log("placement_react", "threat_ingestion source=%s event=%s item=%s priority=%s severity=%.2f relevant=%s" % [
		String(source_metadata.get("source", "building_event")),
		event_type,
		item_id,
		String(assessment.get("priority", "none")),
		float(assessment.get("severity", 0.0)),
		str(bool(assessment.get("is_relevant", false))),
	])
	if _domain_event_dispatcher != null:
		_domain_event_dispatcher.publish("threat_assessed", {
			"source": "placement_reaction",
			"assessment": assessment.duplicate(true),
		})
	var scoped: Dictionary = assessment.get("candidate_group_scope", {}) as Dictionary
	var scoped_candidates: Array = scoped.get("candidates", []) as Array
	if not bool(assessment.get("is_relevant", false)) or scoped_candidates.is_empty():
		_record_debug_event(item_id, target_pos, 0, 0, 0, 0)
		Debug.log("placement_react", "  SKIP: threat_assessment not relevant priority=%s severity=%.2f details=%s" % [String(assessment.get("priority", "none")), float(assessment.get("severity", 0.0)), str(assessment.get("debug", {}))])
		Debug.log("placement_react", "  SUMMARY placement_event skipped_by_interval=%d skipped_by_duplicate=%d skipped_by_lock=%d activated=%d item=%s target=%s" % [0, 0, 0, 0, item_id, str(target_pos)])
		return
	var scoped_by_gid: Dictionary = {}
	for scoped_entry_raw in scoped_candidates:
		if not (scoped_entry_raw is Dictionary):
			continue
		var scoped_entry := scoped_entry_raw as Dictionary
		var scoped_gid: String = String(scoped_entry.get("group_id", ""))
		if scoped_gid.is_empty():
			continue
		scoped_by_gid[scoped_gid] = scoped_entry
	var intent_published: int = 0
	var groups_activated: int = 0
	var skipped_by_lock: int = 0
	for entry in candidate_groups:
		var gid: String = String(entry.get("gid", ""))
		if not scoped_by_gid.has(gid):
			continue
		var g: Dictionary = entry.get("group_data", {}) as Dictionary
		var faction_id: String = String(entry.get("faction_id", ""))
		var anchor_kind: String = String(entry.get("anchor_kind", "unknown"))
		var score_pack: Dictionary = entry.get("score_pack", {}) as Dictionary
		var scoped_entry: Dictionary = scoped_by_gid.get(gid, {}) as Dictionary
		var score: float = float(scoped_entry.get("score", score_pack.get("score", 0.0)))
		var anchor_dist: float = sqrt(float(entry.get("dist_sq", INF)))
		var members: Array = g.get("member_ids", []) as Array
		if members.is_empty():
			continue
		var is_high_priority: bool = score >= _high_priority_score
		var effective_squad_size: int = _resolve_squad_size(is_high_priority)
		var publish_outcome: Dictionary = _group_intent_system.publish_placement_reaction_intent(
			assessment,
			{
				"group_id": gid,
				"score": score,
				"anchor_distance": anchor_dist,
				"anchor_kind": anchor_kind,
				"anchor_position": target_pos,
			},
			{
				"lock_min_relevance_delta": _lock_min_relevance_delta,
				"lock_min_distance_delta_px": _lock_min_distance_delta_px,
				"lock_seconds": _intent_lock_seconds,
				"squad_size": effective_squad_size,
				"ttl_seconds": BanditTuning.structure_assault_active_ttl(),
				"reason_source": "placed_structure",
				"source": BanditGroupMemory.ASSAULT_INTENT_SOURCE_PLACEMENT_REACT,
				"origin_event_ref": assessment.get("source_event", {}),
			}
		)
		var publish_status: String = String(publish_outcome.get("status", "unknown"))
		if publish_status == "ignored_by_lock":
			skipped_by_lock += 1
			Debug.log("placement_react", "  decision=ignored_by_lock group=%s score=%.2f prev_score=%.2f score_delta=%.2f dist=%.1f prev_dist=%.1f dist_delta=%.1f lock_active=%s anchor=%s" % [
				gid, score, float(publish_outcome.get("previous_score", -1.0)), float(publish_outcome.get("score_delta", 0.0)), anchor_dist, float(publish_outcome.get("previous_anchor_distance", INF)), float(publish_outcome.get("anchor_distance_delta", 0.0)), "true", anchor_kind
			])
			continue
		var published: bool = bool(publish_outcome.get("published", false))
		if published:
			intent_published += 1
			if _domain_event_dispatcher != null:
				_domain_event_dispatcher.publish("intent_published", {
					"source": "placement_reaction",
					"group_id": gid,
					"item_id": item_id,
					"event_type": event_type,
					"target_position": target_pos,
					"publish_status": publish_status,
					"intent": (publish_outcome.get("intent", {}) as Dictionary).duplicate(true),
				})
		groups_activated += 1
		var decision_tag: String = "reacted_high_priority" if is_high_priority else ("reacted_wall_global" if is_wall_assault_event else "reacted_local")
		Debug.log("placement_react", "  decision=%s group=%s faction=%s score=%.2f squad_size=%d intent_published=%s intent_status=%s precedence=placement_react>raid_queue>opportunistic anchor=%s details=%s" % [
			decision_tag, gid, faction_id, score, effective_squad_size, str(published), publish_status, anchor_kind, str(score_pack)
		])
	Debug.log("placement_react", "  SUMMARY evaluated=%d eligible=%d activated=%d intents_published=%d radius=%.1f max_groups=%d precedence=placement_react>raid_queue>opportunistic" % [
		groups_evaluated, groups_eligible, groups_activated, intent_published, react_radius, _max_groups_per_event
	])
	var blocking_metrics: Dictionary = NpcPathService.get_line_clear_budget_metrics()
	Debug.log("placement_react", "  blocking_budget pulse=%d used=%d left=%d exhausted=%d cache_hits=%d cache_misses=%d cache_size=%d" % [
		int(blocking_metrics.get("pulse_id", -1)),
		int(blocking_metrics.get("checks_used", 0)),
		int(blocking_query_ctx.get("blocking_checks_budget", 0)),
		int(blocking_metrics.get("budget_exhausted", 0)),
		int(blocking_metrics.get("cache_hits", 0)),
		int(blocking_metrics.get("cache_misses", 0)),
		int(blocking_metrics.get("cache_size", 0))
	])
	Debug.log("placement_react", "  SUMMARY placement_event skipped_by_interval=%d skipped_by_duplicate=%d skipped_by_lock=%d activated=%d item=%s target=%s" % [
		0, 0, skipped_by_lock, groups_activated, item_id, str(target_pos)
	])
	_record_debug_event(item_id, target_pos, groups_activated, intent_published, 0, skipped_by_lock, 0)


func _normalize_building_event(event_data: Dictionary) -> Dictionary:
	return BuildingEventDtoScript.normalize_for_threat_assessment(
		event_data,
		Callable(self, "_tile_to_world")
	)


func _record_debug_event(item_id: String, target_pos: Vector2, groups_activated: int,
		intents_published: int, skipped_by_interval: int, skipped_by_lock: int,
		skipped_by_duplicate: int = 0) -> void:
	_placement_react_debug_total_events += 1
	_placement_react_debug_total_activated_groups += maxi(groups_activated, 0)
	_placement_react_debug_total_intents_published += maxi(intents_published, 0)
	_placement_react_debug_skipped_duplicate_events += maxi(skipped_by_duplicate, 0)
	_placement_react_debug_recent_events.append({
		"at": RunClock.now(),
		"item_id": item_id,
		"target_pos": target_pos,
		"groups_activated": maxi(groups_activated, 0),
		"intents_published": maxi(intents_published, 0),
		"skipped_by_interval": maxi(skipped_by_interval, 0),
		"skipped_by_lock": maxi(skipped_by_lock, 0),
		"skipped_by_duplicate": maxi(skipped_by_duplicate, 0),
	})
	while _placement_react_debug_recent_events.size() > _debug_max_events:
		_placement_react_debug_recent_events.remove_at(0)


func _is_duplicate_event(normalized_event: Dictionary, now: float) -> bool:
	if _event_dedupe_window <= 0.0:
		return false
	var item_id: String = String(normalized_event.get("item_id", ""))
	var tile_pos: Vector2i = normalized_event.get("tile_pos", Vector2i.ZERO) as Vector2i
	var event_type: String = String(normalized_event.get("event_type", ""))
	var dedupe_family: String = _dedupe_family_for_event_type(event_type)
	var fingerprint: String = "%s|%s|%d|%d" % [dedupe_family, item_id, tile_pos.x, tile_pos.y]
	_prune_expired_event_fingerprints(now)
	if _recent_event_fingerprints.has(fingerprint):
		return true
	_recent_event_fingerprints[fingerprint] = now + _event_dedupe_window
	return false


func _dedupe_family_for_event_type(event_type: String) -> String:
	match event_type:
		ThreatAssessmentSystem.EVENT_TYPE_PLACEMENT_COMPLETED, ThreatAssessmentSystem.EVENT_TYPE_STRUCTURE_PLACED:
			return "placed"
		ThreatAssessmentSystem.EVENT_TYPE_STRUCTURE_DAMAGED:
			return "damaged"
		ThreatAssessmentSystem.EVENT_TYPE_STRUCTURE_REMOVED:
			return "removed"
		_:
			return event_type


func _prune_expired_event_fingerprints(now: float) -> void:
	if _recent_event_fingerprints.is_empty():
		return
	var stale: Array[String] = []
	for key_variant in _recent_event_fingerprints.keys():
		var key: String = String(key_variant)
		if float(_recent_event_fingerprints.get(key, 0.0)) <= now:
			stale.append(key)
	for key in stale:
		_recent_event_fingerprints.erase(key)


func _resolve_squad_size(is_high_priority: bool) -> int:
	if is_high_priority and _high_priority_squad_size_override > 0:
		return maxi(1, _high_priority_squad_size_override)
	return _struct_assault_squad_size


func _score_placement_relevance(item_id: String, target_pos: Vector2, anchor_pos: Vector2,
		group_data: Dictionary, react_radius: float, blocking_query_ctx: Dictionary,
		is_wall_assault_event: bool = false) -> Dictionary:
	var safe_radius: float = maxf(1.0, react_radius)
	var dist: float = anchor_pos.distance_to(target_pos)
	var distance_score: float = clampf(1.0 - (dist / safe_radius), 0.0, 1.0)
	var home_pos: Vector2 = group_data.get("home_world_pos", Vector2.ZERO) as Vector2
	var base_proximity_score: float = 0.0
	if home_pos != Vector2.ZERO:
		var base_dist: float = home_pos.distance_to(target_pos)
		base_proximity_score = clampf(1.0 - (base_dist / (safe_radius * 0.85)), 0.0, 1.0)
	var poi_score: float = _score_points_of_interest(item_id, target_pos, safe_radius)
	var blocking_score: float = _score_blocking(anchor_pos, target_pos, home_pos, blocking_query_ctx)
	var score: float = 0.0
	if is_wall_assault_event:
		score = 0.55 + distance_score * 0.18 + base_proximity_score * 0.08 + poi_score * 0.24
	else:
		score = distance_score * 0.50 + base_proximity_score * 0.22 + poi_score * 0.28 - blocking_score * 0.35
	score = clampf(score, 0.0, 1.0)
	return {
		"score": score,
		"distance": distance_score,
		"enemy_base": base_proximity_score,
		"poi": poi_score,
		"blocking": blocking_score,
		"blocking_checks_left": int(blocking_query_ctx.get("blocking_checks_budget", 0)),
	}


func _score_points_of_interest(_item_id: String, target_pos: Vector2, safe_radius: float) -> float:
	var poi_radius: float = minf(420.0, maxf(140.0, safe_radius * 0.65))
	var best_dist_sq: float = INF
	if _world_spatial_index != null:
		var res_nodes: Array = _world_spatial_index.get_runtime_nodes_near(
			WorldSpatialIndex.KIND_WORLD_RESOURCE,
			target_pos,
			poi_radius,
			{"enough_threshold": 3}
		)
		for node in res_nodes:
			if node is Node2D:
				var d_sq: float = (node as Node2D).global_position.distance_squared_to(target_pos)
				if d_sq < best_dist_sq:
					best_dist_sq = d_sq
		var storage_and_workbench: Array[Dictionary] = _world_spatial_index.get_placeables_by_item_ids_near(
			target_pos,
			poi_radius,
			["chest", "barrel", "workbench"],
			{"enough_threshold": 4}
		)
		for entry in storage_and_workbench:
			var tile_pos := Vector2i(int(entry.get("tile_pos_x", -999999)), int(entry.get("tile_pos_y", -999999)))
			if tile_pos.x <= -999999 or tile_pos.y <= -999999:
				continue
			var wpos: Vector2 = _tile_to_world(tile_pos)
			var d_sq: float = wpos.distance_squared_to(target_pos)
			if d_sq < best_dist_sq:
				best_dist_sq = d_sq
	var nearest_wb: Vector2 = _nearest_workbench_world_pos(target_pos, poi_radius)
	if nearest_wb != Vector2.ZERO:
		best_dist_sq = minf(best_dist_sq, nearest_wb.distance_squared_to(target_pos))
	for hotspot in _get_drop_hotspots():
		var hpos: Vector2 = hotspot.get("pos", Vector2.ZERO) as Vector2
		if hpos == Vector2.ZERO:
			continue
		var d_sq: float = hpos.distance_squared_to(target_pos)
		if d_sq < best_dist_sq:
			best_dist_sq = d_sq
	if best_dist_sq == INF:
		return 0.0
	return clampf(1.0 - (sqrt(best_dist_sq) / poi_radius), 0.0, 1.0)


func _score_blocking(anchor_pos: Vector2, target_pos: Vector2, home_pos: Vector2, blocking_query_ctx: Dictionary) -> float:
	if int(blocking_query_ctx.get("blocking_checks_budget", 0)) <= 0:
		return 0.0
	var blocked_votes: int = 0
	var checks_used: int = 0
	if not NpcPathService.has_line_clear(anchor_pos, target_pos, blocking_query_ctx):
		blocked_votes += 1
	checks_used += 1
	if int(blocking_query_ctx.get("blocking_checks_budget", 0)) > 0 and home_pos != Vector2.ZERO:
		if not NpcPathService.has_line_clear(home_pos, target_pos, blocking_query_ctx):
			blocked_votes += 1
		checks_used += 1
	if checks_used <= 0:
		return 0.0
	return float(blocked_votes) / float(checks_used)


func _get_placement_react_radius(item_id: String) -> float:
	if _wall_assault_global_mode and _is_wall_assault_placement_item(item_id):
		return maxf(_wall_assault_radius, _default_radius)
	var by_item: Variant = _radius_by_item_id.get(item_id, -1.0)
	var parsed: float = float(by_item)
	if parsed > 0.0:
		return parsed
	return _default_radius


func _is_wall_assault_placement_item(item_id: String) -> bool:
	return item_id == BuildableCatalog.resolve_runtime_item_id(BuildableCatalog.ID_WALLWOOD)


func _get_group_react_anchor(group_data: Dictionary) -> Dictionary:
	var leader_id: String = String(group_data.get("leader_id", ""))
	if leader_id != "":
		var leader_node: Node = _get_enemy_node(leader_id)
		if leader_node != null and leader_node is Node2D:
			return {"pos": (leader_node as Node2D).global_position, "kind": "leader"}
	var members: Array = group_data.get("member_ids", []) as Array
	if not members.is_empty():
		var sum: Vector2 = Vector2.ZERO
		var count: int = 0
		for raw_mid in members:
			var member_id: String = String(raw_mid)
			if member_id == "":
				continue
			var member_node: Node = _get_enemy_node(member_id)
			if member_node != null and member_node is Node2D:
				sum += (member_node as Node2D).global_position
				count += 1
		if count > 0:
			return {"pos": sum / float(count), "kind": "center"}
	var home_pos: Vector2 = group_data.get("home_world_pos", Vector2.ZERO) as Vector2
	if home_pos != Vector2.ZERO:
		return {"pos": home_pos, "kind": "home"}
	return {"pos": Vector2.ZERO, "kind": "none"}


func _is_group_hostile_for_structure_assault(group_data: Dictionary) -> bool:
	var faction_id: String = String(group_data.get("faction_id", ""))
	if faction_id == "":
		return false
	if _is_faction_baseline_hostile_to_player(faction_id):
		return true
	var profile: FactionBehaviorProfile = FactionHostilityManager.get_behavior_profile(faction_id)
	return profile.can_attack_punitively \
		or profile.can_probe_walls \
		or profile.can_damage_workbenches \
		or profile.can_damage_storage \
		or profile.can_damage_walls \
		or profile.can_raid_base


func _is_faction_baseline_hostile_to_player(faction_id: String) -> bool:
	var fid: String = faction_id.strip_edges().to_lower()
	if fid == "":
		return false
	var aliases: Array[String] = [fid]
	if fid.ends_with("s"):
		var singular: String = fid.substr(0, fid.length() - 1)
		if singular != "":
			aliases.append(singular)
	else:
		aliases.append(fid + "s")
	for raw_alias in aliases:
		var alias: String = String(raw_alias)
		var faction_data: Dictionary = FactionSystem.get_faction(alias)
		if faction_data.is_empty():
			continue
		if float(faction_data.get("hostility_to_player", 0.0)) > 0.0:
			return true
	return fid.find("bandit") >= 0 or fid.find("goblin") >= 0 or fid.find("raider") >= 0


func _tile_to_world(tile_pos: Vector2i) -> Vector2:
	if _tile_to_world_cb.is_valid():
		var world_pos: Variant = _tile_to_world_cb.call(tile_pos)
		if world_pos is Vector2:
			return world_pos as Vector2
	return Vector2.ZERO


func _nearest_workbench_world_pos(target_pos: Vector2, radius: float) -> Vector2:
	if _nearest_workbench_world_pos_cb.is_valid():
		var value: Variant = _nearest_workbench_world_pos_cb.call(target_pos, radius, {"enough_threshold": 1})
		if value is Vector2:
			return value as Vector2
	return Vector2.ZERO


func _get_drop_hotspots() -> Array[Dictionary]:
	if _drop_hotspots_provider_cb.is_valid():
		var value: Variant = _drop_hotspots_provider_cb.call()
		if value is Array:
			var out: Array[Dictionary] = []
			for entry in value as Array:
				if entry is Dictionary:
					out.append(entry as Dictionary)
			return out
	return []


func _get_enemy_node(enemy_id: String) -> Node:
	if _enemy_node_provider_cb.is_valid():
		var maybe_node: Variant = _enemy_node_provider_cb.call(enemy_id)
		if maybe_node is Node:
			return maybe_node as Node
	return null
