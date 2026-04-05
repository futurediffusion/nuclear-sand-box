extends Node
## Reloj global del mundo.
## 1 día de juego = SECONDS_PER_DAY segundos reales (15 min).
##
## Uso:
##   WorldTime.get_current_day()          → int, día actual (empieza en 0)
##   WorldTime.get_time_in_day()          → float 0.0..1.0 (progreso dentro del día)
##   WorldTime.get_seconds_in_day()       → float segundos transcurridos en el día actual
##   WorldTime.day_passed.connect(fn)     → fn(new_day: int)
##
## Save/load: WorldTime.get_save_data() / load_save_data(data)

signal day_passed(new_day: int)

const SECONDS_PER_DAY: float = 900.0   # 15 minutos reales
const DAY_START_NORMALIZED: float = 0.02
const FULL_DAY_START_NORMALIZED: float = 0.14
const NIGHT_START_NORMALIZED: float = 0.74
# Metadata visual de ciclo (no altera la simulación base).
const DAWN_END_NORMALIZED: float = 0.12
const DUSK_START_NORMALIZED: float = 0.68
const DUSK_END_NORMALIZED: float = 0.82

var _elapsed: float = 0.0   # segundos acumulados desde el inicio del mundo
var _current_day: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE


func _process(delta: float) -> void:
	_elapsed += delta
	var new_day: int = int(_elapsed / SECONDS_PER_DAY)
	if new_day != _current_day:
		_current_day = new_day
		day_passed.emit(_current_day)
		Debug.log("world_time", "[WORLDTIME] día %d (%.1f s)" % [_current_day, _elapsed])


# ---------------------------------------------------------------------------
# Getters
# ---------------------------------------------------------------------------

func get_current_day() -> int:
	return _current_day


## Progreso dentro del día actual, 0.0 (amanecer) → 1.0 (fin del día).
func get_time_in_day() -> float:
	return fmod(_elapsed, SECONDS_PER_DAY) / SECONDS_PER_DAY


## Segundos transcurridos dentro del día actual.
func get_seconds_in_day() -> float:
	return fmod(_elapsed, SECONDS_PER_DAY)


## Segundos totales acumulados desde el inicio del mundo.
func get_total_elapsed() -> float:
	return _elapsed


# ---------------------------------------------------------------------------
# API de control del ciclo
# ---------------------------------------------------------------------------

## Ajusta el progreso del día actual (0..1) sin cambiar de día base.
## Contrato: afecta runtime y también lo que se serializa en save vía `_elapsed`.
func set_time_in_day_normalized(t: float) -> void:
	var normalized_t: float = clampf(t, 0.0, 1.0)
	var day_base: int = int(_elapsed / SECONDS_PER_DAY)
	_elapsed = (day_base * SECONDS_PER_DAY) + (normalized_t * SECONDS_PER_DAY)
	_current_day = int(_elapsed / SECONDS_PER_DAY)


## Salta al inicio de día configurado por DAY_START_NORMALIZED.
## Contrato: afecta runtime y también lo que se serializa en save vía `_elapsed`.
func set_to_day_start() -> void:
	set_time_in_day_normalized(DAY_START_NORMALIZED)


## Salta al inicio de día pleno configurado por FULL_DAY_START_NORMALIZED.
## Contrato: afecta runtime y también lo que se serializa en save vía `_elapsed`.
func set_to_full_day() -> void:
	set_time_in_day_normalized(FULL_DAY_START_NORMALIZED)


## Salta al inicio de noche configurado por NIGHT_START_NORMALIZED.
## Contrato: afecta runtime y también lo que se serializa en save vía `_elapsed`.
func set_to_night_start() -> void:
	set_time_in_day_normalized(NIGHT_START_NORMALIZED)


func is_daytime() -> bool:
	var t: float = get_time_in_day()
	return t >= DAY_START_NORMALIZED and t < NIGHT_START_NORMALIZED


func get_cycle_phase_name() -> String:
	var t: float = get_time_in_day()
	if t < DAY_START_NORMALIZED:
		return "night"
	if t < DAWN_END_NORMALIZED:
		return "dawn"
	if t < DUSK_START_NORMALIZED:
		return "day"
	if t < DUSK_END_NORMALIZED:
		return "dusk"
	return "night"


# ---------------------------------------------------------------------------
# Save / Load
# ---------------------------------------------------------------------------

func get_save_data() -> Dictionary:
	return {"elapsed": _elapsed}


func load_save_data(data: Dictionary) -> void:
	_elapsed     = maxf(float(data.get("elapsed", 0.0)), 0.0)
	_current_day = int(_elapsed / SECONDS_PER_DAY)
