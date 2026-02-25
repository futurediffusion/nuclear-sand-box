extends Area2D
class_name ItemDrop

@export var item_data: ItemData
@export var item_id: String = "copper"
@export var amount: int = 1
@export var icon: Texture2D

@export var pickup_sfx: AudioStream

# Pop inicial
@export var pop_height: float = 18.0
@export var pop_time: float = 0.18

# Flotación + “semi 3D”
@export var float_amp: float = 2.0
@export var float_speed: float = 4.0
@export var wobble_deg: float = 6.0
@export var wobble_speed: float = 3.0

# Iman
@export var magnet_range: float = 80.0
@export var magnet_speed: float = 520.0
#item drop
@export var throw_damping: float = 10.0   # freno (más alto = se para más rápido)
@export var throw_gravity: float = 900.0  # gravedad fake para el arco (px/s^2)
@export var ground_y_offset: float = 0.0  # por si quieres ajustar donde “queda” el sprite

@onready var spr: Sprite2D = $Sprite2D
@onready var sfx: AudioStreamPlayer2D = $Sfx
@onready var magnet_delay: Timer = $MagnetDelay

var _t: float = 0.0
var _pop_t: float = 0.0
var _base_y: float = 0.0
var _popping: bool = true
var _player: Node2D = null
var _magnet_on: bool = false
var _vel: Vector2 = Vector2.ZERO
var _throwing: bool = false
var _ground_y: float = 0.0

func _ready() -> void:
	_resolve_item_data()

	if icon != null:
		spr.texture = icon

	_base_y = spr.position.y
	_pop_t = pop_time
	_popping = true

	# un pelín random para que no floten igual
	_t = randf() * 10.0

	magnet_delay.timeout.connect(func(): _magnet_on = true)
	magnet_delay.start()

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _resolve_item_data() -> void:
	var item_db := get_node_or_null("/root/ItemDB")

	if item_data != null:
		item_id = item_data.id
	elif item_id != "" and item_db != null and item_db.has_method("get_item"):
		item_data = item_db.get_item(item_id)

	if item_data == null and item_id == "":
		push_warning("[ItemDrop] Define item_data o item_id para este drop")

	if icon == null and item_data != null:
		icon = item_data.icon

	if pickup_sfx == null and item_data != null and item_data.pickup_sfx != null:
		pickup_sfx = item_data.pickup_sfx

	if item_data != null:
		print("[ItemDrop] resolved item_data id=", item_data.id)
	else:
		print("[ItemDrop] using legacy item_id=", item_id)

func _process(delta: float) -> void:
	_t += delta

	# =========================
	# 1) THROW: sale disparado y cae
	# =========================
	if _throwing:
		_vel.y += throw_gravity * delta
		global_position += _vel * delta

		# freno suave horizontal
		_vel.x = lerpf(_vel.x, 0.0, throw_damping * delta)

		# si tocó el "suelo" (la Y donde nació)
		if global_position.y >= _ground_y:
			global_position.y = _ground_y
			_throwing = false
			_vel = Vector2.ZERO

			# al caer, fija base para flotación
			_base_y = spr.position.y

		# mientras vuela, NO flota ni magnet
		return

	# =========================
	# 2) POP (solo si quieres un pop al aparecer en suelo)
	# =========================
	if _popping:
		_pop_t -= delta
		var k := clampf(1.0 - (_pop_t / pop_time), 0.0, 1.0)
		var yoff := -pop_height * sin(k * PI)
		spr.position.y = _base_y + yoff
		if _pop_t <= 0.0:
			_popping = false
			spr.position.y = _base_y

	# =========================
	# 3) Flotación constante (solo cuando ya está quieto)
	# =========================
	if not _popping:
		spr.position.y = _base_y + sin(_t * float_speed) * float_amp

	# =========================
	# 4) Wobble/rotación leve “semi 3d”
	# =========================
	spr.rotation_degrees = sin(_t * wobble_speed) * wobble_deg

	# =========================
	# 5) Magnet (solo cuando no está volando)
	# =========================
	if _magnet_on and _player != null:
		var d := global_position.distance_to(_player.global_position)
		if d <= magnet_range:
			global_position = global_position.move_toward(_player.global_position, magnet_speed * delta)

			# si ya casi toca, intentar pickup
			if d < 12.0:
				_try_pickup()
				
func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_player = body as Node2D

func _on_body_exited(body: Node) -> void:
	if body == _player:
		_player = null
func _try_pickup() -> void:
	if _player == null:
		return

	var inv := _player.get_node_or_null("InventoryComponent")
	if inv == null or not inv.has_method("add_item"):
		return

	var inserted: int = int(inv.add_item(item_id, amount))
	if inserted <= 0:
		return

	if GameEvents != null and GameEvents.has_method("emit_item_picked"):
		GameEvents.emit_item_picked(item_id, inserted, _player)

	# ✅ tocar sonido y destruir después (sin cortarlo)
	if pickup_sfx != null:
		sfx.stream = pickup_sfx
		sfx.play()

	# desactiva para que no se vuelva a recoger mientras suena
	monitoring = false
	monitorable = false
	spr.visible = false

	# si no hay sonido asignado, igualmente se borra
	if pickup_sfx == null:
		queue_free()
		return

	await sfx.finished
	queue_free()
	
func throw_from(origin: Vector2, dir: Vector2, speed: float, up_boost: float = 260.0) -> void:
	global_position = origin
	_vel = dir.normalized() * speed
	_vel.y -= absf(up_boost)
	_throwing = true
	_ground_y = origin.y
