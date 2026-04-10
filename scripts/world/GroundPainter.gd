extends RefCounted
class_name GroundPainter

const DIRT_TERRAIN_ID: int = 0
const GRASS_TERRAIN_ID: int = 1

var _noise: FastNoiseLite

func setup(noise_seed: int, _world_width: int, _world_height: int) -> void:
	_noise = FastNoiseLite.new()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.09
	_noise.fractal_octaves = 2
	_noise.seed = noise_seed

func get_terrain(x: int, y: int) -> int:
	if _noise == null:
		return GRASS_TERRAIN_ID
	var n := _noise.get_noise_2d(float(x), float(y))
	if n < 0.1:
		return DIRT_TERRAIN_ID
	return GRASS_TERRAIN_ID
