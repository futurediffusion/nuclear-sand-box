extends Area2D
class_name ArrowProjectile

@export var damage: int = 12
@export var knockback: float = 180.0
@export var life_time: float = 2.5
@export var projectile_gravity: float = 900.0
@export var stuck_life_time: float = 15.0
@export var max_distance_from_player: float = 1500.0
@export var distance_check_interval: float = 0.4
@export var prefer_hurtbox_over_world: bool = true
@export var debug_hit_logs: bool = false

var velocity: Vector2 = Vector2.ZERO
var _time_left: float = 0.0
var _owner_ref: WeakRef = null
var _stuck: bool = false
var _ignore_first_frames: int = 0
var _distance_check_left: float = 0.0
var _player_ref: WeakRef = null

func setup(p_velocity: Vector2, p_damage: int, p_knockback: float, p_owner: Node = null) -> void:
	velocity = p_velocity
	damage = p_damage
	knockback = p_knockback
	_owner_ref = weakref(p_owner) if p_owner != null else null
	_time_left = life_time
	_stuck = false
	_ignore_first_frames = 2
	_distance_check_left = distance_check_interval

func _ready() -> void:
	_time_left = life_time
	_ignore_first_frames = 2
	monitoring = false
	monitorable = false
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)
	call_deferred("_enable_collision")

func _enable_collision() -> void:
	if _stuck:
		return
	monitoring = true
	monitorable = true

func _physics_process(delta: float) -> void:
	if _stuck:
		_tick_stuck_state(delta)
		return

	if _ignore_first_frames > 0:
		_ignore_first_frames -= 1
		velocity.y += projectile_gravity * delta
		global_position += velocity * delta

		if velocity.length_squared() > 0.0001:
			rotation = velocity.angle()

		_time_left -= delta
		if _time_left <= 0.0:
			queue_free()
		return

	var prev_pos := global_position
	velocity.y += projectile_gravity * delta
	var next_pos := prev_pos + velocity * delta

	if _sweep_hit(prev_pos, next_pos):
		return

	global_position = next_pos

	if velocity.length_squared() > 0.0001:
		rotation = velocity.angle()

	_time_left -= delta
	if _time_left <= 0.0:
		queue_free()

func _sweep_hit(from_pos: Vector2, to_pos: Vector2) -> bool:
	if from_pos == to_pos:
		return false

	var area_hit := _raycast_between(from_pos, to_pos, true, false)
	var body_hit := _raycast_between(from_pos, to_pos, false, true)

	if prefer_hurtbox_over_world and _handle_area_hit(area_hit):
		return true
	if _handle_body_hit(body_hit):
		return true
	if _handle_area_hit(area_hit):
		return true

	return false

func _raycast_between(from_pos: Vector2, to_pos: Vector2, collide_areas: bool, collide_bodies: bool) -> Dictionary:
	var space_state := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(from_pos, to_pos)
	query.collide_with_areas = collide_areas
	query.collide_with_bodies = collide_bodies
	query.collision_mask = collision_mask
	var excluded: Array[RID] = [get_rid()]
	var owner_node := _get_owner_node()
	if owner_node is CollisionObject2D:
		excluded.append((owner_node as CollisionObject2D).get_rid())
	query.exclude = excluded
	return space_state.intersect_ray(query)

func _handle_area_hit(hit: Dictionary) -> bool:
	if hit.is_empty():
		return false

	var area := hit.get("collider") as Area2D
	_dbg_area(area)
	if area == null:
		return false
	if _is_owner_related_area(area):
		return false

	var is_hurtbox := area is CharacterHurtbox
	if not is_hurtbox and area.has_method("take_damage"):
		is_hurtbox = true
	if not is_hurtbox:
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

	if body is TileMap or body is StaticBody2D:
		_stick_to_world()
		return true

	return false

func _on_area_entered(area: Area2D) -> void:
	if _stuck:
		return

	if area == null:
		return

	if _is_owner_related_area(area):
		return

	var is_hurtbox := area is CharacterHurtbox
	if not is_hurtbox and area.has_method("take_damage"):
		is_hurtbox = true

	if not is_hurtbox:
		return

	global_position = area.global_position
	if area.has_method("take_damage"):
		area.take_damage(damage, global_position)

	queue_free()

func _on_body_entered(body: Node2D) -> void:
	if _stuck:
		return

	if body == null:
		return

	if _is_owner_related_node(body):
		return

	if body is TileMap or body is StaticBody2D:
		_stick_to_world()
		return

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
	_stuck = true
	velocity = Vector2.ZERO
	_time_left = stuck_life_time
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)

func _tick_stuck_state(delta: float) -> void:
	_time_left -= delta
	if _time_left <= 0.0:
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
	var owner_node := _get_owner_node()
	if owner_node == null:
		return false

	if area == owner_node:
		return true

	var current: Node = area
	while current != null:
		if current == owner_node:
			return true
		current = current.get_parent()

	# `Node.owner` puede apuntar al owner de escena (PackedScene), que a veces es
	# compartido por nodos no relacionados en runtime. Solo ignoramos por owner
	# cuando hay igualdad exacta para evitar filtrar enemigos válidos.
	var area_owner := area.owner
	if area_owner == owner_node:
		return true

	return false

func _is_owner_related_node(node: Node) -> bool:
	var owner_node := _get_owner_node()
	if owner_node == null or node == null:
		return false

	if node == owner_node:
		return true

	var current: Node = node
	while current != null:
		if current == owner_node:
			return true
		current = current.get_parent()

	return false

func _get_owner_node() -> Node:
	if _owner_ref == null:
		return null

	var owner_node := _owner_ref.get_ref() as Node
	if owner_node == null or not is_instance_valid(owner_node):
		_owner_ref = null
		return null

	return owner_node
