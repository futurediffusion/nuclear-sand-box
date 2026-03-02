extends WeaponBase
class_name BowWeapon

@export var max_draw_time: float = 1.2
@export var stamina_drain_per_sec: float = 8.0
@export var min_release_ratio: float = 0.15

# Para que exista feedback aunque no dispares todavía
@export var auto_release_on_no_stamina: bool = true
@export var no_stamina_release_ratio: float = 0.25

var is_drawing: bool = false
var draw_time: float = 0.0

func on_equipped(p_player: Node) -> void:
	super.on_equipped(p_player)
	_cancel_draw()

func on_unequipped() -> void:
	_cancel_draw()
	super.on_unequipped()

func tick(delta: float) -> void:
	if player == null:
		return

	var inv = player.get_node_or_null("InventoryComponent")
	if inv == null:
		return

	# Start draw
	if Input.is_action_just_pressed("attack"):
		if inv.get_total("arrow") > 0:
			_start_draw()
		else:
			# Sin flechas: no hace nada
			_cancel_draw()

	# Hold draw
	if is_drawing and Input.is_action_pressed("attack"):
		_hold_draw(delta)

	# Release
	if is_drawing and Input.is_action_just_released("attack"):
		_release(inv)

func _start_draw() -> void:
	is_drawing = true
	draw_time = 0.0
	_update_draw_visuals()

func _hold_draw(delta: float) -> void:
	# Drenaje de stamina mientras tensas
	var stamina = player.get_node_or_null("StaminaComponent")
	if stamina == null:
		# Si no hay stamina component, igual puedes cargar (pero no deberías)
		draw_time = min(draw_time + delta, max_draw_time)
		_update_draw_visuals()
		return

	if stamina.has_method("spend_continuous"):
		var ok := stamina.spend_continuous(stamina_drain_per_sec, delta)
		if not ok:
			# Nos quedamos sin stamina
			if auto_release_on_no_stamina:
				draw_time = max_draw_time * no_stamina_release_ratio
				_update_draw_visuals()
				_force_release_due_to_no_stamina()
			else:
				_cancel_draw()
			return
	else:
		# Si no existe la API (no debería pasar ya), no drenar
		pass

	# acumula carga
	draw_time = min(draw_time + delta, max_draw_time)
	_update_draw_visuals()

func _release(inventory) -> void:
	var ratio := get_draw_ratio()
	var has_arrows := inventory.get_total("arrow") > 0

	if not has_arrows:
		_cancel_draw()
		return

	if ratio < min_release_ratio:
		# Soltaste muy rápido: cancel
		_cancel_draw()
		return

	# Consume 1 flecha
	inventory.remove_item("arrow", 1)

	# Disparo: placeholder hasta el paso 7 (proyectil real)
	_fire_placeholder(ratio)

	# Reset draw
	_cancel_draw()

func _force_release_due_to_no_stamina() -> void:
	# Soltar automáticamente aunque el jugador siga presionando
	var inv = player.get_node_or_null("InventoryComponent")
	if inv == null:
		_cancel_draw()
		return
	_release(inv)

func _cancel_draw() -> void:
	is_drawing = false
	draw_time = 0.0
	_update_draw_visuals(reset := true)

func get_draw_ratio() -> float:
	if max_draw_time <= 0.0:
		return 0.0
	return clamp(draw_time / max_draw_time, 0.0, 1.0)

func _update_draw_visuals(reset: bool = false) -> void:
	# Animación simple: mover la flecha montada hacia atrás según ratio.
	# Requiere que el Player tenga un Sprite2D en WeaponPivot llamado "NockedArrowSprite"
	var arrow_sprite: Sprite2D = player.get_node_or_null("WeaponPivot/NockedArrowSprite")
	if arrow_sprite == null:
		return

	if reset or not is_drawing:
		arrow_sprite.visible = false
		arrow_sprite.position = Vector2.ZERO
		return

	arrow_sprite.visible = true
	var ratio := get_draw_ratio()

	# Ajusta estos números según tu sprite/pivot:
	# Start pos (0) = flecha “normal”
	# End pos (1) = flecha tirada hacia atrás
	var start_x := 0.0
	var end_x := -6.0
	arrow_sprite.position.x = lerp(start_x, end_x, ratio)

func _fire_placeholder(ratio: float) -> void:
	# Por ahora: solo debug. Paso 7 crea Arrow projectile real.
	# Mantener el ángulo igual al apuntado del player.
	var angle := 0.0
	if player.has_variable("mouse_angle"):
		angle = player.mouse_angle
	elif player.has_method("get_mouse_angle"):
		angle = player.get_mouse_angle()

	print("[BowWeapon] FIRE ratio=", ratio, " angle=", angle, " TODO: spawn projectile")
