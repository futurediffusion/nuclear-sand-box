extends RefCounted
class_name WallFeedback

const ITEM_DROP_SCENE: PackedScene = preload("res://scenes/items/ItemDrop.tscn")
const TileHitFeedbackScript := preload("res://scripts/systems/TileHitFeedback.gd")

var owner: Node
var walls_tilemap: TileMap
var walls_map_layer: int = 0
var src_walls: int = 2
var tile_to_world_cb: Callable

var player_wall_hit_shake_duration: float = 0.08
var player_wall_hit_shake_px: float = 5.0
var player_wall_hit_shake_speed: float = 40.0
var player_wall_hit_flash_time: float = 0.06
var player_wall_hit_tint: Color = Color(0.86, 0.76, 0.6, 1.0)

var player_wall_fallback_atlas: Vector2i = Vector2i(0, 0)
var player_wall_fallback_alt: int = 2

func setup(ctx: Dictionary) -> void:
	owner = ctx.get("owner")
	walls_tilemap = ctx.get("walls_tilemap")
	walls_map_layer = int(ctx.get("walls_map_layer", walls_map_layer))
	src_walls = int(ctx.get("src_walls", src_walls))
	tile_to_world_cb = ctx.get("tile_to_world", Callable())

	player_wall_hit_shake_duration = float(ctx.get("player_wall_hit_shake_duration", player_wall_hit_shake_duration))
	player_wall_hit_shake_px = float(ctx.get("player_wall_hit_shake_px", player_wall_hit_shake_px))
	player_wall_hit_shake_speed = float(ctx.get("player_wall_hit_shake_speed", player_wall_hit_shake_speed))
	player_wall_hit_flash_time = float(ctx.get("player_wall_hit_flash_time", player_wall_hit_flash_time))
	player_wall_hit_tint = Color(ctx.get("player_wall_hit_tint", player_wall_hit_tint))
	player_wall_fallback_atlas = Vector2i(ctx.get("player_wall_fallback_atlas", player_wall_fallback_atlas))
	player_wall_fallback_alt = int(ctx.get("player_wall_fallback_alt", player_wall_fallback_alt))

func play_player_wall_hit_feedback(tile_pos: Vector2i, audio_ctx: Dictionary = {}) -> void:
	_play_player_wall_hit_sfx(tile_pos, audio_ctx)
	_spawn_player_wall_hit_shake(tile_pos)

func play_structural_wall_hit_feedback(tile_pos: Vector2i, audio_ctx: Dictionary = {}) -> void:
	_play_player_wall_hit_sfx(tile_pos, audio_ctx)

func play_player_wall_drop_feedback(tile_pos: Vector2i, drop_item_id: String, drop_amount: int, drop_scene: PackedScene = ITEM_DROP_SCENE) -> void:
	if drop_item_id.strip_edges() == "":
		return
	if drop_amount <= 0:
		return
	if not tile_to_world_cb.is_valid():
		return
	var origin_raw: Variant = tile_to_world_cb.call(tile_pos)
	if not (origin_raw is Vector2):
		return
	var origin: Vector2 = (origin_raw as Vector2) + Vector2(0.0, -10.0)
	var overrides := {"drop_scene": drop_scene}
	LootSystem.spawn_drop(null, drop_item_id, drop_amount, origin, owner, overrides)

func _play_player_wall_hit_sfx(tile_pos: Vector2i, audio_ctx: Dictionary) -> void:
	var sfx := _pick_player_wall_hit_sound(audio_ctx)
	if sfx == null:
		return
	if not tile_to_world_cb.is_valid():
		return
	var sfx_pos_raw: Variant = tile_to_world_cb.call(tile_pos)
	if not (sfx_pos_raw is Vector2):
		return
	var sfx_pos: Vector2 = sfx_pos_raw as Vector2
	var volume_db: float = float(audio_ctx.get("player_wall_hit_volume_db", 0.0))
	AudioSystem.play_2d(sfx, sfx_pos, owner, &"SFX", volume_db)

func _pick_player_wall_hit_sound(audio_ctx: Dictionary) -> AudioStream:
	var pool_raw: Variant = audio_ctx.get("player_wall_hit_sounds", [])
	if typeof(pool_raw) != TYPE_ARRAY:
		return null
	var pool: Array = pool_raw as Array
	var valid: Array[AudioStream] = []
	for stream in pool:
		if stream is AudioStream and stream != null:
			valid.append(stream as AudioStream)
	if valid.is_empty():
		return null
	return valid[randi() % valid.size()]

func _spawn_player_wall_hit_shake(tile_pos: Vector2i) -> void:
	if walls_tilemap == null:
		return
	var source_id: int = walls_tilemap.get_cell_source_id(walls_map_layer, tile_pos)
	var atlas_coords: Vector2i = walls_tilemap.get_cell_atlas_coords(walls_map_layer, tile_pos)
	if atlas_coords.x < 0 or atlas_coords.y < 0:
		atlas_coords = player_wall_fallback_atlas
	var alternative_tile: int = walls_tilemap.get_cell_alternative_tile(walls_map_layer, tile_pos)
	var feedback_result: Dictionary = TileHitFeedbackScript.spawn_tile_hit_feedback(
		owner,
		walls_tilemap,
		walls_map_layer,
		tile_pos,
		{
			"source_id": source_id,
			"fallback_source_id": src_walls,
			"atlas_coords": atlas_coords,
			"alternative_tile": alternative_tile,
			"fallback_atlas": player_wall_fallback_atlas,
			"fallback_alternative_tile": player_wall_fallback_alt,
			"shake_duration": player_wall_hit_shake_duration,
			"shake_speed": player_wall_hit_shake_speed,
			"shake_px": player_wall_hit_shake_px,
			"flash_time": player_wall_hit_flash_time,
			"tint": player_wall_hit_tint,
			"z_index": max(walls_tilemap.z_index + 2, 7),
		}
	)
	if bool(feedback_result.get("ok", false)):
		return
	if Debug.is_enabled("wall"):
		var reason: String = String(feedback_result.get("reason", "unknown"))
		Debug.log("wall", "wallwood shake skipped at %s reason=%s" % [str(tile_pos), reason])
