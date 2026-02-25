extends Node

@export var default_pickup_sfx: AudioStream
@export var debug_events := false
@export var pickup_player_only := false

func _ready() -> void:
	if GameEvents != null and GameEvents.has_signal("item_picked"):
		if not GameEvents.item_picked.is_connected(_on_item_picked):
			GameEvents.item_picked.connect(_on_item_picked)
			if debug_events:
				print("[AudioSystem] connected to item_picked")

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

func _on_item_picked(item_id: String, amount: int, picker: Node) -> void:
	if amount <= 0 or picker == null:
		return
	if pickup_player_only and not picker.is_in_group("player"):
		return
	if debug_events:
		print("[AudioSystem] item_picked item_id=", item_id, " amount=", amount, " picker=", picker)

	var item_data: ItemData = ItemDB.get_item(item_id)
	if item_data == null:
		if debug_events:
			print("[AudioSystem] item not found in ItemDB: ", item_id)
		return

	var stream: AudioStream = item_data.pickup_sfx
	if stream == null:
		if debug_events:
			print("[AudioSystem] pickup_sfx missing for item: ", item_id)
		return

	if picker is Node2D:
		play_2d(stream, (picker as Node2D).global_position)
	else:
		play_2d(stream, Vector2.ZERO)
