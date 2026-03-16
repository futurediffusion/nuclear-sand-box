class_name TileHitFeedback
extends RefCounted


static func spawn_tile_hit_feedback(
		host: Node,
		tilemap: TileMap,
		layer: int,
		tile_pos: Vector2i,
		options: Dictionary = {}
	) -> bool:
	if host == null or tilemap == null:
		return false

	var source_id: int = int(options.get("source_id", tilemap.get_cell_source_id(layer, tile_pos)))
	if source_id == -1:
		return false

	var atlas_coords: Vector2i = options.get("atlas_coords", tilemap.get_cell_atlas_coords(layer, tile_pos))
	if atlas_coords.x < 0 or atlas_coords.y < 0:
		if options.has("fallback_atlas") and options.get("fallback_atlas") is Vector2i:
			atlas_coords = options.get("fallback_atlas")
		else:
			return false

	var alternative_tile: int = int(options.get("alternative_tile", tilemap.get_cell_alternative_tile(layer, tile_pos)))
	var ts: TileSet = tilemap.tile_set
	if ts == null:
		return false

	var atlas_source := ts.get_source(source_id) as TileSetAtlasSource
	if atlas_source == null or atlas_source.texture == null:
		return false

	var region_rect: Rect2 = _resolve_region_rect(atlas_source, atlas_coords, alternative_tile)
	if region_rect.size.x <= 0.0 or region_rect.size.y <= 0.0:
		return false

	var ghost := Sprite2D.new()
	ghost.texture = atlas_source.texture
	ghost.region_enabled = true
	ghost.region_rect = region_rect
	ghost.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ghost.z_as_relative = false
	ghost.z_index = int(options.get("z_index", tilemap.z_index + 2))
	ghost.global_position = options.get("world_position", tilemap.to_global(tilemap.map_to_local(tile_pos)))
	ghost.modulate = options.get("tint", Color(1.0, 1.0, 1.0, 1.0))
	host.add_child(ghost)

	var shake_duration: float = maxf(float(options.get("shake_duration", 0.08)), 0.01)
	var shake_speed: float = maxf(float(options.get("shake_speed", 40.0)), 0.01)
	var shake_px: float = maxf(float(options.get("shake_px", 5.0)), 0.0)
	var flash_time: float = maxf(float(options.get("flash_time", 0.06)), 0.0)
	var base_pos: Vector2 = ghost.global_position

	var shake_tween := host.create_tween()
	var shake_updater := func(phase: float) -> void:
		if is_instance_valid(ghost):
			ghost.global_position = base_pos + Vector2(sin(phase) * shake_px, 0.0)
	shake_tween.tween_method(shake_updater, 0.0, shake_speed, shake_duration)
	shake_tween.finished.connect(func() -> void:
		if is_instance_valid(ghost):
			ghost.global_position = base_pos
			ghost.queue_free()
	)

	if flash_time > 0.0:
		var flash_tween := host.create_tween()
		flash_tween.tween_property(ghost, "modulate", Color.WHITE, flash_time)

	return true


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
