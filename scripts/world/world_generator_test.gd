extends Node

@export_node_path("TileMap") var ground_path: NodePath = ^"../TileMapGround"
@export_node_path("Node2D") var player_path: NodePath = ^"../Player"

@export var x_min := -100
@export var x_max := 100
@export var y_min := -40
@export var y_max := 10
@export var layer := 0
@export var source_id := 0
@export var atlas_coords := Vector2i(0, 0)

@onready var tilemap: TileMap = get_node_or_null(ground_path)
@onready var player: Node2D = get_node_or_null(player_path)


func _ready() -> void:
	if tilemap == null:
		push_error("WorldGeneratorTest: TileMapGround no configurado (ground_path).")
		return

	if tilemap.tile_set == null:
		push_error("WorldGeneratorTest: TileMapGround no tiene TileSet asignado.")
		return

	if not tilemap.tile_set.has_source(source_id):
		push_error("WorldGeneratorTest: source_id %d no existe en el TileSet." % source_id)
		return

	generate_world()
	spawn_player_center()
	print("Generated cells:", tilemap.get_used_cells(layer).size())


func generate_world() -> void:
	tilemap.clear_layer(layer)
	for x in range(x_min, x_max + 1):
		for y in range(y_min, y_max + 1):
			tilemap.set_cell(layer, Vector2i(x, y), source_id, atlas_coords)


func spawn_player_center() -> void:
	if player == null:
		push_warning("WorldGeneratorTest: Player no encontrado para reposicionar.")
		return

	player.global_position = tilemap.map_to_local(Vector2i(0, -5))
