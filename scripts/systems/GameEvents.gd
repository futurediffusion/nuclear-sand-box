extends Node

signal entity_died(uid: String, kind: String, pos: Vector2, killer: Node)
signal loot_spawned(item_id: String, amount: int, pos: Vector2, source_uid: String)
signal item_picked(item_id: String, amount: int, picker: Node)

@export var debug_events := false

func emit_entity_died(uid: String, kind: String, pos: Vector2, killer: Node) -> void:
	if debug_events:
		print("[EVT] entity_died uid=", uid, " kind=", kind, " pos=", pos, " killer=", killer)
	emit_signal("entity_died", uid, kind, pos, killer)

func emit_loot_spawned(item_id: String, amount: int, pos: Vector2, source_uid: String) -> void:
	if debug_events:
		print("[EVT] loot_spawned item_id=", item_id, " amount=", amount, " pos=", pos, " source_uid=", source_uid)
	emit_signal("loot_spawned", item_id, amount, pos, source_uid)

func emit_item_picked(item_id: String, amount: int, picker: Node) -> void:
	if debug_events:
		print("[EVT] item_picked item_id=", item_id, " amount=", amount, " picker=", picker)
	emit_signal("item_picked", item_id, amount, picker)
