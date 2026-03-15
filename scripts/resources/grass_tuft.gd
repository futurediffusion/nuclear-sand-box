class_name GrassTuft
extends Area2D

const ITEM_DROP_SCENE: PackedScene = preload("res://scenes/items/ItemDrop.tscn")
const LEAF_SWAY_SHADER: Shader = preload("res://art/shaders/leaves_sway.gdshader")
const DEFAULT_TOUCH_SFX_POOL := [
	preload("res://art/Sounds/grassmove1.ogg"),
	preload("res://art/Sounds/grassmove2.ogg"),
]

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

# --- Touch bend (plant-like) ---
@export var touch_sway_duration: float = 0.34
@export var touch_sway_amount: float = 11.0
@export var touch_sway_cycles: float = 2.2
@export var touch_sway_damping: float = 2.7
@export var touch_trigger_radius: float = 22.0
@export var touch_retrigger_cooldown: float = 0.15
@export var idle_sway_speed: float = 1.9
@export var idle_sway_amount: float = 5.2
@export var idle_sway_base_lock: float = 0.18
@export var touch_sway_profile_exp: float = 1.9
# Backward-compat aliases to avoid parser breaks from stale in-editor buffers.
@export var touch_wiggle_duration: float = 0.34
@export var touch_wiggle_degrees: float = 11.0
@export var touch_wiggle_cycles: float = 2.2
@export var touch_wiggle_damping: float = 2.7
@export var touch_stretch_strength: float = 0.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var hit_particles: GPUParticles2D = $HitParticles

# Audio
@export var hit_sfx: AudioStream
@export var touch_sfx_pool: Array[AudioStream] = []
@export_range(-40.0, 12.0, 0.5, "suffix:dB") var touch_sfx_volume_db: float = 0.0

# --- Persistent identity ---
var entity_uid: String = ""
var entity_cx: int = 0
var entity_cy: int = 0

# --- Runtime ---
var _is_dead: bool = false
var _base_pos: Vector2
var _base_scale: Vector2
var _shake_t: float = 0.0
var _flash_t: float = 0.0
var _touch_sway_t: float = 0.0
var _touch_sway_dir: float = 1.0
var _touch_wiggle_t: float = 0.0
var _touch_retrigger_t: float = 0.0
var _shader_mat: ShaderMaterial = null
var _last_touch_sfx_idx: int = -1
var _player_was_in_touch_radius: bool = false


func _ready() -> void:
	collision_layer = 8   # resources layer 4
	collision_mask = 1    # player layer
	set_physics_process(true)
	monitoring = true
	monitorable = true

	_base_pos = sprite.position
	_base_scale = sprite.scale
	touch_wiggle_duration = touch_sway_duration
	touch_wiggle_degrees = touch_sway_amount
	touch_wiggle_cycles = touch_sway_cycles
	touch_wiggle_damping = touch_sway_damping
	if touch_sfx_pool.is_empty():
		for s in DEFAULT_TOUCH_SFX_POOL:
			if s != null:
				touch_sfx_pool.append(s)

	# Seleccionar variante determinista del atlas
	_apply_variant_from_uid()

	# Ensure per-instance shader params (avoid shared material across all tufts).
	if sprite.material is ShaderMaterial:
		sprite.material = (sprite.material as ShaderMaterial).duplicate()
	else:
		var mat := ShaderMaterial.new()
		mat.shader = LEAF_SWAY_SHADER
		sprite.material = mat

	# Fase unica por posicion + reset del impulso tactil
	_shader_mat = sprite.material as ShaderMaterial
	if _shader_mat != null:
		_shader_mat.set_shader_parameter("sway_speed", idle_sway_speed)
		_shader_mat.set_shader_parameter("sway_amount", idle_sway_amount)
		_shader_mat.set_shader_parameter("sway_base_lock", idle_sway_base_lock)
		_shader_mat.set_shader_parameter("touch_profile_exp", touch_sway_profile_exp)
		_sync_world_phase()
		_set_touch_offset(0.0)

	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	if _touch_retrigger_t > 0.0:
		_touch_retrigger_t -= delta

	var shake_offset := Vector2.ZERO
	if _shake_t > 0.0:
		_shake_t -= delta
		var t: float = (shake_duration - _shake_t) * shake_speed
		shake_offset = Vector2(sin(t) * shake_px, 0.0)

	sprite.position = _base_pos + shake_offset

	if _flash_t > 0.0:
		_flash_t -= delta
		if _flash_t <= 0.0:
			sprite.modulate = Color(1, 1, 1, 1)

	var touch_offset := 0.0
	if _touch_sway_t > 0.0:
		_touch_sway_t -= delta
		_touch_wiggle_t = _touch_sway_t
		var d := maxf(0.01, touch_sway_duration)
		var p := clampf(1.0 - (_touch_sway_t / d), 0.0, 1.0)
		var phase := p * TAU * touch_sway_cycles
		var damper := exp(-p * touch_sway_damping)
		var primary := sin(phase) * touch_sway_amount
		var secondary := sin(phase * 2.2) * touch_sway_amount * 0.18
		touch_offset = (primary + secondary) * damper * _touch_sway_dir

	_set_touch_offset(touch_offset)

	_try_trigger_touch_from_player_proximity()


func _on_body_entered(body: Node) -> void:
	if _is_dead:
		return
	if not body.is_in_group("player"):
		return
	if body is Node2D:
		_start_touch_sway((body as Node2D).global_position.x)
	else:
		_start_touch_sway(global_position.x + randf_range(-1.0, 1.0))


func _set_touch_offset(value: float) -> void:
	if _shader_mat == null:
		return
	_shader_mat.set_shader_parameter("touch_offset", value)


func _apply_variant_from_uid() -> void:
	if grass_sheet == null:
		return
	var total_variants: int = max(1, sheet_cols * sheet_rows)
	var variant: int = abs(hash(entity_uid)) % total_variants
	var col: int = variant % sheet_cols
	var row: int = variant / sheet_cols
	sprite.texture = grass_sheet
	sprite.region_enabled = true
	sprite.region_rect = Rect2(col * cell_size, row * cell_size, cell_size, cell_size)


func _sync_world_phase() -> void:
	if _shader_mat == null:
		return
	var phase: float = global_position.x * 0.011 + global_position.y * 0.007
	_shader_mat.set_shader_parameter("world_phase", phase)


func _try_trigger_touch_from_player_proximity() -> void:
	if _is_dead:
		return
	var players := get_tree().get_nodes_in_group("player")
	var player_in_radius := false
	var trigger_source_x := global_position.x
	for p in players:
		if not (p is Node2D):
			continue
		var player_2d := p as Node2D
		if global_position.distance_to(player_2d.global_position) <= touch_trigger_radius:
			player_in_radius = true
			trigger_source_x = player_2d.global_position.x
			break

	if player_in_radius:
		if not _player_was_in_touch_radius and _touch_retrigger_t <= 0.0:
			_start_touch_sway(trigger_source_x)
		_player_was_in_touch_radius = true
	else:
		_player_was_in_touch_radius = false


func _start_touch_sway(source_global_x: float) -> void:
	var rel_x := global_position.x - source_global_x
	if is_zero_approx(rel_x):
		_touch_sway_dir = -1.0 if randf() < 0.5 else 1.0
	else:
		# If player comes from the left, tuft bends right (and vice versa).
		_touch_sway_dir = sign(rel_x)
	_touch_sway_t = maxf(0.01, touch_sway_duration)
	_touch_wiggle_t = _touch_sway_t
	_touch_retrigger_t = maxf(0.01, touch_retrigger_cooldown)
	_play_touch_sfx()


func _play_touch_sfx() -> void:
	if touch_sfx_pool.is_empty():
		return

	var valid_streams: Array[AudioStream] = []
	for s in touch_sfx_pool:
		if s != null:
			valid_streams.append(s)
	if valid_streams.is_empty():
		return

	var pick_idx := 0
	if valid_streams.size() > 1:
		pick_idx = int(randi() % valid_streams.size())
		if pick_idx == _last_touch_sfx_idx:
			pick_idx = (pick_idx + 1 + int(randi() % (valid_streams.size() - 1))) % valid_streams.size()

	_last_touch_sfx_idx = pick_idx
	AudioSystem.play_2d(valid_streams[pick_idx], global_position, null, &"SFX", touch_sfx_volume_db)


func apply_spawn_data(init_data: Dictionary) -> void:
	var props: Variant = init_data.get("properties", null)
	if props is Dictionary:
		var pd := props as Dictionary
		if pd.has("entity_uid"):
			entity_uid = String(pd["entity_uid"])
		if pd.has("entity_cx"):
			entity_cx = int(pd["entity_cx"])
		if pd.has("entity_cy"):
			entity_cy = int(pd["entity_cy"])

	_apply_variant_from_uid()
	_sync_world_phase()
	_set_touch_offset(0.0)


func hit(_by: Node) -> void:
	if _is_dead:
		return

	if hit_sfx != null:
		AudioSystem.play_2d(hit_sfx, global_position)

	_is_dead = true
	_set_touch_offset(0.0)
	sprite.visible = false
	$CollisionShape2D.set_deferred("disabled", true)

	if hit_particles:
		hit_particles.restart()
		hit_particles.emitting = true

	var fiber_amount := 2 if randf() < 0.3 else 1
	LootSystem.spawn_drop(null, "fiber", fiber_amount, global_position, get_parent(), {"drop_scene": ITEM_DROP_SCENE}, entity_uid + "_fiber")

	WorldSave.set_entity_state(entity_cx, entity_cy, entity_uid, {"dead": true})
	Debug.log("grass", "cut uid=%s" % entity_uid)
	get_tree().create_timer(0.5).timeout.connect(queue_free)


func suppress_default_impact_sound() -> bool:
	return true


func apply_save_state(state: Dictionary) -> void:
	if bool(state.get("dead", false)):
		_is_dead = true
		queue_free()


func get_save_state() -> Dictionary:
	return {"dead": _is_dead}
