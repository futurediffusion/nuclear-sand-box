extends StaticBody2D
class_name DoorWorld

const MAX_HITS: int = 4
const ITEM_DROP_SCENE: PackedScene = preload("res://scenes/items/ItemDrop.tscn")
const DEFAULT_CLOSED_TEXTURE: Texture2D = preload("res://art/placeables/doorwoodclose.png")
const DEFAULT_OPEN_TEXTURE: Texture2D = preload("res://art/placeables/doorwoodopen.png")
const DEFAULT_DOOR_OPEN_SFX: AudioStream = preload("res://art/Sounds/doorwoodopen.ogg")
const DEFAULT_DOOR_CLOSE_SFX: AudioStream = preload("res://art/Sounds/doorwoodclose.ogg")
const DEFAULT_DOOR_SFX_VOLUME_DB: float = 0.0

const SHAKE_DURATION: float = 0.08
const SHAKE_PX: float = 6.0
const SHAKE_SPEED: float = 40.0
const HIT_FLASH_TIME: float = 0.06
const TILE_SIZE: int = 32

@export var closed_texture: Texture2D = DEFAULT_CLOSED_TEXTURE
@export var open_texture: Texture2D = DEFAULT_OPEN_TEXTURE
@export var drop_item_id: String = "doorwood"
@export var starts_open: bool = false
@export var is_mirrored: bool = false
@export var is_vertical_layout: bool = false

@onready var door_collision: CollisionShape2D = $doorcollision
@onready var door_sprite: Sprite2D = $doorsprite
@onready var door_area: Area2D = $doorarea
@onready var interact_icon: Sprite2D = $Sprite2D2

var _player_inside: bool = false
var _is_open: bool = false
var _hit_count: int = 0
var _shake_t: float = 0.0
var _flash_t: float = 0.0
var _base_sprite_pos: Vector2

## UID asignado cuando se coloca via PlacementSystem (para WorldSave).
var placed_uid: String = ""


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("doorwood_placeable")
	z_index = 1
	interact_icon.visible = false
	_base_sprite_pos = door_sprite.position

	collision_layer = CollisionLayers.WORLD_WALL_LAYER_MASK
	collision_mask = 0

	door_area.collision_layer = CollisionLayers.RESOURCES_LAYER_MASK
	door_area.collision_mask = 1

	door_area.body_entered.connect(_on_body_entered)
	door_area.body_exited.connect(_on_body_exited)

	_is_open = starts_open
	if placed_uid == "":
		_apply_mirror_visual()
		_apply_open_state()
		call_deferred("_refresh_double_door_pairing")
		return

	var persisted := WorldSave.get_placed_entity_data(placed_uid)
	if persisted.is_empty():
		_apply_mirror_visual()
		_apply_open_state()
		sync_persistence_data()
		call_deferred("_refresh_double_door_pairing")
		return
	apply_persistence_data(persisted)
	call_deferred("_refresh_double_door_pairing")


func _physics_process(delta: float) -> void:
	if _shake_t > 0.0:
		_shake_t -= delta
		var off: float = sin((SHAKE_DURATION - _shake_t) * SHAKE_SPEED) * SHAKE_PX
		door_sprite.position = _base_sprite_pos + Vector2(off, 0.0)
		if _shake_t <= 0.0:
			door_sprite.position = _base_sprite_pos

	if _flash_t > 0.0:
		_flash_t -= delta
		if _flash_t <= 0.0:
			door_sprite.modulate = Color.WHITE


func _input(event: InputEvent) -> void:
	if not _player_inside:
		return
	if UiManager.is_interact_blocked():
		return
	if not event.is_action_pressed("interact"):
		return

	_refresh_double_door_pairing()
	_set_open_state(not _is_open, true)
	sync_persistence_data()
	UiManager.block_interact_for(150)
	get_viewport().set_input_as_handled()


func hit(_by: Node) -> void:
	_hit_count += 1
	_play_hit_feedback()
	sync_persistence_data()
	if _hit_count >= MAX_HITS:
		_destroy()


func _play_hit_feedback() -> void:
	_shake_t = SHAKE_DURATION
	_flash_t = HIT_FLASH_TIME
	door_sprite.modulate = Color(0.8, 0.8, 0.8, 1.0)


func _destroy() -> void:
	var tile_pos := _get_tile_pos()
	var world_node := get_parent()
	if world_node == null:
		world_node = get_tree().current_scene

	var overrides := {"drop_scene": ITEM_DROP_SCENE}
	var resolved_drop_item_id := drop_item_id.strip_edges()
	if resolved_drop_item_id == "":
		resolved_drop_item_id = BuildableCatalog.resolve_runtime_item_id(BuildableCatalog.ID_DOORWOOD)
	LootSystem.spawn_drop(null, resolved_drop_item_id, 1, global_position, world_node, overrides)

	if placed_uid != "":
		WorldSave.erase_placed_entity_data(placed_uid)
		PlacementSystem.remove_placed_entity(placed_uid)
		if PlacementSystem != null and PlacementSystem.has_method("refresh_door_pairing_around_tile"):
			PlacementSystem.call("refresh_door_pairing_around_tile", tile_pos)

	queue_free()


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	_player_inside = true
	interact_icon.visible = true


func _on_body_exited(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	_player_inside = false
	interact_icon.visible = false


func _set_open_state(is_open: bool, play_sfx: bool = false) -> void:
	var changed := (_is_open != is_open)
	_is_open = is_open
	_apply_open_state()
	if play_sfx and changed:
		_play_toggle_sfx()

func set_mirrored(value: bool, persist: bool = true) -> void:
	if is_mirrored == value:
		return
	is_mirrored = value
	_apply_mirror_visual()
	if persist:
		sync_persistence_data()

func set_vertical_layout(value: bool, persist: bool = true) -> void:
	if is_vertical_layout == value:
		return
	is_vertical_layout = value
	_apply_open_state()
	if persist:
		sync_persistence_data()


func _apply_open_state() -> void:
	var closed_tex := closed_texture if closed_texture != null else DEFAULT_CLOSED_TEXTURE
	var open_tex := open_texture if open_texture != null else closed_tex
	var visual_open := _is_open
	if is_vertical_layout:
		# Vertical layout invierte solo la apariencia; la fisica sigue la logica real.
		visual_open = not visual_open
	door_sprite.texture = open_tex if visual_open else closed_tex
	door_collision.disabled = _is_open


func _apply_mirror_visual() -> void:
	var closed_tex := closed_texture if closed_texture != null else DEFAULT_CLOSED_TEXTURE
	var door_width: float = float(TILE_SIZE)
	if closed_tex != null:
		door_width = float(closed_tex.get_width())
	door_sprite.scale.x = -1.0 if is_mirrored else 1.0
	door_sprite.position.x = door_width if is_mirrored else 0.0
	_base_sprite_pos = door_sprite.position


func _play_toggle_sfx() -> void:
	var stream: AudioStream = null
	var volume_db: float = DEFAULT_DOOR_SFX_VOLUME_DB
	var panel := _resolve_sound_panel()
	if panel != null:
		if _is_open:
			stream = panel.door_open_sfx
			volume_db = panel.door_open_volume_db
		else:
			stream = panel.door_close_sfx
			volume_db = panel.door_close_volume_db
	else:
		stream = DEFAULT_DOOR_OPEN_SFX if _is_open else DEFAULT_DOOR_CLOSE_SFX
	if stream == null:
		return
	AudioSystem.play_2d(stream, global_position + Vector2(16.0, 16.0), null, &"SFX", volume_db)


func _resolve_sound_panel() -> SoundPanel:
	if AudioSystem == null or not AudioSystem.has_method("get_sound_panel"):
		return null
	var node: Node = AudioSystem.get_sound_panel()
	if node is SoundPanel:
		return node as SoundPanel
	return null


func get_persistence_data() -> Dictionary:
	return {
		"uid": placed_uid,
		"is_open": _is_open,
		"hit_count": _hit_count,
		"is_mirrored": is_mirrored,
		"is_vertical_layout": is_vertical_layout,
	}


func apply_persistence_data(data: Dictionary) -> void:
	is_mirrored = bool(data.get("is_mirrored", is_mirrored))
	is_vertical_layout = bool(data.get("is_vertical_layout", is_vertical_layout))
	_apply_mirror_visual()
	_is_open = bool(data.get("is_open", starts_open))
	_hit_count = int(data.get("hit_count", 0))
	_apply_open_state()
	sync_persistence_data()


func sync_persistence_data() -> void:
	if placed_uid == "":
		return
	WorldSave.set_placed_entity_data(placed_uid, get_persistence_data())


func load_persisted_data() -> void:
	if placed_uid == "":
		_is_open = starts_open
		_hit_count = 0
		_apply_mirror_visual()
		_apply_open_state()
		return
	var persisted := WorldSave.get_placed_entity_data(placed_uid)
	if persisted.is_empty():
		_is_open = starts_open
		_hit_count = 0
		_apply_mirror_visual()
		_apply_open_state()
		sync_persistence_data()
		return
	apply_persistence_data(persisted)


func _refresh_double_door_pairing() -> void:
	if PlacementSystem == null:
		return
	if not PlacementSystem.has_method("refresh_door_pairing_around_tile"):
		return
	PlacementSystem.call("refresh_door_pairing_around_tile", _get_tile_pos())


func _get_tile_pos() -> Vector2i:
	return Vector2i(
		floori(position.x / float(TILE_SIZE)),
		floori(position.y / float(TILE_SIZE))
	)
