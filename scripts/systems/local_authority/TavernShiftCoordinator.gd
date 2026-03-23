extends RefCounted
class_name TavernShiftCoordinator

## Gestiona rotaciones simples de rol entre los sentinels de taberna.
##
## Swap: intercambia sentinel_role + home_pos + patrol_points entre
## interior_guard y door_guard cuando ambos están idle (GUARD state).
##
## No hay scheduler complejo ni simulación de turnos — solo un timer y una
## condición de seguridad. El sentinel migra naturalmente a su nueva posición
## siguiendo sus nuevos patrol_points sin necesidad de orden explícita.
##
## Resultado visible: de vez en cuando el guardián de puerta pasa al interior
## y viceversa, dando la sensación de vigilancia viva sin complejidad táctica.

## Segundos reales entre intentos de rotación.
## 240s ≈ ¼ día de juego (1 día = 900s). Produce 3-4 rotaciones por día.
const SHIFT_INTERVAL_SEC: float = 240.0

var _get_sentinels:          Callable = Callable()  # -> Array (raw, sin tipar)
var _get_door_patrol_points: Callable = Callable()  # -> PackedVector2Array

## Empieza con el timer ya parcialmente avanzado para que no haya swap
## al inicio de la sesión (da tiempo a que el jugador observe la posición inicial).
var _timer: float = SHIFT_INTERVAL_SEC * 0.7


func setup(ctx: Dictionary) -> void:
	_get_sentinels          = ctx.get("get_sentinels",          Callable())
	_get_door_patrol_points = ctx.get("get_door_patrol_points", Callable())


## Llamar desde world._process(delta).
func tick(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = SHIFT_INTERVAL_SEC
	_try_swap()


# ── Swap ──────────────────────────────────────────────────────────────────────

func _try_swap() -> void:
	var sentinels := _get_typed_sentinels()
	if sentinels.size() < 2:
		return

	var interior: Sentinel = null
	var door:     Sentinel = null
	for s: Sentinel in sentinels:
		if s.sentinel_role == "interior_guard":
			interior = s
		elif s.sentinel_role == "door_guard":
			door = s

	if interior == null or door == null:
		return

	# Condición de seguridad: ambos deben estar libres en su post.
	# No interrumpir órdenes activas (WARN, EJECT, SUBDUE, HAUL, RETURN).
	if not interior.is_available() or not door.is_available():
		Debug.log("authority", "[SHIFT] Rotación diferida — sentinels ocupados")
		return

	# Swap de roles
	interior.sentinel_role = "door_guard"
	door.sentinel_role     = "interior_guard"

	# Swap de home_pos (el post "dueño" de cada sentinel cambia)
	var tmp_home: Vector2 = interior.home_pos
	interior.home_pos = door.home_pos
	door.home_pos     = tmp_home

	# Patrol points: el nuevo door_guard recibe la ronda exterior;
	# el nuevo interior_guard se queda estático en su post.
	var door_points: PackedVector2Array = PackedVector2Array()
	if _get_door_patrol_points.is_valid():
		door_points = _get_door_patrol_points.call()
	interior.patrol_points = door_points          # interior→door: recibe patrulla
	door.patrol_points     = PackedVector2Array()  # door→interior: post fijo

	Debug.log("authority", "[SHIFT] Rotación: %s(door_guard) ↔ %s(interior_guard)" % [
		interior.name, door.name
	])


# ── Helper ────────────────────────────────────────────────────────────────────

func _get_typed_sentinels() -> Array[Sentinel]:
	var result: Array[Sentinel] = []
	if not _get_sentinels.is_valid():
		return result
	for node: Variant in _get_sentinels.call():
		if node is Sentinel and is_instance_valid(node):
			result.append(node as Sentinel)
	return result
