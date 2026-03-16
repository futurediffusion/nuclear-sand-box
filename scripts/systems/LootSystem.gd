extends Node

const SCATTER_MODE_PROP_RADIAL_SHORT := "prop_radial_short"
const PROP_RADIAL_SHORT_PROFILE := {
	"scatter_min_distance": 12.0,
	"scatter_max_distance": 30.0,
	"scatter_min_duration": 0.18,
	"scatter_max_duration": 0.28,
	"scatter_min_arc_height": 8.0,
	"scatter_max_arc_height": 16.0,
	"scatter_spawn_jitter": 3.0,
}

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

	target_parent.add_child(drop)
	_apply_drop_spawn_motion(drop, origin, overrides)

	print("[LootSystem] spawned drop item_id=", resolved_id, " amount=", amount)
	if GameEvents != null and GameEvents.has_method("emit_loot_spawned"):
		GameEvents.emit_loot_spawned(resolved_id, amount, origin, source_uid)
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
