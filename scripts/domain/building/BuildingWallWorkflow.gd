extends RefCounted
class_name BuildingWallWorkflow

signal building_events_emitted(events: Array[Dictionary])

const BuildingStateScript := preload("res://scripts/domain/building/BuildingState.gd")
const BuildingSystemScript := preload("res://scripts/domain/building/BuildingSystem.gd")
const BuildingCommandsScript := preload("res://scripts/domain/building/BuildingCommands.gd")
const BuildingEventsScript := preload("res://scripts/domain/building/BuildingEvents.gd")
const WorldSaveBuildingRepositoryScript := preload("res://scripts/persistence/save/WorldSaveBuildingRepository.gd")
const WorldSaveAdapterScript := preload("res://scripts/persistence/save/WorldSaveAdapter.gd")

var building_system: BuildingSystem
var building_repository: BuildingRepository
var building_tilemap_projection: BuildingTilemapProjection
var wall_collider_projection: WallColliderProjection

var player_wallwood_max_hp: int = 3
var player_wall_drop_enabled: bool = true
var player_wall_drop_item_id: String = "wallwood"
var player_wall_drop_amount: int = 1

func setup(ctx: Dictionary) -> void:
	building_repository = ctx.get("building_repository")
	if building_repository == null:
		building_repository = WorldSaveBuildingRepositoryScript.new()
	building_system = ctx.get("building_system")
	if building_system == null:
		building_system = BuildingSystemScript.new()
	building_tilemap_projection = ctx.get("building_tilemap_projection")
	wall_collider_projection = ctx.get("wall_collider_projection")
	player_wallwood_max_hp = maxi(1, int(ctx.get("player_wallwood_max_hp", player_wallwood_max_hp)))
	player_wall_drop_enabled = bool(ctx.get("player_wall_drop_enabled", player_wall_drop_enabled))
	player_wall_drop_item_id = String(ctx.get("player_wall_drop_item_id", player_wall_drop_item_id)).strip_edges()
	player_wall_drop_amount = maxi(0, int(ctx.get("player_wall_drop_amount", player_wall_drop_amount)))
	_bootstrap_state_from_repository()

func has_player_wall_at_tile(tile_pos: Vector2i) -> bool:
	return not get_player_wall_structure_at_tile(tile_pos).is_empty()

func get_player_wall_structure_at_tile(tile_pos: Vector2i) -> Dictionary:
	if building_system == null:
		return {}
	var structure := BuildingStateScript.get_structure_at_tile(building_system.get_state(), tile_pos)
	if _is_player_wall_structure(structure):
		return structure
	return {}

func place_player_wall(tile_pos: Vector2i, chunk_pos: Vector2i, hp_override: int = -1) -> Dictionary:
	var configured_max_hp: int = maxi(1, player_wallwood_max_hp)
	var final_hp := hp_override if hp_override > 0 else configured_max_hp
	final_hp = clampi(final_hp, 1, configured_max_hp)
	var place_cmd: Dictionary = BuildingCommandsScript.place_structure(
		"",
		tile_pos,
		configured_max_hp,
		BuildingStateScript.create_player_wall_metadata(player_wall_drop_enabled, player_wall_drop_item_id, player_wall_drop_amount)
	)
	place_cmd["kind"] = "player_wall"
	place_cmd["hp"] = final_hp
	place_cmd["chunk_pos"] = chunk_pos
	return process_command(place_cmd)

func damage_player_wall(tile_pos: Vector2i, amount: int) -> Dictionary:
	return process_command(BuildingCommandsScript.damage_structure(tile_pos, maxi(1, amount)))

func remove_player_wall(tile_pos: Vector2i, drop_item: bool = true) -> Dictionary:
	return process_command(BuildingCommandsScript.remove_structure(tile_pos, "removed", drop_item))

func apply_saved_walls_for_chunk(chunk_pos: Vector2i) -> Array[Dictionary]:
	var entries: Array[Dictionary] = _load_canonical_structures_for_chunk(chunk_pos)
	if entries.is_empty() and building_repository != null:
		entries = building_repository.load_structures_in_chunk(chunk_pos)
	if entries.is_empty():
		return []
	_refresh_building_state_for_chunk(chunk_pos, entries)
	if building_tilemap_projection != null:
		building_tilemap_projection.apply_snapshot(entries)
	if wall_collider_projection != null:
		wall_collider_projection.apply_snapshot(entries)
	return entries

func process_command(command: Dictionary) -> Dictionary:
	if building_system == null:
		return {}
	var result: Dictionary = building_system.process(command)
	if not bool(result.get(BuildingSystem.RESULT_KEY_SUCCESS, false)):
		return result
	if building_repository != null:
		for change_raw in result.get(BuildingSystem.RESULT_KEY_CHANGED_STRUCTURES, []):
			if typeof(change_raw) != TYPE_DICTIONARY:
				continue
			var change: Dictionary = change_raw as Dictionary
			var action: String = String(change.get(BuildingSystem.CHANGE_KEY_ACTION, "")).strip_edges()
			var before: Dictionary = change.get(BuildingSystem.CHANGE_KEY_BEFORE, {}) as Dictionary
			var after: Dictionary = change.get(BuildingSystem.CHANGE_KEY_AFTER, {}) as Dictionary
			if action == BuildingSystem.ACTION_REMOVED:
				var tile_raw: Variant = before.get(BuildingStateScript.STRUCTURE_KEY_TILE_POS, Vector2i.ZERO)
				var chunk_raw: Variant = before.get(BuildingStateScript.STRUCTURE_KEY_CHUNK_POS, Vector2i.ZERO)
				if tile_raw is Vector2i and chunk_raw is Vector2i:
					building_repository.remove_structure(chunk_raw as Vector2i, tile_raw as Vector2i)
				continue
			var normalized_after: Dictionary = _normalize_player_wall_structure(after)
			if normalized_after.is_empty():
				continue
			building_repository.save_structure(normalized_after)
	var events: Array[Dictionary] = result.get(BuildingSystem.RESULT_KEY_EVENTS, [])
	if not events.is_empty():
		if building_tilemap_projection != null:
			building_tilemap_projection.apply_events(events)
		if wall_collider_projection != null:
			wall_collider_projection.apply_events(events)
		emit_signal("building_events_emitted", events.duplicate(true))
	return result

func list_player_wall_structures() -> Array[Dictionary]:
	if building_system == null:
		return []
	var out: Array[Dictionary] = []
	for raw in BuildingStateScript.get_structures_by_id(building_system.get_state()).values():
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var structure: Dictionary = raw as Dictionary
		if _is_player_wall_structure(structure):
			out.append(structure)
	return out

func _bootstrap_state_from_repository() -> void:
	if building_system == null:
		return
	if building_repository == null:
		building_system.setup(BuildingStateScript.create_empty())
		return
	var initial_state: Dictionary = BuildingStateScript.create_empty()
	for structure_raw in building_repository.list_structures():
		if typeof(structure_raw) != TYPE_DICTIONARY:
			continue
		var normalized: Dictionary = _normalize_player_wall_structure(structure_raw as Dictionary)
		if normalized.is_empty():
			continue
		BuildingStateScript.upsert_structure(initial_state, normalized)
	building_system.setup(initial_state)

func _load_canonical_structures_for_chunk(chunk_pos: Vector2i) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var canonical_chunk: Dictionary = WorldSaveAdapterScript.load_canonical_chunk_state(chunk_pos)
	if canonical_chunk.is_empty():
		return out
	var structures_raw: Variant = canonical_chunk.get("structures", [])
	if not (structures_raw is Array):
		return out
	for raw in structures_raw:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var normalized: Dictionary = _normalize_player_wall_structure(raw as Dictionary)
		if normalized.is_empty():
			continue
		out.append(normalized)
	return out

func _refresh_building_state_for_chunk(chunk_pos: Vector2i, structures: Array[Dictionary]) -> void:
	if building_system == null:
		return
	var state: Dictionary = building_system.get_state()
	for structure_id in BuildingStateScript.get_structure_ids_in_chunk(state, chunk_pos):
		BuildingStateScript.remove_structure(state, structure_id)
	for raw in structures:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var normalized: Dictionary = _normalize_player_wall_structure(raw as Dictionary)
		if normalized.is_empty():
			continue
		BuildingStateScript.upsert_structure(state, normalized)

func _normalize_player_wall_structure(structure: Dictionary) -> Dictionary:
	if structure.is_empty():
		return {}
	var tile_raw: Variant = structure.get(BuildingStateScript.STRUCTURE_KEY_TILE_POS, structure.get("tile", Vector2i(-1, -1)))
	if not (tile_raw is Vector2i):
		return {}
	var tile_pos: Vector2i = tile_raw as Vector2i
	var chunk_raw: Variant = structure.get(BuildingStateScript.STRUCTURE_KEY_CHUNK_POS, Vector2i.ZERO)
	if not (chunk_raw is Vector2i):
		return {}
	var chunk_pos: Vector2i = chunk_raw as Vector2i
	var kind: String = String(structure.get(BuildingStateScript.STRUCTURE_KEY_KIND, "player_wall")).strip_edges()
	if kind.is_empty():
		kind = "player_wall"
	var metadata: Dictionary = structure.get(BuildingStateScript.STRUCTURE_KEY_METADATA, {}) as Dictionary
	if metadata.is_empty():
		metadata = BuildingStateScript.create_player_wall_metadata(player_wall_drop_enabled, player_wall_drop_item_id, player_wall_drop_amount)
	var max_hp: int = maxi(1, int(structure.get(BuildingStateScript.STRUCTURE_KEY_MAX_HP, player_wallwood_max_hp)))
	var hp: int = clampi(int(structure.get(BuildingStateScript.STRUCTURE_KEY_HP, max_hp)), 1, max_hp)
	var structure_id: String = String(structure.get(BuildingStateScript.STRUCTURE_KEY_ID, "")).strip_edges()
	return BuildingStateScript.create_structure_record(
		structure_id,
		chunk_pos,
		tile_pos,
		kind,
		hp,
		max_hp,
		metadata
	)

func _is_player_wall_structure(structure: Dictionary) -> bool:
	if structure.is_empty():
		return false
	var metadata: Dictionary = structure.get(BuildingStateScript.STRUCTURE_KEY_METADATA, {}) as Dictionary
	if bool(metadata.get(BuildingStateScript.METADATA_KEY_IS_PLAYER_WALL, false)):
		return true
	var kind: String = String(structure.get(BuildingStateScript.STRUCTURE_KEY_KIND, "")).strip_edges()
	return kind == "player_wall" or kind == "wall"
