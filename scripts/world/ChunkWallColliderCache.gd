extends RefCounted
class_name ChunkWallColliderCache

const FLAG_PROJECTION_WALLS_DIRTY: String = "walls_dirty"
const FLAG_PROJECTION_WALLS_HASH: String = "walls_hash"

var walls_tilemap: TileMap
var collision_builder: CollisionBuilder
var chunk_size: int = 32
var walls_map_layer: int = 0
var src_walls: int = 0
var max_cached_chunk_colliders: int = 0
var debug_collision_cache: bool = false
var loaded_chunks: Dictionary = {}
var current_player_chunk_getter: Callable
var chunk_key: Callable
var is_chunk_in_active_window: Callable
var record_stage_time: Callable
var chunk_perf_stage_collider_build: String = "collider build"
var extra_wall_support_lookup_provider: Callable

var chunk_wall_body: Dictionary = {}
var _chunk_wall_last_used: Dictionary = {}
var _chunk_wall_use_counter: int = 0

func setup(ctx: Dictionary) -> void:
	walls_tilemap = ctx.get("walls_tilemap")
	collision_builder = ctx.get("collision_builder")
	chunk_size = int(ctx.get("chunk_size", 32))
	walls_map_layer = int(ctx.get("walls_map_layer", 0))
	src_walls = int(ctx.get("src_walls", 0))
	max_cached_chunk_colliders = int(ctx.get("max_cached_chunk_colliders", 0))
	debug_collision_cache = bool(ctx.get("debug_collision_cache", false))
	loaded_chunks = ctx.get("loaded_chunks", {})
	current_player_chunk_getter = ctx.get("current_player_chunk_getter", Callable())
	chunk_key = ctx.get("chunk_key", Callable())
	is_chunk_in_active_window = ctx.get("is_chunk_in_active_window", Callable())
	record_stage_time = ctx.get("record_stage_time", Callable())
	chunk_perf_stage_collider_build = String(ctx.get("chunk_perf_stage_collider_build", "collider build"))
	extra_wall_support_lookup_provider = ctx.get("extra_wall_support_lookup_provider", Callable())

func clear_all() -> void:
	for cpos in chunk_wall_body.keys():
		var body: StaticBody2D = chunk_wall_body[cpos]
		if body != null and is_instance_valid(body):
			body.queue_free()
	chunk_wall_body.clear()
	_chunk_wall_last_used.clear()
	_chunk_wall_use_counter = 0

func mark_dirty(cx: int, cy: int) -> void:
	_set_projection_walls_dirty(cx, cy, true)

func ensure_for_chunk(chunk_pos: Vector2i) -> void:
	var collider_start_us: int = Time.get_ticks_usec()
	var cx: int = chunk_pos.x
	var cy: int = chunk_pos.y
	var chunk_key_str: String = _chunk_key(chunk_pos)
	var dirty: bool = _is_projection_walls_dirty(cx, cy)
	var saved_hash = _get_projection_walls_hash(cx, cy)
	var collider_exists: bool = _has_valid_chunk_wall_body(chunk_pos)

	if collider_exists and not dirty and saved_hash != null:
		var fast_body: StaticBody2D = chunk_wall_body[chunk_pos]
		collision_builder.set_chunk_collider_enabled(fast_body, true)
		_touch_chunk_wall_usage(chunk_pos)
		if debug_collision_cache:
			Debug.log("chunk", "REUSE walls collider chunk=%s hash=%d (fast-path)" % [chunk_key_str, int(saved_hash)])
		_record_collider_time(chunk_pos, collider_start_us)
		return

	var current_hash: int = _compute_walls_hash(chunk_pos)
	var must_rebuild: bool = dirty or saved_hash == null or int(saved_hash) != current_hash or not collider_exists
	if must_rebuild:
		if collider_exists:
			var old_body: StaticBody2D = chunk_wall_body[chunk_pos]
			if is_instance_valid(old_body):
				old_body.queue_free()
		chunk_wall_body.erase(chunk_pos)
		_chunk_wall_last_used.erase(chunk_key_str)

		var extra_support_lookup: Dictionary = {}
		if extra_wall_support_lookup_provider.is_valid():
			var provided: Variant = extra_wall_support_lookup_provider.call(chunk_pos)
			if provided is Dictionary:
				extra_support_lookup = provided as Dictionary
		var body: StaticBody2D = collision_builder.build_chunk_walls(
			walls_tilemap, chunk_pos, chunk_size, walls_map_layer, src_walls, extra_support_lookup
		)
		if body != null:
			walls_tilemap.add_child(body)
			chunk_wall_body[chunk_pos] = body
			collision_builder.set_chunk_collider_enabled(body, true)
			_touch_chunk_wall_usage(chunk_pos)

		_set_projection_walls_hash(cx, cy, current_hash)
		_set_projection_walls_dirty(cx, cy, false)
		if debug_collision_cache:
			var reason: String = ""
			if dirty:
				reason = "dirty"
			elif saved_hash == null:
				reason = "missing_hash"
			elif not collider_exists:
				reason = "missing_collider"
			else:
				reason = "hash_changed"
			Debug.log("chunk", "REBUILD walls collider chunk=%s reason=%s hash=%d" % [chunk_key_str, reason, current_hash])
		_record_collider_time(chunk_pos, collider_start_us)
		return

	var cached_body: StaticBody2D = chunk_wall_body[chunk_pos]
	collision_builder.set_chunk_collider_enabled(cached_body, true)
	_touch_chunk_wall_usage(chunk_pos)
	if debug_collision_cache:
		Debug.log("chunk", "REUSE walls collider chunk=%s hash=%d" % [chunk_key_str, current_hash])
	_record_collider_time(chunk_pos, collider_start_us)

func on_chunk_unloaded(chunk_pos: Vector2i) -> void:
	if chunk_wall_body.has(chunk_pos):
		var body: StaticBody2D = chunk_wall_body[chunk_pos]
		if is_instance_valid(body):
			collision_builder.set_chunk_collider_enabled(body, false)
			_touch_chunk_wall_usage(chunk_pos)
	_enforce_chunk_collider_cache_limit()

func _has_valid_chunk_wall_body(chunk_pos: Vector2i) -> bool:
	if not chunk_wall_body.has(chunk_pos):
		return false
	var body: StaticBody2D = chunk_wall_body[chunk_pos]
	if body == null or not is_instance_valid(body):
		chunk_wall_body.erase(chunk_pos)
		_chunk_wall_last_used.erase(_chunk_key(chunk_pos))
		return false
	return true

func _compute_walls_hash(chunk_pos: Vector2i) -> int:
	var start_x: int = chunk_pos.x * chunk_size
	var start_y: int = chunk_pos.y * chunk_size
	var end_x: int = start_x + chunk_size
	var end_y: int = start_y + chunk_size
	var h: int = 2166136261
	for y in range(start_y, end_y):
		for x in range(start_x, end_x):
			var cell := Vector2i(x, y)
			var source_id: int = walls_tilemap.get_cell_source_id(walls_map_layer, cell)
			if source_id == -1:
				continue
			var atlas: Vector2i = walls_tilemap.get_cell_atlas_coords(walls_map_layer, cell)
			var alt: int = walls_tilemap.get_cell_alternative_tile(walls_map_layer, cell)
			h = _fnv1a_mix_int(h, x)
			h = _fnv1a_mix_int(h, y)
			h = _fnv1a_mix_int(h, source_id)
			h = _fnv1a_mix_int(h, atlas.x)
			h = _fnv1a_mix_int(h, atlas.y)
			h = _fnv1a_mix_int(h, alt)
	return h

func _fnv1a_mix_int(h: int, value: int) -> int:
	var n: int = value
	h = int((h ^ n) * 16777619)
	return h

func _touch_chunk_wall_usage(chunk_pos: Vector2i) -> void:
	_chunk_wall_use_counter += 1
	_chunk_wall_last_used[_chunk_key(chunk_pos)] = _chunk_wall_use_counter

func _enforce_chunk_collider_cache_limit() -> void:
	if max_cached_chunk_colliders <= 0:
		return
	if chunk_wall_body.size() <= max_cached_chunk_colliders:
		return

	var current_player_chunk: Vector2i = Vector2i.ZERO
	if current_player_chunk_getter.is_valid():
		current_player_chunk = current_player_chunk_getter.call()

	var candidates: Array[Dictionary] = []
	for cpos in chunk_wall_body.keys():
		if is_chunk_in_active_window.is_valid() and is_chunk_in_active_window.call(cpos, current_player_chunk):
			continue
		if loaded_chunks.has(cpos):
			continue
		var key: String = _chunk_key(cpos)
		var used_at: int = int(_chunk_wall_last_used.get(key, -1))
		candidates.append({"chunk_pos": cpos, "used_at": used_at})

	if candidates.is_empty():
		return

	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("used_at", -1)) < int(b.get("used_at", -1))
	)

	for candidate in candidates:
		if chunk_wall_body.size() <= max_cached_chunk_colliders:
			break
		var cpos: Vector2i = candidate["chunk_pos"]
		var key: String = _chunk_key(cpos)
		var body: StaticBody2D = chunk_wall_body.get(cpos, null)
		if body != null and is_instance_valid(body):
			body.queue_free()
		chunk_wall_body.erase(cpos)
		_chunk_wall_last_used.erase(key)

func _chunk_key(chunk_pos: Vector2i) -> String:
	if chunk_key.is_valid():
		return chunk_key.call(chunk_pos)
	return "%d,%d" % [chunk_pos.x, chunk_pos.y]

func _record_collider_time(chunk_pos: Vector2i, start_us: int) -> void:
	if record_stage_time.is_valid():
		record_stage_time.call(chunk_perf_stage_collider_build, chunk_pos, float(Time.get_ticks_usec() - start_us) / 1000.0)

func _is_projection_walls_dirty(cx: int, cy: int) -> bool:
	return WorldSave.get_chunk_flag(cx, cy, FLAG_PROJECTION_WALLS_DIRTY) == true

func _get_projection_walls_hash(cx: int, cy: int):
	return WorldSave.get_chunk_flag(cx, cy, FLAG_PROJECTION_WALLS_HASH)

func _set_projection_walls_dirty(cx: int, cy: int, value: bool) -> void:
	# Projection bookkeeping only: never canonical wall ownership.
	WorldSave.set_chunk_flag(cx, cy, FLAG_PROJECTION_WALLS_DIRTY, value)

func _set_projection_walls_hash(cx: int, cy: int, value: int) -> void:
	# Projection bookkeeping only: hash tracks collider rebuild parity.
	WorldSave.set_chunk_flag(cx, cy, FLAG_PROJECTION_WALLS_HASH, value)
