extends RefCounted
class_name CollisionBuilder

func _append_raw_side(raw_columns: Dictionary, face: String, x: int, y: int) -> void:
	if not raw_columns.has(face):
		raw_columns[face] = {}
	var face_columns: Dictionary = raw_columns[face]
	if not face_columns.has(x):
		face_columns[x] = []
	face_columns[x].append(y)

func _add_side_strip_run(body: StaticBody2D, tilemap: TileMap, face: String, col_x: int, y0: int, y1: int, tile_size: Vector2, side_width: float) -> void:
	var len_tiles: int = y1 - y0 + 1
	if len_tiles <= 0:
		return

	var shape := CollisionShape2D.new()
	shape.name = "SideStrip_%s_%d_%d" % [face, col_x, y0]
	shape.set_meta("aaa", {"kind": "side", "face": face, "north_free": false})
	var rect := RectangleShape2D.new()
	rect.size = Vector2(side_width, float(len_tiles) * tile_size.y)
	shape.shape = rect

	var top_center: Vector2 = tilemap.map_to_local(Vector2i(col_x, y0))
	var bottom_center: Vector2 = tilemap.map_to_local(Vector2i(col_x, y1))
	var side_x: float = top_center.x
	if face == "W":
		side_x += -tile_size.x * 0.5 + side_width * 0.5
	else:
		side_x += tile_size.x * 0.5 - side_width * 0.5
	shape.position = Vector2(side_x, (top_center.y + bottom_center.y) * 0.5)

	body.add_child(shape)

func _add_side_strip_top_tile(body: StaticBody2D, tilemap: TileMap, face: String, cell: Vector2i, tile_size: Vector2, side_width: float, band_height: float) -> void:
	var shape := CollisionShape2D.new()
	shape.name = "SideStripTop_%s_%d_%d" % [face, cell.x, cell.y]
	shape.set_meta("aaa", {"kind": "side", "face": face, "north_free": true})
	var rect := RectangleShape2D.new()
	rect.size = Vector2(side_width, band_height)
	shape.shape = rect

	var center: Vector2 = tilemap.map_to_local(cell)
	var side_x: float = center.x
	if face == "W":
		side_x += -tile_size.x * 0.5 + side_width * 0.5
	else:
		side_x += tile_size.x * 0.5 - side_width * 0.5
	var center_y: float = center.y + tile_size.y * 0.5 - band_height * 0.5
	shape.position = Vector2(side_x, center_y)

	body.add_child(shape)

func _add_upper_corner_south_band(body: StaticBody2D, tilemap: TileMap, cell: Vector2i, tile_size: Vector2, band_height: float, inset: float) -> void:
	var shape := CollisionShape2D.new()
	shape.name = "UpperCornerSouthBand_%d_%d" % [cell.x, cell.y]
	shape.set_meta("kind", "upper_corner_south_band")
	shape.set_meta("aaa", {"kind": "upper_corner_south_band"})
	var rect := RectangleShape2D.new()
	rect.size = Vector2(max(tile_size.x - inset * 2.0, 0.001), band_height)
	shape.shape = rect

	var center: Vector2 = tilemap.map_to_local(cell)
	shape.position = Vector2(center.x, center.y + tile_size.y * 0.5 - band_height * 0.5)
	body.add_child(shape)

func _is_top_left_corner(wall_lookup: Dictionary, cell: Vector2i) -> bool:
	if not wall_lookup.has(cell):
		return false

	var north_free: bool = not wall_lookup.has(cell + Vector2i(0, -1))
	var south_wall: bool = wall_lookup.has(cell + Vector2i(0, 1))
	var east_wall: bool = wall_lookup.has(cell + Vector2i(1, 0))
	var west_wall: bool = wall_lookup.has(cell + Vector2i(-1, 0))
	return north_free and south_wall and east_wall and not west_wall

func _is_top_right_corner(wall_lookup: Dictionary, cell: Vector2i) -> bool:
	if not wall_lookup.has(cell):
		return false

	var north_free: bool = not wall_lookup.has(cell + Vector2i(0, -1))
	var south_wall: bool = wall_lookup.has(cell + Vector2i(0, 1))
	var west_wall: bool = wall_lookup.has(cell + Vector2i(-1, 0))
	var east_wall: bool = wall_lookup.has(cell + Vector2i(1, 0))
	return north_free and south_wall and west_wall and not east_wall

func _should_add_corner_blocker(wall_lookup: Dictionary, x: int, y: int, side: int) -> bool:
	var edge_cell := Vector2i(x, y)
	if not wall_lookup.has(edge_cell):
		return false
	if wall_lookup.has(edge_cell + Vector2i(0, 1)):
		return false

	var side_neighbor := Vector2i(x + side, y)
	if not wall_lookup.has(side_neighbor):
		return false

	var north_wall: bool = wall_lookup.has(edge_cell + Vector2i(0, -1))
	var inward_wall: bool = wall_lookup.has(side_neighbor)
	return north_wall or inward_wall

func _is_bottom_left_inner_corner(wall_lookup: Dictionary, cell: Vector2i) -> bool:
	if not wall_lookup.has(cell):
		return false

	var south_free: bool = not wall_lookup.has(cell + Vector2i(0, 1))
	var east_wall: bool = wall_lookup.has(cell + Vector2i(1, 0))
	var west_free: bool = not wall_lookup.has(cell + Vector2i(-1, 0))
	var north_wall: bool = wall_lookup.has(cell + Vector2i(0, -1)) or wall_lookup.has(cell + Vector2i(1, -1))
	return south_free and east_wall and west_free and north_wall

func _is_bottom_right_inner_corner(wall_lookup: Dictionary, cell: Vector2i) -> bool:
	if not wall_lookup.has(cell):
		return false

	var south_free: bool = not wall_lookup.has(cell + Vector2i(0, 1))
	var west_wall: bool = wall_lookup.has(cell + Vector2i(-1, 0))
	var east_free: bool = not wall_lookup.has(cell + Vector2i(1, 0))
	var north_wall: bool = wall_lookup.has(cell + Vector2i(0, -1)) or wall_lookup.has(cell + Vector2i(-1, -1))
	return south_free and west_wall and east_free and north_wall

func build_chunk_walls(tilemap: TileMap, chunk_pos: Vector2i, chunk_size: int, walls_layer: int, walls_source_id: int) -> StaticBody2D:
	if tilemap == null:
		return null

	var tile_size: Vector2 = Vector2(32, 32)
	if tilemap.tile_set != null:
		tile_size = tilemap.tile_set.tile_size

	var band_height: float = tile_size.y * 0.25
	if band_height <= 0.0:
		return null
	var side_width: float = tile_size.x * 0.25
	var inset: float = 0.0
	var corner_height: float = tile_size.y * 0.70
	var plug_width: float = side_width
	var plug_height: float = tile_size.y * 0.70

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
	var south_runs: Array[Dictionary] = []
	var raw_side_columns: Dictionary = {"W": {}, "E": {}}
	var top_side_tiles: Array[Dictionary] = []
	var upper_corner_south_bands: Array[Vector2i] = []
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
			south_runs.append({"x0": run_start_x, "x1": run_end_x, "y": y})
			in_run = false

	for y in range(start_y, end_y + 1):
		for x in range(start_x, end_x + 1):
			var cell := Vector2i(x, y)
			if not wall_lookup.has(cell):
				continue

			var north_free: bool = not wall_lookup.has(cell + Vector2i(0, -1))
			var is_top_corner: bool = _is_top_left_corner(wall_lookup, cell) or _is_top_right_corner(wall_lookup, cell)
			if not wall_lookup.has(cell + Vector2i(-1, 0)):
				if north_free and not is_top_corner:
					top_side_tiles.append({"face": "W", "cell": cell})
				elif not north_free:
					_append_raw_side(raw_side_columns, "W", x, y)
			if not wall_lookup.has(cell + Vector2i(1, 0)):
				if north_free and not is_top_corner:
					top_side_tiles.append({"face": "E", "cell": cell})
				elif not north_free:
					_append_raw_side(raw_side_columns, "E", x, y)

			if is_top_corner:
				upper_corner_south_bands.append(cell)

	for face in ["W", "E"]:
		var face_columns: Dictionary = raw_side_columns[face]
		var sorted_columns: Array = face_columns.keys()
		sorted_columns.sort()
		for col_x in sorted_columns:
			var ys: Array = face_columns[col_x]
			ys.sort()
			var run_y0: int = ys[0]
			var prev_y: int = ys[0]
			for i in range(1, ys.size()):
				var current_y: int = ys[i]
				if current_y == prev_y + 1:
					prev_y = current_y
					continue

				_add_side_strip_run(body, tilemap, face, col_x, run_y0, prev_y, tile_size, side_width)
				shape_count += 1
				run_y0 = current_y
				prev_y = current_y

			_add_side_strip_run(body, tilemap, face, col_x, run_y0, prev_y, tile_size, side_width)
			shape_count += 1

	for side_tile in top_side_tiles:
		_add_side_strip_top_tile(body, tilemap, side_tile["face"], side_tile["cell"], tile_size, side_width, band_height)
		shape_count += 1

	for cap_cell in upper_corner_south_bands:
		_add_upper_corner_south_band(body, tilemap, cap_cell, tile_size, band_height, inset)
		shape_count += 1

	var corner_width: float = side_width
	for run in south_runs:
		var x0: int = run["x0"]
		var x1: int = run["x1"]
		var y: int = run["y"]

		if _should_add_corner_blocker(wall_lookup, x0, y, -1):
			var left_center: Vector2 = tilemap.map_to_local(Vector2i(x0, y))
			var left_blocker := CollisionShape2D.new()
			left_blocker.name = "CornerBlocker_%d_%d_left" % [x0, y]
			left_blocker.set_meta("is_corner_blocker", true)
			left_blocker.set_meta("aaa", {"kind": "corner_blocker", "side": -1})
			var left_rect := RectangleShape2D.new()
			left_rect.size = Vector2(corner_width, corner_height)
			left_blocker.shape = left_rect
			left_blocker.position = Vector2(
				left_center.x - tile_size.x * 0.5 + corner_width * 0.5,
				left_center.y + tile_size.y * 0.5 - band_height - corner_height * 0.5 + 2.0
			)
			body.add_child(left_blocker)
			shape_count += 1

		if _should_add_corner_blocker(wall_lookup, x1, y, 1):
			var right_center: Vector2 = tilemap.map_to_local(Vector2i(x1, y))
			var right_blocker := CollisionShape2D.new()
			right_blocker.name = "CornerBlocker_%d_%d_right" % [x1, y]
			right_blocker.set_meta("is_corner_blocker", true)
			right_blocker.set_meta("aaa", {"kind": "corner_blocker", "side": 1})
			var right_rect := RectangleShape2D.new()
			right_rect.size = Vector2(corner_width, corner_height)
			right_blocker.shape = right_rect
			right_blocker.position = Vector2(
				right_center.x + tile_size.x * 0.5 - corner_width * 0.5,
				right_center.y + tile_size.y * 0.5 - band_height - corner_height * 0.5 + 2.0
			)
			body.add_child(right_blocker)
			shape_count += 1

	for y in range(start_y, end_y + 1):
		for x in range(start_x, end_x + 1):
			var cell := Vector2i(x, y)
			var center: Vector2 = tilemap.map_to_local(cell)
			var plug_center_y: float = center.y + tile_size.y * 0.5 - band_height - plug_height * 0.5 + 2.0

			if _is_bottom_left_inner_corner(wall_lookup, cell):
				var left_plug := CollisionShape2D.new()
				left_plug.name = "InnerCornerPlug_%d_%d_E" % [x, y]
				left_plug.set_meta("kind", "inner_corner_plug")
				left_plug.set_meta("side", "E")
				left_plug.set_meta("aaa", {"kind": "inner_corner_plug", "side": "E"})
				var left_plug_rect := RectangleShape2D.new()
				left_plug_rect.size = Vector2(plug_width, plug_height)
				left_plug.shape = left_plug_rect
				left_plug.position = Vector2(
					center.x + tile_size.x * 0.5 - plug_width * 0.5,
					plug_center_y
				)
				body.add_child(left_plug)
				shape_count += 1

			if _is_bottom_right_inner_corner(wall_lookup, cell):
				var right_plug := CollisionShape2D.new()
				right_plug.name = "InnerCornerPlug_%d_%d_W" % [x, y]
				right_plug.set_meta("kind", "inner_corner_plug")
				right_plug.set_meta("side", "W")
				right_plug.set_meta("aaa", {"kind": "inner_corner_plug", "side": "W"})
				var right_plug_rect := RectangleShape2D.new()
				right_plug_rect.size = Vector2(plug_width, plug_height)
				right_plug.shape = right_plug_rect
				right_plug.position = Vector2(
					center.x - tile_size.x * 0.5 + plug_width * 0.5,
					plug_center_y
				)
				body.add_child(right_plug)
				shape_count += 1

	if shape_count == 0:
		body.queue_free()
		return null

	return body
