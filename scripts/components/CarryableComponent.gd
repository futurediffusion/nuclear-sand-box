extends Node
class_name CarryableComponent

@export var carry_offset: Vector2 = Vector2(0, -20)
@export var disable_collision_on_carry: bool = true

var _parent: Node2D
var _carrier: Node2D = null
var _original_parent: Node = null
var _original_collision_layer: int = 1
var _original_collision_mask: int = 1
var _is_carried: bool = false

func _ready() -> void:
	_parent = get_parent() as Node2D
	if _parent == null:
		push_warning("CarryableComponent must be a child of a Node2D.")
		return

	_parent.add_to_group("carryable")

func can_pickup() -> bool:
	return not _is_carried

func pickup(carrier: Node2D) -> void:
	if _is_carried or carrier == null or _parent == null:
		return

	_is_carried = true
	_carrier = carrier

	# Store original state
	_original_parent = _parent.get_parent()
	if _parent is CollisionObject2D and disable_collision_on_carry:
		_original_collision_layer = _parent.collision_layer
		_original_collision_mask = _parent.collision_mask
		_parent.collision_layer = 0
		_parent.collision_mask = 0

	# Reparent to carrier
	if _original_parent != null:
		var global_pos = _parent.global_position
		_original_parent.remove_child(_parent)
		_carrier.add_child(_parent)
		_parent.global_position = global_pos

func update_carry_position(target_offset: Vector2) -> void:
	if not _is_carried or _parent == null:
		return

	carry_offset = target_offset
	var tw = create_tween()
	tw.tween_property(_parent, "position", target_offset, 0.15).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func drop(scatter: bool = false) -> void:
	if not _is_carried or _parent == null:
		return

	_is_carried = false

	var global_drop_pos = _parent.global_position

	# Restore parent
	if _carrier != null:
		_carrier.remove_child(_parent)

	if _original_parent != null:
		_original_parent.add_child(_parent)
	else:
		get_tree().current_scene.add_child(_parent)

	_parent.global_position = global_drop_pos

	if scatter:
		var random_offset = Vector2(randf_range(-15, 15), randf_range(-15, 15))
		var tw = create_tween()
		tw.tween_property(_parent, "global_position", global_drop_pos + random_offset, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	else:
		# Just drop straight down (simulate placing)
		var tw = create_tween()
		tw.tween_property(_parent, "global_position", global_drop_pos, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# Restore collision
	if _parent is CollisionObject2D and disable_collision_on_carry:
		_parent.collision_layer = _original_collision_layer
		_parent.collision_mask = _original_collision_mask

	_carrier = null
	_original_parent = null
