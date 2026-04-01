extends RefCounted
class_name CombatStateService

## Owner canónico de combat_state para actores runtime.
## Contrato de inputs válidos (Dictionary):
## - current_state: int (AI state)
## - has_active_target: bool
## - is_world_behavior_eligible: bool
## - last_engaged_time: float (RunClock timestamp)
##
## Eventos de salida (en state["events"]):
## - "combat_started"
## - "combat_ended"

const SimulationLODPolicyScript := preload("res://scripts/world/SimulationLODPolicy.gd")
const AIComponentScript := preload("res://scripts/components/AIComponent.gd")

const EVENT_COMBAT_STARTED: StringName = &"combat_started"
const EVENT_COMBAT_ENDED: StringName = &"combat_ended"

static var _state_by_actor_id: Dictionary = {}


static func update_actor_state(actor: Node, input: Dictionary) -> Dictionary:
	if actor == null or not is_instance_valid(actor):
		return _default_state()
	var normalized: Dictionary = _normalize_input(input)
	var actor_id: int = actor.get_instance_id()
	var previous: Dictionary = _state_by_actor_id.get(actor_id, _default_state())
	var next_state: Dictionary = _build_state(previous, actor_id, normalized)
	_state_by_actor_id[actor_id] = next_state
	return next_state


static func read_actor_state(actor: Node) -> Dictionary:
	if actor == null or not is_instance_valid(actor):
		return _default_state()
	return (_state_by_actor_id.get(actor.get_instance_id(), _default_state()) as Dictionary).duplicate(true)


static func clear_actor_state(actor: Node) -> void:
	if actor == null:
		return
	_state_by_actor_id.erase(actor.get_instance_id())


static func _normalize_input(input: Dictionary) -> Dictionary:
	return {
		"current_state": int(input.get("current_state", -1)),
		"has_active_target": bool(input.get("has_active_target", false)),
		"is_world_behavior_eligible": bool(input.get("is_world_behavior_eligible", true)),
		"last_engaged_time": float(input.get("last_engaged_time", 0.0)),
	}


static func _build_state(previous: Dictionary, actor_id: int, input: Dictionary) -> Dictionary:
	var current_state: int = int(input.get("current_state", -1))
	var has_active_target: bool = bool(input.get("has_active_target", false))
	var is_world_behavior_eligible: bool = bool(input.get("is_world_behavior_eligible", true))
	var last_engaged_time: float = float(input.get("last_engaged_time", 0.0))

	var is_in_direct_combat: bool = current_state == AIComponentScript.AIState.CHASE \
			or current_state == AIComponentScript.AIState.ATTACK \
			or has_active_target
	var is_runtime_busy_but_not_combat: bool = false
	if not is_in_direct_combat:
		is_runtime_busy_but_not_combat = current_state == AIComponentScript.AIState.HURT \
				or current_state == AIComponentScript.AIState.DISENGAGE \
				or current_state == AIComponentScript.AIState.HOLD_PERIMETER \
				or not is_world_behavior_eligible

	var was_recently_engaged: bool = SimulationLODPolicyScript.was_recently_engaged(last_engaged_time)
	var was_in_combat: bool = bool(previous.get("is_in_direct_combat", false))
	var events: Array[StringName] = []
	if is_in_direct_combat and not was_in_combat:
		events.append(EVENT_COMBAT_STARTED)
	elif not is_in_direct_combat and was_in_combat:
		events.append(EVENT_COMBAT_ENDED)

	return {
		"actor_id": actor_id,
		"is_in_direct_combat": is_in_direct_combat,
		"is_runtime_busy_but_not_combat": is_runtime_busy_but_not_combat,
		"was_recently_engaged": was_recently_engaged,
		"events": events,
	}


static func _default_state() -> Dictionary:
	return {
		"actor_id": 0,
		"is_in_direct_combat": false,
		"is_runtime_busy_but_not_combat": false,
		"was_recently_engaged": false,
		"events": [],
	}
