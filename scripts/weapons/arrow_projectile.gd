extends Area2D
class_name ArrowProjectile

@export var damage: int = 12
@export var knockback: float = 180.0
@export var life_time: float = 2.5
@export var gravity: float = 900.0
@export var stuck_life_time: float = 15.0
@export var max_distance_from_player: float = 1500.0
@export var distance_check_interval: float = 0.4

var velocity: Vector2 = Vector2.ZERO
var _time_left: float = 0.0
var _owner: Node = null
var _stuck: bool = false
var _distance_check_left: float = 0.0
var _player_ref: WeakRef = null

func setup(p_velocity: Vector2, p_damage: int, p_knockback: float, p_owner: Node = null) -> void:
	velocity = p_velocity
	damage = p_damage
	knockback = p_knockback
	_owner = p_owner
	_time_left = life_time
	_stuck = false
	_distance_check_left = distance_check_interval

func _ready() -> void:
	_time_left = life_time
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	if _stuck:
		_tick_stuck_state(delta)
		return

	velocity.y += gravity * delta
	global_position += velocity * delta

	if velocity.length_squared() > 0.0001:
		rotation = velocity.angle()

	_time_left -= delta
	if _time_left <= 0.0:
		queue_free()

func _on_area_entered(area: Area2D) -> void:
	if _stuck:
		return

	if area == null:
		return

	if _is_owner_related_area(area):
		return

	var is_hurtbox := area is CharacterHurtbox
	if not is_hurtbox and area.has_method("receive_hit"):
		is_hurtbox = true

	if not is_hurtbox:
		return

	if area.has_method("receive_hit"):
		area.receive_hit(damage, knockback, global_position)

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
	if _owner == null:
		return false

	if area == _owner:
		return true

	var current: Node = area
	while current != null:
		if current == _owner:
			return true
		current = current.get_parent()

	# `Node.owner` puede apuntar al owner de escena (PackedScene), que a veces es
	# compartido por nodos no relacionados en runtime. Solo ignoramos por owner
	# cuando hay igualdad exacta para evitar filtrar enemigos válidos.
	var area_owner := area.owner
	if area_owner == _owner:
		return true

	return false

func _is_owner_related_node(node: Node) -> bool:
	if _owner == null or node == null:
		return false

	if node == _owner:
		return true

	var current: Node = node
	while current != null:
		if current == _owner:
			return true
		current = current.get_parent()

	return false
