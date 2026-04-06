extends RefCounted
class_name BuildingSystem

## Building domain system (scaffolding).
##
## Current responsibility:
## - Own a building state dictionary.
## - Expose a small command-oriented API surface.
##
## Out of scope for this scaffold:
## - world.gd integration
## - PlayerWallSystem migration
## - scene/tilemap side effects

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

func process(command: Dictionary) -> Array[Dictionary]:
	## Intentionally minimal for initial scaffold.
	## Future implementation will mutate _state and emit domain events.
	if not can_process(command):
		return []
	return []
