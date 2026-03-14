class_name GrassTuft
extends Area2D

# --- Atlas config ---
## Textura del sheet de grass (3 filas x 6 columnas, 16 px por celda)
@export var grass_sheet: Texture2D
@export var sheet_cols: int = 6
@export var sheet_rows: int = 3
@export var cell_size: int = 16

# --- Shake feedback ---
@export var shake_duration: float = 0.05
@export var shake_px: float = 3.0
@export var shake_speed: float = 50.0
@export var hit_flash_time: float = 0.05

@onready var sprite: Sprite2D = $Sprite2D
@onready var hit_particles: GPUParticles2D = $HitParticles

# --- Persistent identity ---
var entity_uid: String = ""
var entity_cx: int = 0
var entity_cy: int = 0

# --- Runtime ---
var _is_dead: bool = false
var _base_pos: Vector2
var _shake_t: float = 0.0
var _flash_t: float = 0.0


func _ready() -> void:
	collision_layer = 8   # resources layer 4 — armas pueden detectar
	collision_mask = 0

	_base_pos = sprite.position

	# Seleccionar variante determinista del atlas
	if grass_sheet != null:
		var total_variants: int = sheet_cols * sheet_rows
		var variant: int = abs(hash(entity_uid)) % total_variants
		var col: int = variant % sheet_cols
		var row: int = variant / sheet_cols
		sprite.texture = grass_sheet
		sprite.region_enabled = true
		sprite.region_rect = Rect2(col * cell_size, row * cell_size, cell_size, cell_size)

	# Fase de sway única por posición
	if sprite.material != null:
		var phase: float = global_position.x * 0.011 + global_position.y * 0.007
		(sprite.material as ShaderMaterial).set_shader_parameter("world_phase", phase)


func _physics_process(delta: float) -> void:
	if _shake_t > 0.0:
		_shake_t -= delta
		var t: float = (shake_duration - _shake_t) * shake_speed
		sprite.position = _base_pos + Vector2(sin(t) * shake_px, 0.0)
	else:
		sprite.position = _base_pos

	if _flash_t > 0.0:
		_flash_t -= delta
		if _flash_t <= 0.0:
			sprite.modulate = Color(1, 1, 1, 1)


func hit(_by: Node) -> void:
	if _is_dead:
		return
	_is_dead = true
	sprite.visible = false
	$CollisionShape2D.set_deferred("disabled", true)

	if hit_particles:
		hit_particles.restart()
		hit_particles.emitting = true

	# Persistir muerte
	WorldSave.set_entity_state(entity_cx, entity_cy, entity_uid, {"dead": true})
	Debug.log("grass", "cut uid=%s" % entity_uid)
	get_tree().create_timer(0.5).timeout.connect(queue_free)


func apply_save_state(state: Dictionary) -> void:
	if bool(state.get("dead", false)):
		_is_dead = true
		queue_free()


func get_save_state() -> Dictionary:
	return {"dead": _is_dead}
