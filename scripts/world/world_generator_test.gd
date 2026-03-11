extends Node

@export_node_path("TileMap") var ground_path: NodePath = ^"../TileMapGround"
@export_node_path("TileMap") var cliffs_path: NodePath = ^"../Tilemap_Cliffs"
@export_node_path("Node2D") var player_path: NodePath = ^"../Player"

@export var x_min := -100
@export var x_max := 100
@export var y_min := -40
@export var y_max := 10
@export var layer := 0
@export var terrain_set_id := 0
@export var dirt_terrain_id := 0
@export var grass_terrain_id := 1
@export var cliff_terrain_id := 2
@export var edge_margin_x := 20
@export var edge_margin_y := 10
@export var min_nodes := 5
@export var max_nodes := 8
@export var corridor_width := 1
@export var cliff_density := 0.75
@export var cliff_thickness := 2
@export var cliff_noise := 0.9
@export var spawn_safe_radius := 5

var nodes: Array[Dictionary] = []
var spawn_cell := Vector2i.ZERO
var corridor_centers: Array[Vector2i] = []

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
		push_error("WorldGeneratorTest: Tilemap_Cliffs no configurado (cliffs_path).")
		return

	if cliffs_tilemap.tile_set == null:
		push_error("WorldGeneratorTest: Tilemap_Cliffs no tiene TileSet asignado.")
		return

	_sync_terrain_ids_from_tileset()
	generate_world()
	spawn_player_center()
	print("Generated cells:", tilemap.get_used_cells(layer).size())


func generate_world() -> void:
	tilemap.clear_layer(layer)
	cliffs_tilemap.clear_layer(layer)
	nodes.clear()
	corridor_centers.clear()

	# Base completa de pasto para que el dirt use transiciones del terrain set existente.
	var all_cells: Array[Vector2i] = []
	for x in range(x_min, x_max + 1):
		for y in range(y_min, y_max + 1):
			all_cells.append(Vector2i(x, y))
	if all_cells.size() > 0:
		tilemap.set_cells_terrain_connect(layer, all_cells, terrain_set_id, grass_terrain_id, false)

	create_nodes()
	if not nodes.is_empty():
		spawn_cell = nodes[0]["pos"]

	connect_nodes()
	var masks := _build_terrain_masks()
	var ground_cells: Array[Vector2i] = masks["ground"]
	var cliff_cells: Array[Vector2i] = masks["cliffs"]

	if ground_cells.size() > 0:
		tilemap.set_cells_terrain_connect(layer, ground_cells, terrain_set_id, dirt_terrain_id, false)

	if cliff_cells.size() > 0:
		cliffs_tilemap.z_index = 1
		cliffs_tilemap.set_cells_terrain_connect(layer, cliff_cells, terrain_set_id, cliff_terrain_id, false)


func create_nodes() -> void:
	var count := randi_range(min_nodes, max_nodes)
	for _i in range(count):
		var node := {
			"pos": Vector2i(
				randi_range(x_min + edge_margin_x, x_max - edge_margin_x),
				randi_range(y_min + edge_margin_y, y_max - edge_margin_y)
			),
			"radius": randi_range(6, 12)
		}
		nodes.append(node)


func connect_nodes() -> void:
	if nodes.size() < 2:
		return

	for i in range(nodes.size() - 1):
		var a: Vector2i = nodes[i]["pos"]
		var b: Vector2i = nodes[i + 1]["pos"]
		draw_path(a, b)

	# Cierra un loop opcional para una estructura más navegable.
	if nodes.size() >= 4 and randf() < 0.6:
		var first: Vector2i = nodes[0]["pos"]
		var last: Vector2i = nodes[nodes.size() - 1]["pos"]
		draw_path(first, last)


func _build_terrain_masks() -> Dictionary:
	var ground_set := {}
	var cliff_set := {}

	for node_data in nodes:
		_add_cells_to_set(ground_set, _collect_node_cells(node_data))
		_add_cells_to_set(cliff_set, _collect_node_cliff_ring(node_data))

	for center in corridor_centers:
		_add_cells_to_set(ground_set, _collect_corridor_cells(center))

	# Parches sueltos para romper formas demasiado limpias.
	var patch_count := randi_range(6, 12)
	for _i in range(patch_count):
		_add_cells_to_set(ground_set, _collect_small_patch_cells(Vector2i(
			randi_range(x_min + edge_margin_x, x_max - edge_margin_x),
			randi_range(y_min + edge_margin_y, y_max - edge_margin_y)
		)))

	_add_cells_to_set(cliff_set, _collect_corridor_cliffs())
	_remove_spawn_safe_cells(cliff_set)

	return {
		"ground": _set_to_array(ground_set),
		"cliffs": _set_to_array(cliff_set),
	}


func _collect_node_cells(node_data: Dictionary) -> Array[Vector2i]:
	var center: Vector2i = node_data["pos"]
	var radius: int = node_data["radius"]
	var cells: Array[Vector2i] = []

	for x in range(-radius, radius + 1):
		for y in range(-radius, radius + 1):
			var p := center + Vector2i(x, y)
			if not _is_inside_bounds(p):
				continue

			var dist := Vector2(x, y).length()
			var jitter := randf_range(-2.2, 2.2)
			if dist <= radius + jitter:
				cells.append(p)
	return cells


func _collect_node_cliff_ring(node_data: Dictionary) -> Array[Vector2i]:
	var center: Vector2i = node_data["pos"]
	var radius: int = node_data["radius"]
	var cells: Array[Vector2i] = []
	var inner_radius: float = maxf(1.0, float(radius) - float(cliff_thickness) - 0.8)
	var outer_radius := float(radius) + float(cliff_thickness) + 1.2

	for x in range(-radius - cliff_thickness - 2, radius + cliff_thickness + 3):
		for y in range(-radius - cliff_thickness - 2, radius + cliff_thickness + 3):
			var p := center + Vector2i(x, y)
			if not _is_inside_bounds(p):
				continue

			var dist := Vector2(x, y).length()
			var jitter := randf_range(-cliff_noise, cliff_noise)
			if dist >= inner_radius + jitter and dist <= outer_radius + jitter and randf() < cliff_density:
				cells.append(p)

	return cells


func draw_path(a: Vector2i, b: Vector2i) -> void:
	var pos := a

	while pos != b:
		corridor_centers.append(pos)

		if abs(b.x - pos.x) > abs(b.y - pos.y):
			pos.x += sign(b.x - pos.x)
		else:
			pos.y += sign(b.y - pos.y)

	corridor_centers.append(b)


func _collect_corridor_cells(pos: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	_append_corridor_brush(cells, pos)
	return cells


func _collect_small_patch_cells(center: Vector2i) -> Array[Vector2i]:
	var shape_roll := randi_range(0, 2)
	var cells: Array[Vector2i] = []

	match shape_roll:
		0:
			# Dot + cruz pequeña.
			cells = [
				center,
				center + Vector2i.LEFT,
				center + Vector2i.RIGHT,
				center + Vector2i.UP,
				center + Vector2i.DOWN,
			]
		1:
			# Diamante.
			for x in range(-2, 3):
				for y in range(-2, 3):
					if abs(x) + abs(y) <= 2:
						cells.append(center + Vector2i(x, y))
		_:
			# Círculo pixelado pequeño.
			for x in range(-3, 4):
				for y in range(-3, 4):
					if Vector2(x, y).length() <= 2.8 + randf_range(-0.6, 0.6):
						cells.append(center + Vector2i(x, y))

	var filtered: Array[Vector2i] = []
	for c in cells:
		if _is_inside_bounds(c):
			filtered.append(c)
	return filtered


func _collect_corridor_cliffs() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for i in range(corridor_centers.size()):
		if randf() > cliff_density:
			continue

		var center := corridor_centers[i]
		var next := center
		if i < corridor_centers.size() - 1:
			next = corridor_centers[i + 1]

		var step := next - center
		if step == Vector2i.ZERO:
			step = Vector2i.RIGHT

		var normal := Vector2i(-step.y, step.x)
		if normal == Vector2i.ZERO:
			normal = Vector2i.UP

		normal = Vector2i(sign(normal.x), sign(normal.y))
		var side := 1 if randf() < 0.5 else -1
		var offset := normal * (corridor_width + cliff_thickness + 1) * side
		var stripe_center := center + offset

		for d in range(-cliff_thickness, cliff_thickness + 1):
			var stripe_cell := stripe_center + normal * d
			if not _is_inside_bounds(stripe_cell):
				continue
			if randf() < 0.85 + randf_range(-cliff_noise * 0.2, cliff_noise * 0.2):
				cells.append(stripe_cell)

	return cells


func _append_corridor_brush(cells: Array[Vector2i], pos: Vector2i) -> void:
	for x in range(-corridor_width, corridor_width + 1):
		for y in range(-corridor_width, corridor_width + 1):
			var p := pos + Vector2i(x, y)
			if _is_inside_bounds(p):
				cells.append(p)


func _add_cells_to_set(cell_set: Dictionary, cells: Array[Vector2i]) -> void:
	for c in cells:
		if _is_inside_bounds(c):
			cell_set[c] = true


func _set_to_array(cell_set: Dictionary) -> Array[Vector2i]:
	var arr: Array[Vector2i] = []
	for c in cell_set.keys():
		arr.append(c)
	return arr


func _remove_spawn_safe_cells(cell_set: Dictionary) -> void:
	for x in range(-spawn_safe_radius, spawn_safe_radius + 1):
		for y in range(-spawn_safe_radius, spawn_safe_radius + 1):
			if Vector2(x, y).length() > spawn_safe_radius:
				continue
			cell_set.erase(spawn_cell + Vector2i(x, y))


func _is_inside_bounds(cell: Vector2i) -> bool:
	return cell.x >= x_min and cell.x <= x_max and cell.y >= y_min and cell.y <= y_max


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

	if cliff_terrain_id < 0 or cliff_terrain_id >= terrain_count:
		var cliff_by_name := _find_terrain_id_by_name("terrain_2")
		if cliff_by_name == -1:
			cliff_by_name = _find_terrain_id_by_name("cliff")
		if cliff_by_name != -1:
			cliff_terrain_id = cliff_by_name

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
