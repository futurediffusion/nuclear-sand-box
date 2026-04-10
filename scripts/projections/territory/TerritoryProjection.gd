extends RefCounted
class_name TerritoryProjection

# TerritoryProjection
# Explicit read-model projection for player territory queries.
#
# Source-of-truth inputs (canonical owners):
#  1) Canonical workbench anchors from persistence-derived snapshots
#     - e.g. WorldSpatialIndex placeables projection / WorldSave placeable entries
#  2) Detected enclosed bases from SettlementIntel scan snapshots
#     - e.g. SettlementIntel.get_detected_bases_near(...)
#
# This projection is intentionally rebuildable from those inputs and does not own
# gameplay/domain state. It only derives query-friendly territory zones.

const WORKBENCH_RADIUS: float = 96.0
const WALL_TERRITORY_EXPANSION: int = 4
const TILE_SIZE: float = 32.0

# Each zone dictionary shape:
#   workbench: {"type":"workbench", "center":Vector2, "radius":float}
#   enclosed:  {"type":"enclosed", "center":Vector2, "rect_world":Rect2, "id":String}
var _zones: Array[Dictionary] = []
var _rebuild_calls: int = 0
var _last_input_workbench_count: int = 0
var _last_input_base_count: int = 0
var _legacy_runtime_anchor_reads: int = 0
var _legacy_runtime_api_attempts: int = 0


# Canonical rebuild entrypoint: derive from explicit source snapshots.
func rebuild_from_sources(sources: Dictionary) -> void:
	apply_inputs(sources)

func apply_inputs(inputs: Dictionary) -> void:
	if inputs.has("workbench_nodes"):
		_reject_legacy_runtime_entrypoint("apply_inputs(workbench_nodes)")
	var workbench_anchors: Array = inputs.get("workbench_anchors", []) as Array
	var detected_bases: Array = inputs.get("detected_bases", []) as Array
	_rebuild_from_canonical_inputs(workbench_anchors, detected_bases)

# Deprecated legacy runtime API.
# Runtime-node rebuilds are intentionally removed to prevent scene nodes from
# becoming implicit source-of-truth again.
func rebuild_from_runtime(_workbench_nodes: Array, _detected_bases: Array) -> void:
	_reject_legacy_runtime_entrypoint("rebuild_from_runtime(...)")


# Deprecated legacy API kept only for explicit migration feedback.
func rebuild(_workbench_nodes: Array, _detected_bases: Array) -> void:
	_reject_legacy_runtime_entrypoint("rebuild(...)")


func _rebuild_from_canonical_inputs(workbench_anchors: Array, detected_bases: Array) -> void:
	_rebuild_calls += 1
	_last_input_workbench_count = workbench_anchors.size()
	_last_input_base_count = detected_bases.size()
	_zones.clear()

	for wb in workbench_anchors:
		var center: Vector2 = _resolve_workbench_anchor_world_pos(wb)
		if center == Vector2.INF:
			continue
		_zones.append({
			"type": "workbench",
			"center": center,
			"radius": WORKBENCH_RADIUS,
		})

	for base in detected_bases:
		var bounds: Rect2i = base.get("bounds", Rect2i()) as Rect2i
		if bounds.size == Vector2i.ZERO:
			continue
		var center: Vector2 = base.get("center_world_pos", Vector2.ZERO) as Vector2
		var expansion: int = WALL_TERRITORY_EXPANSION
		var expanded: Rect2i = Rect2i(
			bounds.position.x - expansion,
			bounds.position.y - expansion,
			bounds.size.x + expansion * 2,
			bounds.size.y + expansion * 2,
		)
		var world_rect: Rect2 = Rect2(
			float(expanded.position.x) * TILE_SIZE,
			float(expanded.position.y) * TILE_SIZE,
			float(expanded.size.x) * TILE_SIZE,
			float(expanded.size.y) * TILE_SIZE,
		)
		_zones.append({
			"type": "enclosed",
			"center": center,
			"rect_world": world_rect,
			"id": String(base.get("id", "")),
		})

	Debug.log("territory", "[TerritoryProjection] rebuilt — workbench_zones=%d enclosed_zones=%d" % [
		_count_by_type("workbench"), _count_by_type("enclosed")])

func _resolve_workbench_anchor_world_pos(anchor: Variant) -> Vector2:
	var n2d: Node2D = anchor as Node2D
	if n2d != null and is_instance_valid(n2d):
		_legacy_runtime_anchor_reads += 1
		_reject_legacy_runtime_entrypoint("workbench_anchors(Node2D)")
		return Vector2.INF
	if anchor is Dictionary:
		var entry: Dictionary = anchor as Dictionary
		if entry.has("world_pos"):
			return entry.get("world_pos", Vector2.INF) as Vector2
		if entry.has("tile_pos_x") and entry.has("tile_pos_y"):
			return Vector2(
				float(int(entry.get("tile_pos_x", 0))) * TILE_SIZE,
				float(int(entry.get("tile_pos_y", 0))) * TILE_SIZE
			)
	return Vector2.INF


func _reject_legacy_runtime_entrypoint(entrypoint: String) -> void:
	_legacy_runtime_api_attempts += 1
	push_error("[TerritoryProjection] Legacy runtime territory input is no longer supported: %s. Use canonical `workbench_anchors` snapshots + `detected_bases` snapshots via rebuild_from_sources/apply_inputs." % entrypoint)
	assert(false, "[TerritoryProjection] Legacy runtime territory input is no longer supported: %s" % entrypoint)


func is_in_player_territory(world_pos: Vector2) -> bool:
	for zone in _zones:
		if _pos_in_zone(world_pos, zone):
			return true
	return false


func get_zones() -> Array[Dictionary]:
	return _zones.duplicate()


func zone_count() -> int:
	return _zones.size()


func has_workbench_anchor() -> bool:
	for zone in _zones:
		if String(zone.get("type", "")) == "workbench":
			return true
	return false


func has_enclosed_base() -> bool:
	for zone in _zones:
		if String(zone.get("type", "")) == "enclosed":
			return true
	return false


func _pos_in_zone(world_pos: Vector2, zone: Dictionary) -> bool:
	match String(zone.get("type", "")):
		"workbench":
			var center: Vector2 = zone.get("center", Vector2.ZERO) as Vector2
			var radius: float = float(zone.get("radius", 0.0))
			return world_pos.distance_squared_to(center) <= radius * radius
		"enclosed":
			var rect: Rect2 = zone.get("rect_world", Rect2()) as Rect2
			return rect.has_point(world_pos)
	return false


func _count_by_type(zone_type: String) -> int:
	var n: int = 0
	for zone in _zones:
		if String(zone.get("type", "")) == zone_type:
			n += 1
	return n

func get_debug_snapshot() -> Dictionary:
	return {
		"rebuild_calls": _rebuild_calls,
		"last_input_workbench_count": _last_input_workbench_count,
		"last_input_base_count": _last_input_base_count,
		"legacy_runtime_anchor_reads": _legacy_runtime_anchor_reads,
		"legacy_runtime_api_attempts": _legacy_runtime_api_attempts,
		"workbench_zone_count": _count_by_type("workbench"),
		"enclosed_zone_count": _count_by_type("enclosed"),
		"zone_count": _zones.size(),
	}
