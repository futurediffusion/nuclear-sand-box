extends RefCounted
class_name TavernGarrisonMonitor

## Monitor de integridad de la guarnición de taberna.
##
## Reemplaza a TavernShiftCoordinator, que estaba diseñado para 2 sentinels
## y era incompatible con la guarnición real de 7.
##
## Responsabilidades:
##   1. Verificar periódicamente que la cobertura mínima del recinto se mantiene.
##   2. Registrar advertencias si la guarnición está incompleta (sentinel muerto,
##      atascado en estado no-GUARD por demasiado tiempo, o no spawneado).
##
## Estructura de guarnición esperada:
##   interior_guard  ×2  — flanquean al keeper
##   door_guard      ×1  — controla la entrada
##   perimeter_guard ×4  — cubren cada lateral exterior
##
## NO hace swaps de rol. El modelo real tiene roles fijos con posts fijos.
## La adaptación dinámica de comportamiento (patrullas, thresholds) la maneja
## TavernDefensePosture (Fase 8), no este monitor.
##
## La verificación es solo observabilidad — no reposiciona sentinels ni cambia
## órdenes activas. El sentinel vuelve a su home_pos por su propia máquina de estados.


# ── Cobertura mínima esperada ─────────────────────────────────────────────────

const MIN_INTERIOR:  int = 2
const MIN_DOOR:      int = 1
const MIN_PERIMETER: int = 4


# ── Cadencia ──────────────────────────────────────────────────────────────────

## Segundos entre verificaciones. 60s es suficiente — esto es observabilidad,
## no control de tiempo real.
const VERIFY_INTERVAL_SEC: float = 60.0

var _timer: float = VERIFY_INTERVAL_SEC * 0.5  # primera verificación a los 30s


# ── Callables ─────────────────────────────────────────────────────────────────

## Devuelve Array de nodos Sentinel del site. Inyectado por world.gd.
var _get_sentinels: Callable = Callable()

## site_id para filtrar. Si está vacío, acepta todos.
var _tavern_site_id: String = ""


# ── API ───────────────────────────────────────────────────────────────────────

func setup(ctx: Dictionary) -> void:
	_get_sentinels  = ctx.get("get_sentinels",  Callable())
	_tavern_site_id = ctx.get("tavern_site_id", "")


## Llamar desde world._process(delta).
func tick(delta: float) -> void:
	_timer += delta
	if _timer < VERIFY_INTERVAL_SEC:
		return
	_timer = 0.0
	_verify_coverage()


# ── Verificación ──────────────────────────────────────────────────────────────

func _verify_coverage() -> void:
	if not _get_sentinels.is_valid():
		return

	var counts: Dictionary = {
		"interior_guard":  0,
		"door_guard":      0,
		"perimeter_guard": 0,
	}
	var available_counts: Dictionary = {
		"interior_guard":  0,
		"door_guard":      0,
		"perimeter_guard": 0,
	}

	var raw: Variant = _get_sentinels.call()
	if not raw is Array:
		return

	for node: Variant in raw:
		if not (node is Sentinel and is_instance_valid(node)):
			continue
		var s := node as Sentinel
		if not _tavern_site_id.is_empty() and s.tavern_site_id != _tavern_site_id:
			continue
		var role: String = s.sentinel_role
		if not counts.has(role):
			continue
		counts[role] = int(counts[role]) + 1
		if s.is_available():
			available_counts[role] = int(available_counts[role]) + 1

	var interior_total:  int = int(counts["interior_guard"])
	var door_total:      int = int(counts["door_guard"])
	var perimeter_total: int = int(counts["perimeter_guard"])

	var coverage_ok: bool = (
		interior_total  >= MIN_INTERIOR  and
		door_total      >= MIN_DOOR      and
		perimeter_total >= MIN_PERIMETER
	)

	if not coverage_ok:
		Debug.log("authority",
			"[GARRISON] COBERTURA INSUFICIENTE — interior=%d/%d door=%d/%d perimeter=%d/%d" % [
				interior_total,  MIN_INTERIOR,
				door_total,      MIN_DOOR,
				perimeter_total, MIN_PERIMETER,
			]
		)
	else:
		Debug.log("authority",
			"[GARRISON] OK — interior=%d(%d idle) door=%d(%d idle) perimeter=%d(%d idle)" % [
				interior_total,  int(available_counts["interior_guard"]),
				door_total,      int(available_counts["door_guard"]),
				perimeter_total, int(available_counts["perimeter_guard"]),
			]
		)
