class_name PlayerTerritoryMap
extends RefCounted

# ── PlayerTerritoryMap ────────────────────────────────────────────────────────
# Mapa de territorio del jugador. Dos fuentes de territorio:
#
#   1. WORKBENCH ANCHOR — cualquier workbench colocado crea un círculo de
#      territorio alrededor de sí mismo (radio WORKBENCH_RADIUS).
#      "Tienes taller aquí, esto es tuyo."
#
#   2. ENCLOSED BASE — habitación cerrada detectada por SettlementIntel
#      (flood-fill desde doorwood + MIN_WALL_COUNT muros). El territorio cubre
#      el interior de la habitación más WALL_TERRITORY_BUFFER tiles hacia afuera.
#      "Tienes casa cerrada, esto es tuyo más los alrededores."
#
# Multiple territories:
#   Las dos listas son independientes. Puedes tener:
#     - Un workbench suelto en el campo  →  zona pequeña
#     - Una base cerrada en otro sitio   →  zona grande
#     - Ambas a la vez
#   No hay límite. Cada workbench y cada base detectada contribuyen su zona.
#
# API pública:
#   rebuild(workbench_nodes, detected_bases)  — reconstruir desde datos actuales
#   is_in_player_territory(world_pos) → bool
#   get_zones() → Array[Dictionary]           — para debug / UI futura
#   zone_count() → int

# ── Constantes de radio ───────────────────────────────────────────────────────
## Radio de territorio de un workbench suelto (sin paredes):  3 tiles = 96 px.
## Suficiente para que el área del taller y sus inmediaciones sean "tuyas".
const WORKBENCH_RADIUS: float = 96.0

## Expansión de territorio más allá del borde interior de la habitación (en tiles).
## 1 tile cubre el grosor del muro. 3 tiles adicionales cubren el exterior inmediato.
## Total efectivo: 4 tiles fuera del interior = ~1 tile exterior de margen.
const WALL_TERRITORY_EXPANSION: int = 4

## Tamaño de tile en píxeles (debe coincidir con el proyecto).
const TILE_SIZE: float = 32.0

# ── Estado ────────────────────────────────────────────────────────────────────
# Cada zona: { type, ... } — dos shapes posibles:
#   type "workbench":  { center: Vector2, radius: float }
#   type "enclosed":   { rect_world: Rect2, center: Vector2, id: String }
var _zones: Array[Dictionary] = []


# ---------------------------------------------------------------------------
# Rebuild — llamado cuando el estado del mundo cambia
# ---------------------------------------------------------------------------

## Reconstruye las zonas de territorio desde datos en vivo.
##
## workbench_nodes  — Array de nodos Node2D en el grupo "workbench" (del SceneTree).
## detected_bases   — Array[Dictionary] de SettlementIntel.get_detected_bases_near().
##   Cada base debe tener: center_world_pos (Vector2), bounds (Rect2i), id (String).
func rebuild(workbench_nodes: Array, detected_bases: Array) -> void:
	_zones.clear()

	# ── 1. Workbench anchors ──────────────────────────────────────────────
	for wb in workbench_nodes:
		var n2d: Node2D = wb as Node2D
		if n2d == null or not is_instance_valid(n2d):
			continue
		_zones.append({
			"type":   "workbench",
			"center": n2d.global_position,
			"radius": WORKBENCH_RADIUS,
		})

	# ── 2. Enclosed bases ─────────────────────────────────────────────────
	for base in detected_bases:
		var bounds: Rect2i = base.get("bounds", Rect2i()) as Rect2i
		if bounds.size == Vector2i.ZERO:
			continue
		var center: Vector2 = base.get("center_world_pos", Vector2.ZERO) as Vector2
		# Expandir el rect interior (tile-space) por WALL_TERRITORY_EXPANSION tiles
		# para cubrir muros + buffer exterior.
		var exp: int = WALL_TERRITORY_EXPANSION
		var expanded: Rect2i = Rect2i(
			bounds.position.x - exp,
			bounds.position.y - exp,
			bounds.size.x + exp * 2,
			bounds.size.y + exp * 2,
		)
		# Convertir a espacio mundo
		var world_rect: Rect2 = Rect2(
			float(expanded.position.x) * TILE_SIZE,
			float(expanded.position.y) * TILE_SIZE,
			float(expanded.size.x)     * TILE_SIZE,
			float(expanded.size.y)     * TILE_SIZE,
		)
		_zones.append({
			"type":       "enclosed",
			"center":     center,
			"rect_world": world_rect,
			"id":         String(base.get("id", "")),
		})

	Debug.log("territory", "[PTM] rebuilt — workbench_zones=%d enclosed_zones=%d" % [
		_count_by_type("workbench"), _count_by_type("enclosed")])


# ---------------------------------------------------------------------------
# Query API
# ---------------------------------------------------------------------------

## True si world_pos está dentro de cualquier zona de territorio del jugador.
func is_in_player_territory(world_pos: Vector2) -> bool:
	for zone in _zones:
		if _pos_in_zone(world_pos, zone):
			return true
	return false


## Devuelve todas las zonas activas (para debug, UI, o sistemas externos).
func get_zones() -> Array[Dictionary]:
	return _zones.duplicate()


## Número total de zonas activas.
func zone_count() -> int:
	return _zones.size()


## True si hay al menos un workbench como anchor (zona "workbench").
func has_workbench_anchor() -> bool:
	for zone in _zones:
		if String(zone.get("type", "")) == "workbench":
			return true
	return false


## True si hay al menos una base cerrada detectada (zona "enclosed").
func has_enclosed_base() -> bool:
	for zone in _zones:
		if String(zone.get("type", "")) == "enclosed":
			return true
	return false


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _pos_in_zone(world_pos: Vector2, zone: Dictionary) -> bool:
	match String(zone.get("type", "")):
		"workbench":
			var center: Vector2 = zone.get("center", Vector2.ZERO) as Vector2
			var radius: float   = float(zone.get("radius", 0.0))
			return world_pos.distance_squared_to(center) <= radius * radius
		"enclosed":
			var rect: Rect2 = zone.get("rect_world", Rect2()) as Rect2
			return rect.has_point(world_pos)
	return false


func _count_by_type(type: String) -> int:
	var n: int = 0
	for z in _zones:
		if String(z.get("type", "")) == type:
			n += 1
	return n
