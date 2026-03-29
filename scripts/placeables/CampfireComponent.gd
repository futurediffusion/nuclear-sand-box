extends StaticBody2D
class_name CampfireWorld

const MAX_HITS: int = 5
const ITEM_DROP_SCENE: PackedScene = preload("res://scenes/items/ItemDrop.tscn")
const DEFAULT_DROP_ITEM_ID: String = "campfire"
const DEFAULT_BREAK_SFX: AudioStream = preload("res://art/Sounds/woodwallbreak.ogg")
const DEFAULT_BREAK_VOLUME_DB: float = 0.0

const SHAKE_DURATION: float = 0.08
const SHAKE_PX: float = 6.0
const SHAKE_SPEED: float = 40.0
const HIT_FLASH_TIME: float = 0.06

@export var drop_item_id: String = DEFAULT_DROP_ITEM_ID

@onready var area: Area2D = $Area2D
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

var _hit_count: int = 0
var _shake_t: float = 0.0
var _flash_t: float = 0.0
var _base_sprite_pos: Vector2

## UID asignado cuando se coloca via PlacementSystem (para WorldSave).
var placed_uid: String = ""
## group_id del campamento bandit dueño de esta hoguera (vacío = colocada por jugador).
var group_id: String = ""


func _ready() -> void:
	_base_sprite_pos = sprite.position
	collision_layer = CollisionLayers.WORLD_WALL_LAYER_MASK | CollisionLayers.RESOURCES_LAYER_MASK
	collision_mask = 0
	area.collision_layer = CollisionLayers.RESOURCES_LAYER_MASK
	area.collision_mask = 0

	if placed_uid == "":
		return
	var persisted := WorldSave.get_placed_entity_data(placed_uid)
	if persisted.is_empty():
		sync_persistence_data()
		return
	apply_persistence_data(persisted)


func _physics_process(delta: float) -> void:
	if _shake_t > 0.0:
		_shake_t -= delta
		var off: float = sin((SHAKE_DURATION - _shake_t) * SHAKE_SPEED) * SHAKE_PX
		sprite.position = _base_sprite_pos + Vector2(off, 0.0)
		if _shake_t <= 0.0:
			sprite.position = _base_sprite_pos

	if _flash_t > 0.0:
		_flash_t -= delta
		if _flash_t <= 0.0:
			sprite.modulate = Color.WHITE


func hit(_by: Node) -> void:
	_hit_count += 1
	_play_hit_feedback()
	sync_persistence_data()
	if _hit_count >= MAX_HITS:
		_destroy()


func _play_hit_feedback() -> void:
	_shake_t = SHAKE_DURATION
	_flash_t = HIT_FLASH_TIME
	sprite.modulate = Color(0.8, 0.8, 0.8, 1.0)


func _destroy() -> void:
	_play_break_sfx()

	var world_node := get_parent()
	if world_node == null:
		world_node = get_tree().current_scene

	var overrides := {"drop_scene": ITEM_DROP_SCENE}
	var resolved_drop_item_id := drop_item_id.strip_edges()
	if resolved_drop_item_id == "":
		resolved_drop_item_id = DEFAULT_DROP_ITEM_ID
	LootSystem.spawn_drop(null, resolved_drop_item_id, 1, global_position, world_node, overrides)

	if placed_uid != "":
		WorldSave.erase_placed_entity_data(placed_uid)
		PlacementSystem.remove_placed_entity(placed_uid)

	if group_id != "":
		FactionViabilitySystem.notify_campfire_destroyed(group_id, get_parent())

	queue_free()


func get_persistence_data() -> Dictionary:
	return {
		"uid": placed_uid,
		"hit_count": _hit_count,
	}


func apply_persistence_data(data: Dictionary) -> void:
	_hit_count = int(data.get("hit_count", 0))
	sync_persistence_data()


func sync_persistence_data() -> void:
	if placed_uid == "":
		return
	WorldSave.set_placed_entity_data(placed_uid, get_persistence_data())


func load_persisted_data() -> void:
	if placed_uid == "":
		_hit_count = 0
		return
	var persisted := WorldSave.get_placed_entity_data(placed_uid)
	if persisted.is_empty():
		_hit_count = 0
		sync_persistence_data()
		return
	apply_persistence_data(persisted)


func _play_break_sfx() -> void:
	var break_sfx := _resolve_break_sfx()
	if break_sfx == null:
		return
	AudioSystem.play_2d(break_sfx, global_position, null, &"SFX", DEFAULT_BREAK_VOLUME_DB)


func _resolve_break_sfx() -> AudioStream:
	if AudioSystem == null or not AudioSystem.has_method("get_sound_panel"):
		return DEFAULT_BREAK_SFX
	var panel: Node = AudioSystem.get_sound_panel()
	if panel != null and panel.has_method("get") and panel.get("player_wall_break_sfx") != null:
		return panel.get("player_wall_break_sfx") as AudioStream
	return DEFAULT_BREAK_SFX
