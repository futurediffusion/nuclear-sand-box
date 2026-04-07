extends RefCounted
class_name BuildingThreatEventAdapter

## Bridges runtime placement/building facts into ThreatAssessmentSystem.
## This adapter only ingests events + returns assessments (no intent dispatch).

const BuildingEventsScript := preload("res://scripts/domain/building/BuildingEvents.gd")

var _threat_assessment_system: ThreatAssessmentSystem
var _tile_to_world_cb: Callable
var _assessment_sink_cb: Callable

func setup(ctx: Dictionary) -> void:
	_threat_assessment_system = ctx.get("threat_assessment_system")
	_tile_to_world_cb = ctx.get("tile_to_world", Callable())
	_assessment_sink_cb = ctx.get("assessment_sink", Callable())

func ingest_placement_completed(item_id: String, tile_pos: Vector2i, metadata: Dictionary = {}) -> void:
	var normalized_item_id: String = item_id.strip_edges()
	var world_pos: Vector2 = _tile_to_world(tile_pos)
	var assessment: Dictionary = _assess({
		"type": ThreatAssessmentSystem.EVENT_TYPE_PLACEMENT_COMPLETED,
		"item_id": normalized_item_id,
		"tile_pos": tile_pos,
		"world_pos": world_pos,
		"metadata": metadata.duplicate(true),
	})
	_publish_assessment(assessment)

func ingest_building_events(events: Array[Dictionary]) -> void:
	for raw_event in events:
		if raw_event.is_empty():
			continue
		var mapped_event: Dictionary = _map_building_event_to_threat_event(raw_event)
		if mapped_event.is_empty():
			continue
		var assessment: Dictionary = _assess(mapped_event)
		_publish_assessment(assessment)

func _assess(event_data: Dictionary) -> Dictionary:
	if _threat_assessment_system == null:
		return {}
	return _threat_assessment_system.assess_building_event(event_data, {})

func _publish_assessment(assessment: Dictionary) -> void:
	if assessment.is_empty():
		return
	if _assessment_sink_cb.is_valid():
		_assessment_sink_cb.call(assessment)

func _map_building_event_to_threat_event(event_data: Dictionary) -> Dictionary:
	var source_type: String = String(event_data.get("type", "")).strip_edges()
	if source_type.is_empty():
		return {}
	var tile_pos_variant: Variant = event_data.get("tile_pos", Vector2i.ZERO)
	var tile_pos: Vector2i = tile_pos_variant if tile_pos_variant is Vector2i else Vector2i.ZERO
	var metadata: Dictionary = event_data.duplicate(true)
	var item_id: String = _resolve_item_id_for_building_event(event_data)
	var mapped_type: String = ""
	match source_type:
		BuildingEventsScript.TYPE_STRUCTURE_PLACED:
			mapped_type = ThreatAssessmentSystem.EVENT_TYPE_STRUCTURE_PLACED
		BuildingEventsScript.TYPE_STRUCTURE_DAMAGED:
			mapped_type = ThreatAssessmentSystem.EVENT_TYPE_STRUCTURE_DAMAGED
		BuildingEventsScript.TYPE_STRUCTURE_REMOVED:
			mapped_type = ThreatAssessmentSystem.EVENT_TYPE_STRUCTURE_REMOVED
		_:
			return {}
	return {
		"type": mapped_type,
		"item_id": item_id,
		"tile_pos": tile_pos,
		"world_pos": _tile_to_world(tile_pos),
		"metadata": metadata,
	}

func _resolve_item_id_for_building_event(event_data: Dictionary) -> String:
	var structure: Dictionary = event_data.get("structure", {}) as Dictionary
	if not structure.is_empty():
		var metadata: Dictionary = structure.get("metadata", {}) as Dictionary
		var explicit_item_id: String = String(metadata.get("item_id", "")).strip_edges()
		if not explicit_item_id.is_empty():
			return explicit_item_id
		var kind: String = String(structure.get("kind", "")).strip_edges()
		if kind == "player_wall":
			return BuildableCatalog.resolve_runtime_item_id(BuildableCatalog.ID_WALLWOOD)
		return kind
	return ""

func _tile_to_world(tile_pos: Vector2i) -> Vector2:
	if _tile_to_world_cb.is_valid():
		var world_pos: Variant = _tile_to_world_cb.call(tile_pos)
		if world_pos is Vector2:
			return world_pos as Vector2
	return Vector2.ZERO
