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

	_noise = FastNoiseLite.new()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.09
	_noise.fractal_octaves = 2
	_noise.seed = _cliff_seed


# Fase global: llama una vez en world._ready() después de setup().
# Construye _cliff_blob_centers y _free_zone. No pinta nada.
func global_phase() -> void:
	_build_free_zone()
	_prebuild_cliff_blobs()


# Pinta tiles de cliff para un chunk + margen.
# Área extendida garantiza que set_cells_terrain_connect vea vecinos completos
# en cada tile del chunk → sin huecos en bordes entre chunks.
func paint_chunk_cliffs(chunk_pos: Vector2i) -> void:
	if _cliffs_tilemap == null:
		return
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

	if cliff_set.is_empty():
		return
	var cliff_cells: Array[Vector2i] = []
	for c in cliff_set.keys():
		cliff_cells.append(c)
	_cliffs_tilemap.set_cells_terrain_connect(_layer, cliff_cells, _terrain_set_id, _terrain_id, false)


# Construye StaticBody2D con bandas N/S/E/O y lo añade como hijo del tilemap.
# Solo tiles dentro del chunk (no el margen). Porta _build_cliff_collisions_simple.
func build_chunk_cliff_collisions(chunk_pos: Vector2i) -> void:
	if _cliffs_tilemap == null:
		return
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
	body.set_collision_layer_value(5, true)
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
		return
	_cliffs_tilemap.add_child(body)


# ── Helpers privados ──────────────────────────────────────────────────────────

func _build_free_zone() -> void:
	_fill_circle(_free_zone, _spawn_center, _spawn_safe_radius + _clear_radius)


func _prebuild_cliff_blobs() -> void:
	var placed := 0
	var attempts := 0
	var margin := _radius_max + 2
	while placed < _blob_count and attempts < _blob_count * 20:
		attempts += 1
		var cx := randi_range(_x_min + margin, _x_max - margin)
		var cy := randi_range(_y_min + margin, _y_max - margin)
		var center := Vector2i(cx, cy)
		if _free_zone.has(center):
			continue
		_cliff_blob_centers.append({
			"center": center,
			"radius": randi_range(_radius_min, _radius_max),
			"ox": randf_range(-500.0, 500.0),
			"oy": randf_range(-500.0, 500.0),
		})
		placed += 1


func _is_inside_bounds(cell: Vector2i) -> bool:
	return cell.x >= _x_min and cell.x <= _x_max and cell.y >= _y_min and cell.y <= _y_max


func _fill_circle(dict: Dictionary, center: Vector2i, radius: int) -> void:
	for x in range(-radius, radius + 1):
		for y in range(-radius, radius + 1):
			if Vector2(x, y).length() <= radius:
				var p := center + Vector2i(x, y)
				if _is_inside_bounds(p):
					dict[p] = true
