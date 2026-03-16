extends Area2D
class_name ArrowProjectile

const CombatQueryScript := preload("res://scripts/systems/CombatQuery.gd")

@export var damage: int = 12
@export var knockback: float = 180.0
@export var wall_damage: int = 1
@export var projectile_gravity: float = 900.0
@export var max_flight_time: float = 4.0
@export var stuck_visible_time: float = 5.0
@export var fade_out_duration: float = 1.0
@export var max_distance_from_player: float = 1500.0
@export var distance_check_interval: float = 0.4
@export var debug_hit_logs: bool = false
@export var visual_rotation_offset_deg: float = 0.0

var ground_velocity: Vector2 = Vector2.ZERO
var height: float = 0.0
var vertical_velocity: float = 0.0
var flight_time: float = 0.0
# NOTE: Collision remains in base Area2D space (ground plane).
# Visual height is fake-top-down only and does not affect collision checks.

var _owner_ref: WeakRef = null
var _stuck: bool = false
var _distance_check_left: float = 0.0
var _player_ref: WeakRef = null
var _stuck_elapsed: float = 0.0
var _visual_root: Node2D = null
var _visual_base_pos: Vector2 = Vector2.ZERO
var _arc_visibility: float = 1.0
var _flight_duration: float = 0.0

func setup(
	p_ground_velocity: Vector2,
	p_damage: int,
	p_knockback: float,
	p_owner: Node = null,
	p_vertical_velocity: float = 0.0,
	p_initial_height: float = 0.0,
	p_flight_duration: float = 0.2,
	p_arc_visibility: float = 1.0
) -> void:
	ground_velocity = p_ground_velocity
	damage = p_damage
	knockback = p_knockback
	_owner_ref = weakref(p_owner) if p_owner != null else null
	vertical_velocity = p_vertical_velocity
	height = maxf(p_initial_height, 0.0)
	flight_time = 0.0
	_flight_duration = maxf(p_flight_duration, 0.01)
	_arc_visibility = clampf(p_arc_visibility, 0.0, 1.0)
	_stuck = false
	_stuck_elapsed = 0.0
	_distance_check_left = distance_check_interval
	_update_visual_height()
	_update_visual_rotation()
	_set_visual_alpha(1.0)

func get_forward_half_extent() -> float:
	var shape_node := get_node_or_null("Collision") as CollisionShape2D
	if shape_node == null or shape_node.shape == null:
		return 5.0

	if shape_node.shape is RectangleShape2D:
		var rect := shape_node.shape as RectangleShape2D
		return rect.size.x * 0.5 * abs(scale.x) * abs(shape_node.scale.x)

	if shape_node.shape is CircleShape2D:
		var circle := shape_node.shape as CircleShape2D
		return circle.radius * maxf(abs(scale.x), abs(scale.y))

	if shape_node.shape is CapsuleShape2D:
		var capsule := shape_node.shape as CapsuleShape2D
		return maxf(capsule.height * 0.5, capsule.radius) * abs(scale.x) * abs(shape_node.scale.x)

	return 5.0

func embed_in_world(at_position: Vector2, facing_dir: Vector2 = Vector2.ZERO) -> void:
	global_position = at_position
	if facing_dir.length_squared() > 0.0001:
		rotation = facing_dir.angle()
		_apply_visual_rotation(facing_dir.angle())
	height = 0.0
	vertical_velocity = 0.0
	_stick_to_world()

func validate_spawn_position() -> void:
	if _stuck:
		return

	var shape_node := get_node_or_null("Collision") as CollisionShape2D
	if shape_node == null or shape_node.shape == null:
		return

	if CombatQueryScript.shape_overlaps_wall(self, shape_node, _build_query_excluded_nodes()):
		embed_in_world(global_position, Vector2.RIGHT.rotated(rotation))

func _ready() -> void:
	_visual_root = get_node_or_null("Visual") as Node2D
	if _visual_root == null:
		_visual_root = get_node_or_null("Sprite") as Node2D
	if _visual_root != null:
		_visual_base_pos = _visual_root.position
	flight_time = 0.0
	_stuck_elapsed = 0.0
	monitoring = false
	monitorable = false
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)
	call_deferred("_enable_collision")
	_update_visual_height()
	_update_visual_rotation()

func _enable_collision() -> void:
	if _stuck:
		return
	monitoring = true
	monitorable = true

func _physics_process(delta: float) -> void:
	if _stuck:
		_tick_stuck_state(delta)
		return

	var prev_pos := global_position
	var next_pos := prev_pos + ground_velocity * delta

	if _sweep_hit(prev_pos, next_pos):
		return

	global_position = next_pos

	vertical_velocity -= projectile_gravity * delta
	height += vertical_velocity * delta
	flight_time += delta
	_update_visual_height()
	_update_visual_rotation()

	if flight_time >= _flight_duration or height <= 0.0:
		height = 0.0
		vertical_velocity = 0.0
		_update_visual_height()
		_stick_to_world()
		return

	if max_flight_time > 0.0 and flight_time >= max_flight_time:
		queue_free()

func _sweep_hit(from_pos: Vector2, to_pos: Vector2) -> bool:
	if from_pos == to_pos:
		return false

	var wall_hit := CombatQueryScript.find_first_wall_hit(self, from_pos, to_pos, _build_query_excluded_nodes())
	var hurtbox_hit := _find_first_hurtbox_hit(from_pos, to_pos)

	if not wall_hit.is_empty() and not hurtbox_hit.is_empty():
		var wall_distance := from_pos.distance_squared_to(wall_hit.get("position", from_pos))
		var hurtbox_distance := from_pos.distance_squared_to(hurtbox_hit.get("position", from_pos))
		if wall_distance <= hurtbox_distance:
			return _handle_body_hit(wall_hit)
		return _handle_area_hit(hurtbox_hit)

	if not wall_hit.is_empty():
		return _handle_body_hit(wall_hit)
	if not hurtbox_hit.is_empty():
		return _handle_area_hit(hurtbox_hit)

	return false

func _find_first_hurtbox_hit(from_pos: Vector2, to_pos: Vector2) -> Dictionary:
	var space_state := get_world_2d().direct_space_state
	var excluded := _build_query_excluded_rids()

	for _attempt in range(12):
		var query := PhysicsRayQueryParameters2D.create(from_pos, to_pos)
		query.collide_with_areas = true
		query.collide_with_bodies = false
		query.collision_mask = collision_mask
		query.exclude = excluded

		var hit := space_state.intersect_ray(query)
		if hit.is_empty():
			return {}

		var area := hit.get("collider") as Area2D
		if area == null:
			break
		if _is_owner_related_area(area) or not (area is CharacterHurtbox):
			excluded.append(area.get_rid())
			continue

		return hit

	return {}

func _build_query_excluded_nodes() -> Array:
	var excluded_nodes: Array = [self]
	var owner_node := _get_owner_node()
	if owner_node != null:
		excluded_nodes.append(owner_node)
	return excluded_nodes

func _build_query_excluded_rids() -> Array[RID]:
	var excluded: Array[RID] = []
	if self is CollisionObject2D:
		excluded.append(get_rid())
	var owner_node := _get_owner_node()
	if owner_node is CollisionObject2D:
		excluded.append((owner_node as CollisionObject2D).get_rid())
	return excluded

func _handle_area_hit(hit: Dictionary) -> bool:
	if hit.is_empty():
		return false

	var area := hit.get("collider") as Area2D
	_dbg_area(area)
	if area == null:
		return false
	if _is_owner_related_area(area):
		return false
	if _stuck:
		return false

	if not (area is CharacterHurtbox):
		return false

	global_position = hit.get("position", global_position)
	if area.has_method("take_damage"):
		area.take_damage(damage, global_position)
	queue_free()
	return true

func _handle_body_hit(hit: Dictionary) -> bool:
	if hit.is_empty():
		return false

	var body := hit.get("collider") as Node
	_dbg_body(body)
	if body == null:
		return false
	if _is_owner_related_node(body):
		return false

	global_position = hit.get("position", global_position)

	if CombatQueryScript.is_wall_collider(body):
		_damage_generic_wall(hit)
		height = 0.0
		vertical_velocity = 0.0
		_stick_to_world()
		return true

	return false

func _on_area_entered(_area: Area2D) -> void:
	pass

func _on_body_entered(_body: Node2D) -> void:
	pass

func _dbg_area(area: Area2D) -> void:
	if not debug_hit_logs:
		return

	if area == null:
		print("[ARROW AREA] collider=<null>")
		return

	print(
		"[ARROW AREA] collider=", area.name,
		" path=", str(area.get_path()),
		" class=", area.get_class(),
		" script=", str(area.get_script()),
		" has_take_damage=", area.has_method("take_damage")
	)

func _dbg_body(body: Node) -> void:
	if not debug_hit_logs:
		return

	if body == null:
		print("[ARROW HIT] collider=<null>")
		return

	print(
		"[ARROW HIT] collider=", body.name,
		" path=", str(body.get_path()),
		" class=", body.get_class(),
		" script=", str(body.get_script()),
		" owner_related=", _is_owner_related_node(body),
		" has_take_damage=", body.has_method("take_damage")
	)

	if body is CollisionObject2D:
		var body_co := body as CollisionObject2D
		print("[ARROW HIT] collider layers=", body_co.collision_layer, " mask=", body_co.collision_mask)

	print("[ARROW HIT] arrow layers=", collision_layer, " mask=", collision_mask)

func _stick_to_world() -> void:
	if _stuck:
		return

	_stuck = true
	ground_velocity = Vector2.ZERO
	vertical_velocity = 0.0
	height = 0.0
	_stuck_elapsed = 0.0
	_update_visual_height()
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)

func _tick_stuck_state(delta: float) -> void:
	_stuck_elapsed += delta

	var fade_start := maxf(stuck_visible_time, 0.0)
	if _stuck_elapsed <= fade_start:
		_set_visual_alpha(1.0)
	else:
		if fade_out_duration <= 0.0:
			queue_free()
			return
		var fade_t: float = clampf((_stuck_elapsed - fade_start) / fade_out_duration, 0.0, 1.0)
		_set_visual_alpha(1.0 - fade_t)
		if fade_t >= 1.0:
			queue_free()
			return

	if max_distance_from_player <= 0.0:
		return

	_distance_check_left -= delta
	if _distance_check_left > 0.0:
		return
	_distance_check_left = distance_check_interval

	var player := _get_player_node()
	if player == null:
		return

	if global_position.distance_to(player.global_position) > max_distance_from_player:
		queue_free()

func _update_visual_height() -> void:
	if _visual_root == null:
		return
	var screen_offset := Vector2(0.0, -(height * _arc_visibility))
	_visual_root.position = _visual_base_pos + screen_offset.rotated(-global_rotation)

func _update_visual_rotation() -> void:
	if _visual_root == null:
		return

	var visual_velocity := ground_velocity + Vector2(0.0, -vertical_velocity * _arc_visibility)
	if visual_velocity.length_squared() > 0.0001:
		_apply_visual_rotation(visual_velocity.angle())

func _apply_visual_rotation(visual_angle: float) -> void:
	if _visual_root == null:
		return
	_visual_root.global_rotation = visual_angle + deg_to_rad(visual_rotation_offset_deg)

func _set_visual_alpha(alpha: float) -> void:
	var color := modulate
	color.a = clampf(alpha, 0.0, 1.0)
	modulate = color

func _get_player_node() -> Node2D:
	if _player_ref != null:
		var cached := _player_ref.get_ref() as Node2D
		if cached != null and is_instance_valid(cached):
			return cached

	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return null

	var player := players[0] as Node2D
	if player != null:
		_player_ref = weakref(player)
	return player

func _is_owner_related_area(area: Area2D) -> bool:
	return CombatQueryScript.is_owner_related(_get_owner_node(), area)

func _is_owner_related_node(node: Node) -> bool:
	return CombatQueryScript.is_owner_related(_get_owner_node(), node)

func _get_owner_node() -> Node:
	if _owner_ref == null:
		return null

	var owner_node := _owner_ref.get_ref() as Node
	if owner_node == null or not is_instance_valid(owner_node):
		_owner_ref = null
		return null

	return owner_node

func _damage_generic_wall(hit: Dictionary) -> void:
	var worlds := get_tree().get_nodes_in_group("world")
	if worlds.is_empty():
		return
	var world := worlds[0]
	if world == null:
		return

	var hit_pos: Vector2 = hit.get("position", global_position)
	var wall_amount: int = maxi(1, wall_damage)
	var wall_radius: float = 12.0

	if world.has_method("hit_wall_at_world_pos"):
		world.call("hit_wall_at_world_pos", hit_pos, wall_amount, wall_radius, true)
		return
	if world.has_method("damage_player_wall_at_world_pos"):
		world.call("damage_player_wall_at_world_pos", hit_pos, wall_amount)
