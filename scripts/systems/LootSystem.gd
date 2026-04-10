extends Node

const SCATTER_MODE_PROP_RADIAL_SHORT := "prop_radial_short"
const DROP_PRESSURE_NORMAL: StringName = &"normal"
const DROP_PRESSURE_HIGH: StringName = &"high"
const DROP_PRESSURE_CRITICAL: StringName = &"critical"
const CRITICAL_SOURCE_MERGE_RADIUS: float = 14.0
const CRITICAL_SOURCE_MERGE_WINDOW_SEC: float = 0.25
const DROP_AGGREGATION_WINDOW_MIN_SEC: float = 0.10
const DROP_AGGREGATION_WINDOW_MAX_SEC: float = 0.25
const DROP_AGGREGATION_WINDOW_DEFAULT_SEC: float = 0.16
const DROP_AGGREGATION_CELL_SIZE_PX: float = 24.0
const DROP_AGGREGATION_MERGE_RADIUS: float = 26.0
const BREAK_EVENT_STATE_TTL_MULT: float = 1.5
const DESTRUCTION_AGGREGATE_ITEM_IDS: Array[String] = [
	"wallwood",
	"doorwood",
	"floorwood",
	"woodfloor",
	"workbench",
	"chest",
	"table",
	"stool",
	"campfire",
]
const PROP_RADIAL_SHORT_PROFILE := {
	"scatter_min_distance": 12.0,
	"scatter_max_distance": 30.0,
	"scatter_min_duration": 0.18,
	"scatter_max_duration": 0.28,
	"scatter_min_arc_height": 8.0,
	"scatter_max_arc_height": 16.0,
	"scatter_spawn_jitter": 3.0,
}

var _drop_pressure_snapshot: Dictionary = {
	"level": String(DROP_PRESSURE_NORMAL),
	"item_drop_count": 0,
	"drop_pressure_stage": 0,
}
var max_drop_entities_per_break_event: int = 4
var _break_event_state: Dictionary = {} # event_key -> {spawned_entities, expires_at, cap}
var _drops_spawned_raw: int = 0
var _drops_spawned_compacted: int = 0

func set_drop_pressure_snapshot(snapshot: Dictionary) -> void:
	_drop_pressure_snapshot = snapshot.duplicate(true)


func get_drop_pressure_snapshot() -> Dictionary:
	return _drop_pressure_snapshot.duplicate(true)


func is_drop_pressure_high() -> bool:
	return String(_drop_pressure_snapshot.get("level", String(DROP_PRESSURE_NORMAL))) == String(DROP_PRESSURE_HIGH)


func is_drop_pressure_critical() -> bool:
	return String(_drop_pressure_snapshot.get("level", String(DROP_PRESSURE_NORMAL))) == String(DROP_PRESSURE_CRITICAL)


func spawn_drop(item: ItemData, item_id: String, amount: int, origin: Vector2, parent: Node, overrides: Dictionary = {}, source_uid: String = "") -> Node:
	var resolved_item_data: ItemData = item
	var resolved_id := item_id

	if resolved_item_data != null and resolved_item_data.id != "":
		resolved_id = resolved_item_data.id
	elif resolved_item_data == null and resolved_id != "":
		var item_db := get_node_or_null("/root/ItemDB")
		if item_db != null and item_db.has_method("get_item"):
			resolved_item_data = item_db.get_item(resolved_id)
			if resolved_item_data != null and resolved_item_data.id != "":
				resolved_id = resolved_item_data.id

	var scene: PackedScene = overrides.get("drop_scene", null)

	if scene == null:
		push_warning("[LootSystem] spawn_drop missing drop_scene for item_id=%s" % resolved_id)
		return null

	var target_parent := parent
	if target_parent == null:
		target_parent = get_tree().current_scene
	if target_parent == null:
		target_parent = get_tree().root
	var aggregation_overrides := overrides.duplicate(true)
	aggregation_overrides["item_id"] = resolved_id
	var resolved_source_uid: String = _resolve_effective_source_uid(resolved_id, origin, overrides, source_uid)
	_drops_spawned_raw += 1
	var merged_drop := _try_merge_spawn_aggregate(
		target_parent,
		resolved_id,
		amount,
		origin,
		aggregation_overrides,
		resolved_source_uid
	)
	if merged_drop != null:
		if GameEvents != null and GameEvents.has_method("emit_loot_spawned"):
			GameEvents.emit_loot_spawned(resolved_id, amount, origin, resolved_source_uid)
		return merged_drop

	var now_sec: float = float(Time.get_ticks_msec()) / 1000.0
	var break_event_key: String = _resolve_break_event_key(overrides, origin, now_sec)
	var break_event_cap: int = _resolve_break_event_cap(overrides)
	if break_event_key != "":
		if not _can_spawn_new_break_event_entity(break_event_key, break_event_cap, now_sec, _resolve_aggregation_window_sec(overrides)):
			var capped_merge := _try_merge_break_event_stack(
				target_parent,
				resolved_id,
				amount,
				origin,
				break_event_key,
				now_sec,
				_resolve_aggregation_window_sec(overrides)
			)
			if capped_merge != null:
				if GameEvents != null and GameEvents.has_method("emit_loot_spawned"):
					GameEvents.emit_loot_spawned(resolved_id, amount, origin, resolved_source_uid)
				return capped_merge

	var drop := scene.instantiate()
	if drop == null:
		push_warning("[LootSystem] failed to instantiate drop_scene for item_id=%s" % resolved_id)
		return null

	if drop is ItemDrop:
		var item_drop := drop as ItemDrop
		item_drop.item_data = resolved_item_data
		item_drop.item_id = resolved_id
		item_drop.amount = amount

		var icon_override: Texture2D = overrides.get("icon", null)
		if icon_override != null:
			item_drop.icon = icon_override
		elif resolved_item_data != null and resolved_item_data.icon != null:
			item_drop.icon = resolved_item_data.icon

		var pickup_sfx_override: AudioStream = overrides.get("pickup_sfx", null)
		if pickup_sfx_override != null:
			item_drop.pickup_sfx = pickup_sfx_override
		elif resolved_item_data != null and resolved_item_data.pickup_sfx != null:
			item_drop.pickup_sfx = resolved_item_data.pickup_sfx
		_apply_pressure_ttl_if_supported(item_drop)

	# Tags don't require the node to be in the scene tree.
	_tag_drop_aggregation_meta(drop, resolved_id, origin, aggregation_overrides, resolved_source_uid)
	_tag_break_event_meta(drop, break_event_key, now_sec)
	_drops_spawned_compacted += 1

	# Defer add_child + motion to avoid "can't change state while flushing queries"
	# when this is called from physics callbacks (e.g. Area2D.body_entered).
	var _tp := target_parent
	var _ov := overrides
	var _o := origin
	var _rid := resolved_id
	var _amt := amount
	var _suid := resolved_source_uid
	(func() -> void:
		if not is_instance_valid(drop):
			return
		_tp.add_child(drop)
		_apply_drop_spawn_motion(drop, _o, _ov)
		if GameEvents != null and GameEvents.has_method("emit_loot_spawned"):
			GameEvents.emit_loot_spawned(_rid, _amt, _o, _suid)
	).call_deferred()
	return drop


func _apply_drop_spawn_motion(drop: Node, origin: Vector2, overrides: Dictionary) -> void:
	if _try_apply_scatter_motion(drop, origin, overrides):
		return

	if drop.has_method("throw_from"):
		var angle := randf_range(0.0, TAU)
		var dir := Vector2(cos(angle), sin(angle))
		var speed := randf_range(25.0, 65.0)
		var up_boost := randf_range(55.0, 95.0)
		drop.call("throw_from", origin, dir, speed, up_boost)
	elif drop is Node2D:
		(drop as Node2D).global_position = origin


func _try_apply_scatter_motion(drop: Node, origin: Vector2, overrides: Dictionary) -> bool:
	var scatter_mode := String(overrides.get("scatter_mode", ""))
	if scatter_mode != SCATTER_MODE_PROP_RADIAL_SHORT:
		return false
	if not drop.has_method("scatter_from"):
		return false

	var profile := _resolve_scatter_profile(overrides)
	var spawn_jitter := maxf(0.0, float(profile["scatter_spawn_jitter"]))
	var scatter_origin := origin + Vector2(
		randf_range(-spawn_jitter, spawn_jitter),
		randf_range(-spawn_jitter, spawn_jitter)
	)

	var min_distance := maxf(0.0, float(profile["scatter_min_distance"]))
	var max_distance := maxf(min_distance, float(profile["scatter_max_distance"]))
	var distance := randf_range(min_distance, max_distance)
	var angle := randf_range(0.0, TAU)
	var target := scatter_origin + Vector2(cos(angle), sin(angle)) * distance

	var min_duration := maxf(0.01, float(profile["scatter_min_duration"]))
	var max_duration := maxf(min_duration, float(profile["scatter_max_duration"]))
	var duration := randf_range(min_duration, max_duration)

	var min_arc_height := maxf(0.0, float(profile["scatter_min_arc_height"]))
	var max_arc_height := maxf(min_arc_height, float(profile["scatter_max_arc_height"]))
	var arc_height := randf_range(min_arc_height, max_arc_height)

	drop.call("scatter_from", scatter_origin, target, duration, arc_height)
	return true


func _resolve_scatter_profile(overrides: Dictionary) -> Dictionary:
	var profile := PROP_RADIAL_SHORT_PROFILE.duplicate(true)
	for key in PROP_RADIAL_SHORT_PROFILE.keys():
		if overrides.has(key):
			profile[key] = overrides[key]
	return profile


func _apply_pressure_ttl_if_supported(item_drop: ItemDrop) -> void:
	if item_drop == null or not is_drop_pressure_high():
		return
	var snapshot := get_drop_pressure_snapshot()
	var ttl_sec: float = float(snapshot.get("high_orphan_ttl_sec", 0.0))
	if ttl_sec <= 0.0:
		return
	if item_drop.has_method("set_orphan_ttl"):
		item_drop.call("set_orphan_ttl", ttl_sec)
	elif item_drop.get("orphan_ttl_sec") != null:
		item_drop.set("orphan_ttl_sec", ttl_sec)
	elif item_drop.get("max_lifetime_sec") != null:
		item_drop.set("max_lifetime_sec", ttl_sec)


func _normalize_source_uid(source_uid: String) -> String:
	var uid := source_uid.strip_edges()
	if uid == "":
		return ""
	var regex := RegEx.new()
	var err: int = regex.compile("_\\d+$")
	if err != OK:
		return uid
	return regex.sub(uid, "", true)


func _try_merge_spawn_aggregate(parent: Node, item_id: String, amount: int, origin: Vector2, overrides: Dictionary, source_uid: String) -> ItemDrop:
	if parent == null or item_id.strip_edges() == "" or amount <= 0:
		return null
	if not _should_aggregate_spawn(overrides, source_uid):
		return null
	var now_sec: float = float(Time.get_ticks_msec()) / 1000.0
	var force_origin_merge: bool = is_drop_pressure_critical()
	var source_key := _build_aggregation_source_key(item_id, origin, source_uid)
	var window_sec := _resolve_aggregation_window_sec(overrides)
	var aggregate_key := _build_spawn_aggregation_key(item_id, origin, source_key, window_sec, force_origin_merge, now_sec)
	var merge_radius := CRITICAL_SOURCE_MERGE_RADIUS if force_origin_merge else DROP_AGGREGATION_MERGE_RADIUS
	return _find_and_merge_drop(parent, item_id, amount, origin, source_key, aggregate_key, now_sec, window_sec, merge_radius, force_origin_merge)


func _tag_drop_aggregation_meta(drop: Node, item_id: String, origin: Vector2, overrides: Dictionary, source_uid: String) -> void:
	var item_drop := drop as ItemDrop
	if item_drop == null:
		return
	var now_sec: float = float(Time.get_ticks_msec()) / 1000.0
	var force_origin_merge: bool = is_drop_pressure_critical()
	var source_key := _build_aggregation_source_key(item_id, origin, source_uid)
	var window_sec := _resolve_aggregation_window_sec(overrides)
	var aggregate_key := _build_spawn_aggregation_key(item_id, origin, source_key, window_sec, force_origin_merge, now_sec)
	item_drop.set_meta("source_spawn_key", source_key)
	item_drop.set_meta("source_spawn_t", now_sec)
	item_drop.set_meta("agg_spawn_key", aggregate_key)


func _find_and_merge_drop(
	parent: Node,
	item_id: String,
	amount: int,
	origin: Vector2,
	source_key: String,
	aggregate_key: String,
	now_sec: float,
	window_sec: float,
	merge_radius: float,
	force_origin_merge: bool
) -> ItemDrop:
	if parent == null or item_id.strip_edges() == "" or amount <= 0:
		return null
	var radius_sq: float = merge_radius * merge_radius
	for child in parent.get_children():
		var drop := child as ItemDrop
		if drop == null or not is_instance_valid(drop) or drop.is_queued_for_deletion():
			continue
		if String(drop.item_id) != item_id:
			continue
		if String(drop.get_meta("source_spawn_key", "")) != source_key:
			continue
		if not force_origin_merge and String(drop.get_meta("agg_spawn_key", "")) != aggregate_key:
			continue
		if drop.global_position.distance_squared_to(origin) > radius_sq:
			continue
		var created_at_sec: float = float(drop.get_meta("source_spawn_t", now_sec))
		var max_window := CRITICAL_SOURCE_MERGE_WINDOW_SEC if force_origin_merge else window_sec
		if absf(now_sec - created_at_sec) > max_window:
			continue
		drop.amount = maxi(0, int(drop.amount)) + amount
		drop.set_meta("source_spawn_t", now_sec)
		return drop
	return null


func _should_aggregate_spawn(overrides: Dictionary, source_uid: String) -> bool:
	if is_drop_pressure_critical():
		return true
	if bool(overrides.get("aggregate_spawn", false)):
		return true
	var normalized_uid := _normalize_source_uid(source_uid)
	if normalized_uid != "":
		return true
	var source_kind := String(overrides.get("source_kind", "")).strip_edges().to_lower()
	if source_kind == "destroy" or source_kind == "destruction":
		return true
	if bool(overrides.get("from_destruction", false)):
		return true
	var item_id := String(overrides.get("item_id", "")).strip_edges().to_lower()
	if item_id != "" and DESTRUCTION_AGGREGATE_ITEM_IDS.has(item_id):
		return true
	return false


func _should_force_stable_source_uid(item_id: String, overrides: Dictionary, source_uid: String) -> bool:
	if source_uid != "":
		return false
	if bool(overrides.get("aggregate_spawn", false)):
		return true
	if bool(overrides.get("from_destruction", false)):
		return true
	var source_kind := String(overrides.get("source_kind", "")).strip_edges().to_lower()
	if source_kind == "destroy" or source_kind == "destruction":
		return true
	var lowered_item := item_id.strip_edges().to_lower()
	if lowered_item != "" and DESTRUCTION_AGGREGATE_ITEM_IDS.has(lowered_item):
		return true
	return false


func _resolve_effective_source_uid(item_id: String, origin: Vector2, overrides: Dictionary, source_uid: String) -> String:
	var normalized_uid := _normalize_source_uid(source_uid)
	if normalized_uid != "":
		return normalized_uid
	if not _should_force_stable_source_uid(item_id, overrides, normalized_uid):
		return ""
	var cell := _quantize_drop_origin(origin)
	return "placeable_%s_%d_%d" % [item_id.strip_edges().to_lower(), cell.x, cell.y]


func _resolve_aggregation_window_sec(overrides: Dictionary) -> float:
	var requested := float(overrides.get("aggregate_window_sec", DROP_AGGREGATION_WINDOW_DEFAULT_SEC))
	return clampf(requested, DROP_AGGREGATION_WINDOW_MIN_SEC, DROP_AGGREGATION_WINDOW_MAX_SEC)


func _build_aggregation_source_key(item_id: String, origin: Vector2, source_uid: String) -> String:
	var source_key: String = _normalize_source_uid(source_uid)
	if source_key != "":
		return source_key
	var cell := _quantize_drop_origin(origin)
	return "%s@%d,%d" % [item_id, cell.x, cell.y]


func _build_spawn_aggregation_key(
	item_id: String,
	origin: Vector2,
	source_key: String,
	window_sec: float,
	force_origin_merge: bool,
	now_sec: float
) -> String:
	var cell := _quantize_drop_origin(origin)
	var bucket: int = -1 if force_origin_merge else int(floor(now_sec / maxf(0.001, window_sec)))
	return "%s|%d,%d|%d|%s" % [item_id, cell.x, cell.y, bucket, source_key]


func _quantize_drop_origin(origin: Vector2) -> Vector2i:
	var cell_size := maxf(1.0, DROP_AGGREGATION_CELL_SIZE_PX)
	return Vector2i(
		int(floor(origin.x / cell_size)),
		int(floor(origin.y / cell_size))
	)


func _resolve_break_event_cap(overrides: Dictionary) -> int:
	var override_cap: int = int(overrides.get("max_drop_entities_per_break_event", max_drop_entities_per_break_event))
	return maxi(1, override_cap)


func _resolve_break_event_key(overrides: Dictionary, origin: Vector2, now_sec: float) -> String:
	var explicit_key := String(overrides.get("break_event_key", "")).strip_edges()
	if explicit_key != "":
		return explicit_key
	var from_break_event: bool = bool(overrides.get("from_break_event", false))
	var kind: String = String(overrides.get("break_event_kind", "")).strip_edges().to_lower()
	if not from_break_event and kind == "":
		return ""
	if kind == "":
		kind = "break"
	var cell: Vector2i = _quantize_drop_origin(origin)
	var window_sec := _resolve_aggregation_window_sec(overrides)
	var batch_bucket: int = int(floor(now_sec / maxf(0.01, window_sec)))
	return "%s|%d,%d|%d" % [kind, cell.x, cell.y, batch_bucket]


func _can_spawn_new_break_event_entity(event_key: String, cap: int, now_sec: float, window_sec: float) -> bool:
	_prune_break_event_state(now_sec)
	var state: Dictionary = _break_event_state.get(event_key, {}) as Dictionary
	var spawned_entities: int = int(state.get("spawned_entities", 0))
	if spawned_entities >= cap:
		return false
	state["spawned_entities"] = spawned_entities + 1
	state["cap"] = cap
	state["expires_at"] = now_sec + maxf(0.08, window_sec * BREAK_EVENT_STATE_TTL_MULT)
	_break_event_state[event_key] = state
	return true


func _try_merge_break_event_stack(
	parent: Node,
	item_id: String,
	amount: int,
	origin: Vector2,
	break_event_key: String,
	now_sec: float,
	window_sec: float
) -> ItemDrop:
	if parent == null or item_id == "" or amount <= 0 or break_event_key == "":
		return null
	var merge_radius: float = DROP_AGGREGATION_MERGE_RADIUS
	var radius_sq: float = merge_radius * merge_radius
	for child in parent.get_children():
		var drop := child as ItemDrop
		if drop == null or not is_instance_valid(drop) or drop.is_queued_for_deletion():
			continue
		if String(drop.item_id) != item_id:
			continue
		if String(drop.get_meta("break_event_key", "")) != break_event_key:
			continue
		if drop.global_position.distance_squared_to(origin) > radius_sq:
			continue
		var tagged_at: float = float(drop.get_meta("break_event_t", now_sec))
		if absf(now_sec - tagged_at) > maxf(0.10, window_sec * BREAK_EVENT_STATE_TTL_MULT):
			continue
		drop.amount = maxi(0, int(drop.amount)) + amount
		drop.set_meta("break_event_t", now_sec)
		return drop
	return null


func _tag_break_event_meta(drop: Node, break_event_key: String, now_sec: float) -> void:
	var item_drop := drop as ItemDrop
	if item_drop == null or break_event_key == "":
		return
	item_drop.set_meta("break_event_key", break_event_key)
	item_drop.set_meta("break_event_t", now_sec)


func _prune_break_event_state(now_sec: float) -> void:
	if _break_event_state.is_empty():
		return
	for key in _break_event_state.keys():
		var state: Dictionary = _break_event_state.get(key, {}) as Dictionary
		if now_sec > float(state.get("expires_at", 0.0)):
			_break_event_state.erase(key)


func get_drop_spawn_metrics() -> Dictionary:
	var ratio: float = 1.0
	if _drops_spawned_raw > 0:
		ratio = float(_drops_spawned_compacted) / float(_drops_spawned_raw)
	return {
		"drops_spawned_raw": _drops_spawned_raw,
		"drops_spawned_compacted": _drops_spawned_compacted,
		"drop_compaction_ratio": snappedf(ratio, 0.0001),
	}
