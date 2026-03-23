extends RefCounted
class_name TavernSanctionDirector

## Ejecutor de sanciones institucionales de la taberna.
##
## Recibe un LocalAuthorityDirective (ya tomada la decisión) y lo convierte
## en acciones concretas sobre keeper y sentinels.
##
## SEPARACIÓN DE RESPONSABILIDADES:
##   - NO toma decisiones (eso es TavernAuthorityPolicy).
##   - NO registra incidentes (eso es TavernLocalMemory).
##   - Solo despacha la acción física/social indicada en el directive.
##
## USO:
##   _tavern_director.setup({
##       "get_keeper":    Callable(self, "_get_tavern_keeper"),
##       "get_sentinels": func(): return get_tree().get_nodes_in_group("tavern_sentinel"),
##   })
##   _tavern_director.dispatch(directive, offender_node)

var _get_keeper:    Callable = Callable()
var _get_sentinels: Callable = Callable()


func setup(ctx: Dictionary) -> void:
	_get_keeper    = ctx.get("get_keeper",    Callable())
	_get_sentinels = ctx.get("get_sentinels", Callable())


## Despacha la sanción indicada en el directive.
## offender_node: nodo CharacterBody2D del ofensor; puede ser null.
func dispatch(directive: LocalAuthorityDirective, offender_node: CharacterBody2D = null) -> void:
	var R := LocalAuthorityResponse.Response
	match directive.response_type:
		R.RECORD_ONLY:
			pass  # solo memoria — sin acción

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


# ── Handlers por tipo de respuesta ───────────────────────────────────────────

func _dispatch_warn(directive: LocalAuthorityDirective, offender: CharacterBody2D) -> void:
	# Un sentinel advierte verbalmente; si el target desaparece o está fuera, sin efecto.
	var sentinel := _pick_nearest_sentinel(offender)
	if sentinel == null:
		return
	sentinel.execute_directive(directive, offender)


func _dispatch_deny_service(directive: LocalAuthorityDirective, offender: CharacterBody2D) -> void:
	# Sanción económica: keeper deja de atender al ofensor.
	# Sin movilización física — WARN se encarga del contacto si es necesario.
	var keeper := _get_keeper_node()
	if keeper != null and keeper.has_method("deny_service"):
		keeper.call("deny_service", directive.offender_actor_id)


func _dispatch_eject(directive: LocalAuthorityDirective, offender: CharacterBody2D) -> void:
	# El sentinel más cercano intercepta y expulsa.
	var sentinel := _pick_nearest_sentinel(offender)
	if sentinel == null:
		return
	sentinel.execute_directive(directive, offender)


func _dispatch_call_backup(directive: LocalAuthorityDirective, offender: CharacterBody2D) -> void:
	# Todos los sentinels disponibles interceden.
	for s in _get_sentinels_array():
		if s != null and is_instance_valid(s):
			(s as Sentinel).execute_directive(directive, offender)


func _dispatch_arrest(directive: LocalAuthorityDirective, offender: CharacterBody2D) -> void:
	# Todos los sentinels intentan someter al ofensor.
	for s in _get_sentinels_array():
		if s != null and is_instance_valid(s):
			(s as Sentinel).execute_directive(directive, offender)
	if directive.suggests_zone_lockdown:
		Debug.log("authority", "[DIRECTOR] LOCKDOWN sugerido — zone=%s offender=%s" \
			% [directive.zone_id, directive.offender_actor_id])


# ── Helpers ───────────────────────────────────────────────────────────────────

func _get_keeper_node() -> Node:
	if not _get_keeper.is_valid():
		return null
	return _get_keeper.call()


func _get_sentinels_array() -> Array:
	if not _get_sentinels.is_valid():
		return []
	var result: Variant = _get_sentinels.call()
	return result if result is Array else []


func _pick_nearest_sentinel(to_node: CharacterBody2D) -> Sentinel:
	var sentinels := _get_sentinels_array()
	if sentinels.is_empty():
		return null
	if to_node == null or not is_instance_valid(to_node):
		# Sin referencia de posición: devolver el primero disponible.
		return sentinels[0] as Sentinel
	var nearest: Sentinel  = null
	var nearest_dist: float = INF
	for s in sentinels:
		if s == null or not is_instance_valid(s) or not (s is Node2D):
			continue
		var d: float = (s as Node2D).global_position.distance_to(to_node.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = s as Sentinel
	return nearest
