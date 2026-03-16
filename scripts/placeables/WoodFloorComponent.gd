extends Node2D
class_name WoodFloorWorld

const MAX_HITS: int = 4
const ITEM_DROP_SCENE: PackedScene = preload("res://scenes/items/ItemDrop.tscn")
const PICKAXE_IDS: Array[String] = ["pickaxe_wood", "pickaxe_stone", "pickaxe_copper"]

const SHAKE_DURATION: float = 0.08
const SHAKE_PX: float = 6.0
const SHAKE_SPEED: float = 40.0
const HIT_FLASH_TIME: float = 0.06

@export var drop_item_id: String = "floorwood"

@onready var floor_sprite: Sprite2D = $floorsprite
@onready var hit_area: Area2D = $hitarea

var _hit_count: int = 0
var _shake_t: float = 0.0
var _flash_t: float = 0.0
var _base_sprite_pos: Vector2

## UID asignado cuando se coloca via PlacementSystem (para WorldSave).
var placed_uid: String = ""


func _ready() -> void:
	z_index = -1
	_base_sprite_pos = floor_sprite.position
	hit_area.collision_layer = CollisionLayers.RESOURCES_LAYER_MASK
	hit_area.collision_mask = 0

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
		floor_sprite.position = _base_sprite_pos + Vector2(off, 0.0)
		if _shake_t <= 0.0:
			floor_sprite.position = _base_sprite_pos

	if _flash_t > 0.0:
		_flash_t -= delta
		if _flash_t <= 0.0:
			floor_sprite.modulate = Color.WHITE


func hit(by: Node) -> void:
	if not _can_mine_with_pickaxe(by):
		return
	_hit_count += 1
	_play_hit_feedback()
	sync_persistence_data()
	if _hit_count >= MAX_HITS:
		_destroy()


func _can_mine_with_pickaxe(by: Node) -> bool:
	if by == null:
		return false
	var wc := by.get_node_or_null("WeaponComponent")
	if wc == null or not wc.has_method("get_current_weapon_id"):
		return false
	var weapon_id := String(wc.call("get_current_weapon_id"))
	return PICKAXE_IDS.has(weapon_id)


func _play_hit_feedback() -> void:
	_shake_t = SHAKE_DURATION
	_flash_t = HIT_FLASH_TIME
	floor_sprite.modulate = Color(0.8, 0.8, 0.8, 1.0)


func _destroy() -> void:
	var world_node := get_parent()
	if world_node == null:
		world_node = get_tree().current_scene

	var overrides := {"drop_scene": ITEM_DROP_SCENE}
	var resolved_drop_item_id := drop_item_id.strip_edges()
	if resolved_drop_item_id == "":
		resolved_drop_item_id = "floorwood"
	LootSystem.spawn_drop(null, resolved_drop_item_id, 1, global_position, world_node, overrides)

	if placed_uid != "":
		WorldSave.erase_placed_entity_data(placed_uid)
		PlacementSystem.remove_placed_entity(placed_uid)

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


func suppress_default_impact_sound() -> bool:
	return true
