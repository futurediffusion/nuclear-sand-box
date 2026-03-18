class_name TavernKeeper
extends "res://scripts/CharacterBase.gd"

const InventoryComponentScript = preload("res://scripts/components/InventoryComponent.gd")
const VendorComponentScript = preload("res://scripts/shop/vendor_component.gd")
const VendorOfferScript = preload("res://scripts/shop/vendor_offer.gd")
const AIComponentScript = preload("res://scripts/components/AIComponent.gd")
const WeaponComponentScript = preload("res://scripts/components/WeaponComponent.gd")
const AIWeaponControllerScript = preload("res://scripts/weapons/AIWeaponController.gd")

@export var slash_scene: PackedScene = preload("res://scenes/slash.tscn")

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
@onready var character_hurtbox: CharacterHurtbox = get_node_or_null("Hurtbox") as CharacterHurtbox
@onready var carry_component: CarryComponent = get_node_or_null("CarryComponent") as CarryComponent
@export var shop_copper_stock: int = 30
@export var shop_stone_stock: int = 50

# =============================================================================
# ESTADO INTERNO
# =============================================================================
enum State { AT_COUNTER, WANDER, IDLE_WANDER, COMBAT }

var _state: State = State.AT_COUNTER
var _target_pos: Vector2 = Vector2.ZERO
var _wander_timer: float = 0.0
var _wander_wait: float  = 0.0
var _player_nearby: bool = false
var _player_ref: Node    = null
var _shop_inv: InventoryComponent = null
var _vendor: VendorComponent = null
var _keeper_menu_ui: KeeperMenuUi = null
var _movement_locked_by_shop: bool = false
var _state_before_shop: State = State.AT_COUNTER

# Referencia al tilemap para convertir tiles → world (se asigna desde world.gd)
var _tilemap: TileMap = null

# --- Salud ---
var entity_uid: String = ""

# --- Combat (duck-typing interface para AIComponent) ---
var max_speed: float = 200.0
var acceleration: float = 800.0
var friction: float = 1200.0
var detection_range: float = 400.0
var attack_range: float = 60.0
const ACTIVE_RADIUS_PX: float = 900.0
const WAKE_HYSTERESIS_PX: float = 200.0
const SLEEP_CHECK_INTERVAL: float = 0.5

var _in_combat: bool = false
var _weapon_pivot: Node2D = null
var _ai_component_node: AIComponent = null
var _weapon_component_node: WeaponComponent = null
var _ai_weapon_controller_node: AIWeaponController = null

var target_attack_angle: float = 0.0
var use_left_offset: bool = false
var angle_offset_left: float = -150.0
var angle_offset_right: float = 150.0

# =============================================================================
func _ready() -> void:
	super._ready()
	_setup_health_component()
	_connect_hurtbox()
	add_to_group("npc")
	add_to_group("tavern_keeper")

	# ✅ Prompt apagado por defecto
	interact_icon.visible = false

	_go_to_counter()
	_cache_keeper_menu_ui()
	_connect_keeper_menu_signals()

	_reset_wander_timer()
	sprite.play("idle")

	# ✅ Conectar área de detección
	if detection_area:
		if not detection_area.body_entered.is_connected(_on_body_entered):
			detection_area.body_entered.connect(_on_body_entered)
		if not detection_area.body_exited.is_connected(_on_body_exited):
			detection_area.body_exited.connect(_on_body_exited)

	# inventario del vendedor (demo)
	if _shop_inv == null:
		_shop_inv = InventoryComponentScript.new()
		_shop_inv.name = "InventoryComponent"
		add_child(_shop_inv)

	if _vendor == null:
		_vendor = VendorComponentScript.new()
		_vendor.name = "VendorComponent"
		add_child(_vendor)
		_vendor.offers = _build_default_offers()


func _connect_hurtbox() -> void:
	if character_hurtbox == null:
		return
	if not character_hurtbox.damaged.is_connected(_on_character_hurtbox_damaged):
		character_hurtbox.damaged.connect(_on_character_hurtbox_damaged)

func _on_character_hurtbox_damaged(dmg: int, from_pos: Vector2) -> void:
	take_damage(dmg, from_pos)
	if not _in_combat:
		_enter_combat_mode()

# =============================================================================
# FÍSICA
# =============================================================================
func _physics_process(delta: float) -> void:
	if hurt_t > 0.0:
		hurt_t -= delta
	if dying or hurt_t > 0.0:
		move_and_slide()
		return
	if _movement_locked_by_shop:
		velocity = Vector2.ZERO
	else:
		_update_state(delta)
	_update_animation()
	if _in_combat:
		_update_weapon_pivot(delta)
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

		State.COMBAT:
			if _ai_component_node != null:
				_ai_component_node.physics_tick(delta)
				if _ai_weapon_controller_node != null:
					_ai_weapon_controller_node.physics_tick()
				if _weapon_component_node != null:
					_weapon_component_node.tick(delta)
			else:
				velocity = velocity.move_toward(Vector2.ZERO, friction * delta)


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
		if _keeper_menu_ui != null and _keeper_menu_ui.is_owner(self):
			_keeper_menu_ui.close_shop()

# =============================================================================
# PROMPT DE INTERACCIÓN
# =============================================================================
func _update_interact_prompt() -> void:
	if _in_combat:
		interact_icon.visible = false
		return
	if UiManager.is_interact_prompt_suppressed():
		interact_icon.visible = false
		return
	# ✅ Mostrar icono SOLO si el player está dentro del área
	interact_icon.visible = _player_nearby and (not dying)

	# Girar sprite hacia el player cuando está cerca
	if _player_nearby and _player_ref != null:
		var dx: float = (_player_ref as Node2D).global_position.x - global_position.x
		sprite.flip_h = dx < 0.0

	# Tecla E → placeholder (solo imprime)
	if _player_nearby and (not UiManager.is_interact_prompt_suppressed()) and Input.is_action_just_pressed("interact"):
		if _keeper_menu_ui != null and _keeper_menu_ui.is_owner(self):
			_keeper_menu_ui.close_shop()
		else:
			_open_shop()

func _open_shop() -> void:
	if _keeper_menu_ui == null:
		_cache_keeper_menu_ui()
		_connect_keeper_menu_signals()

	if _keeper_menu_ui == null:
		push_warning("[SHOP] No encuentro KeeperMenuUi en /root/Main/UI/KeeperMenuUi ni en UI/KeeperMenuUi")
		return

	if UiManager.is_interact_blocked():
		return
	if UiManager.is_interact_prompt_suppressed():
		return

	if _keeper_menu_ui.is_shop_open() and not _keeper_menu_ui.is_owner(self):
		return

	if _player_ref == null:
		return

	# inventario del player (Player crea InventoryComponent en runtime)
	var player_inv: InventoryComponent = _player_ref.get_node_or_null("InventoryComponent") as InventoryComponent
	if player_inv == null and _player_ref.has_method("get_inventory"):
		player_inv = _player_ref.call("get_inventory") as InventoryComponent

	if player_inv == null:
		push_warning("[SHOP] No encuentro InventoryComponent en el Player")
		return

	if _vendor == null:
		push_warning("[SHOP] VendorComponent no inicializado")
		return

	_keeper_menu_ui.set_player_inventory(player_inv)
	_keeper_menu_ui.set_keeper_inventory(_shop_inv)
	_keeper_menu_ui.set_vendor(_vendor)
	_keeper_menu_ui.open_shop(self)



func _cache_keeper_menu_ui() -> void:
	if _keeper_menu_ui != null:
		return
	var keeper_menu_ui := get_node_or_null("/root/Main/UI/KeeperMenuUi")
	if keeper_menu_ui == null:
		keeper_menu_ui = get_tree().current_scene.get_node_or_null("UI/KeeperMenuUi")
	_keeper_menu_ui = keeper_menu_ui as KeeperMenuUi


func _connect_keeper_menu_signals() -> void:
	if _keeper_menu_ui == null:
		return
	if not _keeper_menu_ui.shop_opened.is_connected(_on_shop_opened):
		_keeper_menu_ui.shop_opened.connect(_on_shop_opened)
	if not _keeper_menu_ui.shop_closed.is_connected(_on_shop_closed):
		_keeper_menu_ui.shop_closed.connect(_on_shop_closed)


func _on_shop_opened(owner: Node) -> void:
	if owner != self:
		return
	if _movement_locked_by_shop:
		return
	_movement_locked_by_shop = true
	_state_before_shop = _state
	# Congelar el objetivo una sola vez al abrir la tienda para no pisar
	# sistemas externos que puedan usar _target_pos fuera de navegación.
	_target_pos = global_position
	velocity = Vector2.ZERO
	_state = State.AT_COUNTER


func _on_shop_closed(owner: Node) -> void:
	if owner != self:
		return
	if not _movement_locked_by_shop:
		return
	_movement_locked_by_shop = false
	_state = _state_before_shop
	_reset_wander_timer()


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
	if from_pos != Vector2.ZERO:
		sprite.flip_h = from_pos.x > global_position.x
	super.take_damage(amount, Vector2.INF if from_pos == Vector2.ZERO else from_pos)

func play_hurt() -> void:
	hurt_t = hurt_time
	velocity = Vector2.ZERO
	interact_icon.visible = false
	sprite.play("hurt")
	await sprite.animation_finished
	hurt_t = 0.0

## Intentional carry release: deposits ItemDrops into a nearby chest if present,
## otherwise releases items to the ground. Call from AI behavior.
func release_carry() -> void:
	if carry_component != null:
		carry_component.release_with_chest_check()

func _on_before_die() -> void:
	if carry_component != null:
		carry_component.force_drop_all()
	if _ai_component_node != null:
		_ai_component_node.set_dead()
	if _keeper_menu_ui != null and _keeper_menu_ui.is_owner(self):
		_keeper_menu_ui.close_shop()
	velocity = Vector2.ZERO
	interact_icon.visible = false
	set_collision_layer_value(1, false)
	set_collision_mask_value(1, false)
	if detection_area:
		detection_area.monitoring  = false
		detection_area.monitorable = false
		if detection_area.body_entered.is_connected(_on_body_entered):
			detection_area.body_entered.disconnect(_on_body_entered)
		if detection_area.body_exited.is_connected(_on_body_exited):
			detection_area.body_exited.disconnect(_on_body_exited)


func _exit_tree() -> void:
	if _keeper_menu_ui != null:
		if _keeper_menu_ui.shop_opened.is_connected(_on_shop_opened):
			_keeper_menu_ui.shop_opened.disconnect(_on_shop_opened)
		if _keeper_menu_ui.shop_closed.is_connected(_on_shop_closed):
			_keeper_menu_ui.shop_closed.disconnect(_on_shop_closed)
	if detection_area:
		if detection_area.body_entered.is_connected(_on_body_entered):
			detection_area.body_entered.disconnect(_on_body_entered)
		if detection_area.body_exited.is_connected(_on_body_exited):
			detection_area.body_exited.disconnect(_on_body_exited)

func _on_after_die() -> void:
	queue_free()


# =============================================================================
# COMBAT — modo hostil activado al recibir daño
# =============================================================================
func _enter_combat_mode() -> void:
	if _in_combat:
		return
	_in_combat = true
	_state = State.COMBAT

	if _keeper_menu_ui != null and _keeper_menu_ui.is_owner(self):
		_keeper_menu_ui.close_shop()
	_movement_locked_by_shop = false

	# Construir jerarquía WeaponPivot
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

	var arrow_muzzle_node := Marker2D.new()
	arrow_muzzle_node.name = "ArrowMuzzle"
	arrow_muzzle_node.position = Vector2(24.0, 0.0)
	_weapon_pivot.add_child(arrow_muzzle_node)

	# Inventario de combate (separado del inventario de tienda)
	var combat_inv := InventoryComponentScript.new()
	combat_inv.name = "CombatInventoryComponent"
	add_child(combat_inv)
	combat_inv.add_item("ironpipe", 1)
	combat_inv.add_item("bow", 1)

	# WeaponComponent
	_weapon_component_node = WeaponComponentScript.new()
	_weapon_component_node.name = "WeaponComponent"
	add_child(_weapon_component_node)
	_weapon_component_node.setup_from_inventory(combat_inv)
	if not _weapon_component_node.weapon_equipped.is_connected(_on_weapon_equipped_apply_visuals):
		_weapon_component_node.weapon_equipped.connect(_on_weapon_equipped_apply_visuals)

	var ctrl := _ensure_ai_weapon_controller()
	_weapon_component_node.apply_visuals(self)
	_weapon_component_node.equip_runtime_weapon(self, ctrl)

	# AIComponent
	_ai_component_node = AIComponentScript.new()
	_ai_component_node.name = "AIComponent"
	add_child(_ai_component_node)
	_ai_component_node.setup(self)


func _ensure_ai_weapon_controller() -> AIWeaponController:
	if _ai_weapon_controller_node != null:
		return _ai_weapon_controller_node
	_ai_weapon_controller_node = AIWeaponControllerScript.new()
	_ai_weapon_controller_node.name = "AIWeaponController"
	add_child(_ai_weapon_controller_node)
	return _ai_weapon_controller_node


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


func spawn_slash(angle: float) -> void:
	if slash_scene == null or _weapon_pivot == null:
		return
	var parent := get_tree().current_scene
	if parent == null:
		return
	var slash_spawn_node := _weapon_pivot.get_node_or_null("SlashSpawn")
	if slash_spawn_node == null:
		return
	var s = slash_scene.instantiate()
	s.setup(&"enemy", self)
	s.position = parent.to_local((slash_spawn_node as Node2D).global_position)
	s.rotation = angle
	parent.add_child(s)


func _on_weapon_equipped_apply_visuals(_wid: String) -> void:
	if _weapon_component_node == null:
		return
	var ctrl := _ensure_ai_weapon_controller()
	_weapon_component_node.apply_visuals(self)
	_weapon_component_node.equip_runtime_weapon(self, ctrl)


func _update_weapon_pivot(delta: float) -> void:
	if _weapon_pivot == null or _ai_component_node == null:
		return
	var player_node := _ai_component_node.player
	if player_node == null or not is_instance_valid(player_node):
		return
	var player_pos: Vector2 = (player_node as Node2D).global_position
	var angle_to_player := global_position.angle_to_point(player_pos)
	var weapon_sprite_node := _weapon_pivot.get_node_or_null("WeaponSprite") as Sprite2D

	if _ai_component_node.current_state == AIComponent.AIState.ATTACK:
		_weapon_pivot.rotation = lerp_angle(_weapon_pivot.rotation, target_attack_angle, 1.0 - exp(-50.0 * delta))
	else:
		_weapon_pivot.rotation = lerp_angle(_weapon_pivot.rotation, angle_to_player, 1.0 - exp(-25.0 * delta))

	var angle := wrapf(_weapon_pivot.rotation, -PI, PI)
	if weapon_sprite_node != null:
		weapon_sprite_node.flip_v = abs(angle) > PI / 2.0
	sprite.flip_h = abs(rad_to_deg(angle_to_player)) > 90.0


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


func get_save_state() -> Dictionary:
	return {"spawned": true}

func apply_save_state(_state: Dictionary) -> void:
	# Future: status/inventory/faction hooks (alive/ko/dead, etc.)
	pass


func _build_default_offers() -> Array[VendorOffer]:
	var bandage_offer := VendorOfferScript.new()
	bandage_offer.item_id = "bandage"
	bandage_offer.mode = VendorOfferScript.OfferMode.INFINITE

	var copper_offer := VendorOfferScript.new()
	copper_offer.item_id = "copper"
	copper_offer.mode = VendorOfferScript.OfferMode.STOCKED
	copper_offer.base_stock = shop_copper_stock

	var bow_offer := VendorOfferScript.new()
	bow_offer.item_id = "bow"
	bow_offer.mode = VendorOfferScript.OfferMode.INFINITE

	var ironpipe_offer := VendorOfferScript.new()
	ironpipe_offer.item_id = "ironpipe"
	ironpipe_offer.mode = VendorOfferScript.OfferMode.INFINITE

	var arrow_offer := VendorOfferScript.new()
	arrow_offer.item_id = "arrow"
	arrow_offer.mode = VendorOfferScript.OfferMode.INFINITE

	var stone_offer := VendorOfferScript.new()
	stone_offer.item_id = "stone"
	stone_offer.mode = VendorOfferScript.OfferMode.STOCKED
	stone_offer.base_stock = shop_stone_stock

	var book_offer := VendorOfferScript.new()
	book_offer.item_id = "book"
	book_offer.mode = VendorOfferScript.OfferMode.INFINITE

	var workbench_offer := VendorOfferScript.new()
	workbench_offer.item_id = "workbench"
	workbench_offer.mode = VendorOfferScript.OfferMode.INFINITE

	return [bandage_offer, copper_offer, stone_offer, bow_offer, arrow_offer, ironpipe_offer, book_offer, workbench_offer]
