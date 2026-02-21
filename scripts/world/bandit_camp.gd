extends Node2D
class_name BanditCamp

@export var bandit_scene: PackedScene
@export var max_bandits_alive: int = 4
@export var respawn_time: float = 6.0
@export var spawn_radius_px: float = 48.0

var _alive := 0
@onready var _timer: Timer = Timer.new()

func _ready() -> void:
	add_child(_timer)
	_timer.one_shot = false
	_timer.wait_time = respawn_time
	_timer.timeout.connect(_try_spawn)
	_timer.start()
	var fire := $AnimatedSprite2D as AnimatedSprite2D
	if fire:
		fire.play("default")

	# spawn inicial
	for i in range(max_bandits_alive):
		_try_spawn()

func _try_spawn() -> void:
	if bandit_scene == null:
		return
	if _alive >= max_bandits_alive:
		return

	var b := bandit_scene.instantiate()
	get_tree().current_scene.add_child(b)

	# Spawn alrededor del campamento
	var offset := Vector2(
		randf_range(-spawn_radius_px, spawn_radius_px),
		randf_range(-spawn_radius_px, spawn_radius_px)
	)
	b.global_position = global_position + offset

	_alive += 1
	b.tree_exited.connect(func(): _alive = max(0, _alive - 1))
