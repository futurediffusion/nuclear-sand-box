extends Node2D
class_name VegetationRoot

## Fracción de tiles de grass que tendrán una flor (0.0 = ninguna, 1.0 = todas).
## Cambios aquí solo tienen efecto al recargar chunks (no en runtime).
@export_range(0.0, 1.0, 0.01) var flower_density: float = 0.05

## Tamaño de cada flor en píxeles de mundo (el sprite base es 16×16).
@export_range(2.0, 32.0, 0.5) var flower_size: float = 8.0

## Fracción de tiles de grass que tendrán un hongo (0.0 = ninguno, 1.0 = todos).
@export_range(0.0, 1.0, 0.01) var fungus_density: float = 0.05

## Tamaño de cada hongo en píxeles de mundo.
@export_range(2.0, 32.0, 0.5) var fungus_size: float = 8.0

## Fracción de tiles de grass que tendrán un palo (0.0 = ninguno, 1.0 = todos).
@export_range(0.0, 1.0, 0.01) var sticks_density: float = 0.05

## Tamaño de cada palo en píxeles de mundo.
@export_range(2.0, 32.0, 0.5) var sticks_size: float = 8.0

## Fracción de tiles de grass que tendrán una piedra pequeña.
@export_range(0.0, 1.0, 0.01) var tinystone_density: float = 0.05

## Tamaño de cada piedra pequeña en píxeles de mundo.
@export_range(2.0, 32.0, 0.5) var tinystone_size: float = 7.0

var _flower_painter: FlowerPainter
var _fungus_painter: FungusPainter
var _sticks_painter: SticksPainter
var _tiny_stones_painter: TinyStonesPainter
var _chunk_save: Dictionary = {}


func setup(ctx: Dictionary) -> void:
	_chunk_save = ctx.get("chunk_save", {})
	_flower_painter = FlowerPainter.new()
	_flower_painter.setup({
		"ground_tilemap": ctx["ground_tilemap"],
		"vegetation_root": self,
		"flower_texture": preload("res://art/tiles/flowers.png"),
		"chunk_size": ctx["chunk_size"] as int,
		"tile_size": ctx["tile_size"] as int,
		"grass_source_id": ctx.get("grass_source_id", 3),
		"grass_terrain_id": ctx.get("grass_terrain_id", 1),
		"flower_density": flower_density,
		"flower_size": flower_size,
	})

	_fungus_painter = FungusPainter.new()
	_fungus_painter.setup({
		"ground_tilemap": ctx["ground_tilemap"],
		"vegetation_root": self,
		"flower_texture": preload("res://art/tiles/fungus.png"),
		"chunk_size": ctx["chunk_size"] as int,
		"tile_size": ctx["tile_size"] as int,
		"grass_source_id": ctx.get("grass_source_id", 3),
		"grass_terrain_id": ctx.get("grass_terrain_id", 1),
		"flower_density": fungus_density,
		"flower_size": fungus_size,
	})

	_sticks_painter = SticksPainter.new()
	_sticks_painter.setup({
		"ground_tilemap": ctx["ground_tilemap"],
		"vegetation_root": self,
		"stick_texture": preload("res://art/tiles/sticks.png"),
		"chunk_size": ctx["chunk_size"] as int,
		"tile_size": ctx["tile_size"] as int,
		"grass_source_id": ctx.get("grass_source_id", 3),
		"grass_terrain_id": ctx.get("grass_terrain_id", 1),
		"stick_density": sticks_density,
		"stick_size": sticks_size,
	})

	_tiny_stones_painter = TinyStonesPainter.new()
	_tiny_stones_painter.setup({
		"ground_tilemap": ctx["ground_tilemap"],
		"vegetation_root": self,
		"stone_texture": preload("res://art/tiles/tiny-stones.png"),
		"chunk_size": ctx["chunk_size"] as int,
		"tile_size": ctx["tile_size"] as int,
		"grass_source_id": ctx.get("grass_source_id", 3),
		"grass_terrain_id": ctx.get("grass_terrain_id", 1),
		"stone_density": tinystone_density,
		"stone_size": tinystone_size,
	})


func load_chunk(chunk_coords: Vector2i, occupied: Dictionary = {}) -> void:
	var rects: Array[Rect2i] = _build_exclusion_rects(chunk_coords)
	_flower_painter.set_excluded_rects(rects)
	_fungus_painter.set_excluded_rects(rects)
	_sticks_painter.set_excluded_rects(rects)
	_tiny_stones_painter.set_excluded_rects(rects)
	_flower_painter.load_chunk(chunk_coords, occupied)
	_fungus_painter.load_chunk(chunk_coords, occupied)
	_sticks_painter.load_chunk(chunk_coords, occupied)
	_tiny_stones_painter.load_chunk(chunk_coords, occupied)


## Extrae los rects de tiles excluidos (interior de taberna) del chunk_save.
func _build_exclusion_rects(chunk_coords: Vector2i) -> Array[Rect2i]:
	var rects: Array[Rect2i] = []
	if not _chunk_save.has(chunk_coords):
		return rects
	for p in _chunk_save[chunk_coords].get("placements", []):
		if typeof(p) != TYPE_DICTIONARY:
			continue
		if String(p.get("kind", "")) != "npc_keeper":
			continue
		var imin_raw = p.get("inner_min", [0, 0])
		var imax_raw = p.get("inner_max", [0, 0])
		var imin := Vector2i(int(imin_raw[0]), int(imin_raw[1]))
		var imax := Vector2i(int(imax_raw[0]), int(imax_raw[1]))
		# Rect2i(pos, size) — size es imax - imin + 1 para incluir ambos extremos
		rects.append(Rect2i(imin, imax - imin + Vector2i(1, 1)))
	return rects


func unload_chunk(chunk_coords: Vector2i) -> void:
	_flower_painter.unload_chunk(chunk_coords)
	_fungus_painter.unload_chunk(chunk_coords)
	_sticks_painter.unload_chunk(chunk_coords)
	_tiny_stones_painter.unload_chunk(chunk_coords)
