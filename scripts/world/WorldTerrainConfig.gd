extends RefCounted
class_name WorldTerrainConfig

# Baseline visual de referencia: "EUREKA" (commits 01d19fd + 9b9e1d4).
const TERRAIN_SET: int = 0
const DIRT_ID: int = 0
const GRASS_ID: int = 1

# Mapping legado (fallback conservador).
const LEGACY_GROUND_SOURCE_ID: int = 0
const LEGACY_FALLBACK_ATLAS_BY_TERRAIN := {
	DIRT_ID: Vector2i(0, 1),
	GRASS_ID: Vector2i(0, 0),
}

# Mapping corregido dirt/grass (usa atlas autotile real del suelo).
const DIRT_GRASS_GROUND_SOURCE_ID: int = 3
const DIRT_GRASS_FALLBACK_ATLAS_BY_TERRAIN := {
	DIRT_ID: Vector2i(0, 1),
	GRASS_ID: Vector2i(0, 0),
}
