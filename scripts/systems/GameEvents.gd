extends Node

signal entity_died(uid: String, kind: String, pos: Vector2, killer: Node)
signal loot_spawned(item_id: String, amount: int, pos: Vector2, source_uid: String)
signal item_picked(item_id: String, amount: int, picker: Node)
signal resource_harvested(kind: String, world_pos: Vector2)
signal faction_eradicated(group_id: String)
signal simulation_lod_mode_signal_changed(mode: StringName, enabled: bool)

@export var debug_events := false
var _simulation_lod_mode_signals: Dictionary = {
	&"exploration_normal": false,
	&"combat_close": false,
	&"raid_active": false,
}

func _ready() -> void:
	if debug_events:
		Debug.categories["events"] = true

func emit_entity_died(uid: String, kind: String, pos: Vector2, killer: Node) -> void:
	Debug.log("events", "[EVT] entity_died uid=%s kind=%s pos=%s killer=%s" % [uid, kind, pos, killer])
	emit_signal("entity_died", uid, kind, pos, killer)

func emit_loot_spawned(item_id: String, amount: int, pos: Vector2, source_uid: String) -> void:
	Debug.log("events", "[EVT] loot_spawned item_id=%s amount=%s pos=%s source_uid=%s" % [item_id, amount, pos, source_uid])
	emit_signal("loot_spawned", item_id, amount, pos, source_uid)

func emit_item_picked(item_id: String, amount: int, picker: Node) -> void:
	Debug.log("events", "[EVT] item_picked item_id=%s amount=%s picker=%s" % [item_id, amount, picker])
	emit_signal("item_picked", item_id, amount, picker)

func emit_resource_harvested(kind: String, world_pos: Vector2) -> void:
	Debug.log("events", "[EVT] resource_harvested kind=%s pos=%s" % [kind, world_pos])
	emit_signal("resource_harvested", kind, world_pos)

func emit_faction_eradicated(group_id: String) -> void:
	Debug.log("events", "[EVT] faction_eradicated group_id=%s" % group_id)
	emit_signal("faction_eradicated", group_id)


func set_simulation_lod_mode_signal(mode: StringName, enabled: bool) -> void:
	if not _simulation_lod_mode_signals.has(mode):
		push_warning("[GameEvents] simulation_lod_mode_signal desconocido: %s" % String(mode))
		return
	var was_enabled: bool = bool(_simulation_lod_mode_signals.get(mode, false))
	if was_enabled == enabled:
		return
	_simulation_lod_mode_signals[mode] = enabled
	Debug.log("events", "[EVT] lod_mode_signal mode=%s enabled=%s" % [String(mode), str(enabled)])
	emit_signal("simulation_lod_mode_signal_changed", mode, enabled)


func is_simulation_lod_mode_signal_enabled(mode: StringName) -> bool:
	return bool(_simulation_lod_mode_signals.get(mode, false))


func get_simulation_lod_mode_signals() -> Dictionary:
	return _simulation_lod_mode_signals.duplicate(true)
