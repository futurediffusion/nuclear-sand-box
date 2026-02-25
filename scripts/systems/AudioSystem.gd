extends Node

@export var default_pickup_sfx: AudioStream
@export var debug_events := false
@export var pickup_player_only := false
@export var debug_force_master_bus := false
@export var debug_force_1d_master := false

func _ready() -> void:
	if debug_events:
		Debug.categories["audio"] = true
	Debug.log("audio", "[AudioSystem] buses count=%s" % AudioServer.bus_count)
	for i in range(AudioServer.bus_count):
		Debug.log("audio", "[AudioSystem] bus#%s name=%s mute=%s solo=%s vol_db=%s" % [
			i,
			AudioServer.get_bus_name(i),
			AudioServer.is_bus_mute(i),
			AudioServer.is_bus_solo(i),
			AudioServer.get_bus_volume_db(i),
		])

	var events := get_node_or_null("/root/GameEvents")
	if events == null:
		push_error("[AudioSystem] NO /root/GameEvents. No se puede conectar.")
		return

	if events.has_signal("item_picked"):
		if not events.item_picked.is_connected(_on_item_picked):
			events.item_picked.connect(_on_item_picked)
			Debug.log("audio", "[AudioSystem] connected to /root/GameEvents.item_picked")
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
	player.bus = bus
	player.volume_db = volume_db
	target_parent.add_child(player)
	player.global_position = pos
	Debug.log("audio", "[AudioSystem] added child. inside_tree=%s tree_paused=%s" % [player.is_inside_tree(), get_tree().paused])
	player.tree_entered.connect(func() -> void: Debug.log("audio", "[AudioSystem] player tree_entered"))
	player.finished.connect(func() -> void: Debug.log("audio", "[AudioSystem] player finished (queue_free next)"))
	player.tree_exited.connect(func() -> void: Debug.log("audio", "[AudioSystem] player tree_exited"))
	player.finished.connect(player.queue_free)

	Debug.log("audio", "[AudioSystem] spawned AudioStreamPlayer2D stream=%s bus=%s vol_db=%s pos=%s" % [
		player.stream,
		player.bus,
		player.volume_db,
		player.global_position,
	])

	var bus_index := AudioServer.get_bus_index(String(player.bus))
	if bus_index == -1:
		Debug.log("audio", "[AudioSystem] bus index=-1 for bus=%s" % player.bus)
	else:
		Debug.log("audio", "[AudioSystem] bus index=%s mute=%s solo=%s vol_db=%s" % [
			bus_index,
			AudioServer.is_bus_mute(bus_index),
			AudioServer.is_bus_solo(bus_index),
			AudioServer.get_bus_volume_db(bus_index),
		])
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
	Debug.log("audio", "[AudioSystem] play_1d bus=%s vol_db=%s stream=%s" % [p.bus, p.volume_db, p.stream])
	p.play()

func _on_item_picked(item_id: String, amount: int, picker: Node) -> void:
	Debug.log("audio", "[AudioSystem] RECEIVED item_picked item_id=%s amount=%s picker=%s" % [item_id, amount, picker])
	if amount <= 0 or picker == null:
		Debug.log("audio", "[AudioSystem] abort: amount<=0 o picker null")
		return
	if pickup_player_only and not picker.is_in_group("player"):
		Debug.log("audio", "[AudioSystem] abort: picker no está en grupo player")
		return
	var item_data: ItemData = ItemDB.get_item(item_id)
	if item_data == null:
		Debug.log("audio", "[AudioSystem] ItemDB.get_item returned NULL for item_id=%s" % item_id)
		return
	var stream: AudioStream = item_data.pickup_sfx
	if stream == null:
		Debug.log("audio", "[AudioSystem] pickup_sfx NULL for item_id=%s (revisa .tres)" % item_id)
		return
	Debug.log("audio", "[AudioSystem] playing pickup_sfx=%s bus=SFX" % stream)
	if debug_force_1d_master:
		play_1d(stream, null, &"Master", 12.0)
		return
	if picker is Node2D:
		play_2d(stream, (picker as Node2D).global_position, null, &"SFX", 12.0)
	else:
		play_2d(stream, Vector2.ZERO, null, &"SFX", 12.0)
