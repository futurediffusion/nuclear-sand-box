extends RefCounted
class_name BuildingSystem

## Building domain system.
##
## Responsibility:
## - Validate and process explicit building commands.
## - Mutate BuildingState deterministically.
## - Emit domain events (facts) describing outcomes.
##
## Out of scope:
## - tilemap/collider/world callbacks side effects
## - persistence adapters invocation

const RESULT_KEY_SUCCESS := "success"
const RESULT_KEY_ERROR := "error"
const RESULT_KEY_COMMAND_TYPE := "command_type"
const RESULT_KEY_CHANGED_STRUCTURES := "changed_structures"
const RESULT_KEY_EVENTS := "events"

const CHANGE_KEY_ACTION := "action"
const CHANGE_KEY_BEFORE := "before"
const CHANGE_KEY_AFTER := "after"

const ACTION_PLACED := "placed"
const ACTION_DAMAGED := "damaged"
const ACTION_REMOVED := "removed"

var _state: Dictionary = BuildingState.create_empty()

func setup(initial_state: Dictionary = {}) -> void:
	_state = initial_state.duplicate(true) if not initial_state.is_empty() else BuildingState.create_empty()

func get_state() -> Dictionary:
	return _state

func can_process(command: Dictionary) -> bool:
	var command_type := String(command.get("type", "")).strip_edges()
	if command_type.is_empty():
		return false
	if not command.has("tile_pos"):
		return false
	if not (command.get("tile_pos") is Vector2i):
		return false
	return command_type in [
		BuildingCommands.TYPE_PLACE_STRUCTURE,
		BuildingCommands.TYPE_DAMAGE_STRUCTURE,
		BuildingCommands.TYPE_REMOVE_STRUCTURE,
	]

func process(command: Dictionary) -> Dictionary:
	if not can_process(command):
		return _failure_result("", "invalid_command")

	var command_type := String(command.get("type", "")).strip_edges()
	if command_type == BuildingCommands.TYPE_PLACE_STRUCTURE:
		return _process_place_structure(command)
	if command_type == BuildingCommands.TYPE_DAMAGE_STRUCTURE:
		return _process_damage_structure(command)
	if command_type == BuildingCommands.TYPE_REMOVE_STRUCTURE:
		return _process_remove_structure(command)
	return _failure_result(command_type, "unsupported_command_type")

func _process_place_structure(command: Dictionary) -> Dictionary:
	var tile_pos: Vector2i = command.get("tile_pos", Vector2i.ZERO)
	if not (tile_pos is Vector2i):
		return _failure_result(BuildingCommands.TYPE_PLACE_STRUCTURE, "invalid_tile_pos")

	var requested_id := String(command.get("structure_id", "")).strip_edges()
	var max_hp := maxi(1, int(command.get("max_hp", 1)))
	var initial_hp := int(command.get("hp", max_hp))
	var metadata := command.get("metadata", {}) as Dictionary
	var chunk_pos: Vector2i = command.get("chunk_pos", Vector2i.ZERO)
	if not (chunk_pos is Vector2i):
		chunk_pos = Vector2i.ZERO
	var kind := String(command.get("kind", metadata.get("kind", "wall"))).strip_edges()
	if kind.is_empty():
		kind = "wall"

	if BuildingState.has_structure_at_tile(_state, tile_pos as Vector2i):
		return _failure_result(BuildingCommands.TYPE_PLACE_STRUCTURE, "tile_already_occupied")

	if not requested_id.is_empty() and BuildingState.has_structure(_state, requested_id):
		return _failure_result(BuildingCommands.TYPE_PLACE_STRUCTURE, "structure_id_already_exists")

	var record := BuildingState.create_structure_record(
		requested_id,
		chunk_pos as Vector2i,
		tile_pos as Vector2i,
		kind,
		initial_hp,
		max_hp,
		metadata
	)
	var placed := BuildingState.upsert_structure(_state, record)
	if placed.is_empty():
		return _failure_result(BuildingCommands.TYPE_PLACE_STRUCTURE, "failed_to_place_structure")

	var events: Array[Dictionary] = [BuildingEvents.structure_placed(placed)]
	var changed: Array[Dictionary] = [_change_entry(ACTION_PLACED, {}, placed)]
	return _success_result(BuildingCommands.TYPE_PLACE_STRUCTURE, changed, events)

func _process_damage_structure(command: Dictionary) -> Dictionary:
	var tile_pos: Vector2i = command.get("tile_pos", Vector2i.ZERO)
	if not (tile_pos is Vector2i):
		return _failure_result(BuildingCommands.TYPE_DAMAGE_STRUCTURE, "invalid_tile_pos")

	var amount := int(command.get("amount", 0))
	if amount <= 0:
		return _failure_result(BuildingCommands.TYPE_DAMAGE_STRUCTURE, "invalid_damage_amount")

	var current := BuildingState.get_structure_at_tile(_state, tile_pos as Vector2i)
	if current.is_empty():
		return _failure_result(BuildingCommands.TYPE_DAMAGE_STRUCTURE, "structure_not_found")

	var structure_id := String(current.get(BuildingState.STRUCTURE_KEY_ID, "")).strip_edges()
	if structure_id.is_empty():
		return _failure_result(BuildingCommands.TYPE_DAMAGE_STRUCTURE, "invalid_structure_id")

	var before := current.duplicate(true)
	var max_hp := maxi(1, int(current.get(BuildingState.STRUCTURE_KEY_MAX_HP, 1)))
	var current_hp := int(current.get(BuildingState.STRUCTURE_KEY_HP, max_hp))
	var normalized_hp := clampi(current_hp, 1, max_hp)
	var new_hp := normalized_hp - amount

	var events: Array[Dictionary] = []
	var changed: Array[Dictionary] = []

	if new_hp > 0:
		var updated := current.duplicate(true)
		updated[BuildingState.STRUCTURE_KEY_HP] = new_hp
		updated = BuildingState.upsert_structure(_state, updated)
		events.append(BuildingEvents.structure_damaged(
			structure_id,
			tile_pos as Vector2i,
			amount,
			new_hp,
			false
		))
		changed.append(_change_entry(ACTION_DAMAGED, before, updated))
		return _success_result(BuildingCommands.TYPE_DAMAGE_STRUCTURE, changed, events)

	var removed := BuildingState.remove_structure(_state, structure_id)
	events.append(BuildingEvents.structure_damaged(
		structure_id,
		tile_pos as Vector2i,
		amount,
		0,
		true
	))
	events.append(BuildingEvents.structure_removed(
		structure_id,
		tile_pos as Vector2i,
		"destroyed"
	))
	changed.append(_change_entry(ACTION_REMOVED, before, removed))
	return _success_result(BuildingCommands.TYPE_DAMAGE_STRUCTURE, changed, events)

func _process_remove_structure(command: Dictionary) -> Dictionary:
	var tile_pos: Vector2i = command.get("tile_pos", Vector2i.ZERO)
	if not (tile_pos is Vector2i):
		return _failure_result(BuildingCommands.TYPE_REMOVE_STRUCTURE, "invalid_tile_pos")

	var reason := String(command.get("reason", "")).strip_edges()
	var existing := BuildingState.get_structure_at_tile(_state, tile_pos as Vector2i)
	if existing.is_empty():
		return _failure_result(BuildingCommands.TYPE_REMOVE_STRUCTURE, "structure_not_found")

	var structure_id := String(existing.get(BuildingState.STRUCTURE_KEY_ID, "")).strip_edges()
	if structure_id.is_empty():
		return _failure_result(BuildingCommands.TYPE_REMOVE_STRUCTURE, "invalid_structure_id")

	var removed := BuildingState.remove_structure(_state, structure_id)
	if removed.is_empty():
		return _failure_result(BuildingCommands.TYPE_REMOVE_STRUCTURE, "failed_to_remove_structure")

	var events: Array[Dictionary] = [
		BuildingEvents.structure_removed(structure_id, tile_pos as Vector2i, reason)
	]
	var changed: Array[Dictionary] = [_change_entry(ACTION_REMOVED, existing, removed)]
	return _success_result(BuildingCommands.TYPE_REMOVE_STRUCTURE, changed, events)

func _success_result(command_type: String, changed_structures: Array[Dictionary], events: Array[Dictionary]) -> Dictionary:
	return {
		RESULT_KEY_SUCCESS: true,
		RESULT_KEY_ERROR: "",
		RESULT_KEY_COMMAND_TYPE: command_type,
		RESULT_KEY_CHANGED_STRUCTURES: changed_structures,
		RESULT_KEY_EVENTS: events,
	}

func _failure_result(command_type: String, error_code: String) -> Dictionary:
	return {
		RESULT_KEY_SUCCESS: false,
		RESULT_KEY_ERROR: error_code,
		RESULT_KEY_COMMAND_TYPE: command_type,
		RESULT_KEY_CHANGED_STRUCTURES: [],
		RESULT_KEY_EVENTS: [],
	}

func _change_entry(action: String, before: Dictionary, after: Dictionary) -> Dictionary:
	return {
		CHANGE_KEY_ACTION: action,
		CHANGE_KEY_BEFORE: before.duplicate(true),
		CHANGE_KEY_AFTER: after.duplicate(true),
	}
