extends RefCounted
class_name TerritoryProjection

# TerritoryProjection
# Explicit read-model projection for player territory queries.
#
# Source-of-truth inputs (canonical owners):
#  1) Runtime workbench anchors from scene/runtime index snapshots
#     - e.g. WorldSpatialIndex KIND_WORKBENCH or SceneTree group "workbench"
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


# Canonical rebuild entrypoint: derive from explicit source snapshots.
func rebuild_from_sources(sources: Dictionary) -> void:
	apply_inputs(sources)

func apply_inputs(inputs: Dictionary) -> void:
	var workbench_nodes: Array = inputs.get("workbench_nodes", []) as Array
	var detected_bases: Array = inputs.get("detected_bases", []) as Array
	rebuild(workbench_nodes, detected_bases)

# Compatibility API.
func rebuild_from_runtime(workbench_nodes: Array, detected_bases: Array) -> void:
	rebuild(workbench_nodes, detected_bases)


# Compatibility rebuild API used by existing territory consumers.
func rebuild(workbench_nodes: Array, detected_bases: Array) -> void:
	_zones.clear()

	for wb in workbench_nodes:
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
		var exp: int = WALL_TERRITORY_EXPANSION
		var expanded: Rect2i = Rect2i(
			bounds.position.x - exp,
			bounds.position.y - exp,
			bounds.size.x + exp * 2,
			bounds.size.y + exp * 2,
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
		return n2d.global_position
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
