extends Node

@export var default_pickup_sfx: AudioStream
@export var debug_events := false
@export var pickup_player_only := false
@export var debug_force_master_bus := false
@export var debug_force_1d_master := false

func _ready() -> void:
	print("[AudioSystem] buses count=", AudioServer.bus_count)
	for i in range(AudioServer.bus_count):
		print("[AudioSystem] bus#", i, " name=", AudioServer.get_bus_name(i),
			" mute=", AudioServer.is_bus_mute(i),
			" solo=", AudioServer.is_bus_solo(i),
			" vol_db=", AudioServer.get_bus_volume_db(i))

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
	if debug_force_master_bus:
		player.bus = &"Master"
	player.volume_db = volume_db
	target_parent.add_child(player)
	print("[AudioSystem] added child. inside_tree=", player.is_inside_tree(), " tree_paused=", get_tree().paused)
	player.tree_entered.connect(func(): print("[AudioSystem] player tree_entered"))
	player.finished.connect(func(): print("[AudioSystem] player finished (queue_free next)"))
	player.tree_exited.connect(func(): print("[AudioSystem] player tree_exited"))
	player.finished.connect(player.queue_free)

	print("[AudioSystem] spawned AudioStreamPlayer2D",
		" stream=", player.stream,
		" bus=", player.bus,
		" vol_db=", player.volume_db,
		" pos=", player.global_position,
		" parent=", target_parent,
		" current_scene=", get_tree().current_scene)

	var bus_index := AudioServer.get_bus_index(String(player.bus))
	if bus_index == -1:
		print("[AudioSystem] bus index=-1 for bus=", player.bus)
	else:
		print("[AudioSystem] bus index=", bus_index,
			" bus mute=", AudioServer.is_bus_mute(bus_index),
			" bus solo=", AudioServer.is_bus_solo(bus_index),
			" bus vol_db=", AudioServer.get_bus_volume_db(bus_index))
	player.play()

func play_1d(stream: AudioStream, parent: Node = null, bus: StringName = &"Master", volume_db: float = 0.0) -> void:
	if stream == null:
		return

	var target_parent := parent
	if target_parent == null:
		target_parent = get_tree().current_scene
	if target_parent == null:
		target_parent = get_tree().root

	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.bus = bus
	p.volume_db = volume_db
	target_parent.add_child(p)
	p.finished.connect(p.queue_free)
	print("[AudioSystem] play_1d bus=", p.bus, " vol_db=", p.volume_db, " stream=", p.stream)
	p.play()

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
	if debug_force_1d_master:
		play_1d(stream, null, &"Master", 0.0)
		return

	if picker is Node2D:
		play_2d(stream, (picker as Node2D).global_position)
	else:
		play_2d(stream, Vector2.ZERO)
