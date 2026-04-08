extends RefCounted
class_name ProjectionUpdateInputDto

static func placeables_change(item_id: String, tile_pos: Vector2i, source: String = "event") -> Dictionary:
	return {
		"kind": "placeables_changed",
		"item_id": item_id,
		"tile_pos": tile_pos,
		"source": source,
	}

static func normalize_placeables_change(inputs: Dictionary) -> Dictionary:
	if inputs.is_empty():
		return {}
	var tile_pos_raw: Variant = inputs.get("tile_pos", Vector2i(-1, -1))
	if not (tile_pos_raw is Vector2i):
		return {}
	return {
		"kind": String(inputs.get("kind", "placeables_changed")),
		"item_id": String(inputs.get("item_id", "")).strip_edges(),
		"tile_pos": tile_pos_raw as Vector2i,
		"source": String(inputs.get("source", "event")),
	}
