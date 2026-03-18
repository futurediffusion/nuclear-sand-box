extends StaticBody2D
class_name ContainerPlaceable

const MAX_HITS: int = 4
const ITEM_DROP_SCENE: PackedScene = preload("res://scenes/items/ItemDrop.tscn")
const DEFAULT_CLOSED_TEXTURE: Texture2D = preload("res://art/sprites/chestclosed.png")
const DEFAULT_OPEN_TEXTURE: Texture2D = preload("res://art/sprites/chestopen.png")
const DEFAULT_BREAK_SFX: AudioStream = preload("res://art/Sounds/woodwallbreak.ogg")
const DEFAULT_BREAK_VOLUME_DB: float = 0.0

const SHAKE_DURATION: float = 0.08
const SHAKE_PX: float = 6.0
const SHAKE_SPEED: float = 40.0
const HIT_FLASH_TIME: float = 0.06

@export var closed_texture: Texture2D = DEFAULT_CLOSED_TEXTURE
@export var open_texture: Texture2D = DEFAULT_OPEN_TEXTURE
@export var drop_item_id: String = "chest"
@export var container_group: StringName = &"chest"
@export var max_slots: int = 15
@export var max_stack: int = 10
@export var locked: bool = false
@export var loot_profile: StringName = &""
@export var break_behavior: StringName = &"drop_contents"

@onready var chest_area: Area2D = $chestarea
@onready var chest_sprite: Sprite2D = $chestsprite
@onready var interact_icon: Sprite2D = $Sprite2D2

var _player_inside: bool = false
var _ui_open: bool = false
var _hit_count: int = 0
var _shake_t: float = 0.0
var _flash_t: float = 0.0
var _base_sprite_pos: Vector2

## UID asignado cuando se coloca via PlacementSystem (para WorldSave).
var placed_uid: String = ""

## Hooks de persistencia por UID (contenido interno serializable).
var stored_slots: Array = []


func _ready() -> void:
	add_to_group("interactable")
	if String(container_group) != "":
		add_to_group(container_group)
	interact_icon.visible = false
	_base_sprite_pos = chest_sprite.position
	_set_open_visual(false)

	collision_layer = CollisionLayers.WORLD_WALL_LAYER_MASK | CollisionLayers.RESOURCES_LAYER_MASK
	collision_mask = 0

	chest_area.collision_layer = CollisionLayers.RESOURCES_LAYER_MASK
	chest_area.collision_mask = 1

	chest_area.body_entered.connect(_on_body_entered)
	chest_area.body_exited.connect(_on_body_exited)
	if placed_uid == "":
		stored_slots.clear()
		return

	var persisted := WorldSave.get_placed_entity_data(placed_uid)
	if persisted.is_empty():
		stored_slots.clear()
		sync_persistence_data()
		return
	apply_persistence_data(persisted)


func _physics_process(delta: float) -> void:
	_refresh_interact_prompt_visibility()
	if _shake_t > 0.0:
		_shake_t -= delta
		var off: float = sin((SHAKE_DURATION - _shake_t) * SHAKE_SPEED) * SHAKE_PX
		chest_sprite.position = _base_sprite_pos + Vector2(off, 0.0)
		if _shake_t <= 0.0:
			chest_sprite.position = _base_sprite_pos

	if _flash_t > 0.0:
		_flash_t -= delta
		if _flash_t <= 0.0:
			chest_sprite.modulate = Color.WHITE


func _input(event: InputEvent) -> void:
	if not _player_inside:
		return
	if UiManager.is_interact_prompt_suppressed():
		return
	if UiManager.is_interact_blocked():
		return
	if not event.is_action_pressed("interact"):
		return

	if _ui_open:
		_close_ui()
	else:
		_open_ui()

	UiManager.block_interact_for(150)
	get_viewport().set_input_as_handled()


func hit(_by: Node) -> void:
	_hit_count += 1
	_play_hit_feedback()
	if _hit_count >= MAX_HITS:
		_destroy()


func _play_hit_feedback() -> void:
	_shake_t = SHAKE_DURATION
	_flash_t = HIT_FLASH_TIME
	chest_sprite.modulate = Color(0.8, 0.8, 0.8, 1.0)


func _destroy() -> void:
	if _ui_open:
		_close_ui()
	_play_break_sfx()

	var world_node := get_parent()
	if world_node == null:
		world_node = get_tree().current_scene

	var overrides := {
		"drop_scene": ITEM_DROP_SCENE,
		"scatter_mode": "prop_radial_short",
	}
	var resolved_drop_item_id := drop_item_id.strip_edges()
	if resolved_drop_item_id == "":
		resolved_drop_item_id = BuildableCatalog.resolve_runtime_item_id(BuildableCatalog.ID_CHEST)
	LootSystem.spawn_drop(null, resolved_drop_item_id, 1, global_position, world_node, overrides)
	_drop_internal_contents(world_node, overrides)

	if placed_uid != "":
		WorldSave.erase_placed_entity_data(placed_uid)
		PlacementSystem.remove_placed_entity(placed_uid)

	queue_free()


func _drop_internal_contents(world_node: Node, overrides: Dictionary) -> void:
	for i in range(stored_slots.size()):
		var raw_slot: Variant = stored_slots[i]
		if not (raw_slot is Dictionary):
			continue
		var slot := raw_slot as Dictionary
		var item_id := String(slot.get("id", ""))
		var amount := int(slot.get("count", 0))
		if item_id == "":
			item_id = String(slot.get("item_id", ""))
			amount = int(slot.get("amount", 0))
		if item_id == "" or amount <= 0:
			continue
		LootSystem.spawn_drop(null, item_id, amount, global_position, world_node, overrides)
	stored_slots.clear()


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	_player_inside = true
	_refresh_interact_prompt_visibility()


func _on_body_exited(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	_player_inside = false
	_refresh_interact_prompt_visibility()
	if _ui_open:
		_close_ui()


func _refresh_interact_prompt_visibility() -> void:
	interact_icon.visible = _player_inside and (not UiManager.is_interact_prompt_suppressed())


func _open_ui() -> void:
	var ui := _get_container_ui()
	if ui == null:
		return
	if ui.has_method("open_menu"):
		ui.call("open_menu", self)
	else:
		ui.visible = true
		UiManager.open_ui("chest")
		UiManager.push_combat_block()
	_ui_open = true
	_set_open_visual(true)
	sync_persistence_data()


func _close_ui() -> void:
	var ui := _get_container_ui()
	if ui != null:
		if ui.has_method("close_menu"):
			ui.call("close_menu")
		else:
			ui.visible = false
			UiManager.close_ui("chest")
			UiManager.pop_combat_block()
	_ui_open = false
	_set_open_visual(false)
	sync_persistence_data()


func _set_open_visual(is_open: bool) -> void:
	var closed_tex := closed_texture if closed_texture != null else DEFAULT_CLOSED_TEXTURE
	var open_tex := open_texture if open_texture != null else closed_tex
	chest_sprite.texture = open_tex if is_open else closed_tex


func on_ui_closed_from_ui_layer() -> void:
	if not _ui_open:
		return
	_ui_open = false
	_set_open_visual(false)
	sync_persistence_data()


func _get_container_ui() -> CanvasLayer:
	var scene := get_tree().current_scene
	if scene != null:
		var by_container_path := scene.get_node_or_null("UI/ContainerUi") as CanvasLayer
		if by_container_path != null:
			return by_container_path
		var by_path := scene.get_node_or_null("UI/ChestUi") as CanvasLayer
		if by_path != null:
			return by_path
	for node in get_tree().get_nodes_in_group("container_ui"):
		if node is CanvasLayer:
			return node as CanvasLayer
	for node in get_tree().get_nodes_in_group("chest_ui"):
		if node is CanvasLayer:
			return node as CanvasLayer
	return null


func _get_chest_ui() -> CanvasLayer:
	return _get_container_ui()


func has_player_nearby() -> bool:
	return _player_inside

## Returns true if [pos] is within the chest's interaction area.
## Used by non-player characters that do not trigger the Area2D mask.
func is_position_nearby(pos: Vector2) -> bool:
	# chest_area is 52×40 centered ~(16,21) from origin; far corner ~59px from root.
	# Use 70px to cover all approach angles with margin.
	return global_position.distance_to(pos) <= 70.0


## Inserts up to [amount] of [item_id] into available slots.
## Returns the actually inserted amount. Syncs persistence if anything was inserted.
func try_insert_item(item_id: String, amount: int) -> int:
	if item_id == "" or amount <= 0:
		return 0
	var remaining := amount
	# Stack onto existing matching slots
	for i in range(stored_slots.size()):
		if remaining <= 0:
			break
		var slot = stored_slots[i]
		if slot is Dictionary and String(slot.get("id", "")) == item_id:
			var current: int = int(slot.get("count", 0))
			var space := max_stack - current
			if space > 0:
				var add := mini(space, remaining)
				stored_slots[i] = {"id": item_id, "count": current + add}
				remaining -= add
	# Fill empty/null slots
	for i in range(stored_slots.size()):
		if remaining <= 0:
			break
		if stored_slots[i] == null:
			var add := mini(max_stack, remaining)
			stored_slots[i] = {"id": item_id, "count": add}
			remaining -= add
	# Append new slots if under max_slots
	while remaining > 0 and stored_slots.size() < max_slots:
		var add := mini(max_stack, remaining)
		stored_slots.append({"id": item_id, "count": add})
		remaining -= add
	var inserted := amount - remaining
	if inserted > 0:
		sync_persistence_data()
	return inserted


func get_container_max_slots() -> int:
	return maxi(1, max_slots)


func get_container_max_stack() -> int:
	return maxi(1, max_stack)


func get_persistence_data() -> Dictionary:
	return {
		"uid": placed_uid,
		"stored_slots": stored_slots.duplicate(true),
		"hit_count": _hit_count,
	}


func apply_persistence_data(data: Dictionary) -> void:
	stored_slots.clear()
	var persisted_slots := data.get("stored_slots", []) as Array
	for slot in persisted_slots:
		if slot is Dictionary:
			stored_slots.append((slot as Dictionary).duplicate(true))
		elif slot == null:
			stored_slots.append(null)
	_hit_count = int(data.get("hit_count", 0))
	sync_persistence_data()


func sync_persistence_data() -> void:
	if placed_uid == "":
		return
	WorldSave.set_placed_entity_data(placed_uid, get_persistence_data())


func load_persisted_data() -> void:
	if placed_uid == "":
		stored_slots.clear()
		return
	var persisted := WorldSave.get_placed_entity_data(placed_uid)
	if persisted.is_empty():
		stored_slots.clear()
		sync_persistence_data()
		return
	apply_persistence_data(persisted)


func _play_break_sfx() -> void:
	var break_sfx := _resolve_player_wall_break_sfx()
	if break_sfx == null:
		return
	var break_volume_db := _resolve_player_wall_break_volume_db()
	AudioSystem.play_2d(break_sfx, global_position, null, &"SFX", break_volume_db)


func _resolve_player_wall_break_sfx() -> AudioStream:
	var panel := _resolve_sound_panel()
	if panel != null and panel.player_wall_break_sfx != null:
		return panel.player_wall_break_sfx
	return DEFAULT_BREAK_SFX


func _resolve_player_wall_break_volume_db() -> float:
	var panel := _resolve_sound_panel()
	if panel != null:
		return panel.player_wall_break_volume_db
	return DEFAULT_BREAK_VOLUME_DB


func _resolve_sound_panel() -> SoundPanel:
	if AudioSystem == null or not AudioSystem.has_method("get_sound_panel"):
		return null
	var node: Node = AudioSystem.get_sound_panel()
	if node is SoundPanel:
		return node as SoundPanel
	return null
