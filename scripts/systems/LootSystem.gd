extends Node

func spawn_drop(item: ItemData, item_id: String, amount: int, origin: Vector2, parent: Node, overrides: Dictionary = {}) -> Node:
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

	print("[LootSystem] spawned drop item_id=", resolved_id, " amount=", amount)
	return drop
