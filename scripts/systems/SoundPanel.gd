class_name SoundPanel
extends Node

const DEFAULT_SLASH_SWING_SFX: AudioStream = preload("res://art/Sounds/windslash.ogg")
const DEFAULT_IMPACT_SFX: AudioStream = preload("res://art/Sounds/impact.ogg")
const DEFAULT_BOW_DRAW_SFX: AudioStream = preload("res://art/Sounds/bow1.ogg")
const DEFAULT_BOW_RELEASE_SFX: AudioStream = preload("res://art/Sounds/bow2.ogg")
const DEFAULT_TREE_WIND_SFX: AudioStream = preload("res://art/Sounds/windsound.ogg")
const DEFAULT_GRASS_DESTROY_SFX: AudioStream = preload("res://art/Sounds/grassdestroy.ogg")

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

@export_group("Ambience - Tree Wind")
@export var tree_wind_loop_sfx: AudioStream = DEFAULT_TREE_WIND_SFX
@export_range(-80.0, 12.0, 0.5, "suffix:dB") var tree_wind_loop_volume_db: float = -6.0

@export_group("World - Player Walls")
@export var player_wall_hit_sfx_pool: Array[AudioStream] = [
	preload("res://art/Sounds/wood1.ogg"),
	preload("res://art/Sounds/wood2.ogg"),
]
@export_range(-80.0, 12.0, 0.5, "suffix:dB") var player_wall_hit_volume_db: float = 0.0

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


func get_player_wall_hit_sfx_pool() -> Array[AudioStream]:
	return _collect_valid_streams(player_wall_hit_sfx_pool)


func _collect_valid_streams(pool: Array[AudioStream]) -> Array[AudioStream]:
	var valid: Array[AudioStream] = []
	for stream in pool:
		if stream != null:
			valid.append(stream)
	return valid
