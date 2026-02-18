extends Node2D

# ==========================================================
# CONFIGURACIÓN
# ==========================================================
@export var enemy_scene: PackedScene
@export var spawn_interval: float = 2.0
@export var max_enemies: int = 10
@export var spawn_radius: float = 200.0


# ==========================================================
# ESTADO
# ==========================================================
var current_enemies: int = 0

@onready var timer: Timer = Timer.new()

# ==========================================================
func _ready() -> void:
	add_child(timer)
	timer.one_shot = false
	timer.wait_time = spawn_interval
	timer.timeout.connect(_spawn_enemy)
	
	timer.start() # <- ESTE era el faltante “seguro”
	
func _spawn_enemy() -> void:
	if enemy_scene == null:
		return
	
	if current_enemies >= max_enemies:
		return
	
	var enemy = enemy_scene.instantiate()
	get_tree().current_scene.add_child(enemy)
	
	# Posición aleatoria alrededor del spawner
	var offset = Vector2(
		randf_range(-spawn_radius, spawn_radius),
		randf_range(-spawn_radius, spawn_radius)
	)
	
	enemy.global_position = global_position + offset
	
	current_enemies += 1
	
	# Cuando muera el enemigo, reducir contador
	enemy.tree_exited.connect(_on_enemy_removed)

func _on_enemy_removed() -> void:
	current_enemies -= 1
	
