extends Node

signal entity_died(uid: String, kind: String, pos: Vector2, killer: Node)
signal loot_spawned(item_id: String, amount: int, pos: Vector2, source_uid: String)
signal item_picked(item_id: String, amount: int, picker: Node)

@export var debug_events := false

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
