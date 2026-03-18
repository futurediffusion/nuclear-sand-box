extends Node2D
class_name CarryComponent

@export var stack_base_offset: Vector2 = Vector2(0, -30)
@export var stack_item_offset: Vector2 = Vector2(0, -15)

var _carried_nodes: Array[Node2D] = []
var _carry_anchor: Marker2D

func _ready() -> void:
	_carry_anchor = Marker2D.new()
	_carry_anchor.name = "CarryAnchor"
	_carry_anchor.position = stack_base_offset
	add_child(_carry_anchor)

func can_pickup(node: Node2D) -> bool:
	if not is_instance_valid(node):
		return false
	var carryable = node.get_node_or_null("CarryableComponent")
	if carryable != null and carryable.has_method("can_pickup"):
		return carryable.can_pickup()
	return false

func try_pickup(node: Node2D) -> bool:
	if not can_pickup(node):
		return false

	var carryable = node.get_node("CarryableComponent")
	if carryable.has_method("pickup"):
		carryable.pickup(_carry_anchor)
		_carried_nodes.append(node)
		_update_stack_positions()
		return true

	return false

func release_all() -> void:
	force_drop_all()

func force_drop_all() -> void:
	for i in range(_carried_nodes.size() - 1, -1, -1):
		var node = _carried_nodes[i]
		if is_instance_valid(node):
			var carryable = node.get_node_or_null("CarryableComponent")
			if carryable != null and carryable.has_method("drop"):
				carryable.drop()
	_carried_nodes.clear()

func is_carrying() -> bool:
	# Filter out any invalid nodes first
	_clean_invalid_nodes()
	return _carried_nodes.size() > 0

func get_carried_count() -> int:
	_clean_invalid_nodes()
	return _carried_nodes.size()

func _clean_invalid_nodes() -> void:
	var valid_nodes: Array[Node2D] = []
	for node in _carried_nodes:
		if is_instance_valid(node) and not node.is_queued_for_deletion():
			valid_nodes.append(node)
	if valid_nodes.size() != _carried_nodes.size():
		_carried_nodes = valid_nodes
		_update_stack_positions()

func _update_stack_positions() -> void:
	for i in range(_carried_nodes.size()):
		var node = _carried_nodes[i]
		if is_instance_valid(node):
			var carryable = node.get_node_or_null("CarryableComponent")
			if carryable != null:
				# Override the internal offset or move the node directly
				# Since CarryableComponent manages its own offset internally, we can adjust the item relative to the anchor
				# CarryableComponent puts the item at its carry_offset relative to the carrier (our anchor)
				# So we just update carryable's carry_offset
				if "carry_offset" in carryable:
					carryable.carry_offset = stack_item_offset * i

				# If we want to animate it right now:
				var tw = create_tween()
				tw.tween_property(node, "position", stack_item_offset * i, 0.15).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
