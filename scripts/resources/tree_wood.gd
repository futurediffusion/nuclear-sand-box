class_name TreeWood
extends StaticBody2D

const WOOD_HIT_SOUNDS: Array[AudioStream] = [
	preload("res://art/Sounds/wood1.ogg"),
	preload("res://art/Sounds/wood2.ogg"),
]

# Ambient wind near trees
const DEFAULT_WIND_SFX: AudioStream = preload("res://art/Sounds/windsound.ogg")

# --- Textures (set in Inspector: 4 trunks + 4 leaves) ---
@export var trunk_textures: Array[Texture2D] = []
@export var leaves_textures: Array[Texture2D] = []

# --- Hit / chop settings ---
@export var max_hits: int = 8

# --- Drop settings ---
@export var drop_item: ItemData
@export var drop_scene: PackedScene
@export var drop_icon: Texture2D
@export var drop_pickup_sfx: AudioStream

# --- Shake feedback ---
@export var shake_duration: float = 0.08
@export var shake_px: float = 5.0
@export var shake_speed: float = 40.0
@export var hit_flash_time: float = 0.06
@export var wind_sfx: AudioStream = DEFAULT_WIND_SFX
@export var wind_range_multiplier: float = 2.0
@export var wind_min_radius: float = 32.0
@export var wind_volume_db: float = -6.0

@onready var trunk_sprite: Sprite2D = $TrunkSprite
@onready var leaves_sprite: Sprite2D = $LeavesSprite
@onready var hit_particles: GPUParticles2D = $HitParticles
@onready var trunk_collision: CollisionShape2D = $CollisionShape2D
@onready var wind_range: Area2D = $WindRange
@onready var wind_range_shape: CollisionShape2D = $WindRange/CollisionShape2D
@onready var wind_player: AudioStreamPlayer2D = $WindLoop

# --- Persistent identity (set at spawn time via init_data properties) ---
var entity_uid: String = ""
var entity_cx: int = 0
var entity_cy: int = 0

# --- Runtime state ---
var _hit_count: float = 0.0
var _is_dead: bool = false
var _base_pos: Vector2
var _shake_t: float = 0.0
var _flash_t: float = 0.0
var _player_in_wind_range: bool = false


func _ready() -> void:
	collision_layer = CollisionLayers.WORLD_WALL_LAYER_MASK | CollisionLayers.RESOURCES_LAYER_MASK
	collision_mask = 0
	_base_pos = trunk_sprite.position

	# Pick a deterministic variant from entity_uid so the same tree always looks the same
	if trunk_textures.size() > 0:
		var ti: int = abs(hash(entity_uid)) % trunk_textures.size()
		trunk_sprite.texture = trunk_textures[ti]

	if leaves_textures.size() > 0:
		var li: int = abs(hash(entity_uid + "leaves")) % leaves_textures.size()
		leaves_sprite.texture = leaves_textures[li]

	# Hojas siempre sobre el player — z absoluto para salir del y-sort del parent
	leaves_sprite.z_as_relative = false
	leaves_sprite.z_index = 50

	# Partículas encima de todo (hojas incluidas), posicionadas en el tronco
	hit_particles.z_as_relative = false
	hit_particles.z_index = 60
	hit_particles.position = Vector2(0, 14)

	# Set per-tree sway phase so trees don't all move in sync
	if leaves_sprite.material != null:
		var phase: float = global_position.x * 0.007 + global_position.y * 0.003
		(leaves_sprite.material as ShaderMaterial).set_shader_parameter("world_phase", phase)

	_setup_wind_range()
	_setup_wind_audio()


func _physics_process(delta: float) -> void:
	# --- Shake ---
	if _shake_t > 0.0:
		_shake_t -= delta
		var t: float = (shake_duration - _shake_t) * shake_speed
		var off: float = sin(t) * shake_px
		trunk_sprite.position = _base_pos + Vector2(off, 0.0)
		leaves_sprite.position = Vector2(off, 0.0)  # leaves offset from their own origin
	else:
		trunk_sprite.position = _base_pos
		leaves_sprite.position = Vector2.ZERO

	# --- Flash ---
	if _flash_t > 0.0:
		_flash_t -= delta
		if _flash_t <= 0.0:
			trunk_sprite.modulate = Color(1, 1, 1, 1)
			leaves_sprite.modulate = Color(1, 1, 1, 1)


func hit(by: Node) -> void:
	if _is_dead:
		return

	var hit_sfx := _pick_wood_hit_sound()
	if hit_sfx != null:
		AudioSystem.play_2d(hit_sfx, global_position)

	_play_hit_feedback()
	var strength := _get_hit_strength(by)
	_hit_count += strength
	Debug.log("tree", "hit %.1f/%d uid=%s" % [_hit_count, max_hits, entity_uid])
	if _hit_count >= max_hits:
		_fell_tree()
	else:
		_maybe_drop_stick()


func _get_hit_strength(by: Node) -> float:
	if by == null:
		return 1.0
	var wc := by.get_node_or_null("WeaponComponent")
	if wc == null or not wc.has_method("get_current_weapon_id"):
		return 1.0
	match String(wc.call("get_current_weapon_id")):
		"axe_wood":   return float(max_hits) / 6.0
		"axe_stone":  return float(max_hits) / 4.0
		"axe_copper": return float(max_hits) / 2.0
		_:            return 1.0


func _maybe_drop_stick() -> void:
	if drop_scene == null:
		return
	if randf() >= 0.5:
		return
	var amount := 2 if randf() < 0.3 else 1
	var origin := global_position + Vector2(0.0, -16.0)
	LootSystem.spawn_drop(null, "stick", amount, origin, get_parent(), {"drop_scene": drop_scene}, entity_uid + "_stick_%d" % randi())


func _play_hit_feedback() -> void:
	_shake_t = shake_duration
	_flash_t = hit_flash_time
	trunk_sprite.modulate = Color(0.85, 0.75, 0.6, 1)
	leaves_sprite.modulate = Color(0.85, 0.75, 0.6, 1)
	if hit_particles:
		hit_particles.restart()
		hit_particles.emitting = true


func _pick_wood_hit_sound() -> AudioStream:
	if WOOD_HIT_SOUNDS.is_empty():
		return null
	return WOOD_HIT_SOUNDS[randi() % WOOD_HIT_SOUNDS.size()]


func suppress_default_impact_sound() -> bool:
	return true


func _setup_wind_range() -> void:
	if wind_range == null or wind_range_shape == null:
		return
	wind_range.collision_layer = 0
	wind_range.collision_mask = 1  # player layer
	if trunk_collision != null:
		wind_range.position = trunk_collision.position

	var circle := wind_range_shape.shape as CircleShape2D
	if circle == null:
		circle = CircleShape2D.new()
		wind_range_shape.shape = circle
	circle.radius = _compute_wind_radius()

	if not wind_range.body_entered.is_connected(_on_wind_range_body_entered):
		wind_range.body_entered.connect(_on_wind_range_body_entered)
	if not wind_range.body_exited.is_connected(_on_wind_range_body_exited):
		wind_range.body_exited.connect(_on_wind_range_body_exited)


func _setup_wind_audio() -> void:
	if wind_player == null:
		return
	wind_player.stream = wind_sfx
	wind_player.volume_db = wind_volume_db
	wind_player.bus = &"SFX"
	if not wind_player.finished.is_connected(_on_wind_loop_finished):
		wind_player.finished.connect(_on_wind_loop_finished)


func _compute_wind_radius() -> float:
	var tree_size: float = 0.0
	if trunk_sprite != null and trunk_sprite.texture != null:
		var tsize := trunk_sprite.texture.get_size() * trunk_sprite.scale.abs()
		tree_size = maxf(tree_size, maxf(tsize.x, tsize.y))
	if leaves_sprite != null and leaves_sprite.texture != null:
		var lsize := leaves_sprite.texture.get_size() * leaves_sprite.scale.abs()
		tree_size = maxf(tree_size, maxf(lsize.x, lsize.y))
	if tree_size <= 0.0 and trunk_collision != null and trunk_collision.shape is RectangleShape2D:
		var rect := trunk_collision.shape as RectangleShape2D
		tree_size = maxf(rect.size.x, rect.size.y)
	return maxf(wind_min_radius, tree_size * maxf(1.0, wind_range_multiplier))


func _on_wind_range_body_entered(body: Node) -> void:
	if _is_dead:
		return
	if not body.is_in_group("player"):
		return
	_player_in_wind_range = true
	_play_wind_if_needed()


func _on_wind_range_body_exited(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	_player_in_wind_range = false
	if wind_player != null:
		wind_player.stop()


func _on_wind_loop_finished() -> void:
	if _player_in_wind_range and not _is_dead:
		_play_wind_if_needed()


func _play_wind_if_needed() -> void:
	if wind_player == null or wind_player.stream == null:
		return
	if wind_player.playing:
		return
	wind_player.play()


func _fell_tree() -> void:
	_is_dead = true
	_player_in_wind_range = false
	if wind_player != null:
		wind_player.stop()

	# Drop 3–6 wood, biased toward lower values (take min of two dice)
	var raw: int = mini(randi_range(1, 6), randi_range(1, 6)) + 2
	var wood_count: int = clampi(raw, 3, 6)

	var origin: Vector2 = global_position + Vector2(0.0, -16.0)

	for i in range(wood_count):
		var overrides: Dictionary = {
			"drop_scene": drop_scene,
			"icon": drop_icon,
			"pickup_sfx": drop_pickup_sfx,
		}
		var spawned := LootSystem.spawn_drop(drop_item, "wood", 1, origin, get_parent(), overrides, entity_uid + "_drop_%d" % i)
		if spawned == null:
			push_warning("[TREE] LootSystem no pudo crear drop")

	trunk_sprite.visible = false
	leaves_sprite.visible = false
	$CollisionShape2D.set_deferred("disabled", true)

	# Persist death immediately so tree won't respawn on next chunk load
	WorldSave.set_entity_state(entity_cx, entity_cy, entity_uid, {"dead": true})

	Debug.log("tree", "felled uid=%s dropped=%d" % [entity_uid, wood_count])
	get_tree().create_timer(0.5).timeout.connect(queue_free)


# Called by EntitySpawnCoordinator when a saved state exists for this tree
func apply_save_state(state: Dictionary) -> void:
	if bool(state.get("dead", false)):
		_is_dead = true
		queue_free()


func get_save_state() -> Dictionary:
	return {"dead": _is_dead}
