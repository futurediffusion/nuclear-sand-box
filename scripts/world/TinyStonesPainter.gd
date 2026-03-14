class_name TinyStonesPainter extends RefCounted

## Cuántas variantes hay en tiny-stones.png (columnas del sheet 16×16).
var stone_variant_count: int = 8

var grass_atlas_coords: Array[Vector2i] = []

var _ground_tilemap: TileMap
var _vegetation_root: Node2D
var _stone_texture: Texture2D
var _chunk_size: int = 32
var _tile_size: int = 32
var _active_mmis: Dictionary = {}  # Vector2i -> Array[MultiMeshInstance2D]
var _grass_source_id: int = -1
var _grass_terrain_id: int = 1
## Densidad: fracción de tiles grass que tendrán una piedra (0.0–1.0).
var _stone_density: float = 0.05
## Tamaño del quad en px de mundo.
var _stone_size: float = 7.0
var _excluded_rects: Array[Rect2i] = []

const SPRITE_W: int = 16
const SPRITE_H: int = 16


func setup(ctx: Dictionary) -> void:
	_ground_tilemap = ctx["ground_tilemap"] as TileMap
	_vegetation_root = ctx["vegetation_root"] as Node2D
	_stone_texture = ctx["stone_texture"] as Texture2D
	_chunk_size = ctx["chunk_size"] as int
	_tile_size = ctx["tile_size"] as int
	if ctx.has("grass_atlas_coords"):
		grass_atlas_coords = ctx["grass_atlas_coords"] as Array[Vector2i]
	if ctx.has("grass_source_id"):
		_grass_source_id = ctx["grass_source_id"] as int
	if ctx.has("grass_terrain_id"):
		_grass_terrain_id = ctx["grass_terrain_id"] as int
	if ctx.has("stone_density"):
		_stone_density = ctx["stone_density"] as float
	if ctx.has("stone_size"):
		_stone_size = ctx["stone_size"] as float
	if ctx.has("stone_variant_count"):
		stone_variant_count = ctx["stone_variant_count"] as int


func set_excluded_rects(rects: Array[Rect2i]) -> void:
	_excluded_rects = rects


func _is_excluded(tile: Vector2i) -> bool:
	for r: Rect2i in _excluded_rects:
		if r.has_point(tile):
			return true
	return false


func load_chunk(chunk_coords: Vector2i) -> void:
	var data: Array = WorldSave.get_tiny_stones_data(chunk_coords)
	if data.is_empty():
		data = _generate_stones(chunk_coords)
		WorldSave.set_tiny_stones_data(chunk_coords, data)
	_build_multimesh(chunk_coords, data)


func unload_chunk(chunk_coords: Vector2i) -> void:
	if not _active_mmis.has(chunk_coords):
		return
	for mmi in _active_mmis[chunk_coords]:
		var node := mmi as Node
		if is_instance_valid(node):
			node.queue_free()
	_active_mmis.erase(chunk_coords)


func _generate_stones(chunk_coords: Vector2i) -> Array:
	var result: Array = []
	for y in range(_chunk_size):
		for x in range(_chunk_size):
			var tile_world: Vector2i = chunk_coords * _chunk_size + Vector2i(x, y)

			var src_id: int = _ground_tilemap.get_cell_source_id(0, tile_world)
			if src_id == -1:
				continue
			if _grass_source_id >= 0 and src_id != _grass_source_id:
				continue

			if _is_excluded(tile_world):
				continue

			# Hash determinista — primo distinto a Flower / Fungus / Sticks
			# (sin filtro de terrain: las piedras aparecen sobre grass Y dirt)
			var h: int = hash(chunk_coords.x * 92821363 ^ chunk_coords.y * 58277431 ^ x * 1000 ^ y)

			if absf(float(h % 100)) > _stone_density * 100.0:
				continue

			var variant: int = abs(h / 100) % stone_variant_count

			var ox: float = float((h >> 8) % 17) - 8.0
			var oy: float = float((h >> 16) % 17) - 8.0

			result.append({
				"tile": tile_world,
				"variant": variant,
				"offset": Vector2(ox, oy)
			})
	return result


func _build_multimesh(chunk_coords: Vector2i, stones: Array) -> void:
	if stones.is_empty():
		return

	var by_variant: Dictionary = {}
	for item in stones:
		var stone: Dictionary = item as Dictionary
		var v: int = stone["variant"] as int
		if not by_variant.has(v):
			by_variant[v] = []
		(by_variant[v] as Array).append(stone)

	_active_mmis[chunk_coords] = []

	var tex_w: float = float(_stone_texture.get_width())
	var tex_h: float = float(_stone_texture.get_height())
	var sheet_cols: int = int(tex_w) / SPRITE_W

	var h: float = _stone_size * 0.5

	for raw_variant in by_variant.keys():
		var variant: int = raw_variant as int
		var variant_stones: Array = by_variant[variant] as Array

		var col: int = variant % sheet_cols
		var row: int = variant / sheet_cols

		var uv_x0: float = float(col * SPRITE_W) / tex_w
		var uv_y0: float = float(row * SPRITE_H) / tex_h
		var uv_x1: float = float(col * SPRITE_W + SPRITE_W) / tex_w
		var uv_y1: float = float(row * SPRITE_H + SPRITE_H) / tex_h

		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
			Vector3(-h, -h, 0.0),
			Vector3( h, -h, 0.0),
			Vector3( h,  h, 0.0),
			Vector3(-h,  h, 0.0),
		])
		arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([
			Vector2(uv_x0, uv_y0),
			Vector2(uv_x1, uv_y0),
			Vector2(uv_x1, uv_y1),
			Vector2(uv_x0, uv_y1),
		])
		arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])

		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_2D
		mm.use_colors = false
		mm.instance_count = variant_stones.size()
		mm.mesh = mesh

		for i in range(variant_stones.size()):
			var stone: Dictionary = variant_stones[i] as Dictionary
			var tile: Vector2i = stone["tile"] as Vector2i
			var offset: Vector2 = stone["offset"] as Vector2
			var world_px: Vector2 = Vector2(tile * _tile_size) + Vector2(_tile_size, _tile_size) * 0.5 + offset
			mm.set_instance_transform_2d(i, Transform2D(0.0, world_px))

		var mmi := MultiMeshInstance2D.new()
		mmi.multimesh = mm
		mmi.texture = _stone_texture
		mmi.z_index = 1
		_vegetation_root.add_child(mmi)
		(_active_mmis[chunk_coords] as Array).append(mmi)
