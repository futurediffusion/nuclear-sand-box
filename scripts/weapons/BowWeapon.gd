extends WeaponBase
class_name BowWeapon

const ARROW_SCENE := preload("res://scenes/arrow.tscn")

@export var max_draw_time: float = 1.2
@export var stamina_drain_per_sec: float = 8.0
@export var min_release_ratio: float = 0.05
@export var debug_stamina_logs: bool = false
@export var min_speed: float = 420.0
@export var max_speed: float = 900.0
@export var min_damage: int = 8
@export var max_damage: int = 18
@export var knockback: float = 220.0
@export var nock_start_pos: Vector2 = Vector2(7, 0)
@export var nock_pulled_pos: Vector2 = Vector2(4.5, 0)
@export var arrow_spawn_offset: float = 14.0
@export var trajectory_points: int = 14
@export var trajectory_step_time: float = 0.06
@export var trajectory_gravity: float = 900.0
@export var trajectory_update_interval: float = 0.05
@export var trajectory_mouse_significant_delta: float = 8.0

var is_drawing: bool = false
var draw_time: float = 0.0
var _drain_log_accum: float = 0.0
var _aim_trajectory_line: Line2D
var _last_trajectory_update_time: float = -INF
var _last_trajectory_mouse_global: Vector2 = Vector2.INF

func on_equipped(p_player: Node) -> void:
	super.on_equipped(p_player)
	_aim_trajectory_line = player.get_node_or_null("WeaponPivot/AimTrajectory") as Line2D
	_cancel_draw()

func on_unequipped() -> void:
	_update_draw_visuals(true)
	_cancel_draw()
	_aim_trajectory_line = null
	super.on_unequipped()

func tick(delta: float) -> void:
	if player == null:
		return
	if UiManager.is_combat_input_blocked():
		if is_drawing:
			_cancel_draw()
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
	_drain_log_accum = 0.0
	_update_draw_visuals()
	_set_stamina_regen_block(true)
	if debug_stamina_logs:
		print("[BowWeapon] enter charging")

func _hold_draw(delta: float) -> void:
	# Drenaje de stamina mientras tensas
	var stamina = player.get_node_or_null("StaminaComponent")
	if stamina == null:
		# Si no hay stamina component, igual puedes cargar (pero no deberías)
		return

	if stamina.has_method("spend_continuous"):
		var ok: bool = bool(stamina.spend_continuous(stamina_drain_per_sec, delta))
		_drain_log_accum += delta
		if debug_stamina_logs and _drain_log_accum >= 1.0:
			_drain_log_accum = 0.0
			var current := 0.0
			if stamina.has_method("get_current_stamina"):
				current = float(stamina.get_current_stamina())
			print("[BowWeapon] charging drain | stamina=", current)
		if not ok:
			if debug_stamina_logs:
				print("[BowWeapon] cancel charging: no stamina")
			# Sin stamina: vuelve al estado inicial del arco.
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

func _cancel_draw() -> void:
	is_drawing = false
	draw_time = 0.0
	_drain_log_accum = 0.0
	_set_stamina_regen_block(false)
	_update_draw_visuals(true)

func _set_stamina_regen_block(blocked: bool) -> void:
	if player == null:
		return
	var stamina = player.get_node_or_null("StaminaComponent")
	if stamina == null:
		return
	if stamina.has_method("set_regen_blocked"):
		stamina.set_regen_blocked(blocked, "bow_draw")

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
		_update_trajectory_visuals(0.0, true)
		return

	arrow_sprite.visible = true
	var ratio: float = get_draw_ratio()
	arrow_sprite.position = nock_start_pos.lerp(nock_pulled_pos, ratio)
	_update_trajectory_visuals(ratio)

func _update_trajectory_visuals(ratio: float, reset: bool = false) -> void:
	if player == null:
		return

	var line := _aim_trajectory_line
	if line == null:
		line = player.get_node_or_null("WeaponPivot/AimTrajectory") as Line2D
		_aim_trajectory_line = line
	if line == null:
		return

	if reset:
		line.points = PackedVector2Array()
		line.visible = false
		_last_trajectory_update_time = -INF
		_last_trajectory_mouse_global = Vector2.INF
		return

	var player_node := player as Node2D
	if player_node == null:
		line.points = PackedVector2Array()
		line.visible = false
		_last_trajectory_update_time = -INF
		_last_trajectory_mouse_global = Vector2.INF
		return

	var mouse_global := player_node.get_global_mouse_position()
	var now_sec := float(Time.get_ticks_msec()) * 0.001
	var elapsed := now_sec - _last_trajectory_update_time
	var significant_delta_sq := trajectory_mouse_significant_delta * trajectory_mouse_significant_delta
	var mouse_changed_significantly := _last_trajectory_mouse_global == Vector2.INF \
		or _last_trajectory_mouse_global.distance_squared_to(mouse_global) >= significant_delta_sq
	if elapsed < maxf(trajectory_update_interval, 0.0) and not mouse_changed_significantly:
		return

	var angle: float = player_node.get_angle_to(mouse_global)
	var dir := Vector2.RIGHT.rotated(angle)
	var speed: float = lerp(min_speed, max_speed, ratio)
	var start_global := _get_arrow_spawn_position(player_node, dir)

	var points := PackedVector2Array()
	points.resize(maxi(trajectory_points, 2))
	line.visible = true
	var gravity := trajectory_gravity
	for i in range(maxi(trajectory_points, 2)):
		var t: float = float(i) * maxf(trajectory_step_time, 0.01)
		var point_global := start_global + (dir * speed * t)
		point_global.y += 0.5 * gravity * t * t
		points[i] = line.to_local(point_global)

	line.points = points
	_last_trajectory_update_time = now_sec
	_last_trajectory_mouse_global = mouse_global

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

	var spawn_pos := _get_arrow_spawn_position(player_node, dir)

	arrow.setup(dir * speed, dmg, knockback, player_node)
	player.get_tree().current_scene.add_child(arrow)
	arrow.global_position = spawn_pos
	arrow.rotation = dir.angle()

func _get_arrow_spawn_position(player_node: Node2D, dir: Vector2) -> Vector2:
	var spawn_marker: Node2D = player.get_node_or_null("WeaponPivot/SlashSpawn") as Node2D
	var spawn_pos: Vector2 = player_node.global_position
	if spawn_marker != null:
		spawn_pos = spawn_marker.global_position
	spawn_pos += dir * arrow_spawn_offset
	return spawn_pos
