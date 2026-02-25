extends Node

@export var default_pickup_sfx: AudioStream
@export var debug_events := false
@export var pickup_player_only := false

func _ready() -> void:
	var events := get_node_or_null("/root/GameEvents")
	if events == null:
		push_error("[AudioSystem] NO /root/GameEvents. No se puede conectar.")
		return

	if events.has_signal("item_picked"):
		if not events.item_picked.is_connected(_on_item_picked):
			events.item_picked.connect(_on_item_picked)
			print("[AudioSystem] connected to /root/GameEvents.item_picked")
	else:
		push_error("[AudioSystem] GameEvents sin signal item_picked")

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
	print("[AudioSystem] RECEIVED item_picked item_id=", item_id, " amount=", amount, " picker=", picker)

	if amount <= 0 or picker == null:
		print("[AudioSystem] abort: amount<=0 o picker null")
		return
	if pickup_player_only and not picker.is_in_group("player"):
		print("[AudioSystem] abort: picker no está en grupo player")
		return

	var item_data: ItemData = ItemDB.get_item(item_id)
	if item_data == null:
		print("[AudioSystem] ItemDB.get_item returned NULL for item_id=", item_id)
		return

	var stream: AudioStream = item_data.pickup_sfx
	if stream == null:
		print("[AudioSystem] pickup_sfx NULL for item_id=", item_id, " (revisa .tres)")
		return

	print("[AudioSystem] playing pickup_sfx=", stream, " bus=SFX")
	if picker is Node2D:
		play_2d(stream, (picker as Node2D).global_position)
	else:
		play_2d(stream, Vector2.ZERO)
