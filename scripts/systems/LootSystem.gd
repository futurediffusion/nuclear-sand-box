extends Node

@export var debug_loot_logs: bool = false
@export var metrics_logs_enabled: bool = true
@export var metrics_log_interval_sec: float = 1.0

var _metric_timer: float = 0.0
var _drops_spawned_window: int = 0
var _pickups_window: int = 0
var _camps_spawned_by_chunk: Dictionary = {}

func _ready() -> void:
	set_process(metrics_logs_enabled)

func _process(delta: float) -> void:
	if not metrics_logs_enabled:
		return
	_metric_timer += delta
	if _metric_timer < maxf(0.1, metrics_log_interval_sec):
		return
	_metric_timer = 0.0
	_flush_metrics()

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

	var drop := scene.instantiate()
	if drop == null:
		push_warning("[LootSystem] failed to instantiate drop_scene for item_id=%s" % resolved_id)
		return null

	target_parent.add_child(drop)

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

	if drop.has_method("throw_from"):
		var angle := randf_range(-PI * 0.15, PI + PI * 0.15)
		var dir := Vector2(cos(angle), sin(angle))
		var speed := randf_range(160.0, 220.0)
		var up_boost := randf_range(240.0, 320.0)
		drop.throw_from(origin, dir, speed, up_boost)
	else:
		drop.global_position = origin

	_drops_spawned_window += 1
	_loot_log("[LootSystem] spawned drop item_id=%s amount=%d" % [resolved_id, amount])

	if GameEvents != null and GameEvents.has_method("emit_loot_spawned"):
		GameEvents.emit_loot_spawned(resolved_id, amount, origin, source_uid)
	return drop

func record_pickup() -> void:
	_pickups_window += 1

func record_camps_spawned(chunk_pos: Vector2i, camps_spawned: int) -> void:
	if camps_spawned <= 0:
		return
	var key := "%d,%d" % [chunk_pos.x, chunk_pos.y]
	_camps_spawned_by_chunk[key] = int(_camps_spawned_by_chunk.get(key, 0)) + camps_spawned

func _flush_metrics() -> void:
	if _drops_spawned_window <= 0 and _pickups_window <= 0 and _camps_spawned_by_chunk.is_empty():
		return

	var camps_summary := "{}"
	if not _camps_spawned_by_chunk.is_empty():
		var keys := _camps_spawned_by_chunk.keys()
		keys.sort()
		var parts: Array[String] = []
		for key in keys:
			parts.append("%s=%d" % [str(key), int(_camps_spawned_by_chunk[key])])
		camps_summary = "{%s}" % ", ".join(parts)

	print("[LootMetrics] drops_per_sec=%d pickups_per_sec=%d camps_per_chunk=%s" % [
		_drops_spawned_window,
		_pickups_window,
		camps_summary,
	])

	_drops_spawned_window = 0
	_pickups_window = 0
	_camps_spawned_by_chunk.clear()

func _loot_log(message: String) -> void:
	if not debug_loot_logs:
		return
	print(message)
