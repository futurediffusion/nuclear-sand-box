class_name Sentinel
extends "res://scripts/CharacterBase.gd"

# ── Sentinel ──────────────────────────────────────────────────────────────────
# Primer ejecutor físico del pipeline institucional local de taberna.
#
# POSICIÓN EN LA CADENA:
#   incident → LocalAuthorityEventFeed → LocalAuthorityDirective
#       → [TavernSanctionDirector futuro] → Sentinel.execute_directive()
#
# POR QUÉ NO EXTIENDE EnemyAI:
#   EnemyAI auto-agro al player y está diseñado para combate letal de facción.
#   El sentinel es autoridad civil: responde a órdenes institucionales, no a
#   proximidad del jugador. Su escalada es advertencia → empujón → KO, no "matar".
#
# MOVIMIENTO: usa NpcPathService (tile A*) vía _pathfind_toward(). El estado
#   SUBDUE instancia WeaponComponent + AIWeaponController igual que TavernKeeper.
#   AIComponent completo no se usa: su LOD/bow/duel es overkill para rol civil.
#
# ESTADOS:
#   GUARD       — en el post; escanea periódicamente cuerpos KO en la taberna
#   INTERCEPT   — moviéndose hacia el target o posición de la orden
#   WARN        — advertencia: proximidad + espera antes de escalar
#   SHOVE       — empujón direccional (CombatPhysicsHelper) + mini-grab
#   CHASE_SHORT — persecución dentro de jurisdicción
#   SUBDUE      — combate para dejar KO (WeaponComponent + AIWeaponController)
#   RETURN      — volviendo a home_pos
#   HAUL        — transporta cuerpos KO (player/npc/enemy) fuera de la taberna
#                 via soft-carry (sin reparenteo; mueve global_position cada frame)
#
# QUÉ NO RESUELVE TODAVÍA:
#   - Animación de advertencia visual / speech bubble
#   - Cooldowns sociales persistentes por actor
#   - Coordinación entre múltiples sentinels
#   - Integración completa con TavernSanctionDirector
#
# LÍMITE DE RESPONSABILIDAD (fase 1):
#   El sentinel ya gestiona órdenes, jurisdicción, shove, subdue, haul,
#   geometría de taberna, passthrough y pathing. Para fase 2+ extraer
#   haul y passthrough a helpers/directors antes de añadir más lógica.

const InventoryComponentScript = preload("res://scripts/components/InventoryComponent.gd")
const WeaponComponentScript    = preload("res://scripts/components/WeaponComponent.gd")
const AIWeaponControllerScript = preload("res://scripts/weapons/AIWeaponController.gd")

# ── Estados ───────────────────────────────────────────────────────────────────

enum State {
	GUARD,        ## En el post — mínimo movimiento, vigilando
	INTERCEPT,    ## Moviéndose hacia el target o posición de la orden
	WARN,         ## Advertencia: proximidad + espera antes de escalar
	SHOVE,        ## Empujón sin daño → CHASE_SHORT
	CHASE_SHORT,  ## Persiguiendo dentro de jurisdicción
	SUBDUE,       ## Combate para dejar KO
	RETURN,       ## Volviendo a home_pos
	HAUL,         ## Recogiendo/transportando un cuerpo KO hacia la salida
}

## Tipo de orden externa. Issued por TavernSanctionDirector, TavernKeeper o debug.
enum OrderType {
	NONE,
	WARNING_INTERCEPT,  ## warn + posible shove + retorno si obedece
	EJECT,              ## warn → shove → chase → escalar si no sale
	SUBDUE,             ## saltar advertencia, ir directo a KO
}

# ── Exports — duckt-typing para AIComponent (contrato del futuro) ──────────────

@export_group("Movement")
@export var max_speed: float      = 100.0   ## velocidad de guardia/retorno
@export var chase_speed: float    = 148.0   ## velocidad de persecución
@export var acceleration: float   = 800.0
@export var friction: float       = 1200.0

@export_group("Detection & Jurisdiction")
@export var detection_range: float       = 180.0   ## para futura integración AIComponent
@export var jurisdiction_radius: float   = 320.0   ## ~10 tiles de 32px — radio de guardia
@export var chase_abandon_radius: float  = 380.0   ## abandona persecución si target > dist de home
@export var ACTIVE_RADIUS_PX: float      = 900.0
@export var WAKE_HYSTERESIS_PX: float    = 200.0
@export var SLEEP_CHECK_INTERVAL: float  = 0.5

@export_group("Combat Behavior")
@export var attack_range: float       = 52.0
@export var shove_force: float        = 210.0   ## knockback sin daño
@export var shove_cooldown: float     = 2.2     ## mínimo s entre shoves
@export var max_shoves_before_subdue: int = 3   ## escalada automática
@export var warn_approach_dist: float = 68.0    ## px: distancia para iniciar WARN (entra en modo acercamiento lento)
@export var shove_trigger_dist: float = 26.0    ## px: distancia a la que dispara el empujón al llegar pegado
@export var grab_duration: float      = 0.7     ## s: duración del mini-grab en EJECT (arrastre continuo hacia la puerta)
@export var grab_drag_force: float    = 130.0   ## fuerza continua de arrastre durante el grab (por frame × delta)

@export_group("Institutional Identity")
## Rol dentro del despliegue de taberna. Seteado por world.gd al spawnear.
## Valores: "interior_guard" | "door_guard" | "perimeter_guard" | "" (debug/manual)
## TavernSanctionDirector usa este rol para elegir qué sentinel responde al incidente.
@export var sentinel_role: String = ""
## Site al que pertenece este sentinel. "tavern_main" para sentinels de taberna.
## Permite que el director gestione sentinels de múltiples locaciones si escala.
@export var tavern_site_id: String = ""

@export_group("References")
@export var slash_scene: PackedScene   ## asignar en Inspector — misma slash.tscn del enemy


# ── Nodes ─────────────────────────────────────────────────────────────────────

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var detection_area: Area2D   = $DetectionArea


# ── Identity ──────────────────────────────────────────────────────────────────

## Posición del post de guardia. Se asigna en _ready() o via spawn_near_tavern().
var home_pos: Vector2 = Vector2.ZERO

## Puntos de patrulla corta en GUARD state. Vacío = sentinel estático en home_pos.
## Solo el door_guard recibe puntos (asignados por world.gd al spawnear).
## El interior_guard se queda en su post.
@export var patrol_points: PackedVector2Array = PackedVector2Array()

const _PATROL_SPEED:     float = 35.0  # más lento que max_speed — patrulla tranquila
const _PATROL_WAIT_MIN:  float = 1.5   # espera mínima en cada punto
const _PATROL_WAIT_MAX:  float = 5.0   # espera máxima en cada punto

var _patrol_idx:        int   = 0
var _patrol_wait:       float = 0.0
var _patrol_wait_target: float = 2.5   # se randomiza en cada llegada

## Reporter de incidentes civiles — registrado por world.gd al spawnear.
var _incident_reporter: Callable = Callable()
## Cooldown por instancia de enemy para evitar spam de armed_intruder.
## Clave: instance_id. Valor: tiempo de sesión hasta que se puede volver a reportar.
var _armed_intruder_reported: Dictionary = {}
const _ARMED_INTRUDER_COOLDOWN_SEC: float = 15.0


# ── Estado interno ────────────────────────────────────────────────────────────

var _state: State      = State.GUARD
var _state_timer: float = 0.0

# Orden activa
var _current_order: OrderType          = OrderType.NONE
var _order_target: CharacterBody2D     = null   ## node del target (player u NPC)
var _order_pos: Vector2                = Vector2.ZERO  ## fallback si target no válido
var _shove_count: int                  = 0

# Geometría de la taberna — resuelta una vez en _ready() y al emitir orden EJECT.
var _tavern_exit_pos: Vector2    = Vector2.ZERO
var _tavern_inner_bounds: Rect2  = Rect2()

# HAUL — transporte de cuerpos KO hacia la salida (independiente de órdenes)
# Nota: NO usamos reparenteo (evita que Camera2D salte). En su lugar movemos
# manualmente el cuerpo cada frame para que siga al sentinel.
var _carry_comp: CarryComponent  = null
var _haul_body: CharacterBase    = null
var _haul_phase: int             = 0     ## 0=acercarse, 1=llevar a salida, 2=espera post-drop
var _haul_scan_t: float          = 1.5   ## primer scan rápido al poco de spawnear
const _HAUL_SCAN_INTERVAL: float = 3.5
## Offset del cuerpo respecto al sentinel mientras se lleva (en local space)
const _HAUL_CARRY_OFFSET: Vector2 = Vector2(0, 4)
## Guardamos estado original del body para restaurar al soltar
var _haul_saved_collision_layer: int = 0
var _haul_saved_collision_mask: int  = 0
var _haul_is_carrying: bool          = false

# Timers
var _shove_cooldown_t: float  = 0.0
var _melee_attack_timer: float = 0.0
## Tiempo restante con colisión sentinel↔player desactivada.
## Evita que se "peguen" durante el re-approach post-shove y
## permite que el player pase a través del sentinel en EJECT.
var _passthrough_t: float = 0.0

## ID de agente para NpcPathService. Inicializado al primer uso.
var _path_id: String = ""

# Combat stack (construido bajo demanda en SUBDUE — igual que TavernKeeper)
var _weapon_pivot: Node2D                    = null
var _weapon_component_node: WeaponComponent  = null
var _ai_weapon_controller_node: AIWeaponController = null

# Duck-typing: AIComponent necesita estas vars si alguna vez se conecta
var target_attack_angle: float = 0.0
var use_left_offset: bool      = false
var angle_offset_left: float   = -150.0
var angle_offset_right: float  = 150.0

const _MELEE_ATTACK_INTERVAL: float = 0.9


# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	super._ready()
	_setup_health_component()
	_connect_hurtbox()
	downed_entered.connect(func() -> void: CameraFX.shake_impulse(0.22, 18.0))
	dying_started.connect(func()  -> void: CameraFX.shake_impulse(0.32, 28.0))
	add_to_group("npc")
	add_to_group("sentinel")

	home_pos = global_position

	# CarryComponent para transportar cuerpos KO
	_carry_comp = CarryComponent.new()
	_carry_comp.name = "SentinelCarryComponent"
	_carry_comp.stack_base_offset = Vector2(0, -14)
	add_child(_carry_comp)

	_enter_guard()

	# Resolver geometría de la taberna en diferido (el World puede no estar listo aún)
	_resolve_eject_context.call_deferred()

	if detection_area != null:
		# Activar detección de enemigos (layer 3) en la DetectionArea.
		# Por defecto la máscara es 0 — solo la seteamos si este sentinel tiene site_id,
		# es decir, es un sentinel institucional (no de debug).
		if not tavern_site_id.is_empty():
			detection_area.collision_mask = CollisionLayers.ENEMY_LAYER_MASK
		if not detection_area.body_entered.is_connected(_on_detection_entered):
			detection_area.body_entered.connect(_on_detection_entered)
		if not detection_area.body_exited.is_connected(_on_detection_exited):
			detection_area.body_exited.connect(_on_detection_exited)


func _physics_process(delta: float) -> void:
	if hurt_t > 0.0:
		hurt_t -= delta

	_update_animation()

	if dying or is_downed:
		move_and_slide()
		return
	if hurt_t > 0.0:
		_apply_knockback_step(delta)
		move_and_slide()
		return

	_shove_cooldown_t  = maxf(0.0, _shove_cooldown_t  - delta)
	_melee_attack_timer = maxf(0.0, _melee_attack_timer - delta)
	_state_timer       += delta

	# Colisión física con el player desactivada en dos situaciones:
	#   - EJECT completo: sentinel fantasmea hasta el player desde cualquier ángulo
	#     (esquinas norte, paredes laterales). Se restaura al salir de la orden.
	#   - Post-shove (otras órdenes): evita el "arrastre" por solapamiento.
	if _passthrough_t > 0.0:
		_passthrough_t -= delta
		if _passthrough_t <= 0.0:
			_restore_collision()

	_tick_state(delta)
	_apply_knockback_step(delta)

	if _weapon_pivot != null:
		_update_weapon_pivot(delta)

	move_and_slide()


# ── State machine ─────────────────────────────────────────────────────────────

func _tick_state(delta: float) -> void:
	match _state:
		State.GUARD:       _tick_guard(delta)
		State.INTERCEPT:   _tick_intercept(delta)
		State.WARN:        _tick_warn(delta)
		State.SHOVE:       _tick_shove(delta)
		State.CHASE_SHORT: _tick_chase_short(delta)
		State.SUBDUE:      _tick_subdue(delta)
		State.RETURN:      _tick_return(delta)
		State.HAUL:        _tick_haul(delta)


func _tick_guard(delta: float) -> void:
	_tick_haul_scan(delta)
	if not _tick_patrol(delta):
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)


## Patrulla idle: recorre patrol_points a baja velocidad mientras GUARD.
## Espera aleatoria en cada punto y elige el siguiente punto al azar (no secuencial).
## Devuelve true si el sentinel se está moviendo (no aplicar fricción externa).
func _tick_patrol(delta: float) -> bool:
	if patrol_points.is_empty():
		return false
	var target: Vector2 = patrol_points[_patrol_idx % patrol_points.size()]
	var dist: float     = global_position.distance_to(target)
	if dist < 8.0:
		# Llegó al punto — esperar un tiempo aleatorio antes de continuar
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
		_patrol_wait += delta
		if _patrol_wait >= _patrol_wait_target:
			_patrol_wait        = 0.0
			_patrol_wait_target = randf_range(_PATROL_WAIT_MIN, _PATROL_WAIT_MAX)
			_patrol_idx         = _pick_next_patrol_idx()
		return false
	_patrol_wait = 0.0
	_pathfind_toward(target, _PATROL_SPEED)
	return true


## Elige el siguiente punto de patrulla al azar, distinto del actual.
func _pick_next_patrol_idx() -> int:
	var n: int = patrol_points.size()
	if n <= 1:
		return 0
	var current: int = _patrol_idx % n
	var next: int    = randi() % (n - 1)
	if next >= current:
		next += 1
	return next


func _tick_intercept(delta: float) -> void:
	var target_pos := _get_effective_order_pos()
	var dist := global_position.distance_to(target_pos)

	# Jurisdicción: para EJECT el límite es que el player salga de la taberna,
	# no el radio de home_pos (el player puede estar al otro lado del mapa interior).
	if _order_target != null and is_instance_valid(_order_target):
		if _current_order == OrderType.EJECT:
			if _player_is_outside_tavern():
				_enter_return()
				return
		else:
			if not _is_in_jurisdiction((_order_target as Node2D).global_position):
				_enter_return()
				return

	# Perimeter guards no entran al interior: si el target (o el propio sentinel)
	# ya está dentro del inner bounds, regresar al post.
	if sentinel_role == "perimeter_guard" and _tavern_inner_bounds.size != Vector2.ZERO:
		if _tavern_inner_bounds.has_point(global_position):
			_enter_return()
			return

	if dist < warn_approach_dist:
		# Si el target ya está KO al acercarnos, no continuar hacia warn/chase.
		var target_cb := _order_target as CharacterBase
		if target_cb != null and target_cb.is_downed:
			if _can_haul_target(target_cb):
				_enter_haul(target_cb)
			else:
				_enter_return()
			return
		match _current_order:
			OrderType.SUBDUE:
				_enter_chase_short()   # subdue salta advertencia
			_:
				_enter_warn()
		return

	_pathfind_toward(target_pos, max_speed)


func _tick_warn(delta: float) -> void:
	if _order_target == null or not is_instance_valid(_order_target):
		_enter_return()
		return

	var target_pos := (_order_target as Node2D).global_position

	# Jurisdicción: para EJECT el límite es la salida de la taberna, no el radio.
	if _current_order == OrderType.EJECT:
		if _player_is_outside_tavern():
			_enter_return()
			return
		# Si el player huyó demasiado lejos del post del sentinel, abortar.
		if target_pos.distance_to(home_pos) > chase_abandon_radius:
			_enter_return()
			return
	else:
		if not _is_in_jurisdiction(target_pos):
			_enter_return()
			return

	# Acercarse al player. Para EJECT la dirección del empujón viene de shove_directional
	# (hacia el exit), así que no hace falta posicionarse en un lado específico.
	if global_position.distance_to(target_pos) <= shove_trigger_dist:
		# Nunca empujar un target KO — pasar a haul o retornar.
		var target_cb := _order_target as CharacterBase
		if target_cb != null and target_cb.is_downed:
			if _can_haul_target(target_cb):
				_enter_haul(target_cb)
			else:
				_enter_return()
			return
		_enter_shove()
		return

	_pathfind_toward(target_pos, max_speed * 0.8)


func _tick_shove(delta: float) -> void:
	if _current_order == OrderType.EJECT and _state_timer < grab_duration:
		# ── Mini grab ─────────────────────────────────────────────────────────
		# El sentinel camina hacia la puerta y arrastra al player con él.
		# Útil para esquinas donde un solo impulso no saca al player.
		if _tavern_exit_pos != Vector2.ZERO:
			_pathfind_toward(_tavern_exit_pos, max_speed * 0.45)
			if _order_target != null and is_instance_valid(_order_target):
				var target_base := _order_target as CharacterBase
				if target_base != null and not target_base.dying and not target_base.is_downed:
					var player_to_exit := (_tavern_exit_pos - (_order_target as Node2D).global_position).normalized()
					target_base.apply_knockback(player_to_exit * grab_drag_force * delta)
		return   # seguir en SHOVE hasta que expire grab_duration

	# ── Fin del grab / shove normal ───────────────────────────────────────────
	velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
	var wait_t := grab_duration if _current_order == OrderType.EJECT else 0.4
	if _state_timer >= wait_t:
		_shove_count += 1
		# Si el target quedó KO durante el shove/grab, pasar a haul en vez de
		# volver a WARN (lo que causaría el loop infinito de empujón sobre cuerpo KO).
		var target_cb := _order_target as CharacterBase
		if target_cb != null and target_cb.is_downed:
			if _can_haul_target(target_cb):
				_enter_haul(target_cb)
			else:
				_enter_return()
			return
		if _current_order == OrderType.EJECT:
			if _player_is_outside_tavern():
				_enter_return()
			elif _shove_count >= max_shoves_before_subdue:
				# El player no sale después de varios empujones — escalar a SUBDUE
				# en vez de seguir en el loop EJECT. Evita que el sentinel quede
				# atascado empujando mobiliario o el aire indefinidamente.
				_enter_subdue()
			else:
				_enter_warn()
		elif _current_order == OrderType.SUBDUE or _shove_count >= max_shoves_before_subdue:
			_enter_subdue()
		else:
			_enter_warn()


func _tick_chase_short(delta: float) -> void:
	var target_pos := _get_effective_order_pos()
	var dist := global_position.distance_to(target_pos)

	# Jurisdicción — si el target salió lo suficientemente lejos, misión cumplida
	if _order_target != null and is_instance_valid(_order_target):
		var dist_from_home := (_order_target as Node2D).global_position.distance_to(home_pos)
		if dist_from_home > chase_abandon_radius:
			_enter_return()
			return

	# Perimeter guards no entran al interior de la taberna.
	# Si el target cruzó al interior, abandonar y volver al post.
	if sentinel_role == "perimeter_guard" and _tavern_inner_bounds.size != Vector2.ZERO:
		if _tavern_inner_bounds.has_point(global_position):
			_enter_return()
			return

	# Target neutralizado (KO o muerto)
	if _target_is_neutralized():
		_enter_return()
		return

	# Escalar a SUBDUE si: orden es SUBDUE, o superamos el límite de shoves
	if _current_order == OrderType.SUBDUE or _shove_count >= max_shoves_before_subdue:
		_enter_subdue()
		return

	# Re-shove si podemos y el target sigue cerca
	if dist < attack_range and _shove_cooldown_t <= 0.0 and _current_order == OrderType.EJECT:
		_enter_shove()
		return

	# Seguir al target
	if dist > 8.0:
		_pathfind_toward(target_pos, chase_speed, {"repath_interval": 0.5})
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)


func _tick_subdue(delta: float) -> void:
	# Tick weapon stack (si fue construido)
	if _ai_weapon_controller_node != null:
		_ai_weapon_controller_node.physics_tick()
	if _weapon_component_node != null:
		_weapon_component_node.tick(delta)

	var target_pos := _get_effective_order_pos()
	var dist       := global_position.distance_to(target_pos)

	# Jurisdicción
	if not _is_in_jurisdiction(target_pos):
		_enter_return()
		return

	# Perimeter guards no entran al interior de la taberna.
	if sentinel_role == "perimeter_guard" and _tavern_inner_bounds.size != Vector2.ZERO:
		if _tavern_inner_bounds.has_point(global_position):
			_enter_return()
			return

	# Target neutralizado — intentar HAUL inmediato si quedó KO en la taberna
	if _target_is_neutralized():
		var target_base := _order_target as CharacterBase
		if target_base != null and target_base.is_downed and _can_haul_target(target_base):
			_enter_haul(target_base)
		else:
			_enter_return()
		return

	# Moverse hacia el target
	if dist > attack_range:
		_pathfind_toward(target_pos, chase_speed, {"repath_interval": 0.5})
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
		# Atacar en rango
		if _melee_attack_timer <= 0.0:
			_melee_attack_timer = _MELEE_ATTACK_INTERVAL
			_do_attack(target_pos)


func _tick_return(delta: float) -> void:
	var dist := global_position.distance_to(home_pos)
	if dist < 14.0:
		velocity = Vector2.ZERO
		_enter_guard()
		return
	_pathfind_toward(home_pos, max_speed)


func _tick_haul(delta: float) -> void:
	# Cancelar si el cuerpo desapareció o se recuperó (revivió).
	# Si está dying (murió mientras lo cargaban) seguimos llevándolo al exit —
	# así el respawn ocurre fuera de la taberna, no en medio de ella.
	var _body_gone := _haul_body == null or not is_instance_valid(_haul_body)
	var _body_recovered := not _body_gone \
		and not _haul_body.is_downed \
		and not _haul_body.dying
	if _body_gone:
		# Body inválido — limpiar sin restaurar (el nodo ya no existe).
		_haul_is_carrying = false
		_haul_body = null
		_enter_return()
		return
	if _body_recovered:
		# Solo restaurar colisión si aún estamos cargando activamente.
		# Si ya soltamos en el exit (fase 2, _haul_is_carrying=false), no restaurar
		# desde valores potencialmente stale — la restauración ya ocurrió al soltar.
		if _haul_is_carrying:
			_haul_release()
		_haul_body = null
		_enter_return()
		return

	match _haul_phase:
		0:  # ── Acercarse al cuerpo ──────────────────────────────────────────
			var dist := global_position.distance_to(_haul_body.global_position)
			if dist < 28.0:
				if _try_haul_pickup():
					_haul_phase = 1
				else:
					_haul_body = null
					_enter_return()
			else:
				_pathfind_toward(_haul_body.global_position, max_speed)

		1:  # ── Llevar a la salida ───────────────────────────────────────────
			# Arrastrar el cuerpo junto al sentinel (sin reparenteo)
			if _haul_is_carrying and _haul_body != null and is_instance_valid(_haul_body):
				_haul_body.global_position = global_position + _HAUL_CARRY_OFFSET

			var exit := _tavern_exit_pos if _tavern_exit_pos != Vector2.ZERO \
				else (home_pos + Vector2(0, 48))
			var dist := global_position.distance_to(exit)
			if dist < 24.0:
				_haul_release()
				_haul_phase = 2
				_state_timer = 0.0
				Debug.log("sentinel", "[%s] cuerpo depositado en salida" % name)
			else:
				_pathfind_toward(exit, max_speed * 0.85)

		2:  # ── Breve pausa tras soltar ─────────────────────────────────────
			velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
			if _state_timer >= 0.6:
				_haul_body = null
				_haul_scan_t = _HAUL_SCAN_INTERVAL
				_enter_return()


## Pickup sin reparenteo — evita que la cámara salte.
## Desactiva physics/colisión del body y lo arrastra manualmente cada frame.
func _try_haul_pickup() -> bool:
	if _haul_body == null or not is_instance_valid(_haul_body):
		return false
	if not _haul_body.is_downed:
		Debug.log("sentinel", "[%s] HAUL pickup FAIL: body no está downed" % name)
		return false
	if _haul_is_carrying:
		return true  # ya llevando
	# Guardar y anular colisiones del body para que no choque durante el transporte
	_haul_saved_collision_layer = _haul_body.collision_layer
	_haul_saved_collision_mask  = _haul_body.collision_mask
	_haul_body.collision_layer  = 0
	_haul_body.collision_mask   = 0
	# Desactivar physics del body (lo moveremos nosotros)
	_haul_body.set_physics_process(false)
	_haul_body.set_process(false)
	_haul_is_carrying = true
	Debug.log("sentinel", "[%s] HAUL pickup OK (soft-carry): %s" % [name, _haul_body.name])
	return true


## Suelta el body restaurando su estado físico.
func _haul_release() -> void:
	if _haul_body != null and is_instance_valid(_haul_body):
		_haul_body.collision_layer = _haul_saved_collision_layer
		_haul_body.collision_mask  = _haul_saved_collision_mask
		_haul_body.set_physics_process(true)
		_haul_body.set_process(true)
		_haul_body.remove_from_group("sentinel_haul_claimed")
	_haul_is_carrying = false


## Scan periódico de cuerpos KO en el interior de la taberna.
## Solo activo en estado GUARD (no interrumpe órdenes activas).
func _tick_haul_scan(delta: float) -> void:
	_haul_scan_t -= delta
	if _haul_scan_t > 0.0:
		return
	_haul_scan_t = _HAUL_SCAN_INTERVAL
	if _tavern_inner_bounds.size == Vector2.ZERO:
		return   # geometría de taberna no resuelta aún
	var body := _find_downed_body_in_tavern()
	if body != null and _can_haul_target(body):
		_enter_haul(body)


## Busca un cuerpo KO dentro de la taberna que sea transportable.
## Excluye: tavern_keeper, otros sentinels, cuerpos ya siendo cargados o
## ya reclamados por otro sentinel (grupo "sentinel_haul_claimed").
func _find_downed_body_in_tavern() -> CharacterBase:
	var search_bounds := _tavern_inner_bounds.grow(32.0)
	for group in ["npc", "player", "enemy"]:
		for node in get_tree().get_nodes_in_group(group):
			var cb := node as CharacterBase
			if cb == null or not cb.is_downed:
				continue
			if cb.is_in_group("tavern_keeper") or cb.is_in_group("sentinel"):
				continue
			if cb.is_in_group("sentinel_haul_claimed"):
				continue
			if _tavern_inner_bounds.size != Vector2.ZERO \
					and not search_bounds.has_point(cb.global_position):
				continue
			var carryable := cb.get_node_or_null("CarryableComponent") as CarryableComponent
			if carryable != null and carryable._is_carried:
				continue
			return cb
	return null



# ── State transitions ─────────────────────────────────────────────────────────

func _enter_guard() -> void:
	_state        = State.GUARD
	_state_timer  = 0.0
	_current_order = OrderType.NONE
	_order_target  = null
	_restore_collision()
	_order_pos     = Vector2.ZERO
	_shove_count   = 0
	velocity       = Vector2.ZERO


func _enter_intercept() -> void:
	_state       = State.INTERCEPT
	_state_timer = 0.0


func _enter_warn() -> void:
	_state       = State.WARN
	_state_timer = 0.0
	# TODO: activar indicador visual / speech bubble de advertencia


func _enter_shove() -> void:
	_state            = State.SHOVE
	_state_timer      = 0.0
	_shove_cooldown_t = shove_cooldown

	# Desactivar colisión física sentinel↔player durante el ventana de shove + re-approach.
	# mask(1): evita que el player bloquee el movimiento del sentinel.
	# mask(1): el sentinel ignora al player temporalmente para poder empujar sin
	#          quedar enredado en su collider. layer(3) permanece activo siempre
	#          para que los sentinels no se solapen entre sí.
	_passthrough_t = shove_cooldown + 0.4   # cubre la espera de SHOVE (0.4s) + el re-approach
	set_collision_mask_value(1, false)

	# Aplicar empujón en la entrada del estado.
	# Nunca empujar un target KO — si llegamos aquí con un target downed es un bug
	# de la llamada, pero nos protegemos igualmente.
	if _order_target != null and is_instance_valid(_order_target):
		var target_base := _order_target as CharacterBase
		if target_base != null and not target_base.is_downed:
			if _current_order == OrderType.EJECT and _tavern_exit_pos != Vector2.ZERO:
				var shove_dir := (_tavern_exit_pos - (_order_target as Node2D).global_position).normalized()
				CombatPhysicsHelper.shove_directional(target_base, shove_dir, shove_force)
			else:
				CombatPhysicsHelper.shove_no_damage(global_position, target_base, shove_force)
			_play_shove_impact_sound()


func _enter_chase_short() -> void:
	_state       = State.CHASE_SHORT
	_state_timer = 0.0


func _enter_subdue() -> void:
	_state       = State.SUBDUE
	_state_timer = 0.0
	_build_combat_stack_if_needed()


func _enter_return() -> void:
	_state       = State.RETURN
	_state_timer = 0.0
	velocity     = Vector2.ZERO
	_restore_collision()


func _can_haul_target(cb: CharacterBase) -> bool:
	if cb == null or not is_instance_valid(cb):
		return false
	if not cb.is_downed:
		return false
	if cb.is_in_group("tavern_keeper") or cb.is_in_group("sentinel"):
		return false
	# Evitar cargar un cuerpo que ya está siendo gestionado por otro sentinel.
	# Sin esta comprobación, un segundo sentinel puede guardar collision_mask=0
	# (ya anulado por el primero) y restaurarlo a 0 al soltar → pass-through de paredes.
	if cb.is_in_group("sentinel_haul_claimed"):
		return false
	# Verificar que tiene CarryableComponent y puede cargarse
	var carryable := cb.get_node_or_null("CarryableComponent") as CarryableComponent
	if carryable == null:
		Debug.log("sentinel", "[%s] _can_haul_target: %s sin CarryableComponent" % [name, cb.name])
		return false
	if carryable._is_carried:
		return false
	# Aceptar si está en bounds de taberna O si es el target directo de SUBDUE
	if _tavern_inner_bounds.size != Vector2.ZERO:
		if not _tavern_inner_bounds.grow(32.0).has_point(cb.global_position):
			Debug.log("sentinel", "[%s] _can_haul_target: %s fuera de bounds ampliados" % [name, cb.name])
			return false
	return true


func _enter_haul(body: CharacterBase) -> void:
	_haul_body  = body
	_haul_phase = 0
	_state       = State.HAUL
	_state_timer = 0.0
	_current_order = OrderType.NONE
	_order_target  = null
	body.add_to_group("sentinel_haul_claimed")
	Debug.log("sentinel", "[%s] → HAUL cuerpo=%s downed=%s" % [name, body.name, str(body.is_downed)])


# ── Attack ────────────────────────────────────────────────────────────────────

func _do_attack(target_pos: Vector2) -> void:
	if _weapon_component_node != null:
		# Camino preferido: pasar por el weapon controller (igual que TavernKeeper)
		queue_ai_attack_press(target_pos)
	else:
		# Fallback sin arma: daño directo al hurtbox del target
		if _order_target != null and is_instance_valid(_order_target):
			var target_base := _order_target as CharacterBase
			if target_base != null and not target_base.is_downed:
				target_base.take_damage(1, global_position)


## Requerido por duck-typing de AIComponent y WeaponComponent.
func queue_ai_attack_press(aim_global_position: Vector2) -> void:
	var ctrl := _ensure_ai_weapon_controller()
	ctrl.queue_attack_press_with_aim(aim_global_position)
	ctrl.set_attack_down(false)
	var angle_to_target := global_position.angle_to_point(aim_global_position)
	if use_left_offset:
		target_attack_angle = angle_to_target + deg_to_rad(angle_offset_left)
	else:
		target_attack_angle = angle_to_target + deg_to_rad(angle_offset_right)
	use_left_offset = not use_left_offset


## Requerido por duck-typing de AIComponent.
func spawn_slash(angle: float) -> void:
	if slash_scene == null or _weapon_pivot == null:
		return
	var parent := get_tree().current_scene
	if parent == null:
		return
	var slash_spawn_node := _weapon_pivot.get_node_or_null("SlashSpawn")
	if slash_spawn_node == null:
		return
	var s := slash_scene.instantiate()
	s.setup(&"enemy", self)
	s.position = parent.to_local((slash_spawn_node as Node2D).global_position)
	s.rotation = angle
	parent.add_child(s)


# ── Combat stack (construido bajo demanda, igual que TavernKeeper) ────────────

func _build_combat_stack_if_needed() -> void:
	if _weapon_pivot != null:
		return   # ya construido

	_weapon_pivot = Node2D.new()
	_weapon_pivot.name = "WeaponPivot"
	_weapon_pivot.z_index = 10
	add_child(_weapon_pivot)

	var weapon_sprite_node := Sprite2D.new()
	weapon_sprite_node.name = "WeaponSprite"
	weapon_sprite_node.z_index = 10
	_weapon_pivot.add_child(weapon_sprite_node)

	var slash_spawn_node := Marker2D.new()
	slash_spawn_node.name = "SlashSpawn"
	slash_spawn_node.position = Vector2(24.0, 0.0)
	_weapon_pivot.add_child(slash_spawn_node)

	var arrow_muzzle := Marker2D.new()
	arrow_muzzle.name = "ArrowMuzzle"
	arrow_muzzle.position = Vector2(24.0, 0.0)
	_weapon_pivot.add_child(arrow_muzzle)

	var combat_inv := InventoryComponentScript.new()
	combat_inv.name = "SentinelCombatInventory"
	add_child(combat_inv)
	combat_inv.add_item("ironpipe", 1)   # solo cuerpo a cuerpo — sin arco

	_weapon_component_node = WeaponComponentScript.new()
	_weapon_component_node.name = "WeaponComponent"
	add_child(_weapon_component_node)
	_weapon_component_node.setup_from_inventory(combat_inv)
	if not _weapon_component_node.weapon_equipped.is_connected(_on_weapon_equipped):
		_weapon_component_node.weapon_equipped.connect(_on_weapon_equipped)

	var ctrl := _ensure_ai_weapon_controller()
	_weapon_component_node.apply_visuals(self)
	_weapon_component_node.equip_runtime_weapon(self, ctrl)


func _ensure_ai_weapon_controller() -> AIWeaponController:
	if _ai_weapon_controller_node != null:
		return _ai_weapon_controller_node
	_ai_weapon_controller_node = AIWeaponControllerScript.new()
	_ai_weapon_controller_node.name = "AIWeaponController"
	add_child(_ai_weapon_controller_node)
	return _ai_weapon_controller_node


func _on_weapon_equipped(_wid: String) -> void:
	if _weapon_component_node == null:
		return
	var ctrl := _ensure_ai_weapon_controller()
	_weapon_component_node.apply_visuals(self)
	_weapon_component_node.equip_runtime_weapon(self, ctrl)


func _update_weapon_pivot(delta: float) -> void:
	if _weapon_pivot == null:
		return
	var target_pos := _get_effective_order_pos()
	var angle_to_target := global_position.angle_to_point(target_pos)

	# El sentinel no usa el swing-arc de ±150° del enemy — siempre apunta directo al target.
	# target_attack_angle se pasa al AIWeaponController para que calcule el arc interno,
	# pero el pivot visual siempre mira hacia el target para que SlashSpawn quede en frente.
	_weapon_pivot.rotation = lerp_angle(_weapon_pivot.rotation, angle_to_target,
		1.0 - exp(-50.0 * delta))

	var ws := _weapon_pivot.get_node_or_null("WeaponSprite") as Sprite2D
	if ws != null:
		var angle := wrapf(_weapon_pivot.rotation, -PI, PI)
		ws.flip_v = abs(angle) > PI / 2.0


# ── Hurtbox ───────────────────────────────────────────────────────────────────

func _connect_hurtbox() -> void:
	var hb := get_node_or_null("Hurtbox") as CharacterHurtbox
	if hb == null:
		return
	if not hb.damaged.is_connected(_on_hurtbox_damaged):
		hb.damaged.connect(_on_hurtbox_damaged)


func _on_hurtbox_damaged(dmg: int, from_pos: Vector2) -> void:
	take_damage(dmg, from_pos)
	CameraFX.shake(6.5)
	# El sentinel no contra-agrede automáticamente al recibir daño.
	# Mantiene su orden activa (institucional, no instintiva).
	if _incident_reporter.is_valid() and not tavern_site_id.is_empty():
		_incident_reporter.call("assault_sentinel", {"pos": from_pos, "victim": self})




# ── Detection area (reserved for future use) ──────────────────────────────────

func _on_detection_entered(body: Node) -> void:
	# Solo actuar si el sentinel está en GUARD (en post) y tiene reporter institucional.
	if _state != State.GUARD:
		return
	if not _incident_reporter.is_valid() or tavern_site_id.is_empty():
		return
	if body == null or not is_instance_valid(body):
		return
	if not body.is_in_group("enemy"):
		return

	# Cooldown por individuo: no re-reportar el mismo enemy en menos de N segundos.
	var iid: int = body.get_instance_id()
	var now: float = Time.get_ticks_msec() / 1000.0
	if _armed_intruder_reported.get(iid, 0.0) > now:
		return
	_armed_intruder_reported[iid] = now + _ARMED_INTRUDER_COOLDOWN_SEC

	# Nuance: distinguir entre presencia hostil pasiva y amenaza activa.
	# Un enemy que entra pero no está atacando = trespass (presencia tensa sin agresión).
	# Un enemy que ya está atacando al entrar = armed_intruder (amenaza inmediata).
	# Esto evita que bandits merodeando desencadenen siempre la respuesta máxima.
	var body_pos: Vector2 = (body as Node2D).global_position
	var is_attacking: bool = body.has_method("is_attacking") and bool(body.call("is_attacking"))
	if is_attacking:
		_incident_reporter.call("armed_intruder", {"offender": body, "pos": body_pos})
	else:
		_incident_reporter.call("trespass", {"offender": body, "pos": body_pos})


func _on_detection_exited(_body: Node) -> void:
	pass


# ── Helpers ───────────────────────────────────────────────────────────────────

## Devuelve (o crea) el ID de agente para NpcPathService.
func _get_path_id() -> String:
	if _path_id.is_empty():
		_path_id = str(get_instance_id())
	return _path_id


## Mueve el sentinel hacia `goal` a `speed` usando NpcPathService cuando esté listo.
## Fallback a dirección directa si el servicio no está disponible o el path falla.
func _pathfind_toward(goal: Vector2, speed: float, opts: Dictionary = {}) -> void:
	var my_pos := global_position
	var d: Vector2
	if NpcPathService.is_ready():
		var wp := NpcPathService.get_next_waypoint(_get_path_id(), my_pos, goal, opts)
		d = wp - my_pos
		# Si el waypoint es la posición actual el path falló (sin ruta en el nav mesh).
		# Fallback a movimiento directo para que el sentinel no se quede inmóvil.
		if d.length_squared() < 4.0:
			d = goal - my_pos
	else:
		d = goal - my_pos
	var dsq := d.length_squared()
	velocity = (d / sqrt(dsq)) * speed if dsq > 1.0 else Vector2.ZERO


func _restore_collision() -> void:
	_passthrough_t = 0.0
	set_collision_mask_value(1, true)
	set_collision_layer_value(3, true)


func _play_shove_impact_sound() -> void:
	var panel := AudioSystem.get_sound_panel() as SoundPanel
	if panel == null:
		return
	var stream: AudioStream = panel.npc_enemy_hit_sfx
	if stream == null:
		return
	var hit_pos := global_position
	if _order_target != null and is_instance_valid(_order_target) and _order_target is Node2D:
		hit_pos = (_order_target as Node2D).global_position
	AudioSystem.play_2d(stream, hit_pos, null, &"SFX", panel.npc_enemy_hit_volume_db)


## Resuelve la geometría de la taberna al inicio de una orden EJECT.
## Almacena exit_pos e inner_bounds para el resto del ciclo.
func _resolve_eject_context() -> void:
	_tavern_exit_pos    = Vector2.ZERO
	_tavern_inner_bounds = Rect2()
	var worlds := get_tree().get_nodes_in_group("world")
	if worlds.is_empty():
		Debug.log("sentinel", "[%s] _resolve_eject_context: grupo 'world' vacío" % name)
		return
	var w := worlds[0]
	if w.has_method("get_tavern_exit_world_pos"):
		_tavern_exit_pos = w.call("get_tavern_exit_world_pos")
	if w.has_method("get_tavern_inner_bounds_world"):
		_tavern_inner_bounds = w.call("get_tavern_inner_bounds_world")
	Debug.log("sentinel", "[%s] eject_exit=%s  inner_bounds=%s" % [
		name, str(_tavern_exit_pos), str(_tavern_inner_bounds)
	])


## Devuelve true si el target ya salió de la taberna.
## Fin de condición para el ciclo EJECT.
func _player_is_outside_tavern() -> bool:
	if _order_target == null or not is_instance_valid(_order_target):
		return true
	var p := (_order_target as Node2D).global_position
	if _tavern_inner_bounds.size != Vector2.ZERO:
		return not _tavern_inner_bounds.has_point(p)
	# Fallback: considera que salió si está cerca del exit_pos
	if _tavern_exit_pos != Vector2.ZERO:
		return p.distance_to(_tavern_exit_pos) < 64.0
	return false


func _get_effective_order_pos() -> Vector2:
	if _order_target != null and is_instance_valid(_order_target):
		return (_order_target as Node2D).global_position
	return _order_pos


func _is_in_jurisdiction(pos: Vector2) -> bool:
	return pos.distance_to(home_pos) <= jurisdiction_radius


func _target_is_neutralized() -> bool:
	if _order_target == null or not is_instance_valid(_order_target):
		return true
	if _order_target.has_method("is_final_dead") \
			and bool(_order_target.call("is_final_dead")):
		return true
	var target_base := _order_target as CharacterBase
	if target_base != null and target_base.is_downed:
		return true
	return false


# ── Animation ─────────────────────────────────────────────────────────────────

func _update_animation() -> void:
	if not is_instance_valid(sprite):
		return
	# Prioridad: death > downed > hurt > estado de movimiento
	if dying:
		if sprite.animation != &"death":
			sprite.play("death")
		return
	if is_downed:
		# _on_entered_downed() ya lanzó "death"; no sobreescribir con idle.
		return
	if hurt_t > 0.0:
		if sprite.animation != &"hurt":
			sprite.play("hurt")
		return
	# Estados en movimiento: walk cuando se mueve, idle cuando para
	match _state:
		State.GUARD:
			if velocity.length() > 5.0:
				sprite.play("walk")
				sprite.flip_h = velocity.x < 0.0
			else:
				sprite.play("idle")
		State.WARN, State.SHOVE:
			if velocity.length() > 5.0:
				sprite.play("walk")
				sprite.flip_h = velocity.x < 0.0
			else:
				sprite.play("idle")
		State.INTERCEPT, State.RETURN, State.CHASE_SHORT, State.SUBDUE, State.HAUL:
			if velocity.length() > 5.0:
				sprite.play("walk")
				sprite.flip_h = velocity.x < 0.0
			else:
				sprite.play("idle")


# ── Death ─────────────────────────────────────────────────────────────────────

func _on_before_die() -> void:
	velocity       = Vector2.ZERO
	_current_order = OrderType.NONE
	_order_target  = null
	_haul_release()
	_haul_body     = null
	_restore_collision()
	if detection_area != null:
		detection_area.monitoring  = false
		detection_area.monitorable = false


func _on_after_die() -> void:
	if not _path_id.is_empty() and NpcPathService.is_ready():
		NpcPathService.clear_agent(_path_id)
	queue_free()


# ── Public order API ──────────────────────────────────────────────────────────
#
# CÓMO LO LLAMARÁ TavernSanctionDirector (futuro):
#
#   var sentinel := get_available_sentinel()
#   sentinel.execute_directive(directive, offender_node)
#
# o directamente:
#
#   sentinel.issue_order(Sentinel.OrderType.EJECT, player_node)


## Orden directa. Emitida por TavernSanctionDirector, TavernKeeper o debug.
## target: node del actor objetivo (puede ser el player u otro NPC)
## pos:    posición de fallback si target no tiene node válido
func issue_order(order: OrderType, target: CharacterBody2D = null,
		pos: Vector2 = Vector2.ZERO) -> void:
	# Nunca emitir una orden contra otro sentinel — evita que sentinels se saquen
	# entre sí (loop de empujones / cross-ejection).
	if target != null and target.is_in_group("tavern_sentinel"):
		return
	# Si estábamos cargando un cuerpo, soltarlo antes de aceptar la nueva orden.
	# Sin este release, el body queda con collision_layer=0 y process desactivado.
	if _haul_is_carrying:
		_haul_release()
		_haul_body  = null
		_haul_phase = 0
	_current_order = order
	_order_target  = target
	_order_pos     = pos if target == null \
					 else (target as Node2D).global_position
	_shove_count   = 0
	if not _path_id.is_empty() and NpcPathService.is_ready():
		NpcPathService.invalidate_path(_path_id)
	if order == OrderType.EJECT:
		_resolve_eject_context()
		# Desactivar mask(1) para que el sentinel pueda alcanzar al player sin
		# quedar atrapado en su collider. NO desactivar layer(3) — los sentinels
		# deben seguir siendo sólidos entre sí para no solaparse.
		set_collision_mask_value(1, false)
	if order != OrderType.NONE:
		_enter_intercept()


## True cuando el sentinel está en su post (GUARD) y puede aceptar una nueva directiva.
## El director lo usa para preferir sentinels libres sobre los que ya tienen una orden activa.
func is_available() -> bool:
	return _state == State.GUARD


## Registra el callable para reportar incidentes civiles (world.report_tavern_incident).
func set_incident_reporter(reporter: Callable) -> void:
	_incident_reporter = reporter


## Interfaz con el pipeline institutional local.
## Convierte un LocalAuthorityDirective en una orden concreta.
## offender_node: el llamador debe resolver el nodo desde directive.offender_actor_id.
func execute_directive(directive: LocalAuthorityDirective,
		offender_node: CharacterBody2D = null) -> void:
	var R := LocalAuthorityResponse.Response
	match directive.response_type:
		R.WARN:
			issue_order(OrderType.WARNING_INTERCEPT, offender_node,
				(offender_node as Node2D).global_position \
				if offender_node != null else Vector2.ZERO)
		R.DENY_SERVICE, R.EJECT:
			issue_order(OrderType.EJECT, offender_node,
				(offender_node as Node2D).global_position \
				if offender_node != null else Vector2.ZERO)
		R.CALL_BACKUP, R.ARREST_OR_SUBDUE:
			issue_order(OrderType.SUBDUE, offender_node,
				(offender_node as Node2D).global_position \
				if offender_node != null else Vector2.ZERO)
		_:
			# RECORD_ONLY: sin acción física — el sentinel no hace nada
			pass


# ── Factory ───────────────────────────────────────────────────────────────────

## Instancia un sentinel cerca del tavern keeper.
## Llamar desde world.gd (o similar) tras instanciar la taberna.
##
##   var sentinel := Sentinel.spawn_near_tavern(
##       get_tree().current_scene,
##       tavern_keeper.global_position,
##       preload("res://scenes/sentinel.tscn")
##   )
static func spawn_near_tavern(parent: Node, tavern_world_pos: Vector2,
		sentinel_scene: PackedScene) -> Sentinel:
	var s := sentinel_scene.instantiate() as Sentinel
	# 2 tiles a la derecha del keeper (32px/tile × 2 = 64px)
	s.global_position = tavern_world_pos + Vector2(64.0, 0.0)
	parent.add_child(s)
	s.home_pos = s.global_position
	return s


# ── Debug / Smoke test ────────────────────────────────────────────────────────
#
# Cómo probar desde un DevHelper o la consola de debug:
#
#   var sentinel = get_tree().get_first_node_in_group("sentinel") as Sentinel
#   var player   = get_tree().get_first_node_in_group("player") as CharacterBody2D
#
#   sentinel.debug_warn(player)     # advertencia → shove si no obedece
#   sentinel.debug_eject(player)    # warn → shove → chase hasta salir jurisdicción
#   sentinel.debug_subdue(player)   # va directo a KO
#   sentinel.debug_return()         # cancela orden y vuelve al post


func debug_warn(target: CharacterBody2D) -> void:
	Debug.log("sentinel", "[%s] DEBUG warn → %s" % [name, target.name])
	issue_order(OrderType.WARNING_INTERCEPT, target)


func debug_eject(target: CharacterBody2D) -> void:
	Debug.log("sentinel", "[%s] DEBUG eject → %s" % [name, target.name])
	issue_order(OrderType.EJECT, target)


func debug_subdue(target: CharacterBody2D) -> void:
	Debug.log("sentinel", "[%s] DEBUG subdue → %s" % [name, target.name])
	issue_order(OrderType.SUBDUE, target)


func debug_return() -> void:
	Debug.log("sentinel", "[%s] DEBUG returning to post" % name)
	_enter_return()
