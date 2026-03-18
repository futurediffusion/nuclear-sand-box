extends Node2D
class_name CarryComponent

const _FALLBACK_PICKUP_SFX: AudioStream = preload("res://art/Sounds/pickup.ogg")

@export var stack_base_offset: Vector2 = Vector2(0, -18)
@export var stack_item_offset: Vector2 = Vector2(0, -8)

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
	_drop_all(false)

func force_drop_all() -> void:
	_drop_all(true)

func _drop_all(scatter: bool) -> void:
	for i in range(_carried_nodes.size() - 1, -1, -1):
		var node = _carried_nodes[i]
		if is_instance_valid(node):
			var carryable = node.get_node_or_null("CarryableComponent")
			if carryable != null and carryable.has_method("drop"):
				carryable.drop(scatter)
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

func get_carried_nodes() -> Array[Node2D]:
	_clean_invalid_nodes()
	return _carried_nodes.duplicate()

## Remove a single node from carry without scattering.
## Use for items being consumed (e.g. transferred to chest).
func consume_node(node: Node2D) -> void:
	var idx := _carried_nodes.find(node)
	if idx == -1:
		return
	_carried_nodes.remove_at(idx)
	if is_instance_valid(node):
		var carryable := node.get_node_or_null("CarryableComponent")
		if carryable != null and carryable.has_method("drop"):
			carryable.drop(false)
	_update_stack_positions()

## Intentional release: deposits ItemDrop nodes into a nearby chest if one exists,
## then releases any remaining carried nodes normally.
## Bodies (CharacterBase) are never deposited and are released instead.
func release_with_chest_check() -> void:
	if not is_carrying():
		return
	var origin := (get_parent() as Node2D)
	if origin == null:
		release_all()
		return
	var chest := _find_nearby_chest(origin.global_position)
	if chest == null:
		release_all()
		return
	_dump_to_chest(chest, origin.global_position)
	# Release anything that didn't go into the chest (bodies, chest full, etc.)
	if is_carrying():
		release_all()

func _find_nearby_chest(pos: Vector2) -> ContainerPlaceable:
	for node in get_tree().get_nodes_in_group("interactable"):
		if node is ContainerPlaceable:
			var chest := node as ContainerPlaceable
			if chest.is_position_nearby(pos):
				return chest
	return null

func _dump_to_chest(chest: ContainerPlaceable, origin_pos: Vector2) -> void:
	var to_deposit := get_carried_nodes()
	var sound_index := 0
	for node in to_deposit:
		if not is_instance_valid(node):
			continue
		# Bodies cannot go into chests
		if node is CharacterBase:
			continue
		if not (node is ItemDrop):
			continue
		var item_drop := node as ItemDrop
		var item_id := item_drop.item_id
		var amount := item_drop.amount
		if item_id == "" or amount <= 0:
			continue
		var inserted := chest.try_insert_item(item_id, amount)
		if inserted <= 0:
			continue
		consume_node(node)
		item_drop.queue_free()
		# Staggered pickup sound (tutututu)
		var sfx: AudioStream = item_drop.pickup_sfx
		if sfx == null:
			sfx = _FALLBACK_PICKUP_SFX
		if sfx != null:
			var delay := sound_index * 0.09
			if delay == 0.0:
				AudioSystem.play_2d(sfx, origin_pos, null, &"SFX")
			else:
				get_tree().create_timer(delay).timeout.connect(
					func(): if is_instance_valid(self): AudioSystem.play_2d(sfx, origin_pos, null, &"SFX")
				)
		sound_index += 1

func _update_stack_positions() -> void:
	for i in range(_carried_nodes.size()):
		var node = _carried_nodes[i]
		if is_instance_valid(node):
			var carryable = node.get_node_or_null("CarryableComponent")
			if carryable != null and carryable.has_method("update_carry_position"):
				var target_offset = stack_item_offset * i
				carryable.update_carry_position(target_offset)
