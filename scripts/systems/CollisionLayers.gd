class_name CollisionLayers
extends RefCounted

# Mapa de capas (CLAUDE.md): 1=Player, 2=Attacks, 3=EnemyNCP, 4=resources, 5=WALLPROPS.
# Índices de bit (1-indexed) usados por set_collision_*_value.
# Máscaras en formato bitmask (0-indexed): layer N → mask = 1 << (N-1).

const PLAYER_LAYER_BIT:  int = 1
const PLAYER_LAYER_MASK: int = 1 << (PLAYER_LAYER_BIT - 1)   # 1

const ATTACKS_LAYER_BIT:  int = 2
const ATTACKS_LAYER_MASK: int = 1 << (ATTACKS_LAYER_BIT - 1)  # 2

const ENEMY_LAYER_BIT:  int = 3
const ENEMY_LAYER_MASK: int = 1 << (ENEMY_LAYER_BIT - 1)     # 4

# Layer 4 = Resources (minerales, árboles, pasto) — detectados por slash y armas.
const RESOURCES_LAYER_BIT: int = 4
const RESOURCES_LAYER_MASK: int = 1 << (RESOURCES_LAYER_BIT - 1)  # 8

const WORLD_WALL_LAYER_BIT: int = 5
const WORLD_WALL_LAYER_MASK: int = 1 << (WORLD_WALL_LAYER_BIT - 1)  # 16

# Los colliders estáticos de muro/props solo necesitan detectar actores.
const WORLD_WALL_COLLIDER_MASK: int = 1 << 2
