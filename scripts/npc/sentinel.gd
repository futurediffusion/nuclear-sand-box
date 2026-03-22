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
# POR QUÉ NO USA AIComponent PARA MOVIMIENTO (todavía):
#   AIComponent está diseñado para enemy combat con LOD, duel system, bow/melee
#   style switching, etc. Para el sentinel es overkill ahora. Se construye solo
#   para SUBDUE (combat) como hace TavernKeeper, no para navegación general.
#   EXTENSIÓN FUTURA: pasar movimiento a AIComponent si la riqueza de combate
#   del sentinel justifica la complejidad añadida.
#
# ESTADOS:
#   GUARD       — en el post, mínimo movimiento
#   INTERCEPT   — moviéndose al target de la orden
#   WARN        — advertencia verbal/física cerca del target
#   SHOVE       — empujón sin daño (CombatPhysicsHelper)
#   CHASE_SHORT — persecución dentro de jurisdicción
#   SUBDUE      — combate para dejar KO (usa WeaponComponent + AIWeaponController)
#   RETURN      — volviendo al home_pos
#
# QUÉ NO RESUELVE TODAVÍA:
#   - Animación de advertencia visual / speech bubble
#   - Cooldowns sociales persistentes por actor
#   - Coordinación entre múltiples sentinels
#   - Pathfinding sofisticado (usa movimiento directo como TavernKeeper)
#   - Integración completa con TavernSanctionDirector

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

@export_group("References")
@export var slash_scene: PackedScene   ## asignar en Inspector — misma slash.tscn del enemy


# ── Nodes ─────────────────────────────────────────────────────────────────────

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var detection_area: Area2D   = $DetectionArea


# ── Identity ──────────────────────────────────────────────────────────────────

## Posición del post de guardia. Se asigna en _ready() o via spawn_near_tavern().
var home_pos: Vector2 = Vector2.ZERO


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
		# Solo restaurar al expirar si NO estamos en EJECT (EJECT lo gestiona manualmente).
		if _passthrough_t <= 0.0 and _current_order != OrderType.EJECT:
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
	velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
	_tick_haul_scan(delta)


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

	if dist < warn_approach_dist:
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
	else:
		if not _is_in_jurisdiction(target_pos):
			_enter_return()
			return

	# Acercarse al player. Para EJECT la dirección del empujón viene de shove_directional
	# (hacia el exit), así que no hace falta posicionarse en un lado específico.
	if global_position.distance_to(target_pos) <= shove_trigger_dist:
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
				if target_base != null and not target_base.dying:
					var player_to_exit := (_tavern_exit_pos - (_order_target as Node2D).global_position).normalized()
					target_base.apply_knockback(player_to_exit * grab_drag_force * delta)
		return   # seguir en SHOVE hasta que expire grab_duration

	# ── Fin del grab / shove normal ───────────────────────────────────────────
	velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
	var wait_t := grab_duration if _current_order == OrderType.EJECT else 0.4
	if _state_timer >= wait_t:
		_shove_count += 1
		if _current_order == OrderType.EJECT:
			if _player_is_outside_tavern():
				_enter_return()
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
		velocity = velocity.move_toward(Vector2.ZERO, friction * _state_timer)


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
	# Cancelar si el cuerpo desapareció o se recuperó
	if _haul_body == null or not is_instance_valid(_haul_body) or not _haul_body.is_downed:
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
	if body != null:
		_enter_haul(body)


## Busca un cuerpo KO dentro de la taberna que sea transportable.
## Excluye: tavern_keeper, otros sentinels, cuerpos ya siendo cargados.
func _find_downed_body_in_tavern() -> CharacterBase:
	var search_bounds := _tavern_inner_bounds.grow(32.0)
	for group in ["npc", "player", "enemy"]:
		for node in get_tree().get_nodes_in_group(group):
			var cb := node as CharacterBase
			if cb == null or not cb.is_downed:
				continue
			if cb.is_in_group("tavern_keeper") or cb.is_in_group("sentinel"):
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
	# Esto soluciona dos bugs:
	#   1. El "arrastre" al acercarse de nuevo (solapamiento de CharacterBody2D).
	#   2. El propio cuerpo del sentinel bloqueando el empujón en EJECT.
	_passthrough_t = shove_cooldown + 0.4   # cubre la espera de SHOVE (0.4s) + el re-approach
	set_collision_mask_value(1, false)       # no detectar al player como obstáculo
	set_collision_layer_value(3, false)      # salir de la capa EnemyNCP: el player pasa a través

	# Aplicar empujón en la entrada del estado.
	# EJECT: empujón direccional hacia la salida (puerta de la taberna).
	# Otros: empujón radial alejándose del sentinel.
	if _order_target != null and is_instance_valid(_order_target):
		var target_base := _order_target as CharacterBase
		if target_base != null:
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
	# El sentinel no contra-agrede automáticamente al recibir daño.
	# Mantiene su orden activa (institucional, no instintiva).
	# TODO: si está en GUARD y la amenaza es inminente, considerar auto-defensa limitada.


# ── Detection area (reserved for future use) ──────────────────────────────────

func _on_detection_entered(_body: Node) -> void:
	pass   # Reservado: detección de ingreso sin orden activa (p.ej. zona restringida)


func _on_detection_exited(_body: Node) -> void:
	pass   # Reservado


# ── Helpers ───────────────────────────────────────────────────────────────────

## Devuelve (o crea) el ID de agente para NpcPathService.
func _get_path_id() -> String:
	if _path_id.is_empty():
		_path_id = str(get_instance_id())
	return _path_id


## Mueve el sentinel hacia `goal` a `speed` usando NpcPathService cuando esté listo.
## Fallback a dirección directa si el servicio no está disponible.
func _pathfind_toward(goal: Vector2, speed: float, opts: Dictionary = {}) -> void:
	var my_pos := global_position
	var d: Vector2
	if NpcPathService.is_ready():
		var wp := NpcPathService.get_next_waypoint(_get_path_id(), my_pos, goal, opts)
		d = wp - my_pos
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
	# Prioridad: death > hurt > estado de movimiento
	if dying:
		if sprite.animation != &"death":
			sprite.play("death")
		return
	if hurt_t > 0.0:
		if sprite.animation != &"hurt":
			sprite.play("hurt")
		return
	# Estados en movimiento: walk cuando se mueve, idle cuando para
	match _state:
		State.GUARD:
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
	_current_order = order
	_order_target  = target
	_order_pos     = pos if target == null \
	                 else (target as Node2D).global_position
	_shove_count   = 0
	if not _path_id.is_empty() and NpcPathService.is_ready():
		NpcPathService.invalidate_path(_path_id)
	if order == OrderType.EJECT:
		_resolve_eject_context()
		# El sentinel fantasmea durante toda la orden EJECT para poder alcanzar
		# al player desde cualquier ángulo (esquinas, pared norte, etc.).
		set_collision_mask_value(1, false)
		set_collision_layer_value(3, false)
	if order != OrderType.NONE:
		_enter_intercept()


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
