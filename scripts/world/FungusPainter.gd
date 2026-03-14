class_name FungusPainter extends RefCounted

## Qué atlas_coords del GroundTileMap se consideran grass.
var grass_atlas_coords: Array[Vector2i] = []

## Cuántas variantes hay en fungus.png (columnas × filas del sheet 16×16).
var flower_variant_count: int = 10

var _ground_tilemap: TileMap
var _vegetation_root: Node2D
var _flower_texture: Texture2D
var _chunk_size: int = 32
var _tile_size: int = 32
var _active_mmis: Dictionary = {}  # Vector2i -> Array[MultiMeshInstance2D]
## source_id del autotile grass. Pre-filtro rápido antes de leer TileData.
var _grass_source_id: int = -1
## terrain_id que identifica grass en el TileSet (terrain_set 0, terrain 1 = "grass").
var _grass_terrain_id: int = 1
## Densidad de hongos: fracción de tiles grass que tendrán hongo (0.0–1.0).
var _flower_density: float = 0.05
## Tamaño del quad de cada hongo en px de mundo (half-extent = flower_size / 2).
var _flower_size: float = 8.0
var _excluded_rects: Array[Rect2i] = []


func setup(ctx: Dictionary) -> void:
	_ground_tilemap = ctx["ground_tilemap"] as TileMap
	_vegetation_root = ctx["vegetation_root"] as Node2D
	_flower_texture = ctx["flower_texture"] as Texture2D
	_chunk_size = ctx["chunk_size"] as int
	_tile_size = ctx["tile_size"] as int
	if ctx.has("grass_atlas_coords"):
		grass_atlas_coords = ctx["grass_atlas_coords"] as Array[Vector2i]
	if ctx.has("grass_source_id"):
		_grass_source_id = ctx["grass_source_id"] as int
	if ctx.has("grass_terrain_id"):
		_grass_terrain_id = ctx["grass_terrain_id"] as int
	if ctx.has("flower_density"):
		_flower_density = ctx["flower_density"] as float
	if ctx.has("flower_size"):
		_flower_size = ctx["flower_size"] as float
	if ctx.has("flower_variant_count"):
		flower_variant_count = ctx["flower_variant_count"] as int


func load_chunk(chunk_coords: Vector2i) -> void:
	var data: Array = WorldSave.get_fungus_data(chunk_coords)
	if data.is_empty():
		data = _generate_flowers(chunk_coords)
		WorldSave.set_fungus_data(chunk_coords, data)
	_build_multimesh(chunk_coords, data)


func unload_chunk(chunk_coords: Vector2i) -> void:
	if not _active_mmis.has(chunk_coords):
		return
	for mmi in _active_mmis[chunk_coords]:
		var node := mmi as Node
		if is_instance_valid(node):
			node.queue_free()
	_active_mmis.erase(chunk_coords)


func _generate_flowers(chunk_coords: Vector2i) -> Array:
	var result: Array = []
	for y in range(_chunk_size):
		for x in range(_chunk_size):
			var tile_world: Vector2i = chunk_coords * _chunk_size + Vector2i(x, y)

			var src_id: int = _ground_tilemap.get_cell_source_id(0, tile_world)
			if src_id == -1:
				continue

			# Pre-filtro rápido por source antes de leer TileData
			if _grass_source_id >= 0 and src_id != _grass_source_id:
				continue

			# Verificar terrain == grass usando TileData (distingue grass de dirt en el mismo source)
			var td: TileData = _ground_tilemap.get_cell_tile_data(0, tile_world)
			if td == null or td.terrain != _grass_terrain_id:
				continue

			if _is_excluded(tile_world):
				continue

			# Hash determinista — nunca randf() — seed distinta a FlowerPainter (primo diferente)
			var h: int = hash(chunk_coords.x * 83492791 ^ chunk_coords.y * 31458713 ^ x * 1000 ^ y)

			# Densidad controlada por _flower_density (fracción 0.0–1.0)
			if absf(float(h % 100)) > _flower_density * 100.0:
				continue

			var variant: int = abs(h / 100) % flower_variant_count

			# Offset AAA dentro del tile: rango -8..+8 px
			var ox: float = float((h >> 8) % 17) - 8.0
			var oy: float = float((h >> 16) % 17) - 8.0

			result.append({
				"tile": tile_world,
				"variant": variant,
				"offset": Vector2(ox, oy)
			})
	return result


func set_excluded_rects(rects: Array[Rect2i]) -> void:
	_excluded_rects = rects


func _is_excluded(tile: Vector2i) -> bool:
	for r: Rect2i in _excluded_rects:
		if r.has_point(tile):
			return true
	return false


func _is_grass(src_id: int, atlas: Vector2i) -> bool:
	if _grass_source_id >= 0:
		return src_id == _grass_source_id
	return grass_atlas_coords.has(atlas)


func _build_multimesh(chunk_coords: Vector2i, flowers: Array) -> void:
	if flowers.is_empty():
		return

	var by_variant: Dictionary = {}  # int -> Array
	for item in flowers:
		var flower: Dictionary = item as Dictionary
		var v: int = flower["variant"] as int
		if not by_variant.has(v):
			by_variant[v] = []
		(by_variant[v] as Array).append(flower)

	_active_mmis[chunk_coords] = []

	var tex_w: float = float(_flower_texture.get_width())
	var tex_h: float = float(_flower_texture.get_height())
	var sheet_cols: int = int(tex_w) / 16

	for raw_variant in by_variant.keys():
		var variant: int = raw_variant as int
		var variant_flowers: Array = by_variant[variant] as Array

		var col: int = variant % sheet_cols
		var row: int = variant / sheet_cols

		var uv_x0: float = float(col * 16) / tex_w
		var uv_y0: float = float(row * 16) / tex_h
		var uv_x1: float = float(col * 16 + 16) / tex_w
		var uv_y1: float = float(row * 16 + 16) / tex_h

		var hf: float = _flower_size * 0.5
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
			Vector3(-hf, -hf, 0.0),
			Vector3( hf, -hf, 0.0),
			Vector3( hf,  hf, 0.0),
			Vector3(-hf,  hf, 0.0),
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
		mm.instance_count = variant_flowers.size()
		mm.mesh = mesh

		for i in range(variant_flowers.size()):
			var flower: Dictionary = variant_flowers[i] as Dictionary
			var tile: Vector2i = flower["tile"] as Vector2i
			var offset: Vector2 = flower["offset"] as Vector2
			var world_px: Vector2 = Vector2(tile * _tile_size) + Vector2(_tile_size, _tile_size) * 0.5 + offset
			mm.set_instance_transform_2d(i, Transform2D(0.0, world_px))

		var mmi := MultiMeshInstance2D.new()
		mmi.multimesh = mm
		mmi.texture = _flower_texture
		mmi.z_index = 1
		_vegetation_root.add_child(mmi)
		(_active_mmis[chunk_coords] as Array).append(mmi)
