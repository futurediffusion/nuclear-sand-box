class_name TavernPerimeterBrawl
extends RefCounted

## Caos perimetral inicial: 1-2 bandits rebeldes atacan sentinels periódicamente.
## Los sentinels responden con SUBDUE inmediato. El conflicto esporádico construye
## tensión natural antes de que el jugador haya provocado nada.
##
## Mecanismo:
##   1. Cada BRAWL_INTERVAL segundos (con varianza) elige 1-2 bandits elegibles
##      cerca de la taberna.
##   2. force_target(sentinel, duración) en el ai_component del rebelde → bandit
##      persigue y ataca al sentinel.
##   3. issue_order(SUBDUE, rebelde) en el sentinel → respuesta institucional
##      inmediata sin pasar por el ciclo warn→shove.
##   4. Tras la pelea el sentinel vuelve a GUARD y el bandit a su comportamiento
##      normal. Nuevo brawl en el siguiente intervalo.
##
## No registra incidentes directamente — el sentinel ya llama armed_intruder al
## detectar al atacante, lo que alimenta TavernLocalMemory y sube la tensión.

const BRAWL_INTERVAL_MIN:    float = 38.0   # s — mínimo entre brawls
const BRAWL_INTERVAL_MAX:    float = 85.0   # s — máximo entre brawls
const FIRST_BRAWL_MIN:       float = 10.0   # s — primer brawl tras activación
const FIRST_BRAWL_MAX:       float = 24.0   # s — primer brawl tras activación
const SCAN_RADIUS:           float = 660.0  # px — radio de búsqueda de bandits
const FORCE_TARGET_DURATION: float = 20.0   # s — duración del lock de agresión

var _get_sentinels:      Callable = Callable()
var _get_nearby_enemies: Callable = Callable()  # (center: Vector2, radius: float) -> Array
var _get_tavern_center:  Callable = Callable()
var _next_brawl_at:      float    = 0.0


func setup(ctx: Dictionary) -> void:
	_get_sentinels      = ctx.get("get_sentinels",      Callable())
	_get_nearby_enemies = ctx.get("get_nearby_enemies", Callable())
	_get_tavern_center  = ctx.get("get_tavern_center",  Callable())
	_next_brawl_at = RunClock.now() + randf_range(FIRST_BRAWL_MIN, FIRST_BRAWL_MAX)


func tick(_delta: float) -> void:
	if RunClock.now() < _next_brawl_at:
		return
	_next_brawl_at = RunClock.now() + randf_range(BRAWL_INTERVAL_MIN, BRAWL_INTERVAL_MAX)
	_trigger_brawl()


# ---------------------------------------------------------------------------
# Brawl — selección y despacho
# ---------------------------------------------------------------------------

func _trigger_brawl() -> void:
	var center: Vector2 = _get_tavern_center.call() if _get_tavern_center.is_valid() else Vector2.ZERO
	if center == Vector2.ZERO:
		return

	# Sentinels perimetrales libres (en GUARD = disponibles)
	var sentinels: Array = _get_sentinels.call() if _get_sentinels.is_valid() else []
	var perimeter: Array = []
	for s in sentinels:
		if not is_instance_valid(s):
			continue
		if String(s.get("sentinel_role")) != "perimeter_guard":
			continue
		if s.has_method("is_available") and bool(s.call("is_available")):
			perimeter.append(s)

	if perimeter.is_empty():
		return

	# Bandits elegibles — cercanos, en grupo "enemy", con ai_component capaz de force_target
	if not _get_nearby_enemies.is_valid():
		return
	var candidates: Array = _get_nearby_enemies.call(center, SCAN_RADIUS)
	var eligible: Array = []
	for e in candidates:
		if not is_instance_valid(e):
			continue
		if e.is_in_group("tavern_sentinel"):
			continue
		if not e.is_in_group("enemy"):
			continue
		var ai = e.get("ai_component")
		if ai == null or not ai.has_method("force_target"):
			continue
		eligible.append(e)

	if eligible.is_empty():
		return

	eligible.shuffle()

	# 1 rebelde siempre; 2 con 40 % si hay suficientes
	var rebel_count: int = 2 if (eligible.size() >= 2 and randf() < 0.40) else 1

	for i in rebel_count:
		var rebel: Node      = eligible[i]
		var sentinel: Node   = perimeter[randi() % perimeter.size()]

		# Bandit persigue y ataca al sentinel
		var ai = rebel.get("ai_component")
		ai.force_target(sentinel, FORCE_TARGET_DURATION)

		# Sentinel responde con SUBDUE inmediato (sin ciclo warn→shove)
		if sentinel.has_method("issue_order"):
			sentinel.call("issue_order",
				Sentinel.OrderType.SUBDUE,
				rebel as CharacterBody2D)

		Debug.log("brawl",
			"[PerimeterBrawl] rebelde=%s → sentinel=%s" % [rebel.name, sentinel.name])
