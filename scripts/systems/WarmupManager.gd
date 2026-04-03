extends Node

@export var enabled: bool = true
@export var min_warmup_seconds: float = 0.3
@export var warmup_scene_paths: PackedStringArray = [
	"res://scenes/enemy.tscn",
	"res://scenes/arrow.tscn",
	"res://scenes/slash.tscn",
	"res://scenes/items/ItemDrop.tscn",
	"res://scenes/blood_burst.tscn",
	"res://scenes/blood_droplet.tscn"
]
@export var warmup_resource_paths: PackedStringArray = [
	"res://data/items/bow.tres",
	"res://data/items/arrow.tres",
	"res://scripts/weapons/arrow_projectile.gd",
	"res://art/sprites/slash.png",
	"res://art/sprites/GOBLIN1-Shee-walkt.png",
	"res://shaders/wall_occlusion.gdshader",
	"res://art/tiles/terrain.tres"
]

const WARMUP_META_KEY := "warmup_instance"

static var _session_warmup_done: bool = false


static func reset_session_warmup() -> void:
	_session_warmup_done = false

func run_warmup() -> void:
	if _session_warmup_done or not enabled:
		return

	_session_warmup_done = true
	await _run_with_master_bus_muted(_run_warmup_impl)


func _run_with_master_bus_muted(work: Callable) -> void:
	var bus_was_muted := _mute_master_bus()
	call_deferred("_restore_master_bus", bus_was_muted)
	await work.call()
	_restore_master_bus(bus_was_muted)


func _run_warmup_impl() -> void:
	var start_ms := Time.get_ticks_msec()
	var warmup_container := Node.new()
	warmup_container.name = "WarmupContainer"
	add_child(warmup_container)

	for path in warmup_resource_paths:
		if path.is_empty():
			continue
		ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)

	for path in warmup_scene_paths:
		if path.is_empty():
			continue
		var packed := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_REUSE) as PackedScene
		if packed == null:
			continue
		await _warm_scene_instance(packed, warmup_container)

	warmup_container.queue_free()
	if get_tree() != null:
		await get_tree().process_frame

	var elapsed_sec := float(Time.get_ticks_msec() - start_ms) * 0.001
	Debug.log("boot", "Warmup finished in %.3fs" % elapsed_sec)
	if elapsed_sec < min_warmup_seconds and get_tree() != null:
		await get_tree().create_timer(min_warmup_seconds - elapsed_sec).timeout

func _warm_scene_instance(packed: PackedScene, warmup_container: Node) -> void:
	var instance := packed.instantiate()
	if instance == null:
		return
	instance.set_meta(WARMUP_META_KEY, true)
	_set_node_processing_recursive(instance, false)

	if instance is CanvasItem:
		var item := instance as CanvasItem
		item.visible = false
	if instance is Node2D:
		(instance as Node2D).global_position = Vector2(-100000.0, -100000.0)

	warmup_container.add_child(instance)
	if get_tree() != null:
		await get_tree().process_frame

	if is_instance_valid(instance):
		instance.queue_free()
	if get_tree() != null:
		await get_tree().process_frame

func _set_node_processing_recursive(root: Node, should_process: bool) -> void:
	root.set_process(should_process)
	root.set_physics_process(should_process)
	root.set_process_input(should_process)
	root.set_process_unhandled_input(should_process)
	root.set_process_unhandled_key_input(should_process)
	root.set_process_shortcut_input(should_process)
	for child in root.get_children():
		_set_node_processing_recursive(child, should_process)

func _mute_master_bus() -> bool:
	var master_bus_idx := AudioServer.get_bus_index("Master")
	if master_bus_idx < 0:
		return false
	var was_muted := AudioServer.is_bus_mute(master_bus_idx)
	if not was_muted:
		AudioServer.set_bus_mute(master_bus_idx, true)
	return was_muted


func _restore_master_bus(previously_muted: bool) -> void:
	var master_bus_idx := AudioServer.get_bus_index("Master")
	if master_bus_idx < 0:
		return
	AudioServer.set_bus_mute(master_bus_idx, previously_muted)
