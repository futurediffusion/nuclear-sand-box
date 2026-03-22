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
@export var shove_force: float        = 380.0   ## knockback sin daño
@export var shove_cooldown: float     = 2.2     ## mínimo s entre shoves
@export var max_shoves_before_subdue: int = 3   ## escalada automática
@export var warn_duration: float      = 2.5     ## s en WARN antes de shove
@export var warn_approach_dist: float = 68.0    ## px: distancia para iniciar warn

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

# Timers
var _shove_cooldown_t: float  = 0.0
var _melee_attack_timer: float = 0.0

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
	_enter_guard()

	if detection_area != null:
		if not detection_area.body_entered.is_connected(_on_detection_entered):
			detection_area.body_entered.connect(_on_detection_entered)
		if not detection_area.body_exited.is_connected(_on_detection_exited):
			detection_area.body_exited.connect(_on_detection_exited)


func _physics_process(delta: float) -> void:
	if hurt_t > 0.0:
		hurt_t -= delta
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

	_tick_state(delta)
	_apply_knockback_step(delta)
	_update_animation()

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


func _tick_guard(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, friction * delta)


func _tick_intercept(delta: float) -> void:
	var target_pos := _get_effective_order_pos()
	var dist := global_position.distance_to(target_pos)

	# Jurisdicción: si el target ya salió, no perseguir
	if _order_target != null and is_instance_valid(_order_target):
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

	var dir := (target_pos - global_position).normalized()
	velocity = dir * max_speed


func _tick_warn(delta: float) -> void:
	var target_pos := _get_effective_order_pos()

	# Jurisdicción
	if _order_target != null and is_instance_valid(_order_target):
		if not _is_in_jurisdiction((_order_target as Node2D).global_position):
			_enter_return()
			return

	# Mantenerse cerca — si el target retrocede, seguirlo despacio
	var dist := global_position.distance_to(target_pos)
	if dist > warn_approach_dist * 1.5:
		var dir := (target_pos - global_position).normalized()
		velocity = dir * (max_speed * 0.55)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)

	# TODO: emitir speech bubble "Detente!" cuando el sistema de bubbles esté disponible
	# Algo como: SpeechBubbleSystem.show(self, "¡Detente!")

	if _state_timer >= warn_duration:
		_enter_shove()


func _tick_shove(delta: float) -> void:
	# El shove se aplica en _enter_shove(). Este estado solo espera brevemente.
	velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
	if _state_timer >= 0.4:
		_enter_chase_short()


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
		var dir := (target_pos - global_position).normalized()
		velocity = dir * chase_speed
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction * _state_timer)  # _state_timer != delta but close enough here


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

	# Target neutralizado
	if _target_is_neutralized():
		_enter_return()
		return

	# Moverse hacia el target
	if dist > attack_range:
		var dir := (target_pos - global_position).normalized()
		velocity = dir * chase_speed
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
	var dir := (home_pos - global_position).normalized()
	velocity = dir * max_speed


# ── State transitions ─────────────────────────────────────────────────────────

func _enter_guard() -> void:
	_state        = State.GUARD
	_state_timer  = 0.0
	_current_order = OrderType.NONE
	_order_target  = null
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

	# Aplicar empujón sin daño en la entrada del estado
	if _order_target != null and is_instance_valid(_order_target):
		var target_base := _order_target as CharacterBase
		if target_base != null:
			CombatPhysicsHelper.shove_no_damage(global_position, target_base, shove_force)


func _enter_chase_short() -> void:
	_state       = State.CHASE_SHORT
	_state_timer = 0.0
	_shove_count += 1


func _enter_subdue() -> void:
	_state       = State.SUBDUE
	_state_timer = 0.0
	_build_combat_stack_if_needed()


func _enter_return() -> void:
	_state       = State.RETURN
	_state_timer = 0.0
	velocity     = Vector2.ZERO


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

	if _state == State.SUBDUE:
		_weapon_pivot.rotation = lerp_angle(_weapon_pivot.rotation, target_attack_angle,
			1.0 - exp(-50.0 * delta))
	else:
		_weapon_pivot.rotation = lerp_angle(_weapon_pivot.rotation, angle_to_target,
			1.0 - exp(-25.0 * delta))

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
	match _state:
		State.GUARD, State.WARN:
			sprite.play("idle")
		State.INTERCEPT, State.RETURN, State.CHASE_SHORT:
			if velocity.length() > 5.0:
				sprite.play("walk")
				sprite.flip_h = velocity.x < 0.0
			else:
				sprite.play("idle")
		State.SHOVE, State.SUBDUE:
			if sprite.sprite_frames != null \
					and sprite.sprite_frames.has_animation("attack"):
				sprite.play("attack")
			else:
				sprite.play("idle")   # placeholder hasta tener animación


# ── Death ─────────────────────────────────────────────────────────────────────

func _on_before_die() -> void:
	velocity       = Vector2.ZERO
	_current_order = OrderType.NONE
	_order_target  = null
	if detection_area != null:
		detection_area.monitoring  = false
		detection_area.monitorable = false


func _on_after_die() -> void:
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
