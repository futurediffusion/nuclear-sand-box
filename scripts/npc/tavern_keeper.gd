class_name TavernKeeper
extends CharacterBody2D

# =============================================================================
# TAVERN KEEPER NPC
# Deambula dentro de la taberna, detecta al player y muestra prompt de interacción.
# =============================================================================

# --- Bounds de la taberna (se asignan desde world.gd al instanciar) ---
@export var tavern_inner_min: Vector2i = Vector2i.ZERO   # tile min interior
@export var tavern_inner_max: Vector2i = Vector2i.ZERO   # tile max interior
@export var counter_tile: Vector2i     = Vector2i.ZERO   # tile detrás del mostrador

# --- Movimiento ---
@export var move_speed: float     = 40.0
@export var wander_interval_min: float = 3.0
@export var wander_interval_max: float = 7.0
@export var arrival_threshold: float   = 4.0   # px para considerar "llegué"

# --- Detección de player ---
@export var interact_range_px: float = 64.0    # ~2 tiles (tile = 32px)

# --- Refs ---
@onready var sprite: AnimatedSprite2D        = $AnimatedSprite2D
@onready var interact_icon: Sprite2D = $InteractIcon
@onready var detection_area: Area2D          = $DetectionArea

# =============================================================================
# ESTADO INTERNO
# =============================================================================
enum State { AT_COUNTER, WANDER, IDLE_WANDER }

var _state: State = State.AT_COUNTER
var _target_pos: Vector2 = Vector2.ZERO
var _wander_timer: float = 0.0
var _wander_wait: float  = 0.0
var _player_nearby: bool = false
var _player_ref: Node    = null

# Referencia al tilemap para convertir tiles → world (se asigna desde world.gd)
var _tilemap: TileMap = null

# --- Salud ---
@export var max_health: int = 5
var _health: int = max_health
var _is_dead: bool = false
var _is_hurt: bool = false

# =============================================================================
func _ready() -> void:
	_health = max_health
	add_to_group("npc")
	add_to_group("tavern_keeper")

	# ✅ Prompt apagado por defecto
	interact_icon.visible = false

	_go_to_counter()
	_reset_wander_timer()
	sprite.play("idle")

	# ✅ Conectar área de detección
	if detection_area:
		detection_area.body_entered.connect(_on_body_entered)
		detection_area.body_exited.connect(_on_body_exited)

# =============================================================================
# FÍSICA
# =============================================================================
func _physics_process(delta: float) -> void:
	if _is_dead or _is_hurt:
		move_and_slide()
		return
	_update_state(delta)
	_update_animation()
	_update_interact_prompt()
	move_and_slide()


func _update_state(delta: float) -> void:
	match _state:
		State.AT_COUNTER:
			velocity = velocity.move_toward(Vector2.ZERO, 400.0 * delta)
			_wander_timer += delta
			if _wander_timer >= _wander_wait:
				_start_wander()

		State.WANDER:
			var dist := global_position.distance_to(_target_pos)
			if dist < arrival_threshold:
				velocity = Vector2.ZERO
				_state = State.IDLE_WANDER
				_reset_wander_timer()
			else:
				var dir := (_target_pos - global_position).normalized()
				velocity = dir * move_speed

		State.IDLE_WANDER:
			velocity = velocity.move_toward(Vector2.ZERO, 400.0 * delta)
			_wander_timer += delta
			if _wander_timer >= _wander_wait:
				# 50% de volver al counter, 50% de ir a otro tile random
				if randf() < 0.5:
					_go_to_counter()
				else:
					_start_wander()


# =============================================================================
# WANDER
# =============================================================================
func _start_wander() -> void:
	if tavern_inner_min == Vector2i.ZERO and tavern_inner_max == Vector2i.ZERO:
		# Sin bounds asignados: quedarse quieto
		_state = State.AT_COUNTER
		_reset_wander_timer()
		return

	# Elegir tile random dentro de los bounds interiores de la taberna
	var tx := randi_range(tavern_inner_min.x, tavern_inner_max.x)
	var ty := randi_range(tavern_inner_min.y, tavern_inner_max.y)
	var target_tile := Vector2i(tx, ty)

	if _tilemap != null:
		_target_pos = _tilemap.to_global(_tilemap.map_to_local(target_tile))
	else:
		# Fallback: offset relativo al counter en world units
		var tile_size := 32.0
		_target_pos = global_position + Vector2(
			(tx - counter_tile.x) * tile_size,
			(ty - counter_tile.y) * tile_size
		)

	_state = State.WANDER


func _go_to_counter() -> void:
	if _tilemap != null and counter_tile != Vector2i.ZERO:
		_target_pos = _tilemap.to_global(_tilemap.map_to_local(counter_tile))
	else:
		_target_pos = global_position
	_state = State.AT_COUNTER
	_reset_wander_timer()


func _reset_wander_timer() -> void:
	_wander_timer = 0.0
	_wander_wait  = randf_range(wander_interval_min, wander_interval_max)


# =============================================================================
# DETECCIÓN DE PLAYER (Area2D)
# =============================================================================
func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_player_nearby = true
		_player_ref = body

func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		_player_nearby = false
		if _player_ref == body:
			_player_ref = null

# =============================================================================
# PROMPT DE INTERACCIÓN
# =============================================================================
func _update_interact_prompt() -> void:
	# ✅ Mostrar icono SOLO si el player está dentro del área
	interact_icon.visible = _player_nearby and (not _is_dead)

	# Girar sprite hacia el player cuando está cerca
	if _player_nearby and _player_ref != null:
		var dx: float = (_player_ref as Node2D).global_position.x - global_position.x
		sprite.flip_h = dx < 0.0

	# Tecla E → placeholder (solo imprime)
	if _player_nearby and Input.is_action_just_pressed("interact"):
		_open_shop()

func _open_shop() -> void:
	# TODO: abrir UI de compra/venta
	print("[SHOP] Keeper: abriendo tienda (pendiente UI)")


# =============================================================================
# ANIMACIÓN
# =============================================================================
func _update_animation() -> void:
	if velocity.length() > 5.0:
		sprite.play("walk")
		# Flip según dirección de movimiento
		sprite.flip_h = velocity.x < 0.0
	else:
		sprite.play("idle")


# =============================================================================
# DAÑO Y MUERTE
# =============================================================================
func take_damage(amount: int, from_pos: Vector2 = Vector2.ZERO) -> void:
	if _is_dead or _is_hurt:
		return

	_health -= amount

	# (Opcional) mirar hacia donde vino el golpe
	if from_pos != Vector2.ZERO:
		sprite.flip_h = from_pos.x > global_position.x

	if _health <= 0:
		die()
		return

	# Reproducir hurt y volver a idle al terminar
	_is_hurt = true
	velocity = Vector2.ZERO
	interact_icon.visible = false

	sprite.play("hurt")
	await sprite.animation_finished

	_is_hurt = false

func die() -> void:
	if _is_dead:
		return
	_is_dead = true

	velocity = Vector2.ZERO
	interact_icon.visible = false

	# Deshabilitar colisiones para que no bloquee al player
	set_collision_layer_value(1, false)
	set_collision_mask_value(1, false)
	if detection_area:
		detection_area.monitoring  = false
		detection_area.monitorable = false

	sprite.play("death")
	await sprite.animation_finished
	queue_free()


# =============================================================================
# API PÚBLICA — llamada desde world.gd al instanciar
# =============================================================================
func setup(tilemap: TileMap, inner_min: Vector2i, inner_max: Vector2i, the_counter_tile: Vector2i) -> void:
	_tilemap        = tilemap
	tavern_inner_min = inner_min
	tavern_inner_max = inner_max
	counter_tile     = the_counter_tile
	# Reposicionarse en el counter con los datos correctos
	_go_to_counter()
