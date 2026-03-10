extends Node

@export_node_path("TileMap") var ground_path: NodePath = ^"../TileMapGround"
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

var nodes: Array[Dictionary] = []

@onready var tilemap: TileMap = get_node_or_null(ground_path)
@onready var player: Node2D = get_node_or_null(player_path)


func _ready() -> void:
	if tilemap == null:
		push_error("WorldGeneratorTest: TileMapGround no configurado (ground_path).")
		return

	if tilemap.tile_set == null:
		push_error("WorldGeneratorTest: TileMapGround no tiene TileSet asignado.")
		return

	_sync_terrain_ids_from_tileset()
	generate_world()
	spawn_player_center()
	print("Generated cells:", tilemap.get_used_cells(layer).size())


func generate_world() -> void:
	tilemap.clear_layer(layer)
	nodes.clear()

	# Base completa de pasto para que el dirt use transiciones del terrain set existente.
	var all_cells: Array[Vector2i] = []
	for x in range(x_min, x_max + 1):
		for y in range(y_min, y_max + 1):
			all_cells.append(Vector2i(x, y))
	if all_cells.size() > 0:
		tilemap.set_cells_terrain_connect(layer, all_cells, terrain_set_id, grass_terrain_id, false)

	create_nodes()
	connect_nodes()
	paint_terrain_features()


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


func paint_terrain_features() -> void:
	for node_data in nodes:
		paint_node(node_data)

	# Parches sueltos para romper formas demasiado limpias.
	var patch_count := randi_range(6, 12)
	for _i in range(patch_count):
		paint_small_patch(Vector2i(
			randi_range(x_min + edge_margin_x, x_max - edge_margin_x),
			randi_range(y_min + edge_margin_y, y_max - edge_margin_y)
		))


func paint_node(node_data: Dictionary) -> void:
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

	if cells.size() > 0:
		tilemap.set_cells_terrain_connect(layer, cells, terrain_set_id, dirt_terrain_id, false)


func draw_path(a: Vector2i, b: Vector2i) -> void:
	var pos := a
	var corridor_cells: Array[Vector2i] = []

	while pos != b:
		_append_corridor_brush(corridor_cells, pos)

		if abs(b.x - pos.x) > abs(b.y - pos.y):
			pos.x += sign(b.x - pos.x)
		else:
			pos.y += sign(b.y - pos.y)

	_append_corridor_brush(corridor_cells, b)
	if corridor_cells.size() > 0:
		tilemap.set_cells_terrain_connect(layer, corridor_cells, terrain_set_id, dirt_terrain_id, false)


func paint_small_patch(center: Vector2i) -> void:
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

	if filtered.size() > 0:
		tilemap.set_cells_terrain_connect(layer, filtered, terrain_set_id, dirt_terrain_id, false)


func _append_corridor_brush(cells: Array[Vector2i], pos: Vector2i) -> void:
	for x in range(-corridor_width, corridor_width + 1):
		for y in range(-corridor_width, corridor_width + 1):
			var p := pos + Vector2i(x, y)
			if _is_inside_bounds(p):
				cells.append(p)


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

	var spawn_cell: Vector2i = nodes[0]["pos"]
	player.global_position = tilemap.map_to_local(spawn_cell)
