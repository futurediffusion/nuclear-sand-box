class_name TreeWood
extends StaticBody2D

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

@onready var trunk_sprite: Sprite2D = $TrunkSprite
@onready var leaves_sprite: Sprite2D = $LeavesSprite
@onready var hit_particles: GPUParticles2D = $HitParticles

# --- Persistent identity (set at spawn time via init_data properties) ---
var entity_uid: String = ""
var entity_cx: int = 0
var entity_cy: int = 0

# --- Runtime state ---
var _hit_count: int = 0
var _is_dead: bool = false
var _base_pos: Vector2
var _shake_t: float = 0.0
var _flash_t: float = 0.0


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
	_play_hit_feedback()
	_hit_count += 1
	Debug.log("tree", "hit %d/%d uid=%s" % [_hit_count, max_hits, entity_uid])
	if _hit_count >= max_hits:
		_fell_tree()


func _play_hit_feedback() -> void:
	_shake_t = shake_duration
	_flash_t = hit_flash_time
	trunk_sprite.modulate = Color(0.85, 0.75, 0.6, 1)
	leaves_sprite.modulate = Color(0.85, 0.75, 0.6, 1)
	if hit_particles:
		hit_particles.restart()
		hit_particles.emitting = true


func _fell_tree() -> void:
	_is_dead = true

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
