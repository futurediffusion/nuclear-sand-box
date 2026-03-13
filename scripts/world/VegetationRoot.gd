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

var _flower_painter: FlowerPainter
var _fungus_painter: FungusPainter


func setup(ctx: Dictionary) -> void:
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


func load_chunk(chunk_coords: Vector2i) -> void:
	_flower_painter.load_chunk(chunk_coords)
	_fungus_painter.load_chunk(chunk_coords)


func unload_chunk(chunk_coords: Vector2i) -> void:
	_flower_painter.unload_chunk(chunk_coords)
	_fungus_painter.unload_chunk(chunk_coords)
