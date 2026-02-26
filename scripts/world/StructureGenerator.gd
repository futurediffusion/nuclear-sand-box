extends RefCounted
class_name StructureGenerator

## Resultado de generate_tavern. Todo son coordenadas de tile, sin tocar TileMap.
class TavernData:
	var floor_cells: Array[Vector2i] = []
	var wall_cells: Array[Vector2i] = []
	var door_cells: Array[Vector2i] = []
	var bounds: Rect2i
	var inner_min: Vector2i
	var inner_max: Vector2i
	var placements: Array[Dictionary] = []

func generate_tavern(chunk_pos: Vector2i, chunk_size: int) -> TavernData:
	var d := TavernData.new()

	var w: int = 12
	var h: int = 8
	var x0: int = chunk_pos.x * chunk_size + 4
	var y0: int = chunk_pos.y * chunk_size + 3
	var x1: int = x0 + w - 1
	var y1: int = y0 + h - 1
	var door_x: int = x0 + w / 2

	d.bounds = Rect2i(x0, y0, w, h)
	d.inner_min = Vector2i(x0 + 1, y0 + 1)
	d.inner_max = Vector2i(x1 - 1, y1 - 1)

	for y: int in range(y0 + 1, y1):
		for x: int in range(x0 + 1, x1):
			d.floor_cells.append(Vector2i(x, y))

	for x: int in range(x0, x1 + 1):
		d.wall_cells.append(Vector2i(x, y0 + 1))

	for x: int in range(x0, x1 + 1):
		if x == door_x:
			d.door_cells.append(Vector2i(x, y1))
			continue
		d.wall_cells.append(Vector2i(x, y1))

	for y: int in range(y0 + 2, y1):
		d.wall_cells.append(Vector2i(x0, y))
		d.wall_cells.append(Vector2i(x1, y))

	d.placements = _generate_furniture(d.inner_min, d.inner_max, Vector2i(door_x, y1))
	return d

func _is_free(occupied: Dictionary, cell: Vector2i) -> bool:
	return not occupied.has(cell)

func _mark_rect(occupied: Dictionary, pos: Vector2i, size: Vector2i) -> void:
	for y: int in range(size.y):
		for x: int in range(size.x):
			occupied[Vector2i(pos.x + x, pos.y + y)] = true

func _rect_fits_and_free(occupied: Dictionary, pos: Vector2i, size: Vector2i, inner_min: Vector2i, inner_max: Vector2i) -> bool:
	for y: int in range(size.y):
		for x: int in range(size.x):
			var c: Vector2i = Vector2i(pos.x + x, pos.y + y)
			if c.x < inner_min.x or c.y < inner_min.y or c.x > inner_max.x or c.y > inner_max.y:
				return false
			if occupied.has(c):
				return false
	return true

func _generate_furniture(inner_min: Vector2i, inner_max: Vector2i, door_cell: Vector2i) -> Array[Dictionary]:
	var occupied: Dictionary = {}
	var placements: Array[Dictionary] = []

	for i: int in range(4):
		for w: int in range(2):
			occupied[Vector2i(door_cell.x + w, door_cell.y - i)] = true

	var counter_size: Vector2i = Vector2i(3, 1)
	var counter_pos: Vector2i = Vector2i(door_cell.x, inner_min.y + 2)
	var counter_cell: Vector2i = counter_pos
	if _rect_fits_and_free(occupied, counter_pos, counter_size, inner_min, inner_max):
		_mark_rect(occupied, counter_pos, counter_size)
		placements.append({
			"kind": "prop",
			"prop_id": "counter",
			"site_id": "tavern_counter_01",
			"cell": [counter_pos.x, counter_pos.y]
		})
		var behind: Vector2i = Vector2i(counter_pos.x, counter_pos.y - 1)
		if behind.y >= inner_min.y:
			_mark_rect(occupied, behind, Vector2i(counter_size.x, 1))
		counter_cell = Vector2i(counter_pos.x + 1, counter_pos.y - 1)

	var table_size: Vector2i = Vector2i(2, 2)
	var placed_tables: int = 0
	var candidates: Array[Vector2i] = [
		Vector2i(inner_min.x + 2, inner_max.y - 1),
		Vector2i(inner_max.x - 2, inner_max.y - 1),
	]
	for pos in candidates:
		if placed_tables >= 2:
			break
		if _rect_fits_and_free(occupied, pos, table_size, inner_min, inner_max):
			_mark_rect(occupied, pos, table_size)
			placed_tables += 1
			placements.append({
				"kind": "prop",
				"prop_id": "table",
				"site_id": "tavern_table_%02d" % placed_tables,
				"cell": [pos.x, pos.y]
			})

	var corners: Array[Vector2i] = [
		Vector2i(inner_min.x, inner_min.y + 1),
		Vector2i(inner_max.x, inner_min.y + 1),
		Vector2i(inner_min.x, inner_max.y),
		Vector2i(inner_max.x, inner_max.y),
	]
	var barrel_count: int = 0
	for c in corners:
		if barrel_count >= 4:
			break
		if _is_free(occupied, c):
			occupied[c] = true
			barrel_count += 1
			placements.append({
				"kind": "prop",
				"prop_id": "barrel",
				"site_id": "tavern_barrel_%02d" % barrel_count,
				"cell": [c.x, c.y]
			})

	placements.append({
		"kind": "npc_keeper",
		"site_id": "tavern_keeper_01",
		"cell": [counter_cell.x, counter_cell.y],
		"inner_min": [inner_min.x, inner_min.y],
		"inner_max": [inner_max.x, inner_max.y]
	})

	return placements
