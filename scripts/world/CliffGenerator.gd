class_name CliffGenerator
extends Node

# ── Configuración inyectada via setup() ──────────────────────────────────────
var _x_min: int = 0
var _x_max: int = 256
var _y_min: int = 0
var _y_max: int = 256
var _chunk_size: int = 32
var _layer: int = 0
var _terrain_set_id: int = 0
var _terrain_id: int = 2
var _blob_count: int = 10
var _radius_min: int = 5
var _radius_max: int = 11
var _warp_strength: float = 3.5
var _clear_radius: int = 4
var _collision_band: float = 0.3
var _spawn_center: Vector2i = Vector2i.ZERO
var _spawn_safe_radius: int = 5
var _cliff_seed: int = 0
var _cliffs_tilemap: TileMap = null

var _record_stage_time: Callable
var _cliff_collision_bodies: Dictionary = {}

# ── Borde de mundo ────────────────────────────────────────────────────────────
const FILL_SOURCE_ID: int = 3
const FILL_ATLAS: Vector2i = Vector2i(1, 5)
var _border_width: int = 4
var _fill_outer_band: int = 40
var _fill_solid_width: int = 32
var _border_cells: Dictionary = {}

# ── Estado interno ────────────────────────────────────────────────────────────
var _cliff_blob_centers: Array[Dictionary] = []
var _free_zone: Dictionary = {}
var _noise: FastNoiseLite


func setup(ctx: Dictionary) -> void:
	_x_min = ctx.get("x_min", 0)
	_x_max = ctx.get("x_max", 256)
	_y_min = ctx.get("y_min", 0)
	_y_max = ctx.get("y_max", 256)
	_chunk_size = ctx.get("chunk_size", 32)
	_layer = ctx.get("layer", 0)
	_terrain_set_id = ctx.get("terrain_set_id", 0)
	_terrain_id = ctx.get("terrain_id", 2)
	_blob_count = ctx.get("blob_count", 10)
	_radius_min = ctx.get("radius_min", 5)
	_radius_max = ctx.get("radius_max", 11)
	_warp_strength = ctx.get("warp_strength", 3.5)
	_clear_radius = ctx.get("clear_radius", 4)
	_collision_band = ctx.get("collision_band", 0.3)
	_spawn_center = ctx.get("spawn_center", Vector2i.ZERO)
	_spawn_safe_radius = ctx.get("spawn_safe_radius", 5)
	_cliff_seed = ctx.get("cliff_seed", 0)
	_cliffs_tilemap = ctx.get("cliffs_tilemap")
	_border_width = ctx.get("border_width", 4)
	_record_stage_time = ctx.get("record_stage_time", Callable())

	_noise = FastNoiseLite.new()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.09
	_noise.fractal_octaves = 2
	_noise.seed = _cliff_seed


# Fase global: llama una vez en world._ready() después de setup().
# Construye _cliff_blob_centers, _free_zone y borde de mundo. Pinta relleno exterior.
func global_phase() -> void:
	_build_free_zone()
	_prebuild_cliff_blobs()
	_prebuild_border_cells()
	_paint_global_fill_tiles()


# Pinta tiles de cliff para un chunk + margen.
# Área extendida garantiza que set_cells_terrain_connect vea vecinos completos
# en cada tile del chunk → sin huecos en bordes entre chunks.
func paint_chunk_cliffs(chunk_pos: Vector2i) -> void:
	if _cliffs_tilemap == null:
		return
	var _paint_start_us: int = Time.get_ticks_usec()
	var margin: int = _radius_max + ceili(_warp_strength) + 2
	var area_x0: int = chunk_pos.x * _chunk_size - margin
	var area_y0: int = chunk_pos.y * _chunk_size - margin
	var area_x1: int = chunk_pos.x * _chunk_size + _chunk_size + margin
	var area_y1: int = chunk_pos.y * _chunk_size + _chunk_size + margin

	var cliff_set: Dictionary = {}
	for blob in _cliff_blob_centers:
		var center: Vector2i = blob["center"]
		var radius: int = blob["radius"]
		var ox: float = blob["ox"]
		var oy: float = blob["oy"]
		var scan: int = radius + int(_warp_strength) + 2
		# AABB rápido: ¿intersecta este blob el área extendida?
		if center.x + scan < area_x0 or center.x - scan > area_x1:
			continue
		if center.y + scan < area_y0 or center.y - scan > area_y1:
			continue
		for x in range(-scan, scan + 1):
			for y in range(-scan, scan + 1):
				var p := center + Vector2i(x, y)
				if p.x < area_x0 or p.x > area_x1 or p.y < area_y0 or p.y > area_y1:
					continue
				if not _is_inside_bounds(p):
					continue
				if _free_zone.has(p):
					continue
				var dist := Vector2(x, y).length()
				var warp := _noise.get_noise_2d(float(p.x) + ox, float(p.y) + oy) * _warp_strength
				var angle_var := sin(atan2(float(y), float(x)) * 2.5 + ox * 0.005) * (radius * 0.15)
				if dist <= float(radius) + warp + angle_var:
					cliff_set[p] = true

	# Añadir tiles del borde de mundo que caigan en el área de este chunk
	for cell in _border_cells.keys():
		var p: Vector2i = cell
		if p.x >= area_x0 and p.x <= area_x1 and p.y >= area_y0 and p.y <= area_y1:
			cliff_set[p] = true

	if cliff_set.is_empty():
		return
	var cliff_cells: Array[Vector2i] = []
	for c in cliff_set.keys():
		cliff_cells.append(c)
	_cliffs_tilemap.set_cells_terrain_connect(_layer, cliff_cells, _terrain_set_id, _terrain_id, false)
	if _record_stage_time.is_valid():
		_record_stage_time.call("cliff terrain paint", chunk_pos, float(Time.get_ticks_usec() - _paint_start_us) / 1000.0)


# Construye StaticBody2D con bandas N/S/E/O y lo añade como hijo del tilemap.
# Solo tiles dentro del chunk (no el margen). Porta _build_cliff_collisions_simple.
func build_chunk_cliff_collisions(chunk_pos: Vector2i) -> void:
	if _cliffs_tilemap == null:
		return
	if _cliff_collision_bodies.has(chunk_pos) and is_instance_valid(_cliff_collision_bodies[chunk_pos]):
		return
	var _collider_start_us: int = Time.get_ticks_usec()
	var start_x := chunk_pos.x * _chunk_size
	var start_y := chunk_pos.y * _chunk_size
	var end_x   := start_x + _chunk_size - 1
	var end_y   := start_y + _chunk_size - 1

	var tile_size: Vector2 = Vector2(32.0, 32.0)
	if _cliffs_tilemap.tile_set != null:
		tile_size = Vector2(_cliffs_tilemap.tile_set.tile_size)
	var band_h := tile_size.y * _collision_band
	var band_w := tile_size.x * _collision_band

	# Lookup con margen de 1 para consultar vecinos.
	var wall_lookup: Dictionary = {}
	for y in range(start_y - 1, end_y + 2):
		for x in range(start_x - 1, end_x + 2):
			var cell := Vector2i(x, y)
			if _cliffs_tilemap.get_cell_source_id(_layer, cell) != -1:
				wall_lookup[cell] = true

	var body := StaticBody2D.new()
	body.set_collision_layer_value(CollisionLayers.WORLD_WALL_LAYER_BIT, true)
	body.name = "CliffCollision_%d_%d" % [chunk_pos.x, chunk_pos.y]
	var shape_count := 0

	# ── Bandas SUR: runs horizontales por fila ────────────────────────────────
	for y in range(start_y, end_y + 1):
		var in_run := false
		var run_x0 := start_x
		for x in range(start_x, end_x + 2):
			var active := (x <= end_x
					and wall_lookup.has(Vector2i(x, y))
					and not wall_lookup.has(Vector2i(x, y + 1)))
			if active:
				if not in_run:
					run_x0 = x
					in_run = true
			else:
				if in_run:
					var run_x1 := x - 1
					var len_tiles := run_x1 - run_x0 + 1
					var shape := CollisionShape2D.new()
					var rect := RectangleShape2D.new()
					rect.size = Vector2(float(len_tiles) * tile_size.x, band_h)
					shape.shape = rect
					var lc := _cliffs_tilemap.map_to_local(Vector2i(run_x0, y))
					var rc := _cliffs_tilemap.map_to_local(Vector2i(run_x1, y))
					shape.position = Vector2(
						(lc.x + rc.x) * 0.5,
						lc.y + tile_size.y * 0.5 - band_h * 0.5
					)
					body.add_child(shape)
					shape_count += 1
					in_run = false

	# ── Bandas NORTE: runs horizontales por fila ──────────────────────────────
	for y in range(start_y, end_y + 1):
		var in_run := false
		var run_x0 := start_x
		for x in range(start_x, end_x + 2):
			var active := (x <= end_x
					and wall_lookup.has(Vector2i(x, y))
					and not wall_lookup.has(Vector2i(x, y - 1)))
			if active:
				if not in_run:
					run_x0 = x
					in_run = true
			else:
				if in_run:
					var run_x1 := x - 1
					var len_tiles := run_x1 - run_x0 + 1
					var shape := CollisionShape2D.new()
					var rect := RectangleShape2D.new()
					rect.size = Vector2(float(len_tiles) * tile_size.x, band_h)
					shape.shape = rect
					var lc := _cliffs_tilemap.map_to_local(Vector2i(run_x0, y))
					var rc := _cliffs_tilemap.map_to_local(Vector2i(run_x1, y))
					shape.position = Vector2(
						(lc.x + rc.x) * 0.5,
						lc.y - tile_size.y * 0.5 + band_h * 0.5 + tile_size.y * 0.8
					)
					body.add_child(shape)
					shape_count += 1
					in_run = false

	# ── Bandas ESTE: runs verticales por columna ──────────────────────────────
	for x in range(start_x, end_x + 1):
		var in_run := false
		var run_y0 := start_y
		for y in range(start_y, end_y + 2):
			var active := (y <= end_y
					and wall_lookup.has(Vector2i(x, y))
					and not wall_lookup.has(Vector2i(x + 1, y)))
			if active:
				if not in_run:
					run_y0 = y
					in_run = true
			else:
				if in_run:
					var run_y1 := y - 1
					var len_tiles := run_y1 - run_y0 + 1
					var top_shrink := tile_size.y * 0.8 if not wall_lookup.has(Vector2i(x, run_y0 - 1)) else 0.0
					var bot_ext := tile_size.y * 0.8 if wall_lookup.has(Vector2i(x, run_y1 + 1)) else 0.0
					var shape := CollisionShape2D.new()
					var rect := RectangleShape2D.new()
					rect.size = Vector2(band_w, float(len_tiles) * tile_size.y + bot_ext - top_shrink)
					shape.shape = rect
					var tc := _cliffs_tilemap.map_to_local(Vector2i(x, run_y0))
					var bc := _cliffs_tilemap.map_to_local(Vector2i(x, run_y1))
					shape.position = Vector2(
						tc.x + tile_size.x * 0.5 - band_w * 0.5,
						(tc.y + bc.y) * 0.5 + bot_ext * 0.5 + top_shrink * 0.5
					)
					body.add_child(shape)
					shape_count += 1
					in_run = false

	# ── Bandas OESTE: runs verticales por columna ─────────────────────────────
	for x in range(start_x, end_x + 1):
		var in_run := false
		var run_y0 := start_y
		for y in range(start_y, end_y + 2):
			var active := (y <= end_y
					and wall_lookup.has(Vector2i(x, y))
					and not wall_lookup.has(Vector2i(x - 1, y)))
			if active:
				if not in_run:
					run_y0 = y
					in_run = true
			else:
				if in_run:
					var run_y1 := y - 1
					var len_tiles := run_y1 - run_y0 + 1
					var top_shrink := tile_size.y * 0.8 if not wall_lookup.has(Vector2i(x, run_y0 - 1)) else 0.0
					var bot_ext := tile_size.y * 0.8 if wall_lookup.has(Vector2i(x, run_y1 + 1)) else 0.0
					var shape := CollisionShape2D.new()
					var rect := RectangleShape2D.new()
					rect.size = Vector2(band_w, float(len_tiles) * tile_size.y + bot_ext - top_shrink)
					shape.shape = rect
					var tc := _cliffs_tilemap.map_to_local(Vector2i(x, run_y0))
					var bc := _cliffs_tilemap.map_to_local(Vector2i(x, run_y1))
					shape.position = Vector2(
						tc.x - tile_size.x * 0.5 + band_w * 0.5,
						(tc.y + bc.y) * 0.5 + bot_ext * 0.5 + top_shrink * 0.5
					)
					body.add_child(shape)
					shape_count += 1
					in_run = false

	if shape_count == 0:
		body.queue_free()
		if _record_stage_time.is_valid():
			_record_stage_time.call("cliff collider build", chunk_pos, float(Time.get_ticks_usec() - _collider_start_us) / 1000.0)
		return
	_cliff_collision_bodies[chunk_pos] = body
	_cliffs_tilemap.add_child(body)
	if _record_stage_time.is_valid():
		_record_stage_time.call("cliff collider build", chunk_pos, float(Time.get_ticks_usec() - _collider_start_us) / 1000.0)


func release_chunk_cliff_collisions(chunk_pos: Vector2i) -> void:
	if _cliff_collision_bodies.has(chunk_pos):
		var body: StaticBody2D = _cliff_collision_bodies[chunk_pos]
		if is_instance_valid(body):
			body.queue_free()
		_cliff_collision_bodies.erase(chunk_pos)


# ── Helpers privados ──────────────────────────────────────────────────────────

func _build_free_zone() -> void:
	_fill_circle(_free_zone, _spawn_center, _spawn_safe_radius + _clear_radius)


func _prebuild_cliff_blobs() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _cliff_seed
	var placed := 0
	var attempts := 0
	var margin := _radius_max + 2
	while placed < _blob_count and attempts < _blob_count * 20:
		attempts += 1
		var cx := rng.randi_range(_x_min + margin, _x_max - margin)
		var cy := rng.randi_range(_y_min + margin, _y_max - margin)
		var center := Vector2i(cx, cy)
		if _free_zone.has(center):
			continue
		_cliff_blob_centers.append({
			"center": center,
			"radius": rng.randi_range(_radius_min, _radius_max),
			"ox": rng.randf_range(-500.0, 500.0),
			"oy": rng.randf_range(-500.0, 500.0),
		})
		placed += 1


func _prebuild_border_cells() -> void:
	_border_cells.clear()
	var x_last: int = _x_max - 1
	var y_last: int = _y_max - 1
	var amp: float = float(_border_width) * 0.6

	for x in range(_x_min, _x_max):
		var d_top: int = _border_width + roundi(_noise.get_noise_2d(float(x) * 0.4, 500.0) * amp)
		d_top = clampi(d_top, 2, _border_width * 2)
		for b in range(d_top):
			_border_cells[Vector2i(x, _y_min + b)] = true

		var d_bot: int = _border_width + roundi(_noise.get_noise_2d(float(x) * 0.4, 600.0) * amp)
		d_bot = clampi(d_bot, 2, _border_width * 2)
		for b in range(d_bot):
			_border_cells[Vector2i(x, y_last - b)] = true

	for y in range(_y_min, _y_max):
		var d_left: int = _border_width + roundi(_noise.get_noise_2d(500.0, float(y) * 0.4) * amp)
		d_left = clampi(d_left, 2, _border_width * 2)
		for b in range(d_left):
			_border_cells[Vector2i(_x_min + b, y)] = true

		var d_right: int = _border_width + roundi(_noise.get_noise_2d(600.0, float(y) * 0.4) * amp)
		d_right = clampi(d_right, 2, _border_width * 2)
		for b in range(d_right):
			_border_cells[Vector2i(x_last - b, y)] = true


func _paint_global_fill_tiles() -> void:
	if _cliffs_tilemap == null:
		return
	# Outer band: tiles justo fuera del mundo — terrain connect para que empalmen con el borde interior
	var outer_cells: Array[Vector2i] = []
	for i in range(1, _fill_outer_band + 1):
		for x in range(_x_min - i, _x_max + i + 1):
			outer_cells.append(Vector2i(x, _y_min - i))
			outer_cells.append(Vector2i(x, _y_max - 1 + i))
		for y in range(_y_min - i + 1, _y_max + i):
			outer_cells.append(Vector2i(_x_min - i, y))
			outer_cells.append(Vector2i(_x_max - 1 + i, y))
	if not outer_cells.is_empty():
		_cliffs_tilemap.set_cells_terrain_connect(_layer, outer_cells, _terrain_set_id, _terrain_id, false)
	# Solid fill: tiles más alejados con set_cell directo para cubrir el vacío gris
	var fill_start: int = _fill_outer_band + 1
	var fill_end: int = _fill_outer_band + _fill_solid_width
	for i in range(fill_start, fill_end + 1):
		for x in range(_x_min - fill_end, _x_max + fill_end + 1):
			_cliffs_tilemap.set_cell(_layer, Vector2i(x, _y_min - i), FILL_SOURCE_ID, FILL_ATLAS)
			_cliffs_tilemap.set_cell(_layer, Vector2i(x, _y_max - 1 + i), FILL_SOURCE_ID, FILL_ATLAS)
		for y in range(_y_min - i + 1, _y_max + i):
			_cliffs_tilemap.set_cell(_layer, Vector2i(_x_min - i, y), FILL_SOURCE_ID, FILL_ATLAS)
			_cliffs_tilemap.set_cell(_layer, Vector2i(_x_max - 1 + i, y), FILL_SOURCE_ID, FILL_ATLAS)


func _is_inside_bounds(cell: Vector2i) -> bool:
	return cell.x >= _x_min and cell.x <= _x_max and cell.y >= _y_min and cell.y <= _y_max


func is_cliff_tile(tile_pos: Vector2i) -> bool:
	if _border_cells.has(tile_pos):
		return true
	if _free_zone.has(tile_pos):
		return false
	if not _is_inside_bounds(tile_pos):
		return false
	for blob in _cliff_blob_centers:
		var center: Vector2i = blob["center"]
		var radius: int = blob["radius"]
		var ox: float = blob["ox"]
		var oy: float = blob["oy"]
		var diff := tile_pos - center
		var dist := Vector2(diff.x, diff.y).length()
		var scan: int = radius + int(_warp_strength) + 2
		if abs(diff.x) > scan or abs(diff.y) > scan:
			continue
		var warp := _noise.get_noise_2d(float(tile_pos.x) + ox, float(tile_pos.y) + oy) * _warp_strength
		var angle_var := sin(atan2(float(diff.y), float(diff.x)) * 2.5 + ox * 0.005) * (radius * 0.15)
		if dist <= float(radius) + warp + angle_var:
			return true
	return false


func _fill_circle(dict: Dictionary, center: Vector2i, radius: int) -> void:
	for x in range(-radius, radius + 1):
		for y in range(-radius, radius + 1):
			if Vector2(x, y).length() <= radius:
				var p := center + Vector2i(x, y)
				if _is_inside_bounds(p):
					dict[p] = true
