class_name SticksPainter extends RefCounted

## Cuántas variantes hay en sticks.png.
## Cada variante ocupa 32×16 px (dos tiles de 16×16 lado a lado).
var stick_variant_count: int = 9

var grass_atlas_coords: Array[Vector2i] = []

var _ground_tilemap: TileMap
var _vegetation_root: Node2D
var _stick_texture: Texture2D
var _chunk_size: int = 32
var _tile_size: int = 32
var _active_mmis: Dictionary = {}  # Vector2i -> Array[MultiMeshInstance2D]
var _grass_source_id: int = -1
var _grass_terrain_id: int = 1
## Densidad: fracción de tiles grass que tendrán un palo (0.0–1.0).
var _stick_density: float = 0.05
## Altura del quad renderizado en px de mundo. El ancho es stick_size * 2 (ratio 2:1).
var _stick_size: float = 8.0
var _excluded_rects: Array[Rect2i] = []

# Tamaño fijo de cada sprite en el sheet (en px del PNG)
const SPRITE_W: int = 32
const SPRITE_H: int = 16


func setup(ctx: Dictionary) -> void:
	_ground_tilemap = ctx["ground_tilemap"] as TileMap
	_vegetation_root = ctx["vegetation_root"] as Node2D
	_stick_texture = ctx["stick_texture"] as Texture2D
	_chunk_size = ctx["chunk_size"] as int
	_tile_size = ctx["tile_size"] as int
	if ctx.has("grass_atlas_coords"):
		grass_atlas_coords = ctx["grass_atlas_coords"] as Array[Vector2i]
	if ctx.has("grass_source_id"):
		_grass_source_id = ctx["grass_source_id"] as int
	if ctx.has("grass_terrain_id"):
		_grass_terrain_id = ctx["grass_terrain_id"] as int
	if ctx.has("stick_density"):
		_stick_density = ctx["stick_density"] as float
	if ctx.has("stick_size"):
		_stick_size = ctx["stick_size"] as float
	if ctx.has("stick_variant_count"):
		stick_variant_count = ctx["stick_variant_count"] as int


func set_excluded_rects(rects: Array[Rect2i]) -> void:
	_excluded_rects = rects


func _is_excluded(tile: Vector2i) -> bool:
	for r: Rect2i in _excluded_rects:
		if r.has_point(tile):
			return true
	return false


func load_chunk(chunk_coords: Vector2i, occupied: Dictionary = {}) -> void:
	var data: Array = WorldSave.get_sticks_data(chunk_coords)
	if data.is_empty():
		data = _generate_sticks(chunk_coords, occupied)
		WorldSave.set_sticks_data(chunk_coords, data)
	_build_multimesh(chunk_coords, data)


func unload_chunk(chunk_coords: Vector2i) -> void:
	if not _active_mmis.has(chunk_coords):
		return
	for mmi in _active_mmis[chunk_coords]:
		var node := mmi as Node
		if is_instance_valid(node):
			node.queue_free()
	_active_mmis.erase(chunk_coords)


func _generate_sticks(chunk_coords: Vector2i, occupied: Dictionary = {}) -> Array:
	var result: Array = []
	for y in range(_chunk_size):
		for x in range(_chunk_size):
			var tile_world: Vector2i = chunk_coords * _chunk_size + Vector2i(x, y)

			var src_id: int = _ground_tilemap.get_cell_source_id(0, tile_world)
			if src_id == -1:
				continue
			if _grass_source_id >= 0 and src_id != _grass_source_id:
				continue

			var td: TileData = _ground_tilemap.get_cell_tile_data(0, tile_world)
			if td == null or td.terrain != _grass_terrain_id:
				continue

			if _is_excluded(tile_world):
				continue

			if occupied.has(tile_world):
				continue

			# Hash determinista — primo distinto a FlowerPainter y FungusPainter
			var h: int = hash(chunk_coords.x * 67867979 ^ chunk_coords.y * 40503479 ^ x * 1000 ^ y)

			if absf(float(h % 100)) > _stick_density * 100.0:
				continue

			var variant: int = abs(h / 100) % stick_variant_count

			# Offset dentro del tile: rango -8..+8 px
			var ox: float = float((h >> 8) % 17) - 8.0
			var oy: float = float((h >> 16) % 17) - 8.0

			result.append({
				"tile": tile_world,
				"variant": variant,
				"offset": Vector2(ox, oy)
			})
	return result


func _build_multimesh(chunk_coords: Vector2i, sticks: Array) -> void:
	if sticks.is_empty():
		return

	var by_variant: Dictionary = {}
	for item in sticks:
		var stick: Dictionary = item as Dictionary
		var v: int = stick["variant"] as int
		if not by_variant.has(v):
			by_variant[v] = []
		(by_variant[v] as Array).append(stick)

	_active_mmis[chunk_coords] = []

	var tex_w: float = float(_stick_texture.get_width())
	var tex_h: float = float(_stick_texture.get_height())
	# Cada variante ocupa SPRITE_W × SPRITE_H px en el sheet
	var sheet_cols: int = int(tex_w) / SPRITE_W

	# Quad: ancho = stick_size * 2, alto = stick_size  (ratio 2:1 igual al sprite)
	var hw: float = _stick_size          # half-width
	var hh: float = _stick_size * 0.5   # half-height

	for raw_variant in by_variant.keys():
		var variant: int = raw_variant as int
		var variant_sticks: Array = by_variant[variant] as Array

		var col: int = variant % sheet_cols
		var row: int = variant / sheet_cols

		var uv_x0: float = float(col * SPRITE_W) / tex_w
		var uv_y0: float = float(row * SPRITE_H) / tex_h
		var uv_x1: float = float(col * SPRITE_W + SPRITE_W) / tex_w
		var uv_y1: float = float(row * SPRITE_H + SPRITE_H) / tex_h

		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
			Vector3(-hw, -hh, 0.0),
			Vector3( hw, -hh, 0.0),
			Vector3( hw,  hh, 0.0),
			Vector3(-hw,  hh, 0.0),
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
		mm.instance_count = variant_sticks.size()
		mm.mesh = mesh

		for i in range(variant_sticks.size()):
			var stick: Dictionary = variant_sticks[i] as Dictionary
			var tile: Vector2i = stick["tile"] as Vector2i
			var offset: Vector2 = stick["offset"] as Vector2
			var world_px: Vector2 = Vector2(tile * _tile_size) + Vector2(_tile_size, _tile_size) * 0.5 + offset
			mm.set_instance_transform_2d(i, Transform2D(0.0, world_px))

		var mmi := MultiMeshInstance2D.new()
		mmi.multimesh = mm
		mmi.texture = _stick_texture
		mmi.z_index = 1
		_vegetation_root.add_child(mmi)
		(_active_mmis[chunk_coords] as Array).append(mmi)
