extends RefCounted
class_name TavernDefensePosture

## Computa el nivel de postura defensiva del recinto de taberna.
##
## Combina tres fuentes de señal:
##   1. Ataques físicos recientes a la estructura exterior (wall_damaged_exterior, bandit_attack)
##   2. Presencia territorial bandit cerca de la taberna (BanditTerritoryQuery)
##   3. Tensión institucional acumulada (TavernLocalMemory.get_tension_level)
##
## Niveles:
##   NORMAL    — operación estándar; thresholds base
##   GUARDED   — presión detectada; thresholds más estrictos; perimeter patrulla normal
##   FORTIFIED — ataques sostenidos; thresholds mínimos; perimeter en post fijo
##
## Evaluación periódica (cada ~10s desde world.gd).
## No tiene estado propio — compute() es puro y determinista.


# ── Niveles ───────────────────────────────────────────────────────────────────

const NORMAL    := 0
const GUARDED   := 1
const FORTIFIED := 2


# ── Parámetros de clasificación ───────────────────────────────────────────────

## Ventana temporal para contar daño exterior (más corta que tensión general).
## 120s ≈ 2 min de juego: presión real de los últimos momentos.
const EXTERIOR_WINDOW_SEC: float = 120.0

## Hits exteriores en la ventana para entrar en GUARDED.
const GUARDED_HIT_THRESHOLD: int = 1

## Hits exteriores para FORTIFIED, o tensión alta + campamento.
const FORTIFIED_HIT_THRESHOLD: int = 3


# ── API ───────────────────────────────────────────────────────────────────────

## Computa el nivel de postura actual.
##
## memory       — TavernLocalMemory del recinto
## tavern_center — posición world del centro de la taberna (para BanditTerritoryQuery)
##                 Si es Vector2.ZERO, la comprobación territorial se omite
## now          — RunClock.now()
static func compute(
		memory: TavernLocalMemory,
		tavern_center: Vector2,
		now: float,
) -> int:
	if memory == null:
		return NORMAL

	# Ataques físicos recientes a la estructura exterior.
	# wall_damaged_exterior: daño directo a paredes desde fuera del perímetro.
	# bandit_attack:         agresión bandit confirmada dentro/cerca del recinto.
	var exterior_tags := PackedStringArray(["wall_damaged_exterior", "bandit_attack"])
	var ext_hits: int = memory.count_recent_by_source_tags(exterior_tags, now, EXTERIOR_WINDOW_SEC)

	# Presencia territorial bandit (campamento cerca del recinto).
	var has_nearby_camp: bool = false
	if tavern_center != Vector2.ZERO:
		has_nearby_camp = BanditTerritoryQuery.is_in_territory(tavern_center)

	# Tensión institucional acumulada de los últimos incidentes.
	var tension: float = memory.get_tension_level(now)

	# FORTIFIED: múltiples ataques o tensión sostenida + campamento cercano.
	if ext_hits >= FORTIFIED_HIT_THRESHOLD or (tension >= 2.0 and has_nearby_camp):
		return FORTIFIED

	# GUARDED: al menos un ataque, campamento presente, o tensión moderada.
	if ext_hits >= GUARDED_HIT_THRESHOLD or has_nearby_camp or tension >= 1.0:
		return GUARDED

	return NORMAL


## Nombre legible para logs de debug.
static func name_of(level: int) -> String:
	match level:
		NORMAL:    return "NORMAL"
		GUARDED:   return "GUARDED"
		FORTIFIED: return "FORTIFIED"
	return "UNKNOWN(%d)" % level
