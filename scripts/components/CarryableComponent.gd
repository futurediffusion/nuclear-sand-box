extends Node
class_name CarryableComponent

@export var carry_offset: Vector2 = Vector2(0, -20)
@export var disable_collision_on_carry: bool = true
@export var drop_ground_offset: Vector2 = Vector2(0, 0)

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

	# Save elevated carry position BEFORE reparenting (coordinate space changes after)
	var carry_global_pos := _parent.global_position

	# Compute landing target from player ground plane
	var global_drop_pos: Vector2
	if _carrier != null and is_instance_valid(_carrier) and _carrier.get_parent() != null:
		global_drop_pos = _carrier.get_parent().global_position + drop_ground_offset
	else:
		global_drop_pos = carry_global_pos

	# Restore parent
	if _carrier != null:
		_carrier.remove_child(_parent)
	if _original_parent != null:
		_original_parent.add_child(_parent)
	else:
		get_tree().current_scene.add_child(_parent)

	# Keep item at its elevated carry position so the fall tween is visible
	_parent.global_position = carry_global_pos

	# Restore collision
	if _parent is CollisionObject2D and disable_collision_on_carry:
		_parent.collision_layer = _original_collision_layer
		_parent.collision_mask = _original_collision_mask

	# Reset magnet so it doesn't fight the fall tween
	if _parent.has_method("reset_magnet_delay"):
		_parent.reset_magnet_delay()

	if scatter:
		var random_offset = Vector2(randf_range(-15, 15), randf_range(-15, 15))
		var tw = create_tween()
		tw.tween_property(_parent, "global_position", global_drop_pos + random_offset, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	else:
		var tw = create_tween()
		tw.tween_property(_parent, "global_position", global_drop_pos, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	_carrier = null
	_original_parent = null
