extends RefCounted
class_name TavernSanctionDirector

## Ejecutor de sanciones institucionales de la taberna.
##
## Convierte un LocalAuthorityDirective en acciones concretas sobre keeper y sentinels.
## No toma decisiones — solo ejecuta la orden que le llega.
##
## Selección de sentinel por rol:
##   WARN    → interior_guard  (contacto verbal dentro del espacio)
##   EJECT   → door_guard      (escort hasta la salida — es su posición natural)
##   BACKUP, ARREST → todos los sentinels del site
##
## deny_service: registra en TavernLocalMemory (fuente de verdad) y notifica al keeper.

var _get_keeper:          Callable = Callable()
var _get_sentinels:       Callable = Callable()
var _memory_deny_service: Callable = Callable()  # TavernLocalMemory.deny_service_for


func setup(ctx: Dictionary) -> void:
	_get_keeper          = ctx.get("get_keeper",          Callable())
	_get_sentinels       = ctx.get("get_sentinels",       Callable())
	_memory_deny_service = ctx.get("memory_deny_service", Callable())


## Despacha la sanción. offender_node puede ser null si no se pudo resolver.
func dispatch(directive: LocalAuthorityDirective, offender_node: CharacterBody2D = null) -> void:
	var R := LocalAuthorityResponse.Response
	match directive.response_type:
		R.RECORD_ONLY:
			pass

		R.WARN:
			_dispatch_warn(directive, offender_node)

		R.DENY_SERVICE:
			_dispatch_deny_service(directive, offender_node)

		R.EJECT:
			_dispatch_eject(directive, offender_node)

		R.CALL_BACKUP:
			_dispatch_call_backup(directive, offender_node)

		R.ARREST_OR_SUBDUE:
			_dispatch_arrest(directive, offender_node)

		_:
			Debug.log("authority", "[DIRECTOR] response desconocido: %s" % directive.response_type)


# ── Handlers ──────────────────────────────────────────────────────────────────

func _dispatch_warn(directive: LocalAuthorityDirective, offender: CharacterBody2D) -> void:
	# Advertencia verbal: el guardian más adecuado según zona del incidente.
	# Interior → interior_guard (ya está dentro del espacio).
	# Grounds/perimeter o desconocida → door_guard (más cercano a la entrada).
	var preferred_role := _role_for_zone(directive.zone_id, "warn")
	var sentinel := _pick_by_role_then_zone(preferred_role, directive.zone_id, offender)
	if sentinel != null:
		sentinel.execute_directive(directive, offender)


func _dispatch_deny_service(directive: LocalAuthorityDirective, _offender: CharacterBody2D) -> void:
	# Sanción económica: solo keeper. No movilizar sentinel físicamente.
	# 1. Registrar en memoria (fuente de verdad — el keeper la consulta).
	if _memory_deny_service.is_valid():
		_memory_deny_service.call(directive.offender_actor_id)
	# 2. Notificar al keeper por si quiere reaccionar inmediatamente (cerrar UI, etc.).
	var keeper := _get_keeper_node()
	if keeper != null and keeper.has_method("deny_service"):
		keeper.call("deny_service", directive.offender_actor_id)


func _dispatch_eject(directive: LocalAuthorityDirective, offender: CharacterBody2D) -> void:
	# Expulsión física: door_guard preferido — conoce la salida y está posicionado ahí.
	# Si no hay door_guard, cualquier sentinel disponible.
	var sentinel := _pick_by_role_then_zone("door_guard", directive.zone_id, offender)
	if sentinel != null:
		sentinel.execute_directive(directive, offender)


func _dispatch_call_backup(directive: LocalAuthorityDirective, offender: CharacterBody2D) -> void:
	# Respaldo: movilizar todos — interior_guard primero (más cerca de la acción).
	var sentinels := _get_sentinel_nodes()
	sentinels.sort_custom(func(a: Sentinel, b: Sentinel) -> bool:
		return a.sentinel_role == "interior_guard" and b.sentinel_role != "interior_guard"
	)
	for s: Sentinel in sentinels:
		s.execute_directive(directive, offender)


func _dispatch_arrest(directive: LocalAuthorityDirective, offender: CharacterBody2D) -> void:
	# Detención: todos los sentinels, sin orden de preferencia.
	for s: Sentinel in _get_sentinel_nodes():
		s.execute_directive(directive, offender)
	if directive.suggests_zone_lockdown:
		Debug.log("authority", "[DIRECTOR] LOCKDOWN sugerido — zone=%s offender=%s" \
			% [directive.zone_id, directive.offender_actor_id])


# ── Helpers ───────────────────────────────────────────────────────────────────

func _get_keeper_node() -> Node:
	return _get_keeper.call() if _get_keeper.is_valid() else null


## Devuelve solo los nodos Sentinel válidos del site.
func _get_sentinel_nodes() -> Array[Sentinel]:
	var result: Array[Sentinel] = []
	if not _get_sentinels.is_valid():
		return result
	var raw: Variant = _get_sentinels.call()
	if not raw is Array:
		return result
	for node: Variant in raw:
		if node is Sentinel and is_instance_valid(node):
			result.append(node as Sentinel)
	return result


## Qué rol es más apropiado para un incidente según zona y tipo de respuesta.
##   interior → interior_guard (ya está dentro, contacto inmediato)
##   grounds/perimeter/desconocido → door_guard (controla el acceso)
func _role_for_zone(zone_id: String, _response_hint: String = "") -> String:
	var C := LocalCivilAuthorityConstants
	if zone_id == C.ZONE_TAVERN_INTERIOR:
		return "interior_guard"
	return "door_guard"


## Elige sentinel por rol, con fallback a zona (más cercano al incidente) y luego al ofensor.
func _pick_by_role_then_zone(
		preferred_role: String,
		zone_id: String,
		offender: CharacterBody2D,
) -> Sentinel:
	var sentinels := _get_sentinel_nodes()
	if sentinels.is_empty():
		return null

	# 1. Rol exacto dentro del mismo site
	for s: Sentinel in sentinels:
		if s.sentinel_role == preferred_role:
			return s

	# 2. Si el rol preferido no existe, intentar el rol complementario.
	# Ej: si no hay door_guard, el interior_guard es mejor que nada.
	var fallback_role := "interior_guard" if preferred_role == "door_guard" else "door_guard"
	for s: Sentinel in sentinels:
		if s.sentinel_role == fallback_role:
			return s

	# 3. Ultimo recurso: más cercano al ofensor (no hay roles configurados).
	return _pick_nearest(sentinels, offender)


func _pick_nearest(sentinels: Array[Sentinel], to_node: CharacterBody2D) -> Sentinel:
	if sentinels.is_empty():
		return null
	if to_node == null or not is_instance_valid(to_node):
		return sentinels[0]
	var nearest: Sentinel   = null
	var nearest_dist: float = INF
	for s: Sentinel in sentinels:
		var d: float = (s as Node2D).global_position.distance_to(to_node.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest      = s
	return nearest
