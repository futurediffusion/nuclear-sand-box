extends Node

func _ready() -> void:
	if GameEvents == null:
		return

	if not GameEvents.entity_died.is_connected(_on_entity_died):
		GameEvents.entity_died.connect(_on_entity_died)
	if not GameEvents.loot_spawned.is_connected(_on_loot_spawned):
		GameEvents.loot_spawned.connect(_on_loot_spawned)
	if not GameEvents.item_picked.is_connected(_on_item_picked):
		GameEvents.item_picked.connect(_on_item_picked)

func _on_entity_died(uid: String, kind: String, pos: Vector2, killer: Node) -> void:
	print("[EventLogger] entity_died uid=", uid, " kind=", kind, " pos=", pos, " killer=", killer)

func _on_loot_spawned(item_id: String, amount: int, pos: Vector2, source_uid: String) -> void:
	print("[EventLogger] loot_spawned item_id=", item_id, " amount=", amount, " pos=", pos, " source_uid=", source_uid)

func _on_item_picked(item_id: String, amount: int, picker: Node) -> void:
	print("[EventLogger] item_picked item_id=", item_id, " amount=", amount, " picker=", picker)
