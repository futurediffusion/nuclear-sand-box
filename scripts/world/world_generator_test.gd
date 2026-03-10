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
@export var biome_module_size: int = 6
@export var biome_module_bias: float = 0.22
@export var dirt_threshold: float = 0.46
@export var grass_threshold: float = 0.60

var biome_noise := FastNoiseLite.new()

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

	biome_noise.seed = randi()
	biome_noise.frequency = 0.015
	biome_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH

	generate_world()
	spawn_player_center()
	print("Generated cells:", tilemap.get_used_cells(layer).size())


func generate_world() -> void:
	tilemap.clear_layer(layer)
	var dirt_cells: Array[Vector2i] = []
	var grass_cells: Array[Vector2i] = []

	for x in range(x_min, x_max + 1):
		for y in range(y_min, y_max + 1):
			var cell := Vector2i(x, y)
			if get_biome(x, y) == 0:
				dirt_cells.append(cell)
			else:
				grass_cells.append(cell)

	if dirt_cells.size() > 0:
		tilemap.set_cells_terrain_connect(layer, dirt_cells, terrain_set_id, dirt_terrain_id, false)

	if grass_cells.size() > 0:
		tilemap.set_cells_terrain_connect(layer, grass_cells, terrain_set_id, grass_terrain_id, false)

	# Segunda pasada para que el autotile vuelva a evaluar bordes entre biomas.
	if dirt_cells.size() > 0:
		tilemap.set_cells_terrain_connect(layer, dirt_cells, terrain_set_id, dirt_terrain_id, false)

	if grass_cells.size() > 0:
		tilemap.set_cells_terrain_connect(layer, grass_cells, terrain_set_id, grass_terrain_id, false)


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


func get_biome(x: int, y: int) -> int:
	var noise_v := (biome_noise.get_noise_2d(x, y) + 1.0) * 0.5
	var module_v := _module_pattern_value(x, y)
	var v := clampf(noise_v + (module_v * biome_module_bias), 0.0, 1.0)
	if v < dirt_threshold:
		return 0
	elif v >= grass_threshold:
		return 1
	return 0


func _module_pattern_value(x: int, y: int) -> float:
	var module_size: int = max(1, biome_module_size)
	var module_x: int = int(floor(float(x) / float(module_size)))
	var module_y: int = int(floor(float(y) / float(module_size)))
	var module_pos := Vector2i(module_x, module_y)

	var gate_roll: int = int(abs(hash(module_pos)) % 100)
	var path_roll: int = int(abs(hash(module_pos + Vector2i(31, 17))) % 100)
	if gate_roll < 18:
		return -1.0
	if path_roll < 28:
		return -0.65

	var block_roll: int = int(abs(hash(module_pos + Vector2i(97, -53))) % 100)
	if block_roll < 36:
		return 0.20
	if block_roll > 84:
		return 0.75
	return -0.15


func spawn_player_center() -> void:
	if player == null:
		push_warning("WorldGeneratorTest: Player no encontrado para reposicionar.")
		return

	player.global_position = tilemap.map_to_local(Vector2i(0, -5))
