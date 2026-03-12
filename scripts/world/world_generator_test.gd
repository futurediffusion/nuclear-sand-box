extends Node

const WorldTerrainConfig = preload("res://scripts/world/WorldTerrainConfig.gd")

@export var map_min_x := -100
@export var map_max_x := 100
@export var map_min_y := -40
@export var map_max_y := 10
@export var grass_source_id := WorldTerrainConfig.GRASS_ID
@export var dirt_source_id := WorldTerrainConfig.DIRT_ID
@export var ground_atlas := Vector2i(0, 0)
@export var dirt_atlas := Vector2i(0, 0)

@onready var tilemap: TileMap = get_node_or_null("../TileMapGround")
@onready var player: Node2D = get_node_or_null("../Player")


func _ready() -> void:
	if tilemap == null:
		push_error("WorldGeneratorTest: no se encontró ../TileMapGround")
		return

	if tilemap.tile_set == null:
		push_error("WorldGeneratorTest: TileMapGround no tiene TileSet asignado")
		return

	randomize()
	generate_world()
	spawn_player_center()
	print("Generated cells:", tilemap.get_used_cells(WorldTerrainConfig.TERRAIN_SET).size())


func generate_world() -> void:
	tilemap.clear_layer(WorldTerrainConfig.TERRAIN_SET)

	for x in range(map_min_x, map_max_x + 1):
		for y in range(map_min_y, map_max_y + 1):
			var use_dirt := y > -8 or randf() < 0.08
			if use_dirt:
				tilemap.set_cell(WorldTerrainConfig.TERRAIN_SET, Vector2i(x, y), dirt_source_id, dirt_atlas)
			else:
				tilemap.set_cell(WorldTerrainConfig.TERRAIN_SET, Vector2i(x, y), grass_source_id, ground_atlas)


func spawn_player_center() -> void:
	if player == null:
		push_warning("WorldGeneratorTest: no se encontró ../Player para reposicionar")
		return

	player.global_position = tilemap.map_to_local(Vector2i(0, -5))
