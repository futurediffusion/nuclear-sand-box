extends WeaponBase
class_name BowWeapon

const ARROW_SCENE := preload("res://scenes/arrow.tscn")
const CombatQueryScript := preload("res://scripts/systems/CombatQuery.gd")

@export var max_draw_time: float = 1.2
@export var stamina_drain_per_sec: float = 8.0
@export var min_release_ratio: float = 0.05
@export var debug_stamina_logs: bool = false
@export var min_range: float = 90.0
@export var max_range: float = 420.0
@export var min_damage: int = 1
@export var max_damage: int = 2
@export var knockback: float = 220.0
@export var nock_start_pos: Vector2 = Vector2(7, 0)
@export var nock_pulled_pos: Vector2 = Vector2(4.5, 0)
@export var arrow_spawn_offset: float = 14.0
@export var arrow_wall_skin: float = 1.0
@export var arrow_min_center_advance: float = 2.0
@export var trajectory_points: int = 14
@export var trajectory_gravity: float = 900.0
@export var min_flight_time: float = 0.2
@export var max_flight_time: float = 0.5
@export var trajectory_update_interval: float = 0.05
@export var trajectory_aim_significant_delta: float = 8.0
@export var consume_arrows: bool = true

var is_drawing: bool = false
var draw_time: float = 0.0
var _drain_log_accum: float = 0.0
var _aim_trajectory_line: Line2D
var _last_trajectory_update_time: float = -INF
var _last_trajectory_aim_global: Vector2 = Vector2.INF

func on_equipped(p_owner: Node, p_controller: WeaponController = null) -> void:
	super.on_equipped(p_owner, p_controller)
	if owner_entity != null:
		_aim_trajectory_line = owner_entity.get_node_or_null("WeaponPivot/AimTrajectory") as Line2D
	else:
		_aim_trajectory_line = null
	_cancel_draw()

func on_unequipped() -> void:
	_update_draw_visuals(true)
	_cancel_draw()
	_aim_trajectory_line = null
	super.on_unequipped()

func tick(delta: float) -> void:
	if owner_entity == null:
		return
	if controller == null:
		return
	if UiManager.is_combat_input_blocked():
		if is_drawing:
			_cancel_draw()
		return

	var inv = owner_entity.get_node_or_null("InventoryComponent")

	# Start draw
	if controller.is_attack_just_pressed():
		if _can_start_draw(inv):
			_start_draw()
		else:
			# Sin flechas: no hace nada
			_cancel_draw()

	# Hold draw
	if is_drawing and controller.is_attack_pressed():
		draw_time = min(draw_time + delta, max_draw_time)
		_update_draw_visuals()
		_hold_draw(delta)

	# Release
	if is_drawing and controller.is_attack_just_released():
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
	var stamina = owner_entity.get_node_or_null("StaminaComponent")
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

	if not _has_ammo_for_release(inventory):
		_cancel_draw()
		return

	if ratio < min_release_ratio:
		# Soltaste muy rápido: cancel
		_cancel_draw()
		return

	# Consume 1 flecha
	if consume_arrows and inventory != null and inventory.has_method("remove_item"):
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
	if owner_entity == null:
		return
	var stamina = owner_entity.get_node_or_null("StaminaComponent")
	if stamina == null:
		return
	if stamina.has_method("set_regen_blocked"):
		stamina.set_regen_blocked(blocked, "bow_draw")

func get_draw_ratio() -> float:
	if max_draw_time <= 0.0:
		return 0.0
	return clamp(draw_time / max_draw_time, 0.0, 1.0)

func _update_draw_visuals(reset: bool = false) -> void:
	if owner_entity == null:
		return

	var arrow_sprite: Node2D = owner_entity.get_node_or_null("WeaponPivot/NockedArrowSprite") as Node2D
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
	if owner_entity == null:
		return

	var line := _aim_trajectory_line
	if line == null:
		line = owner_entity.get_node_or_null("WeaponPivot/AimTrajectory") as Line2D
		_aim_trajectory_line = line
	if line == null:
		return

	if reset:
		line.points = PackedVector2Array()
		line.visible = false
		_last_trajectory_update_time = -INF
		_last_trajectory_aim_global = Vector2.INF
		return

	var owner_entity_node := _get_owner_node2d()
	if owner_entity_node == null:
		line.points = PackedVector2Array()
		line.visible = false
		_last_trajectory_update_time = -INF
		_last_trajectory_aim_global = Vector2.INF
		return

	var aim_global := _get_aim_global_position()
	if aim_global == Vector2.ZERO:
		return
	var now_sec := float(Time.get_ticks_msec()) * 0.001
	var elapsed := now_sec - _last_trajectory_update_time
	var significant_delta_sq := trajectory_aim_significant_delta * trajectory_aim_significant_delta
	var aim_changed_significantly := _last_trajectory_aim_global == Vector2.INF \
		or _last_trajectory_aim_global.distance_squared_to(aim_global) >= significant_delta_sq
	if elapsed < maxf(trajectory_update_interval, 0.0) and not aim_changed_significantly:
		return

	if owner_entity_node.global_position.distance_squared_to(aim_global) < 0.0001:
		return

	var shot := _build_arrow_shot(ratio)
	if shot.is_empty():
		line.points = PackedVector2Array()
		line.visible = false
		_last_trajectory_update_time = now_sec
		_last_trajectory_aim_global = aim_global
		return

	var start_global: Vector2 = shot["start_global"]
	var dir: Vector2 = shot["dir"]
	var ground_speed: float = shot["ground_speed"]
	var flight_duration: float = shot["flight_duration"]
	var vertical_launch_speed: float = shot["vertical_launch_speed"]
	var arc_visibility: float = shot["arc_visibility"]

	var points := PackedVector2Array()
	line.visible = true
	var gravity: float = trajectory_gravity
	var total_points := maxi(trajectory_points, 2)
	for i in range(total_points):
		var u: float = float(i) / float(total_points - 1)
		var t: float = flight_duration * u
		var ground_point := start_global + dir * ground_speed * t
		var point_height := maxf(0.0, (vertical_launch_speed * t) - (0.5 * gravity * t * t))
		var point_global := ground_point + Vector2(0.0, -point_height * arc_visibility)
		points.append(line.to_local(point_global))

	if points.size() < 2:
		points.append(points[0] if points.size() == 1 else line.to_local(start_global))

	line.points = points
	_last_trajectory_update_time = now_sec
	_last_trajectory_aim_global = aim_global

func _fire_arrow(ratio: float) -> void:
	if owner_entity == null:
		return

	var owner_entity_node := _get_owner_node2d()
	if owner_entity_node == null:
		return

	var aim_global := _get_aim_global_position()
	if aim_global == Vector2.ZERO:
		return
	if owner_entity_node.global_position.distance_squared_to(aim_global) < 0.0001:
		return

	var shot := _build_arrow_shot(ratio)
	if shot.is_empty():
		return

	var dir: Vector2 = shot["dir"]
	var ground_velocity: Vector2 = shot["ground_velocity"]
	var vertical_launch_speed: float = shot["vertical_launch_speed"]
	var flight_duration: float = shot["flight_duration"]
	var arc_visibility: float = shot["arc_visibility"]
	var dmg := int(round(lerp(float(min_damage), float(max_damage), ratio)))

	var arrow := ARROW_SCENE.instantiate() as ArrowProjectile
	if arrow == null:
		return

	var launch := _resolve_arrow_launch(owner_entity_node, dir, arrow)

	arrow.setup(
		ground_velocity,
		dmg,
		knockback,
		owner_entity_node,
		vertical_launch_speed,
		0.0,
		flight_duration,
		arc_visibility
	)
	var scene_root := owner_entity.get_tree().current_scene
	if scene_root != null:
		scene_root.add_child(arrow)
	else:
		owner_entity.get_tree().root.add_child(arrow)
	arrow.global_position = launch["spawn_pos"]
	arrow.rotation = dir.angle()

	if bool(launch.get("blocked", false)):
		arrow.embed_in_world(launch["spawn_pos"], dir)
	else:
		arrow.call_deferred("validate_spawn_position")

func _build_arrow_shot(ratio: float) -> Dictionary:
	var owner_entity_node := _get_owner_node2d()
	if owner_entity_node == null:
		return {}

	var aim_global := _get_aim_global_position()
	var muzzle_global := _get_arrow_muzzle_position(owner_entity_node)
	var to_aim := aim_global - muzzle_global
	if to_aim.length_squared() < 0.0001:
		return {}

	var dir := to_aim.normalized()
	var start_global := muzzle_global + dir * arrow_spawn_offset
	var to_aim_from_start := aim_global - start_global
	if to_aim_from_start.length_squared() < 0.0001:
		return {}

	var max_range_now: float = lerpf(min_range, max_range, ratio)
	var distance_to_target: float = minf(to_aim_from_start.length(), max_range_now)
	if distance_to_target <= 0.0:
		return {}

	var target_global := start_global + dir * distance_to_target
	var flight_duration: float = maxf(lerpf(min_flight_time, max_flight_time, ratio), 0.05)
	var ground_speed: float = distance_to_target / flight_duration
	var vertical_launch_speed: float = 0.5 * trajectory_gravity * flight_duration
	var arc_visibility: float = absf(dir.x)

	return {
		"start_global": start_global,
		"target_global": target_global,
		"dir": dir,
		"distance_to_target": distance_to_target,
		"ground_speed": ground_speed,
		"ground_velocity": dir * ground_speed,
		"flight_duration": flight_duration,
		"vertical_launch_speed": vertical_launch_speed,
		"arc_visibility": arc_visibility,
	}


func _get_owner_node2d() -> Node2D:
	if owner_entity is Node2D:
		return owner_entity as Node2D
	return null

func _get_aim_global_position() -> Vector2:
	if controller == null:
		return Vector2.ZERO
	return controller.get_aim_global_position()

func _can_start_draw(inventory: Node) -> bool:
	if not consume_arrows:
		return true
	if inventory == null:
		return false
	if not inventory.has_method("get_total"):
		return false
	return int(inventory.get_total("arrow")) > 0

func _has_ammo_for_release(inventory: Node) -> bool:
	if not consume_arrows:
		return true
	if inventory == null:
		return false
	if not inventory.has_method("get_total"):
		return false
	return int(inventory.get_total("arrow")) > 0

func _get_arrow_muzzle_position(owner_entity_node: Node2D) -> Vector2:
	var muzzle: Node2D = owner_entity.get_node_or_null("WeaponPivot/ArrowMuzzle") as Node2D
	if muzzle != null:
		return muzzle.global_position
	return owner_entity_node.global_position

func _resolve_arrow_launch(owner_entity_node: Node2D, dir: Vector2, arrow: ArrowProjectile) -> Dictionary:
	var muzzle := _get_arrow_muzzle_position(owner_entity_node)
	var desired_center := muzzle + dir * arrow_spawn_offset
	var nose_clearance := arrow.get_forward_half_extent() + arrow_wall_skin

	var body_to_muzzle_hit := CombatQueryScript.find_first_wall_hit(
		owner_entity_node,
		owner_entity_node.global_position,
		muzzle,
		[owner_entity_node],
		true
	)

	if not body_to_muzzle_hit.is_empty():
		var body_muzzle_hit_pos: Vector2 = body_to_muzzle_hit.get("position", muzzle)
		return {
			"blocked": true,
			"spawn_pos": body_muzzle_hit_pos - dir * arrow_wall_skin,
		}

	var desired_nose := desired_center + dir * nose_clearance
	var muzzle_hit := CombatQueryScript.find_first_wall_hit(
		owner_entity_node,
		muzzle,
		desired_nose,
		[owner_entity_node],
		true
	)

	if muzzle_hit.is_empty():
		return {
			"blocked": false,
			"spawn_pos": desired_center,
		}

	var hit_pos: Vector2 = muzzle_hit.get("position", desired_nose)
	var available_center_distance := maxf(muzzle.distance_to(hit_pos) - nose_clearance, 0.0)

	if available_center_distance <= arrow_min_center_advance:
		return {
			"blocked": true,
			"spawn_pos": hit_pos - dir * arrow_wall_skin,
		}

	return {
		"blocked": false,
		"spawn_pos": muzzle + dir * minf(arrow_spawn_offset, available_center_distance),
	}
