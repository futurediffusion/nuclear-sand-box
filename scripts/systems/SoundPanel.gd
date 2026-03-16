class_name SoundPanel
extends Node

const DEFAULT_SLASH_SWING_SFX: AudioStream = preload("res://art/Sounds/windslash.ogg")
const DEFAULT_IMPACT_SFX: AudioStream = preload("res://art/Sounds/impact.ogg")
const DEFAULT_BOW_DRAW_SFX: AudioStream = preload("res://art/Sounds/bow1.ogg")
const DEFAULT_BOW_RELEASE_SFX: AudioStream = preload("res://art/Sounds/bow2.ogg")
const DEFAULT_TREE_WIND_SFX: AudioStream = preload("res://art/Sounds/windsound.ogg")
const DEFAULT_GRASS_DESTROY_SFX: AudioStream = preload("res://art/Sounds/grassdestroy.ogg")
const DEFAULT_DOOR_OPEN_SFX: AudioStream = preload("res://art/Sounds/doorwoodopen.ogg")
const DEFAULT_DOOR_CLOSE_SFX: AudioStream = preload("res://art/Sounds/doorwoodclose.ogg")
const DEFAULT_DOOR_PLACE_SFX: AudioStream = preload("res://art/Sounds/doorplace.ogg")
const DEFAULT_INVENTORY_OPEN_SFX: AudioStream = preload("res://art/Sounds/inventoryopen.ogg")
const DEFAULT_INVENTORY_CLOSE_SFX: AudioStream = preload("res://art/Sounds/inventoryclose.ogg")
const DEFAULT_INVENTORY_ITEM_SELECT_SFX: AudioStream = preload("res://art/Sounds/inventoryitemgrab.ogg")
const DEFAULT_INVENTORY_SHIFT_TRANSFER_SFX: AudioStream = preload("res://art/Sounds/inventoryshifttransfer.ogg")
const DEFAULT_CHEST_OPEN_SFX: AudioStream = preload("res://art/Sounds/chestopen.ogg")
const DEFAULT_CHEST_CLOSE_SFX: AudioStream = preload("res://art/Sounds/chestclose.ogg")
const DEFAULT_WORKBENCH_OPEN_SFX: AudioStream = preload("res://art/Sounds/workbenchopen.ogg")
const DEFAULT_WORKBENCH_CLOSE_SFX: AudioStream = preload("res://art/Sounds/workbenchclose.ogg")
const DEFAULT_WORKBENCH_SELECT_RECIPE_SFX: AudioStream = preload("res://art/Sounds/chooseitem.ogg")
const DEFAULT_WORKBENCH_TAB_SFX: AudioStream = preload("res://art/Sounds/workbenchtab.ogg")
const DEFAULT_WOODWALL_BREAK_SFX: AudioStream = preload("res://art/Sounds/woodwallbreak.ogg")
const DEFAULT_WALKING_GRASS_SFX: AudioStream = preload("res://art/Sounds/walking/walkingongrass.ogg")
const DEFAULT_WALKING_DIRT_SFX: AudioStream = preload("res://art/Sounds/walking/walkingondirt.ogg")
const DEFAULT_WALKING_WOOD_SFX: AudioStream = preload("res://art/Sounds/walking/walkingonfloorwood.ogg")

const WALK_SURFACE_GRASS: StringName = &"grass"
const WALK_SURFACE_DIRT: StringName = &"dirt"
const WALK_SURFACE_WOOD: StringName = &"wood"

@export_group("Melee - Slash")
@export var slash_swing_sfx: AudioStream = DEFAULT_SLASH_SWING_SFX
@export_range(-80.0, 12.0, 0.5, "suffix:dB") var slash_swing_volume_db: float = 0.0
@export var slash_impact_sfx: AudioStream = DEFAULT_IMPACT_SFX
@export_range(-80.0, 12.0, 0.5, "suffix:dB") var slash_impact_volume_db: float = 0.0

@export_group("Melee - NPC/Enemy Hit")
@export var npc_enemy_hit_sfx: AudioStream = DEFAULT_IMPACT_SFX
@export_range(-80.0, 12.0, 0.5, "suffix:dB") var npc_enemy_hit_volume_db: float = 0.0

@export_group("Resources - Wood")
@export var wood_hit_sfx_pool: Array[AudioStream] = [
	preload("res://art/Sounds/wood1.ogg"),
	preload("res://art/Sounds/wood2.ogg"),
]
@export_range(-80.0, 12.0, 0.5, "suffix:dB") var wood_hit_volume_db: float = 0.0

@export_group("Resources - Stone")
@export var stone_hit_sfx_pool: Array[AudioStream] = [
	preload("res://art/Sounds/stone1.ogg"),
	preload("res://art/Sounds/stone 2.ogg"),
	preload("res://art/Sounds/stone 3.ogg"),
]
@export_range(-80.0, 12.0, 0.5, "suffix:dB") var stone_hit_volume_db: float = 0.0

@export_group("Resources - Grass")
@export var grass_destroy_sfx: AudioStream = DEFAULT_GRASS_DESTROY_SFX
@export_range(-80.0, 12.0, 0.5, "suffix:dB") var grass_destroy_volume_db: float = 0.0
@export var grass_touch_sfx_pool: Array[AudioStream] = [
	preload("res://art/Sounds/grassmove1.ogg"),
	preload("res://art/Sounds/grassmove2.ogg"),
]
@export_range(-80.0, 12.0, 0.5, "suffix:dB") var grass_touch_volume_db: float = 7.5

@export_group("Movement - Walk")
@export var walking_grass_loop_sfx: AudioStream = DEFAULT_WALKING_GRASS_SFX
@export_range(-80.0, 12.0, 0.5, "suffix:dB") var walking_grass_loop_volume_db: float = 0.0
@export var walking_dirt_loop_sfx: AudioStream = DEFAULT_WALKING_DIRT_SFX
@export_range(-80.0, 12.0, 0.5, "suffix:dB") var walking_dirt_loop_volume_db: float = 0.0
@export var walking_wood_loop_sfx: AudioStream = DEFAULT_WALKING_WOOD_SFX
@export_range(-80.0, 12.0, 0.5, "suffix:dB") var walking_wood_loop_volume_db: float = 0.0

@export_group("Items - Pickup")
@export_range(-80.0, 12.0, 0.5, "suffix:dB") var pickup_volume_db: float = 12.0

@export_group("UI - Inventory")
@export var inventory_open_sfx: AudioStream = DEFAULT_INVENTORY_OPEN_SFX
@export_range(-80.0, 12.0, 0.5, "suffix:dB") var inventory_open_volume_db: float = 0.0
@export var inventory_close_sfx: AudioStream = DEFAULT_INVENTORY_CLOSE_SFX
@export_range(-80.0, 12.0, 0.5, "suffix:dB") var inventory_close_volume_db: float = 0.0
@export var inventory_item_select_sfx: AudioStream = DEFAULT_INVENTORY_ITEM_SELECT_SFX
@export_range(-80.0, 12.0, 0.5, "suffix:dB") var inventory_item_select_volume_db: float = 0.0
@export var inventory_shift_transfer_sfx: AudioStream = DEFAULT_INVENTORY_SHIFT_TRANSFER_SFX
@export_range(-80.0, 12.0, 0.5, "suffix:dB") var inventory_shift_transfer_volume_db: float = 0.0

@export_group("UI - Containers")
@export var chest_open_sfx: AudioStream = DEFAULT_CHEST_OPEN_SFX
@export_range(-80.0, 12.0, 0.5, "suffix:dB") var chest_open_volume_db: float = 0.0
@export var chest_close_sfx: AudioStream = DEFAULT_CHEST_CLOSE_SFX
@export_range(-80.0, 12.0, 0.5, "suffix:dB") var chest_close_volume_db: float = 0.0

@export_group("UI - Workbench")
@export var workbench_open_sfx: AudioStream = DEFAULT_WORKBENCH_OPEN_SFX
@export_range(-80.0, 12.0, 0.5, "suffix:dB") var workbench_open_volume_db: float = 0.0
@export var workbench_close_sfx: AudioStream = DEFAULT_WORKBENCH_CLOSE_SFX
@export_range(-80.0, 12.0, 0.5, "suffix:dB") var workbench_close_volume_db: float = 0.0
@export var workbench_select_recipe_sfx: AudioStream = DEFAULT_WORKBENCH_SELECT_RECIPE_SFX
@export_range(-80.0, 12.0, 0.5, "suffix:dB") var workbench_select_recipe_volume_db: float = 0.0
@export var workbench_tab_sfx: AudioStream = DEFAULT_WORKBENCH_TAB_SFX
@export_range(-80.0, 12.0, 0.5, "suffix:dB") var workbench_tab_volume_db: float = 0.0

@export_group("UI - Drag & Drop")
@export var ui_slot_place_sfx_pool: Array[AudioStream] = [
	preload("res://art/Sounds/place1.ogg"),
	preload("res://art/Sounds/place2.ogg"),
	preload("res://art/Sounds/place3.ogg"),
	preload("res://art/Sounds/place4.ogg"),
]
@export_range(-80.0, 12.0, 0.5, "suffix:dB") var ui_slot_place_volume_db: float = 0.0

@export_group("Placement - Hover")
@export_range(-80.0, 12.0, 0.5, "suffix:dB") var placement_hover_volume_db: float = 0.0

@export_group("Placeables - Door")
@export var door_open_sfx: AudioStream = DEFAULT_DOOR_OPEN_SFX
@export_range(-80.0, 12.0, 0.5, "suffix:dB") var door_open_volume_db: float = 0.0
@export var door_close_sfx: AudioStream = DEFAULT_DOOR_CLOSE_SFX
@export_range(-80.0, 12.0, 0.5, "suffix:dB") var door_close_volume_db: float = 0.0
@export var door_place_sfx: AudioStream = DEFAULT_DOOR_PLACE_SFX
@export_range(-80.0, 12.0, 0.5, "suffix:dB") var door_place_volume_db: float = 0.0

@export_group("Ambience - Tree Wind")
@export var tree_wind_loop_sfx: AudioStream = DEFAULT_TREE_WIND_SFX
@export_range(-80.0, 12.0, 0.5, "suffix:dB") var tree_wind_loop_volume_db: float = -6.0

@export_group("World - Player Walls")
@export var player_wall_hit_sfx_pool: Array[AudioStream] = [
	preload("res://art/Sounds/wood1.ogg"),
	preload("res://art/Sounds/wood2.ogg"),
]
@export_range(-80.0, 12.0, 0.5, "suffix:dB") var player_wall_hit_volume_db: float = 0.0
@export var player_wall_break_sfx: AudioStream = DEFAULT_WOODWALL_BREAK_SFX
@export_range(-80.0, 12.0, 0.5, "suffix:dB") var player_wall_break_volume_db: float = 0.0

@export_group("Ranged - Bow")
@export var bow_draw_sfx: AudioStream = DEFAULT_BOW_DRAW_SFX
@export_range(-80.0, 12.0, 0.5, "suffix:dB") var bow_draw_volume_db: float = 0.0
@export var bow_release_sfx: AudioStream = DEFAULT_BOW_RELEASE_SFX
@export_range(-80.0, 12.0, 0.5, "suffix:dB") var bow_release_volume_db: float = 0.0

@export_group("Characters - Enemy")
@export var enemy_death_sfx: AudioStream = DEFAULT_IMPACT_SFX
@export_range(-80.0, 12.0, 0.5, "suffix:dB") var enemy_death_volume_db: float = 2.0


func get_wood_hit_sfx_pool() -> Array[AudioStream]:
	return _collect_valid_streams(wood_hit_sfx_pool)


func get_stone_hit_sfx_pool() -> Array[AudioStream]:
	return _collect_valid_streams(stone_hit_sfx_pool)


func get_grass_touch_sfx_pool() -> Array[AudioStream]:
	return _collect_valid_streams(grass_touch_sfx_pool)


func get_walk_surface_sfx(surface_id: StringName) -> AudioStream:
	match surface_id:
		WALK_SURFACE_DIRT:
			return walking_dirt_loop_sfx
		WALK_SURFACE_WOOD:
			return walking_wood_loop_sfx
		_:
			return walking_grass_loop_sfx


func get_walk_surface_volume_db(surface_id: StringName) -> float:
	match surface_id:
		WALK_SURFACE_DIRT:
			return walking_dirt_loop_volume_db
		WALK_SURFACE_WOOD:
			return walking_wood_loop_volume_db
		_:
			return walking_grass_loop_volume_db


func get_player_wall_hit_sfx_pool() -> Array[AudioStream]:
	return _collect_valid_streams(player_wall_hit_sfx_pool)


func get_ui_slot_place_sfx_pool() -> Array[AudioStream]:
	return _collect_valid_streams(ui_slot_place_sfx_pool)


func _collect_valid_streams(pool: Array[AudioStream]) -> Array[AudioStream]:
	var valid: Array[AudioStream] = []
	for stream in pool:
		if stream != null:
			valid.append(stream)
	return valid
