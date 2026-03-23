extends RefCounted
class_name TavernSanctionDirector

## Ejecutor de sanciones institucionales de la taberna.
##
## Convierte un LocalAuthorityDirective en acciones concretas sobre keeper y sentinels.
## No toma decisiones institucionales — solo ejecuta la orden que le llega.
##
## ── Modelo de respuesta: primary + support ────────────────────────────────────
##
## La selección de respondedores depende de zone_id × response_type.
## No todos responden siempre — se mantiene cobertura mínima del recinto.
##
## WARN (contacto individual — sin movilización):
##   INTERIOR  → interior_guard primary
##   GROUNDS   → door_guard primary
##   PERIMETER → perimeter_guard más cercano
##
## EJECT:
##   INTERIOR/GROUNDS → door_guard primary + un interior_guard de apoyo
##                      perimeter guards mantienen exterior
##   PERIMETER → redirige a ARREST_OR_SUBDUE (OrderType.SUBDUE en sentinel)
##               perimeter_guard más cercano primary
##               Si severity ≥ HIGH: todos los perimeter_guards apoyan
##               Interior/door mantienen cobertura interior
##
## CALL_BACKUP:
##   INTERIOR/GROUNDS → interior_guards + door_guard
##                      perimeter mantiene exterior
##                      Si severity CRITICAL: todos los sentinels
##   PERIMETER → todos los perimeter_guards + un interior_guard
##               door_guard mantiene entrada, interior restante cubre keeper
##
## ARREST_OR_SUBDUE → todos los sentinels (caso extremo / murder / lockdown)
##
## DENY_SERVICE → solo keeper (sanción económica, sin movilización física)


var _get_keeper:          Callable = Callable()
var _get_sentinels:       Callable = Callable()
var _memory_deny_service: Callable = Callable()
var _tavern_site_id:      String   = ""


func setup(ctx: Dictionary) -> void:
	_get_keeper          = ctx.get("get_keeper",          Callable())
	_get_sentinels       = ctx.get("get_sentinels",       Callable())
	_memory_deny_service = ctx.get("memory_deny_service", Callable())
	_tavern_site_id      = ctx.get("tavern_site_id",      "")


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
	# Contacto individual — un solo respondedor.
	# La advertencia es presencia intimidante, no una movilización del recinto.
	var role := _role_for_zone(directive.zone_id)
	var s := _pick_primary(role, offender, [])
	if s != null:
		s.execute_directive(directive, offender)
		Debug.log("authority", "[DIRECTOR] WARN → %s (%s) zone=%s" % [
			s.name, role, directive.zone_id])


func _dispatch_deny_service(directive: LocalAuthorityDirective, _offender: CharacterBody2D) -> void:
	# Sanción económica: solo keeper.
	# No moviliza sentinels — la respuesta es institucional, no física.
	if _memory_deny_service.is_valid():
		_memory_deny_service.call(directive.offender_actor_id)
	var keeper := _get_keeper_node()
	if keeper != null and keeper.has_method("deny_service"):
		keeper.call("deny_service", directive.offender_actor_id)


func _dispatch_eject(directive: LocalAuthorityDirective, offender: CharacterBody2D) -> void:
	var C := LocalCivilAuthorityConstants
	if directive.zone_id == C.ZONE_TAVERN_PERIMETER:
		# Ataque o intrusión desde el exterior — "expulsar hacia afuera" no tiene sentido.
		# La respuesta correcta es física: el perimeter_guard intercepta y neutraliza.
		_dispatch_perimeter_force(directive, offender)
		return

	# Interior / grounds: door_guard primary (conoce la salida y está posicionado ahí)
	# + un interior_guard de apoyo (flanquea, bloquea la retirada).
	var assigned: Array[Sentinel] = []

	var primary := _pick_primary("door_guard", offender, assigned)
	if primary != null:
		primary.execute_directive(directive, offender)
		assigned.append(primary)
		Debug.log("authority", "[DIRECTOR] EJECT primary → %s (door_guard)" % primary.name)

	var support := _pick_support_single("interior_guard", offender, assigned)
	if support != null:
		support.execute_directive(directive, offender)
		Debug.log("authority", "[DIRECTOR] EJECT support → %s (interior_guard)" % support.name)

	# perimeter_guards mantienen el exterior — no participan en expulsiones interiores.


func _dispatch_perimeter_force(directive: LocalAuthorityDirective, offender: CharacterBody2D) -> void:
	# Daño o presencia hostil en el perímetro exterior — respuesta física directa.
	#
	# Reescribimos response_type a ARREST_OR_SUBDUE para que execute_directive
	# en el sentinel use OrderType.SUBDUE (combate/KO) en vez de OrderType.EJECT (escort).
	# El sentinel de EJECT intenta llevar al ofensor hacia la puerta — incoherente
	# si el ofensor está atacando la estructura desde fuera.
	var B := LocalAuthorityResponse.SeverityBand
	var force := _reclone_as(directive, LocalAuthorityResponse.Response.ARREST_OR_SUBDUE,
		" [perimeter→force]")

	var assigned: Array[Sentinel] = []

	# Perimeter_guard más cercano al punto de incidente — respuesta inmediata.
	var primary := _pick_primary("perimeter_guard", offender, assigned)
	if primary != null:
		primary.execute_directive(force, offender)
		assigned.append(primary)
		Debug.log("authority", "[DIRECTOR] PERIMETER_FORCE primary → %s" % primary.name)

	# Apoyo de los demás perimeter_guards si la situación es seria.
	# Si severity < HIGH: el incidente lo maneja el guardia asignado solo.
	if directive.severity_band >= B.HIGH:
		for s: Sentinel in _get_by_role("perimeter_guard", assigned):
			s.execute_directive(force, offender)
			Debug.log("authority", "[DIRECTOR] PERIMETER_FORCE support → %s" % s.name)

	# Interior guards y door_guard: mantienen cobertura interior.
	# No cruzar roles en incidentes perimetrales a menos que escale a CALL_BACKUP/ARREST.


func _dispatch_call_backup(directive: LocalAuthorityDirective, offender: CharacterBody2D) -> void:
	var C := LocalCivilAuthorityConstants
	var B := LocalAuthorityResponse.SeverityBand

	if directive.zone_id == C.ZONE_TAVERN_PERIMETER:
		# Escalación exterior: todos los perimeter_guards responden.
		# Un interior_guard sale a reforzar el perímetro.
		# Door_guard mantiene la entrada. Interior restante cubre al keeper.
		for s: Sentinel in _get_by_role("perimeter_guard", []):
			s.execute_directive(directive, offender)
			Debug.log("authority", "[DIRECTOR] BACKUP perimeter → %s" % s.name)

		var interior_reinforce := _pick_primary("interior_guard", offender, [])
		if interior_reinforce != null:
			interior_reinforce.execute_directive(directive, offender)
			Debug.log("authority", "[DIRECTOR] BACKUP reinforce→perimeter → %s" % interior_reinforce.name)

	else:
		# Escalación interior/grounds: interior_guards + door_guard.
		# Perimeter guards mantienen el exterior — cobertura mínima activa.
		for s: Sentinel in _get_sentinel_nodes():
			if s.sentinel_role == "perimeter_guard":
				continue
			s.execute_directive(directive, offender)
			Debug.log("authority", "[DIRECTOR] BACKUP interior → %s" % s.name)

		# En CRITICAL: la institución ya no puede mantener cobertura exterior.
		# Todos los sentinels convergen — el recinto se concentra en la amenaza.
		if directive.severity_band >= B.CRITICAL:
			for s: Sentinel in _get_by_role("perimeter_guard", []):
				s.execute_directive(directive, offender)
				Debug.log("authority", "[DIRECTOR] BACKUP all (CRITICAL) → %s" % s.name)


func _dispatch_arrest(directive: LocalAuthorityDirective, offender: CharacterBody2D) -> void:
	# Detención total — todos los sentinels sin excepción.
	# Solo casos extremos: murder, amenaza crítica armada, lockdown.
	for s: Sentinel in _get_sentinel_nodes():
		s.execute_directive(directive, offender)
	if directive.suggests_zone_lockdown:
		Debug.log("authority", "[DIRECTOR] LOCKDOWN sugerido — zone=%s offender=%s" \
			% [directive.zone_id, directive.offender_actor_id])


# ── Selección de sentinels ────────────────────────────────────────────────────

func _get_keeper_node() -> Node:
	return _get_keeper.call() if _get_keeper.is_valid() else null


## Todos los sentinels válidos del site actual.
func _get_sentinel_nodes() -> Array[Sentinel]:
	var result: Array[Sentinel] = []
	if not _get_sentinels.is_valid():
		return result
	var raw: Variant = _get_sentinels.call()
	if not raw is Array:
		return result
	for node: Variant in raw:
		if not (node is Sentinel and is_instance_valid(node)):
			continue
		var s := node as Sentinel
		if not _tavern_site_id.is_empty() and s.tavern_site_id != _tavern_site_id:
			continue
		result.append(s)
	return result


## Sentinels del rol dado, excluyendo los ya asignados.
func _get_by_role(role: String, exclude: Array[Sentinel]) -> Array[Sentinel]:
	var result: Array[Sentinel] = []
	for s: Sentinel in _get_sentinel_nodes():
		if s.sentinel_role == role and not exclude.has(s):
			result.append(s)
	return result


## Rol que debe responder primero según zona del incidente.
func _role_for_zone(zone_id: String) -> String:
	var C := LocalCivilAuthorityConstants
	if zone_id == C.ZONE_TAVERN_INTERIOR:
		return "interior_guard"
	if zone_id == C.ZONE_TAVERN_PERIMETER:
		return "perimeter_guard"
	return "door_guard"


## Elige el sentinel más apropiado como respondedor primario.
##
## Prioridad (en orden):
##   1. Rol exacto, idle (GUARD state) — el más cercano al ofensor
##   2. Rol exacto, ocupado            — ya tiene orden pero puede redirigirse
##   3. Rol de fallback, idle          — si el rol preferido no existe
##   4. Rol de fallback, ocupado
##   5. Cualquier sentinel del site    — último recurso
func _pick_primary(
		preferred_role: String,
		offender: CharacterBody2D,
		exclude: Array[Sentinel],
) -> Sentinel:
	var sentinels := _get_sentinel_nodes()
	if sentinels.is_empty():
		return null

	var fallback_role: String
	match preferred_role:
		"interior_guard":  fallback_role = "door_guard"
		"door_guard":      fallback_role = "interior_guard"
		"perimeter_guard": fallback_role = "door_guard"
		_:                 fallback_role = "interior_guard"

	var exact_idle:   Array[Sentinel] = []
	var exact_busy:   Array[Sentinel] = []
	var fallbk_idle:  Array[Sentinel] = []
	var fallbk_busy:  Array[Sentinel] = []

	for s: Sentinel in sentinels:
		if exclude.has(s):
			continue
		var idle := s.is_available()
		if s.sentinel_role == preferred_role:
			if idle: exact_idle.append(s)
			else:    exact_busy.append(s)
		elif s.sentinel_role == fallback_role:
			if idle: fallbk_idle.append(s)
			else:    fallbk_busy.append(s)

	for bucket: Array[Sentinel] in [exact_idle, exact_busy, fallbk_idle, fallbk_busy]:
		if not bucket.is_empty():
			return _pick_nearest(bucket, offender)

	# Último recurso: cualquier sentinel no excluido
	var any_pool: Array[Sentinel] = []
	for s: Sentinel in sentinels:
		if not exclude.has(s):
			any_pool.append(s)
	return _pick_nearest(any_pool, offender)


## Elige un único sentinel de soporte del rol dado, sin incluir ya asignados.
## Prefiere idle; acepta busy si no hay otro disponible.
func _pick_support_single(
		role: String,
		offender: CharacterBody2D,
		exclude: Array[Sentinel],
) -> Sentinel:
	var idle_pool:  Array[Sentinel] = []
	var busy_pool:  Array[Sentinel] = []
	for s: Sentinel in _get_sentinel_nodes():
		if s.sentinel_role != role or exclude.has(s):
			continue
		if s.is_available(): idle_pool.append(s)
		else:                busy_pool.append(s)
	if not idle_pool.is_empty():
		return _pick_nearest(idle_pool, offender)
	return _pick_nearest(busy_pool, offender)


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


## Construye un directive idéntico al base pero con response_type diferente.
## Usado para redirigir EJECT → ARREST_OR_SUBDUE en respuestas perimetrales.
func _reclone_as(
		base: LocalAuthorityDirective,
		new_response: String,
		note_suffix: String = "",
) -> LocalAuthorityDirective:
	var d := LocalAuthorityDirective.new()
	d.local_authority_id     = base.local_authority_id
	d.incident_id            = base.incident_id
	d.offender_actor_id      = base.offender_actor_id
	d.zone_id                = base.zone_id
	d.response_type          = new_response
	d.severity_band          = base.severity_band
	d.requires_responder     = LocalAuthorityResponse.Response.is_active_response(new_response)
	d.should_record          = base.should_record
	d.suggests_zone_lockdown = base.suggests_zone_lockdown
	d.notes                  = base.notes + note_suffix
	return d
