extends WeaponBase
class_name BowWeapon

const ARROW_SCENE := preload("res://scenes/arrow.tscn")

@export var max_draw_time: float = 1.2
@export var stamina_drain_per_sec: float = 8.0
@export var min_release_ratio: float = 0.15

# Para que exista feedback aunque no dispares todavía
@export var auto_release_on_no_stamina: bool = true
@export var no_stamina_release_ratio: float = 0.25
@export var min_speed: float = 420.0
@export var max_speed: float = 900.0
@export var min_damage: int = 8
@export var max_damage: int = 18
@export var knockback: float = 220.0
@export var nock_start_pos: Vector2 = Vector2(7, 0)
@export var nock_pulled_pos: Vector2 = Vector2(4.5, 0)
@export var arrow_spawn_offset: float = 14.0

var is_drawing: bool = false
var draw_time: float = 0.0

func on_equipped(p_player: Node) -> void:
	super.on_equipped(p_player)
	_cancel_draw()

func on_unequipped() -> void:
	_update_draw_visuals(true)
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
		draw_time = min(draw_time + delta, max_draw_time)
		_update_draw_visuals()
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
		return

	if stamina.has_method("spend_continuous"):
		var ok: bool = bool(stamina.spend_continuous(stamina_drain_per_sec, delta))
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

	# La carga visual/tiempo se actualiza en tick().

func _release(inventory: Node) -> void:
	var ratio: float = get_draw_ratio()
	var has_arrows: bool = bool(inventory.get_total("arrow") > 0)

	if not has_arrows:
		_cancel_draw()
		return

	if ratio < min_release_ratio:
		# Soltaste muy rápido: cancel
		_cancel_draw()
		return

	# Consume 1 flecha
	inventory.remove_item("arrow", 1)

	_fire_arrow(ratio)
	_update_draw_visuals(true)

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
	_update_draw_visuals(true)

func get_draw_ratio() -> float:
	if max_draw_time <= 0.0:
		return 0.0
	return clamp(draw_time / max_draw_time, 0.0, 1.0)

func _update_draw_visuals(reset: bool = false) -> void:
	if player == null:
		return

	var arrow_sprite: Node2D = player.get_node_or_null("WeaponPivot/NockedArrowSprite") as Node2D
	if arrow_sprite == null:
		return

	if reset:
		arrow_sprite.visible = false
		arrow_sprite.position = nock_start_pos
		return

	arrow_sprite.visible = true
	var ratio: float = get_draw_ratio()
	arrow_sprite.position = nock_start_pos.lerp(nock_pulled_pos, ratio)

func _fire_arrow(ratio: float) -> void:
	if player == null:
		return

	var player_node: Node2D = player as Node2D
	if player_node == null:
		return

	var angle: float = player_node.get_angle_to(player_node.get_global_mouse_position())
	var dir := Vector2.RIGHT.rotated(angle)

	var speed: float = lerp(min_speed, max_speed, ratio)
	var dmg := int(round(lerp(float(min_damage), float(max_damage), ratio)))

	var arrow := ARROW_SCENE.instantiate() as ArrowProjectile
	if arrow == null:
		return

	var spawn_marker: Node2D = player.get_node_or_null("WeaponPivot/SlashSpawn") as Node2D
	var spawn_pos: Vector2 = player_node.global_position
	if spawn_marker != null:
		spawn_pos = spawn_marker.global_position
	spawn_pos += dir * arrow_spawn_offset

	arrow.global_position = spawn_pos
	arrow.rotation = dir.angle()
	arrow.setup(dir * speed, dmg, knockback, player_node)

	player.get_tree().current_scene.add_child(arrow)
