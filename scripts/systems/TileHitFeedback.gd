class_name TileHitFeedback
extends Node2D

var _ghost: Sprite2D
var _base_pos: Vector2 = Vector2.ZERO
var _shake_duration: float = 0.08
var _shake_speed: float = 40.0
var _shake_px: float = 5.0
var _flash_time: float = 0.06
var _elapsed: float = 0.0
var _flash_elapsed: float = 0.0
var _flash_enabled: bool = false
var _start_tint: Color = Color.WHITE


static func spawn_tile_hit_feedback(
		host: Node,
		tilemap: TileMap,
		layer: int,
		tile_pos: Vector2i,
		options: Dictionary = {}
	) -> Dictionary:
	if host == null:
		return _result(false, "host_missing")
	if tilemap == null:
		return _result(false, "tilemap_missing")

	var ts: TileSet = tilemap.tile_set
	if ts == null:
		return _result(false, "tileset_missing")

	var source_id: int = _resolve_source_id(ts, tilemap, layer, tile_pos, options)
	if source_id == -1:
		return _result(false, "source_missing")

	var atlas_source := ts.get_source(source_id) as TileSetAtlasSource
	if atlas_source == null or atlas_source.texture == null:
		return _result(false, "atlas_source_missing")

	var atlas_data: Dictionary = _resolve_atlas_coords(tilemap, layer, tile_pos, atlas_source, options)
	if not bool(atlas_data.get("ok", false)):
		return _result(false, String(atlas_data.get("reason", "atlas_missing")))
	var atlas_coords: Vector2i = atlas_data.get("atlas_coords", Vector2i.ZERO)

	var alternative_tile: int = int(options.get(
		"alternative_tile",
		tilemap.get_cell_alternative_tile(layer, tile_pos)
	))
	if alternative_tile < 0:
		alternative_tile = int(options.get("fallback_alternative_tile", 0))

	var raw_region_rect: Rect2 = _resolve_region_rect(atlas_source, atlas_coords, alternative_tile)
	var region_rect: Rect2 = _sanitize_region_rect(atlas_source, raw_region_rect)
	if region_rect.size.x <= 0.0 or region_rect.size.y <= 0.0:
		return _result(false, "region_invalid")

	var feedback := TileHitFeedback.new()
	feedback._configure(host, tilemap, tile_pos, atlas_source.texture, region_rect, options)
	host.add_child(feedback)
	return _result(true, "ok", feedback)


func _configure(
		_host: Node,
		tilemap: TileMap,
		tile_pos: Vector2i,
		texture: Texture2D,
		region_rect: Rect2,
		options: Dictionary
	) -> void:
	_ghost = Sprite2D.new()
	_ghost.texture = texture
	_ghost.region_enabled = true
	_ghost.region_rect = region_rect
	_ghost.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ghost.z_as_relative = false
	_ghost.z_index = int(options.get("z_index", tilemap.z_index + 2))
	_start_tint = options.get("tint", Color.WHITE)
	_ghost.modulate = _start_tint
	add_child(_ghost)

	_shake_duration = maxf(float(options.get("shake_duration", 0.08)), 0.01)
	_shake_speed = maxf(float(options.get("shake_speed", 40.0)), 0.01)
	_shake_px = maxf(float(options.get("shake_px", 5.0)), 0.0)
	_flash_time = maxf(float(options.get("flash_time", 0.06)), 0.0)
	_flash_enabled = _flash_time > 0.0

	global_position = options.get("world_position", tilemap.to_global(tilemap.map_to_local(tile_pos)))
	_base_pos = global_position
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(_ghost):
		queue_free()
		return

	_elapsed += delta
	var phase: float = _elapsed * _shake_speed
	var offset_x: float = sin(phase) * _shake_px if _elapsed < _shake_duration else 0.0
	global_position = _base_pos + Vector2(offset_x, 0.0)

	if _flash_enabled:
		_flash_elapsed += delta
		var t: float = clampf(_flash_elapsed / _flash_time, 0.0, 1.0)
		_ghost.modulate = _start_tint.lerp(Color.WHITE, t)

	if _elapsed >= _shake_duration:
		global_position = _base_pos
		_ghost.modulate = Color.WHITE
		queue_free()


static func _result(ok: bool, reason: String, feedback: TileHitFeedback = null) -> Dictionary:
	var out := {
		"ok": ok,
		"reason": reason,
	}
	if feedback != null:
		out["node"] = feedback
	return out


static func _resolve_source_id(
		ts: TileSet,
		tilemap: TileMap,
		layer: int,
		tile_pos: Vector2i,
		options: Dictionary
	) -> int:
	var candidates: Array[int] = []
	if options.has("source_id"):
		candidates.append(int(options.get("source_id", -1)))
	candidates.append(tilemap.get_cell_source_id(layer, tile_pos))
	if options.has("fallback_source_id"):
		candidates.append(int(options.get("fallback_source_id", -1)))

	for candidate in candidates:
		if candidate == -1:
			continue
		var source := ts.get_source(candidate) as TileSetAtlasSource
		if source != null and source.texture != null:
			return candidate
	return _find_first_atlas_source_id(ts)


static func _find_first_atlas_source_id(ts: TileSet) -> int:
	if ts == null:
		return -1
	if not ts.has_method("get_source_count") or not ts.has_method("get_source_id"):
		return -1
	var source_count: int = int(ts.call("get_source_count"))
	for idx in range(source_count):
		var source_id: int = int(ts.call("get_source_id", idx))
		var source := ts.get_source(source_id) as TileSetAtlasSource
		if source != null and source.texture != null:
			return source_id
	return -1


static func _resolve_atlas_coords(
		tilemap: TileMap,
		layer: int,
		tile_pos: Vector2i,
		atlas_source: TileSetAtlasSource,
		options: Dictionary
	) -> Dictionary:
	var atlas_coords: Vector2i = options.get("atlas_coords", tilemap.get_cell_atlas_coords(layer, tile_pos))
	if atlas_coords.x < 0 or atlas_coords.y < 0:
		if options.has("fallback_atlas") and options.get("fallback_atlas") is Vector2i:
			atlas_coords = options.get("fallback_atlas")
		else:
			atlas_coords = Vector2i.ZERO

	if atlas_source != null and atlas_source.has_method("has_tile"):
		var has_tile: bool = bool(atlas_source.call("has_tile", atlas_coords))
		if not has_tile:
			var fallback_atlas: Vector2i = options.get("fallback_atlas", Vector2i.ZERO)
			if bool(atlas_source.call("has_tile", fallback_atlas)):
				atlas_coords = fallback_atlas
			elif bool(atlas_source.call("has_tile", Vector2i.ZERO)):
				atlas_coords = Vector2i.ZERO
			else:
				return {
					"ok": false,
					"reason": "atlas_missing",
				}

	return {
		"ok": true,
		"atlas_coords": atlas_coords,
	}


static func _resolve_region_rect(atlas_source: TileSetAtlasSource, atlas_coords: Vector2i, _alternative_tile: int) -> Rect2:
	if atlas_source.has_method("get_tile_texture_region"):
		var resolved: Variant = atlas_source.call("get_tile_texture_region", atlas_coords)
		if resolved is Rect2:
			return resolved
		if resolved is Rect2i:
			var rect_i: Rect2i = resolved
			return Rect2(Vector2(rect_i.position), Vector2(rect_i.size))

	var region_size: Vector2 = Vector2(atlas_source.texture_region_size)
	if region_size.x <= 0.0 or region_size.y <= 0.0:
		region_size = Vector2(32.0, 32.0)
	var region_pos: Vector2 = Vector2(atlas_coords) * region_size
	return Rect2(region_pos, region_size)


static func _sanitize_region_rect(atlas_source: TileSetAtlasSource, region_rect: Rect2) -> Rect2:
	if atlas_source == null or atlas_source.texture == null:
		return Rect2()

	var texture_size: Vector2 = Vector2(atlas_source.texture.get_size())
	if texture_size.x <= 0.0 or texture_size.y <= 0.0:
		return Rect2()

	var safe_size: Vector2 = region_rect.size
	if safe_size.x <= 0.0 or safe_size.y <= 0.0:
		safe_size = Vector2(atlas_source.texture_region_size)
	if safe_size.x <= 0.0 or safe_size.y <= 0.0:
		safe_size = Vector2(32.0, 32.0)
	safe_size.x = minf(safe_size.x, texture_size.x)
	safe_size.y = minf(safe_size.y, texture_size.y)

	var safe_pos: Vector2 = region_rect.position
	var out_of_bounds: bool = (
		safe_pos.x < 0.0 or
		safe_pos.y < 0.0 or
		safe_pos.x + safe_size.x > texture_size.x or
		safe_pos.y + safe_size.y > texture_size.y
	)
	if out_of_bounds:
		safe_pos = Vector2.ZERO

	return Rect2(safe_pos, safe_size)
