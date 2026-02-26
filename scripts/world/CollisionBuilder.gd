extends RefCounted
class_name CollisionBuilder

func build_chunk_walls(tilemap: TileMap, chunk_pos: Vector2i, chunk_size: int, walls_layer: int, walls_source_id: int) -> StaticBody2D:
	if tilemap == null:
		return null

	var tile_size: Vector2 = Vector2(32, 32)
	if tilemap.tile_set != null:
		tile_size = tilemap.tile_set.tile_size

	var band_height: float = tile_size.y * 0.25
	if band_height <= 0.0:
		return null

	var start_x: int = chunk_pos.x * chunk_size
	var start_y: int = chunk_pos.y * chunk_size
	var end_x: int = start_x + chunk_size - 1
	var end_y: int = start_y + chunk_size - 1

	var margin: int = 1
	var wall_lookup: Dictionary = {}

	for y in range(start_y - margin, end_y + margin + 1):
		for x in range(start_x - margin, end_x + margin + 1):
			var cell := Vector2i(x, y)
			if tilemap.get_cell_source_id(walls_layer, cell) == walls_source_id:
				wall_lookup[cell] = true

	var body := StaticBody2D.new()
	body.name = "WallCollisionBody_%d_%d" % [chunk_pos.x, chunk_pos.y]
	body.collision_layer = 2
	body.collision_mask = 0

	var shape_count: int = 0
	for y in range(start_y, end_y + 1):
		var run_start_x: int = start_x
		var in_run: bool = false

		for x in range(start_x, end_x + 2):
			var cell := Vector2i(x, y)
			var is_wall: bool = wall_lookup.has(cell)
			var south_exposed: bool = false
			if is_wall:
				south_exposed = not wall_lookup.has(cell + Vector2i(0, 1))

			if south_exposed:
				if not in_run:
					run_start_x = x
					in_run = true
				continue

			if not in_run:
				continue

			var run_end_x: int = x - 1
			var len_tiles: int = run_end_x - run_start_x + 1
			if len_tiles <= 0:
				in_run = false
				continue

			var shape := CollisionShape2D.new()
			var rect := RectangleShape2D.new()
			rect.size = Vector2(float(len_tiles) * tile_size.x, band_height)
			shape.shape = rect

			var left_center: Vector2 = tilemap.map_to_local(Vector2i(run_start_x, y))
			var right_center: Vector2 = tilemap.map_to_local(Vector2i(run_end_x, y))
			var center_x: float = (left_center.x + right_center.x) * 0.5
			var center_y: float = left_center.y + tile_size.y * 0.5 - band_height * 0.5
			shape.position = Vector2(center_x, center_y)

			body.add_child(shape)
			shape_count += 1
			in_run = false

	if shape_count == 0:
		body.queue_free()
		return null

	return body
