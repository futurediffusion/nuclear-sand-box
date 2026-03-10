extends Node

@export var ground: TileMap
@export var map_size := Vector2i(120, 120)

const TERRAIN_SET := 0
const GRASS := 0
const DIRT := 1


func _ready() -> void:
	randomize()
	generate_world()


func fill_grass() -> void:
	for x in range(map_size.x):
		for y in range(map_size.y):
			ground.set_cells_terrain_connect(
				0,
				[Vector2i(x, y)],
				TERRAIN_SET,
				GRASS
			)


func blob(center: Vector2i, radius: int) -> void:
	for x in range(-radius, radius):
		for y in range(-radius, radius):
			var pos := center + Vector2i(x, y)
			if pos.x < 0 or pos.y < 0:
				continue
			if pos.x >= map_size.x or pos.y >= map_size.y:
				continue

			var dist := Vector2(x, y).length()
			if dist < radius + randf_range(-2.0, 2.0):
				ground.set_cells_terrain_connect(
					0,
					[pos],
					TERRAIN_SET,
					DIRT
				)


func patch_rect(center: Vector2i, size: int) -> void:
	for x in range(-size, size):
		for y in range(-size, size):
			if randf() < 0.85:
				var pos := center + Vector2i(x, y)
				if pos.x < 0 or pos.y < 0:
					continue
				if pos.x >= map_size.x or pos.y >= map_size.y:
					continue

				ground.set_cells_terrain_connect(
					0,
					[pos],
					TERRAIN_SET,
					DIRT
				)


func path(start: Vector2i, length: int) -> void:
	var pos := start
	var dirs := [
		Vector2i.LEFT,
		Vector2i.RIGHT,
		Vector2i.UP,
		Vector2i.DOWN,
	]
	var dir: Vector2i = dirs.pick_random()

	for _i in range(length):
		if pos.x < 0 or pos.y < 0 or pos.x >= map_size.x or pos.y >= map_size.y:
			break

		ground.set_cells_terrain_connect(
			0,
			[pos],
			TERRAIN_SET,
			DIRT
		)

		pos += dir
		if randf() < 0.25:
			dir = dirs.pick_random()


func sprinkle() -> void:
	for _i in range(200):
		var pos := Vector2i(
			randi_range(0, map_size.x - 1),
			randi_range(0, map_size.y - 1)
		)
		if randf() < 0.35:
			ground.set_cells_terrain_connect(
				0,
				[pos],
				TERRAIN_SET,
				DIRT
			)


func generate_world() -> void:
	fill_grass()

	for _i in range(6):
		blob(
			Vector2i(
				randi_range(10, map_size.x - 10),
				randi_range(10, map_size.y - 10)
			),
			randi_range(6, 12)
		)

	for _i in range(4):
		patch_rect(
			Vector2i(
				randi_range(10, map_size.x - 10),
				randi_range(10, map_size.y - 10)
			),
			randi_range(3, 6)
		)

	for _i in range(8):
		path(
			Vector2i(
				randi_range(0, map_size.x - 1),
				randi_range(0, map_size.y - 1)
			),
			randi_range(10, 40)
		)

	sprinkle()
