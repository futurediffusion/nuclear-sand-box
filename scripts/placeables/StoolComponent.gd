extends StaticBody2D
class_name StoolWorld

const MAX_HITS: int = 4
const ITEM_DROP_SCENE: PackedScene = preload("res://scenes/items/ItemDrop.tscn")
const DEFAULT_DROP_ITEM_ID: String = "stool"
const DEFAULT_BREAK_SFX: AudioStream = preload("res://art/Sounds/woodwallbreak.ogg")
const DEFAULT_BREAK_VOLUME_DB: float = 0.0
const DEFAULT_STOOL_SIT_SFX: AudioStream = preload("res://art/Sounds/stoolsit.ogg")
const DEFAULT_STOOL_OUT_SFX: AudioStream = preload("res://art/Sounds/stoolout.ogg")
const DEFAULT_STOOL_TOGGLE_VOLUME_DB: float = 0.0

const SHAKE_DURATION: float = 0.08
const SHAKE_PX: float = 6.0
const SHAKE_SPEED: float = 40.0
const HIT_FLASH_TIME: float = 0.06
const DEFAULT_SEAT_OFFSET: Vector2 = Vector2(16.0, 18.0)
const STOOL_Z_BEHIND_PLAYER: int = 0
const STOOL_Z_IN_FRONT_OF_PLAYER: int = 16

@export var drop_item_id: String = DEFAULT_DROP_ITEM_ID
@export var seat_offset: Vector2 = DEFAULT_SEAT_OFFSET
@export var y_sort_pivot_local_y: float = 26.0

@onready var area: Area2D = $Area2D
@onready var sprite: Sprite2D = $Sprite2D
@onready var interact_icon: Sprite2D = $Sprite2D2
@onready var seat_point: Marker2D = $SeatPoint

var _player_inside: bool = false
var _hit_count: int = 0
var _shake_t: float = 0.0
var _flash_t: float = 0.0
var _base_sprite_pos: Vector2
var _seated_player_ref: WeakRef = null
var _runtime_player_ref: WeakRef = null

## UID assigned by PlacementSystem for WorldSave persistence.
var placed_uid: String = ""


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("stool_placeable")
	interact_icon.visible = false
	_base_sprite_pos = sprite.position
	seat_point.position = seat_offset

	collision_layer = CollisionLayers.WORLD_WALL_LAYER_MASK | CollisionLayers.RESOURCES_LAYER_MASK
	collision_mask = 0

	area.collision_layer = CollisionLayers.RESOURCES_LAYER_MASK
	area.collision_mask = 1

	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)

	if placed_uid == "":
		_update_draw_order()
		return
	var persisted := WorldSave.get_placed_entity_data(placed_uid)
	if persisted.is_empty():
		sync_persistence_data()
		_update_draw_order()
		return
	apply_persistence_data(persisted)
	_update_draw_order()


func _process(_delta: float) -> void:
	_refresh_interact_prompt_visibility()
	_update_draw_order()


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


func _input(event: InputEvent) -> void:
	if UiManager.is_interact_blocked():
		return
	if not event.is_action_pressed("interact"):
		return

	var player := _resolve_player_for_interact()
	if player == null:
		return
	if not player.has_method("toggle_stool_seat"):
		return

	var now_sitting := bool(player.call("toggle_stool_seat", self, _get_seat_world_position()))
	_update_seated_player_tracking(player)
	_play_stool_toggle_sfx(now_sitting)
	UiManager.block_interact_for(150)
	get_viewport().set_input_as_handled()


func hit(_by: Node) -> void:
	_hit_count += 1
	_play_hit_feedback()
	sync_persistence_data()
	if _hit_count >= MAX_HITS:
		_destroy()


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


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	_player_inside = true
	_runtime_player_ref = weakref(body)
	_refresh_interact_prompt_visibility()
	_update_draw_order()


func _on_body_exited(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	_player_inside = false
	if _runtime_player_ref != null:
		var cached: Node = _runtime_player_ref.get_ref() as Node
		if cached == body:
			_runtime_player_ref = null
	_refresh_interact_prompt_visibility()
	_update_draw_order()


func _play_hit_feedback() -> void:
	_shake_t = SHAKE_DURATION
	_flash_t = HIT_FLASH_TIME
	sprite.modulate = Color(0.8, 0.8, 0.8, 1.0)


func _destroy() -> void:
	_force_unseat_player()
	_play_break_sfx()

	var world_node := get_parent()
	if world_node == null:
		world_node = get_tree().current_scene

	var overrides := {"drop_scene": ITEM_DROP_SCENE}
	var resolved_drop_item_id := BuildableCatalog.resolve_drop_item_id(drop_item_id, BuildableCatalog.ID_STOOL)
	LootSystem.spawn_drop(null, resolved_drop_item_id, 1, global_position, world_node, overrides)

	if placed_uid != "":
		WorldSave.erase_placed_entity_data(placed_uid)
		PlacementSystem.remove_placed_entity(placed_uid)

	queue_free()


func _exit_tree() -> void:
	_force_unseat_player()


func _resolve_player_for_interact() -> Node:
	var seated := _get_seated_player()
	if seated != null:
		return seated
	if not _player_inside:
		return null
	for node in get_tree().get_nodes_in_group("player"):
		if node is Node:
			return node as Node
	return null


func _get_seat_world_position() -> Vector2:
	if seat_point != null and is_instance_valid(seat_point):
		return seat_point.global_position
	return global_position + seat_offset


func _get_seated_player() -> Node:
	if _seated_player_ref == null:
		return null
	var player: Node = _seated_player_ref.get_ref() as Node
	if player == null or not is_instance_valid(player):
		_seated_player_ref = null
		return null
	return player


func _get_runtime_player() -> Node2D:
	if _runtime_player_ref != null:
		var cached: Node2D = _runtime_player_ref.get_ref() as Node2D
		if cached != null and is_instance_valid(cached):
			return cached
		_runtime_player_ref = null
	for node in get_tree().get_nodes_in_group("player"):
		if node is Node2D:
			var player := node as Node2D
			_runtime_player_ref = weakref(player)
			return player
	return null


func _update_seated_player_tracking(player: Node) -> void:
	if player == null or not player.has_method("is_seated_on"):
		_seated_player_ref = null
		_refresh_interact_prompt_visibility()
		return
	var is_on_this: bool = bool(player.call("is_seated_on", self))
	if is_on_this:
		_seated_player_ref = weakref(player)
	else:
		_seated_player_ref = null
	_refresh_interact_prompt_visibility()


func _refresh_interact_prompt_visibility() -> void:
	interact_icon.visible = _player_inside and (not UiManager.is_interact_prompt_suppressed())


func _is_player_still_seated_on_this(player: Node) -> bool:
	if player == null or not player.has_method("is_seated_on"):
		return false
	return bool(player.call("is_seated_on", self))


func _force_unseat_player() -> void:
	var player := _get_seated_player()
	if player == null:
		return
	if player.has_method("force_leave_seat"):
		player.call("force_leave_seat")
	_seated_player_ref = null
	_refresh_interact_prompt_visibility()
	_update_draw_order()


func _update_draw_order() -> void:
	var player := _get_runtime_player()
	if player == null:
		z_index = STOOL_Z_BEHIND_PLAYER
		return
	if _is_player_still_seated_on_this(player):
		# Sentado: player siempre por encima del stool.
		z_index = STOOL_Z_BEHIND_PLAYER
		return
	var stool_pivot_world_y := global_position.y + y_sort_pivot_local_y
	var player_world_y := player.global_position.y
	if player_world_y < stool_pivot_world_y:
		# Player arriba del stool: el stool queda delante.
		z_index = STOOL_Z_IN_FRONT_OF_PLAYER
	else:
		# Player abajo del stool: el player queda delante.
		z_index = STOOL_Z_BEHIND_PLAYER


func _play_break_sfx() -> void:
	var break_sfx := _resolve_player_wall_break_sfx()
	if break_sfx == null:
		return
	var break_volume_db := _resolve_player_wall_break_volume_db()
	AudioSystem.play_2d(break_sfx, global_position, null, &"SFX", break_volume_db)


func _play_stool_toggle_sfx(now_sitting: bool) -> void:
	var stream: AudioStream = DEFAULT_STOOL_SIT_SFX if now_sitting else DEFAULT_STOOL_OUT_SFX
	var volume_db: float = DEFAULT_STOOL_TOGGLE_VOLUME_DB
	var panel := _resolve_sound_panel()
	if panel != null:
		if now_sitting:
			if panel.stool_sit_sfx != null:
				stream = panel.stool_sit_sfx
			volume_db = panel.stool_sit_volume_db
		else:
			if panel.stool_out_sfx != null:
				stream = panel.stool_out_sfx
			volume_db = panel.stool_out_volume_db
	if stream == null:
		return
	AudioSystem.play_2d(stream, global_position + Vector2(16.0, 16.0), null, &"SFX", volume_db)


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
