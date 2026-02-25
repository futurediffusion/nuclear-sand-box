extends Node

@export var default_pickup_sfx: AudioStream

func _ready() -> void:
	if GameEvents != null and GameEvents.has_signal("item_picked"):
		if not GameEvents.item_picked.is_connected(_on_item_picked):
			GameEvents.item_picked.connect(_on_item_picked)

func play_2d(stream: AudioStream, pos: Vector2, parent: Node = null, bus: StringName = &"SFX", volume_db: float = 0.0) -> void:
	if stream == null:
		return

	var target_parent := parent
	if target_parent == null:
		target_parent = get_tree().current_scene
	if target_parent == null:
		target_parent = get_tree().root

	var player := AudioStreamPlayer2D.new()
	player.stream = stream
	player.global_position = pos
	player.bus = bus
	player.volume_db = volume_db
	target_parent.add_child(player)
	player.finished.connect(player.queue_free)
	player.play()

func _on_item_picked(item_id: String, _amount: int, picker: Node) -> void:
	var stream := _resolve_pickup_sfx(item_id)
	if stream == null:
		return

	var pos := Vector2.ZERO
	if picker is Node2D:
		pos = (picker as Node2D).global_position

	play_2d(stream, pos)

func _resolve_pickup_sfx(item_id: String) -> AudioStream:
	var item_db := get_node_or_null("/root/ItemDB")
	if item_db != null and item_db.has_method("get_item"):
		var item_data: ItemData = item_db.get_item(item_id)
		if item_data != null and item_data.pickup_sfx != null:
			return item_data.pickup_sfx
	return default_pickup_sfx
