class_name CollisionLayers
extends RefCounted

# Índices de bit (1-indexed) usados por set_collision_*_value.
const WORLD_WALL_LAYER_BIT: int = 5

# Máscaras en formato bitmask (0-indexed): bit 4 = 16.
const WORLD_WALL_LAYER_MASK: int = 1 << (WORLD_WALL_LAYER_BIT - 1)

# Los colliders estáticos de muro/props solo necesitan detectar actores.
const WORLD_WALL_COLLIDER_MASK: int = 1 << 2

# Layer 4 = Resources (minerales, árboles, pasto) — detectados por slash y armas.
const RESOURCES_LAYER_BIT: int = 4
const RESOURCES_LAYER_MASK: int = 1 << 3
