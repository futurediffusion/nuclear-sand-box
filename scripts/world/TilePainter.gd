extends RefCounted
class_name TilePainter

func apply_floor(tilemap: TileMap, layer: int, source_id: int, atlas: Vector2i, cells: Array[Vector2i]) -> void:
	if cells.is_empty():
		return

	if tilemap.has_method("set_cells"):
		tilemap.set_cells(layer, cells, source_id, atlas)
		return

	for cell in cells:
		tilemap.set_cell(layer, cell, source_id, atlas)


func apply_walls_terrain_connect(tilemap: TileMap, layer: int, terrain_set: int, terrain: int, cells: Array[Vector2i]) -> void:
	if cells.is_empty():
		return
	tilemap.set_cells_terrain_connect(layer, cells, terrain_set, terrain, true)


func apply_manual_tiles(tilemap: TileMap, tiles: Array[Dictionary]) -> void:
	for t in tiles:
		tilemap.set_cell(int(t["layer"]), t["tile"], int(t.get("source", 0)), t["atlas"])


func erase_chunk_region(tilemap: TileMap, chunk_pos: Vector2i, chunk_size: int, layers: Array[int]) -> void:
	var start_x: int = chunk_pos.x * chunk_size
	var start_y: int = chunk_pos.y * chunk_size
	for y in range(start_y, start_y + chunk_size):
		for x in range(start_x, start_x + chunk_size):
			var tile_pos := Vector2i(x, y)
			for layer in layers:
				tilemap.erase_cell(layer, tile_pos)
