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
	"res://art/sprites/GOBLIN1-Shee-walkt.png"
]

var _did_run: bool = false

func run_warmup() -> void:
	if _did_run or not enabled:
		return

	_did_run = true
	var start_ms := Time.get_ticks_msec()

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
		await _warm_scene_instance(packed)

	var elapsed_sec := float(Time.get_ticks_msec() - start_ms) * 0.001
	if elapsed_sec < min_warmup_seconds:
		await get_tree().create_timer(min_warmup_seconds - elapsed_sec).timeout

func _warm_scene_instance(packed: PackedScene) -> void:
	var instance := packed.instantiate()
	if instance == null:
		return

	if instance is CanvasItem:
		var item := instance as CanvasItem
		item.visible = false
	if instance is Node2D:
		(instance as Node2D).global_position = Vector2(-100000.0, -100000.0)

	add_child(instance)
	await get_tree().process_frame
	await get_tree().process_frame

	instance.queue_free()
	await get_tree().process_frame
