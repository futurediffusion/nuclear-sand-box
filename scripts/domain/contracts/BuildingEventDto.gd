extends RefCounted
class_name BuildingEventDto

const EVENT_TYPE_STRUCTURE_PLACED := "structure_placed"
const EVENT_TYPE_STRUCTURE_DAMAGED := "structure_damaged"
const EVENT_TYPE_STRUCTURE_REMOVED := "structure_removed"
const EVENT_TYPE_PLACEMENT_COMPLETED := "placement_completed"

const KEY_EVENT_TYPE := "event_type"
const KEY_ITEM_ID := "item_id"
const KEY_TILE_POS := "tile_pos"
const KEY_TARGET_POSITION := "target_position"
const KEY_METADATA := "metadata"

static func structure_placed(structure: Dictionary) -> Dictionary:
	return {
		"type": EVENT_TYPE_STRUCTURE_PLACED,
		"structure": structure.duplicate(true),
	}

static func structure_damaged(structure_id: String, tile_pos: Vector2i,
		damage_amount: int, remaining_hp: int, was_destroyed: bool) -> Dictionary:
	return {
		"type": EVENT_TYPE_STRUCTURE_DAMAGED,
		"structure_id": structure_id,
		"tile_pos": tile_pos,
		"damage_amount": maxi(0, damage_amount),
		"remaining_hp": maxi(0, remaining_hp),
		"was_destroyed": was_destroyed,
	}

static func structure_removed(structure_id: String, tile_pos: Vector2i, reason: String = "") -> Dictionary:
	return {
		"type": EVENT_TYPE_STRUCTURE_REMOVED,
		"structure_id": structure_id,
		"tile_pos": tile_pos,
		"reason": reason,
	}

static func placement_completed(item_id: String, tile_pos: Vector2i, target_position: Vector2,
		source: String = "placement_system", metadata: Dictionary = {}) -> Dictionary:
	var event_metadata: Dictionary = metadata.duplicate(true)
	event_metadata["source"] = source
	return {
		"type": EVENT_TYPE_PLACEMENT_COMPLETED,
		"event_type": EVENT_TYPE_PLACEMENT_COMPLETED,
		"item_id": item_id,
		"tile_pos": tile_pos,
		"world_pos": target_position,
		"target_position": target_position,
		"metadata": event_metadata,
	}

static func normalize_for_threat_assessment(event_data: Dictionary, tile_to_world_cb: Callable = Callable()) -> Dictionary:
	if event_data.is_empty():
		return {}
	var source_type: String = String(event_data.get("type", event_data.get("event_type", ""))).strip_edges()
	if source_type.is_empty():
		return {}
	var mapped_event_type: String = _map_event_type(source_type)
	if mapped_event_type.is_empty():
		return {}
	var tile_pos_variant: Variant = event_data.get("tile_pos", Vector2i.ZERO)
	var tile_pos: Vector2i = tile_pos_variant if tile_pos_variant is Vector2i else Vector2i.ZERO
	var target_variant: Variant = event_data.get("world_pos", event_data.get("target_position", Vector2.ZERO))
	var target_pos: Vector2 = target_variant if target_variant is Vector2 else Vector2.ZERO
	if target_pos == Vector2.ZERO and tile_to_world_cb.is_valid():
		var converted: Variant = tile_to_world_cb.call(tile_pos)
		if converted is Vector2:
			target_pos = converted as Vector2
	if not target_pos.is_finite():
		return {}
	var metadata: Dictionary = _build_metadata_copy(event_data)
	return {
		KEY_EVENT_TYPE: mapped_event_type,
		KEY_ITEM_ID: resolve_item_id(event_data),
		KEY_TILE_POS: tile_pos,
		KEY_TARGET_POSITION: target_pos,
		KEY_METADATA: metadata,
	}

static func resolve_item_id(event_data: Dictionary) -> String:
	var explicit_item_id: String = String(event_data.get("item_id", "")).strip_edges()
	if not explicit_item_id.is_empty():
		return explicit_item_id
	var structure: Dictionary = event_data.get("structure", {}) as Dictionary
	if structure.is_empty():
		return ""
	var metadata: Dictionary = structure.get("metadata", {}) as Dictionary
	explicit_item_id = String(metadata.get("item_id", "")).strip_edges()
	if not explicit_item_id.is_empty():
		return explicit_item_id
	var kind: String = String(structure.get("kind", "")).strip_edges()
	if kind == "player_wall":
		return BuildableCatalog.resolve_runtime_item_id(BuildableCatalog.ID_WALLWOOD)
	return kind

static func _map_event_type(source_type: String) -> String:
	match source_type:
		EVENT_TYPE_PLACEMENT_COMPLETED:
			return EVENT_TYPE_PLACEMENT_COMPLETED
		EVENT_TYPE_STRUCTURE_PLACED:
			return EVENT_TYPE_STRUCTURE_PLACED
		EVENT_TYPE_STRUCTURE_DAMAGED:
			return EVENT_TYPE_STRUCTURE_DAMAGED
		EVENT_TYPE_STRUCTURE_REMOVED:
			return EVENT_TYPE_STRUCTURE_REMOVED
		_:
			return ""

static func _build_metadata_copy(event_data: Dictionary) -> Dictionary:
	var metadata: Dictionary = event_data.get("metadata", {}) as Dictionary
	if metadata.is_empty():
		metadata = event_data.duplicate(true)
	if metadata.has("structure"):
		metadata.erase("structure")
	return metadata
