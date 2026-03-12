extends Node

@export_node_path("TileMap") var ground_path: NodePath = ^"../TileMapGround"
@export_node_path("TileMap") var cliffs_path: NodePath = ^"../TileMap_Cliffs"
@export_node_path("Node2D") var player_path: NodePath = ^"../Player"

@export var x_min := -100
@export var x_max := 100
@export var y_min := -40
@export var y_max := 10
@export var layer := 0
@export var terrain_set_id := 0
@export var dirt_terrain_id := 0
@export var grass_terrain_id := 1
@export var edge_margin_x := 20
@export var edge_margin_y := 10
@export var min_nodes := 5
@export var max_nodes := 8
@export var corridor_width := 1

# Cliffs — terrain 2 en TileMap_Cliffs, Terrain Set 0
@export var cliff_terrain_set_id := 0
@export var cliff_terrain_id := 2
@export var spawn_safe_radius := 5

# Parámetros de los blobs de cliff
@export var cliff_blob_count := 10
@export var cliff_blob_radius_min := 5
@export var cliff_blob_radius_max := 11
@export var cliff_warp_strength := 3.5
@export var cliff_clear_radius := 4
## Fracción del tile_size usada como ancho de banda de colisión (sur/este/oeste).
@export var cliff_collision_band := 0.3

@export var chunk_size: int = 32

# ── Estado global del generador ───────────────────────────────────────────────
var nodes: Array[Dictionary] = []
var spawn_cell := Vector2i.ZERO
## Centerline de todos los corredores (sin expansión de pincel).
var _corridor_points: Array[Vector2i] = []
## Centros de pequeños parches de dirt: {pos, shape}
var _patch_centers: Array[Dictionary] = []
## Blobs de cliff pre-generados: {center, radius, ox, oy}
var _cliff_blob_centers: Array[Dictionary] = []
## Zona libre global (spawn + arenas + corredores): cliffs no se pintan aquí.
var _free_zone: Dictionary = {}

var _noise: FastNoiseLite

@onready var tilemap: TileMap = get_node_or_null(ground_path)
@onready var cliffs_tilemap: TileMap = get_node_or_null(cliffs_path)
@onready var player: Node2D = get_node_or_null(player_path)


func _ready() -> void:
	if tilemap == null:
		push_error("WorldGeneratorTest: TileMapGround no configurado (ground_path).")
		return
	if tilemap.tile_set == null:
		push_error("WorldGeneratorTest: TileMapGround no tiene TileSet asignado.")
		return
	if cliffs_tilemap == null:
		push_error("WorldGeneratorTest: TileMap_Cliffs no configurado (cliffs_path).")
		return

	_noise = FastNoiseLite.new()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.09
	_noise.fractal_octaves = 2

	_sync_terrain_ids_from_tileset()
	_global_phase()
	_generate_all_chunks()
	spawn_player_center()
	print("Generated ground cells:", tilemap.get_used_cells(layer).size())
	print("Generated cliff cells:", cliffs_tilemap.get_used_cells(layer).size())


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		regenerate()


func regenerate() -> void:
	tilemap.clear_layer(layer)
	cliffs_tilemap.clear_layer(layer)
	# Eliminar StaticBody2D de colisión previos
	for child in cliffs_tilemap.get_children():
		if child is StaticBody2D:
			child.queue_free()
	nodes.clear()
	_corridor_points.clear()
	_patch_centers.clear()
	_cliff_blob_centers.clear()
	_free_zone.clear()
	_global_phase()
	_generate_all_chunks()
	spawn_player_center()
	print("Regenerated — ground:", tilemap.get_used_cells(layer).size(),
		" cliffs:", cliffs_tilemap.get_used_cells(layer).size())


# ── FASE GLOBAL ───────────────────────────────────────────────────────────────
# Se ejecuta una sola vez antes de generar ningún chunk.
# Calcula posiciones, conectividad y parámetros de blobs. No pinta nada.

func _global_phase() -> void:
	_noise.seed = randi()
	create_nodes()
	spawn_cell = nodes[0]["pos"] if not nodes.is_empty() else Vector2i.ZERO
	connect_nodes()
	_prebuild_patch_centers()
	_build_free_zone()
	_prebuild_cliff_blobs()


func _build_free_zone() -> void:
	_fill_circle(_free_zone, spawn_cell, spawn_safe_radius + cliff_clear_radius)
	for node_data in nodes:
		_fill_circle(_free_zone, node_data["pos"], node_data["radius"] + cliff_clear_radius)
	for pt in _corridor_points:
		_fill_circle(_free_zone, pt, cliff_clear_radius)


func _prebuild_patch_centers() -> void:
	var patch_count := randi_range(6, 12)
	for _i in range(patch_count):
		_patch_centers.append({
			"pos": Vector2i(
				randi_range(x_min + edge_margin_x, x_max - edge_margin_x),
				randi_range(y_min + edge_margin_y, y_max - edge_margin_y)
			),
			"shape": randi_range(0, 2),
		})


func _prebuild_cliff_blobs() -> void:
	var placed := 0
	var attempts := 0
	var margin := cliff_blob_radius_max + 2
	while placed < cliff_blob_count and attempts < cliff_blob_count * 20:
		attempts += 1
		var cx := randi_range(x_min + margin, x_max - margin)
		var cy := randi_range(y_min + margin, y_max - margin)
		var center := Vector2i(cx, cy)
		if _free_zone.has(center):
			continue
		_cliff_blob_centers.append({
			"center": center,
			"radius": randi_range(cliff_blob_radius_min, cliff_blob_radius_max),
			"ox":     randf_range(-500.0, 500.0),
			"oy":     randf_range(-500.0, 500.0),
		})
		placed += 1


# ── SISTEMA DE CHUNKS ─────────────────────────────────────────────────────────

func _generate_all_chunks() -> void:
	var cx_min := floori(float(x_min) / chunk_size)
	var cx_max := floori(float(x_max) / chunk_size)
	var cy_min := floori(float(y_min) / chunk_size)
	var cy_max := floori(float(y_max) / chunk_size)
	# Pasada 1: pintar grass + dirt (sin cliffs).
	for cy in range(cy_min, cy_max + 1):
		for cx in range(cx_min, cx_max + 1):
			generate_chunk(Vector2i(cx, cy))
	# Pasada 2: pintar TODOS los cliffs en un solo batch global.
	# set_cells_terrain_connect necesita ver el conjunto completo para
	# elegir la variante correcta (interior vs borde) en cada tile.
	_paint_all_cliffs()
	# Pasada 3: colisiones — el mapa completo ya está pintado.
	for cy in range(cy_min, cy_max + 1):
		for cx in range(cx_min, cx_max + 1):
			_build_cliff_collisions_simple(Vector2i(cx, cy))


func generate_chunk(chunk_pos: Vector2i) -> void:
	var start_x := chunk_pos.x * chunk_size
	var start_y := chunk_pos.y * chunk_size
	var end_x   := start_x + chunk_size - 1
	var end_y   := start_y + chunk_size - 1

	# Recortar al rango del mundo
	var tx_min := maxi(start_x, x_min)
	var tx_max := mini(end_x, x_max)
	var ty_min := maxi(start_y, y_min)
	var ty_max := mini(end_y, y_max)
	if tx_min > tx_max or ty_min > ty_max:
		return

	# a) Pintar grass en todos los tiles del chunk
	var grass_cells: Array[Vector2i] = []
	for x in range(tx_min, tx_max + 1):
		for y in range(ty_min, ty_max + 1):
			grass_cells.append(Vector2i(x, y))
	tilemap.set_cells_terrain_connect(layer, grass_cells, terrain_set_id, grass_terrain_id, false)

	# b) Pintar dirt: nodos + corredores + parches que intersectan este chunk
	var dirt_cells: Array[Vector2i] = []
	for node_data in nodes:
		_collect_node_dirt(dirt_cells, node_data, tx_min, tx_max, ty_min, ty_max)
	_collect_corridor_dirt(dirt_cells, tx_min, tx_max, ty_min, ty_max)
	_collect_patch_dirt(dirt_cells, tx_min, tx_max, ty_min, ty_max)
	if dirt_cells.size() > 0:
		tilemap.set_cells_terrain_connect(layer, dirt_cells, terrain_set_id, dirt_terrain_id, false)

	# c) Cliffs se pintan en pasada global desde _generate_all_chunks.


# ── Colección de dirt por chunk ───────────────────────────────────────────────

func _collect_node_dirt(cells: Array[Vector2i], node_data: Dictionary,
		tx_min: int, tx_max: int, ty_min: int, ty_max: int) -> void:
	var center: Vector2i = node_data["pos"]
	var radius: int = node_data["radius"]
	# Rechazo AABB rápido
	if center.x + radius < tx_min or center.x - radius > tx_max:
		return
	if center.y + radius < ty_min or center.y - radius > ty_max:
		return
	# Mismo rango de escaneo que el original
	for x in range(-radius, radius + 1):
		for y in range(-radius, radius + 1):
			var p := center + Vector2i(x, y)
			if p.x < tx_min or p.x > tx_max or p.y < ty_min or p.y > ty_max:
				continue
			if not _is_inside_bounds(p):
				continue
			var dist := Vector2(x, y).length()
			# Jitter determinístico vía noise (reemplaza randf_range(-2.2, 2.2)).
			# Produce el mismo estilo orgánico; independiente del orden de chunks.
			var jitter := _noise.get_noise_2d(float(p.x) * 3.71, float(p.y) * 3.71) * 2.2
			if dist <= radius + jitter:
				cells.append(p)


func _collect_corridor_dirt(cells: Array[Vector2i],
		tx_min: int, tx_max: int, ty_min: int, ty_max: int) -> void:
	for pt in _corridor_points:
		# Rechazo AABB del punto + pincel
		if pt.x + corridor_width < tx_min or pt.x - corridor_width > tx_max:
			continue
		if pt.y + corridor_width < ty_min or pt.y - corridor_width > ty_max:
			continue
		for x in range(-corridor_width, corridor_width + 1):
			for y in range(-corridor_width, corridor_width + 1):
				var p := pt + Vector2i(x, y)
				if p.x < tx_min or p.x > tx_max or p.y < ty_min or p.y > ty_max:
					continue
				if _is_inside_bounds(p):
					cells.append(p)


func _collect_patch_dirt(cells: Array[Vector2i],
		tx_min: int, tx_max: int, ty_min: int, ty_max: int) -> void:
	for patch in _patch_centers:
		var center: Vector2i = patch["pos"]
		var shape_roll: int  = patch["shape"]
		# Parche como máximo ~3 tiles desde el centro
		if center.x + 4 < tx_min or center.x - 4 > tx_max:
			continue
		if center.y + 4 < ty_min or center.y - 4 > ty_max:
			continue
		var patch_cells: Array[Vector2i] = []
		match shape_roll:
			0:
				patch_cells = [center, center + Vector2i.LEFT, center + Vector2i.RIGHT,
						center + Vector2i.UP, center + Vector2i.DOWN]
			1:
				for x in range(-2, 3):
					for y in range(-2, 3):
						if abs(x) + abs(y) <= 2:
							patch_cells.append(center + Vector2i(x, y))
			_:
				for x in range(-3, 4):
					for y in range(-3, 4):
						var p := center + Vector2i(x, y)
						# Variación de radio determinística vía noise
						var r_var := _noise.get_noise_2d(float(p.x) * 5.31, float(p.y) * 5.31) * 0.6
						if Vector2(x, y).length() <= 2.8 + r_var:
							patch_cells.append(p)
		for p in patch_cells:
			if p.x >= tx_min and p.x <= tx_max and p.y >= ty_min and p.y <= ty_max:
				if _is_inside_bounds(p):
					cells.append(p)


# ── Cliffs — pasada global ────────────────────────────────────────────────────
# Todos los blobs se acumulan en un solo Dictionary y se pasan en una única
# llamada a set_cells_terrain_connect. Esto garantiza que Godot tenga el
# contexto completo de vecinos al elegir la variante de cada tile, eliminando
# los huecos que aparecen cuando se pinta chunk por chunk.

func _paint_all_cliffs() -> void:
	var cliff_set: Dictionary = {}
	for blob in _cliff_blob_centers:
		var center: Vector2i = blob["center"]
		var radius: int      = blob["radius"]
		var ox: float        = blob["ox"]
		var oy: float        = blob["oy"]
		var scan := radius + int(cliff_warp_strength) + 2
		for x in range(-scan, scan + 1):
			for y in range(-scan, scan + 1):
				var p := center + Vector2i(x, y)
				if not _is_inside_bounds(p):
					continue
				if _free_zone.has(p):
					continue
				var dist := Vector2(x, y).length()
				var warp := _noise.get_noise_2d(float(p.x) + ox, float(p.y) + oy) * cliff_warp_strength
				var angle_var := sin(atan2(float(y), float(x)) * 2.5 + ox * 0.005) * (radius * 0.15)
				if dist <= float(radius) + warp + angle_var:
					cliff_set[p] = true
	if cliff_set.is_empty():
		return
	var cliff_cells: Array[Vector2i] = []
	for c in cliff_set.keys():
		cliff_cells.append(c)
	cliffs_tilemap.set_cells_terrain_connect(layer, cliff_cells, cliff_terrain_set_id, cliff_terrain_id, false)


# ── Colisión simple de cliffs por chunk ──────────────────────────────────────
# Para cada tile cliff del chunk:
#   · Vecino SUR no es cliff  → banda horizontal en borde inferior del tile.
#   · Vecino ESTE no es cliff → banda vertical en borde derecho del tile.
#   · Vecino OESTE no es cliff→ banda vertical en borde izquierdo del tile.
#   · Vecino NORTE no es cliff → banda horizontal en borde superior del tile.
# "No es cliff" incluye tiles de grass/dirt Y celdas vacías.
# Los segmentos contiguos y colineales se fusionan en un solo shape.

func _build_cliff_collisions_simple(chunk_pos: Vector2i) -> void:
	var start_x := chunk_pos.x * chunk_size
	var start_y := chunk_pos.y * chunk_size
	var end_x   := start_x + chunk_size - 1
	var end_y   := start_y + chunk_size - 1

	var tile_size: Vector2 = Vector2(32.0, 32.0)
	if cliffs_tilemap.tile_set != null:
		tile_size = Vector2(cliffs_tilemap.tile_set.tile_size)
	var band_h := tile_size.y * cliff_collision_band
	var band_w := tile_size.x * cliff_collision_band

	# Lookup de presencia de cliff con margen de 1 para consultar vecinos.
	var wall_lookup: Dictionary = {}
	for y in range(start_y - 1, end_y + 2):
		for x in range(start_x - 1, end_x + 2):
			var cell := Vector2i(x, y)
			if cliffs_tilemap.get_cell_source_id(layer, cell) != -1:
				wall_lookup[cell] = true

	var body := StaticBody2D.new()
	body.set_collision_layer_value(5, true)
	body.name = "CliffCollision_%d_%d" % [chunk_pos.x, chunk_pos.y]
	var shape_count := 0

	# ── Bandas SUR: runs horizontales por fila ────────────────────────────────
	# Condición: tile es cliff Y vecino sur no es cliff (vacío o grass/dirt).
	for y in range(start_y, end_y + 1):
		var in_run := false
		var run_x0 := start_x
		for x in range(start_x, end_x + 2):  # +1 extra para cerrar el último run
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
					var lc := cliffs_tilemap.map_to_local(Vector2i(run_x0, y))
					var rc := cliffs_tilemap.map_to_local(Vector2i(run_x1, y))
					shape.position = Vector2(
						(lc.x + rc.x) * 0.5,
						lc.y + tile_size.y * 0.5 - band_h * 0.5
					)
					body.add_child(shape)
					shape_count += 1
					in_run = false

	# ── Bandas NORTE: runs horizontales por fila ─────────────────────────────
	# Condición: tile es cliff Y vecino norte no es cliff.
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
					var lc := cliffs_tilemap.map_to_local(Vector2i(run_x0, y))
					var rc := cliffs_tilemap.map_to_local(Vector2i(run_x1, y))
					shape.position = Vector2(
						(lc.x + rc.x) * 0.5,
						lc.y - tile_size.y * 0.5 + band_h * 0.5 + tile_size.y * 0.8
					)
					body.add_child(shape)
					shape_count += 1
					in_run = false

	# ── Bandas ESTE: runs verticales por columna ──────────────────────────────
	# Condición: tile es cliff Y vecino este no es cliff.
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
					var tc := cliffs_tilemap.map_to_local(Vector2i(x, run_y0))
					var bc := cliffs_tilemap.map_to_local(Vector2i(x, run_y1))
					shape.position = Vector2(
						tc.x + tile_size.x * 0.5 - band_w * 0.5,
						(tc.y + bc.y) * 0.5 + bot_ext * 0.5 + top_shrink * 0.5
					)
					body.add_child(shape)
					shape_count += 1
					in_run = false

	# ── Bandas OESTE: runs verticales por columna ─────────────────────────────
	# Condición: tile es cliff Y vecino oeste no es cliff.
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
					var tc := cliffs_tilemap.map_to_local(Vector2i(x, run_y0))
					var bc := cliffs_tilemap.map_to_local(Vector2i(x, run_y1))
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
	cliffs_tilemap.add_child(body)


# ── GENERACIÓN DE NODOS Y CORREDORES ─────────────────────────────────────────

func create_nodes() -> void:
	var count := randi_range(min_nodes, max_nodes)
	for _i in range(count):
		nodes.append({
			"pos": Vector2i(
				randi_range(x_min + edge_margin_x, x_max - edge_margin_x),
				randi_range(y_min + edge_margin_y, y_max - edge_margin_y)
			),
			"radius": randi_range(6, 12),
		})


func connect_nodes() -> void:
	if nodes.size() < 2:
		return
	for i in range(nodes.size() - 1):
		draw_path(nodes[i]["pos"], nodes[i + 1]["pos"])
	if nodes.size() >= 4 and randf() < 0.6:
		draw_path(nodes[0]["pos"], nodes[nodes.size() - 1]["pos"])


func draw_path(a: Vector2i, b: Vector2i) -> void:
	# Solo acumula la centerline; la expansión de pincel ocurre por chunk.
	var pos := a
	while pos != b:
		_corridor_points.append(pos)
		if abs(b.x - pos.x) > abs(b.y - pos.y):
			pos.x += sign(b.x - pos.x)
		else:
			pos.y += sign(b.y - pos.y)
	_corridor_points.append(b)


# ── HELPERS ───────────────────────────────────────────────────────────────────

func _is_inside_bounds(cell: Vector2i) -> bool:
	return cell.x >= x_min and cell.x <= x_max and cell.y >= y_min and cell.y <= y_max


func _fill_circle(dict: Dictionary, center: Vector2i, radius: int) -> void:
	for x in range(-radius, radius + 1):
		for y in range(-radius, radius + 1):
			if Vector2(x, y).length() <= radius:
				var p := center + Vector2i(x, y)
				if _is_inside_bounds(p):
					dict[p] = true


func _sync_terrain_ids_from_tileset() -> void:
	var ts := tilemap.tile_set
	var terrain_count := ts.get_terrains_count(terrain_set_id)
	if terrain_count <= 0:
		push_warning("WorldGeneratorTest: terrain_set_id sin terrains. Revisa TileSetGround.")
		return
	if dirt_terrain_id < 0 or dirt_terrain_id >= terrain_count:
		var by_name := _find_terrain_id_by_name("dirt")
		if by_name != -1:
			dirt_terrain_id = by_name
	if grass_terrain_id < 0 or grass_terrain_id >= terrain_count:
		var by_name := _find_terrain_id_by_name("grass")
		if by_name != -1:
			grass_terrain_id = by_name
	if dirt_terrain_id == grass_terrain_id:
		push_warning("WorldGeneratorTest: dirt_terrain_id y grass_terrain_id apuntan al mismo terrain.")


func _find_terrain_id_by_name(expected_name: String) -> int:
	var ts := tilemap.tile_set
	var terrain_count := ts.get_terrains_count(terrain_set_id)
	for terrain_id in range(terrain_count):
		if ts.get_terrain_name(terrain_set_id, terrain_id).to_lower() == expected_name:
			return terrain_id
	return -1


func spawn_player_center() -> void:
	if player == null:
		push_warning("WorldGeneratorTest: Player no encontrado para reposicionar.")
		return
	if nodes.is_empty():
		player.global_position = tilemap.map_to_local(Vector2i(0, -5))
		return
	player.global_position = tilemap.map_to_local(spawn_cell)
