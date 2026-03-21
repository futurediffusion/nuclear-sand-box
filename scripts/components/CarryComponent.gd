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
	var carrier := get_parent()
	var carrier_is_player := carrier != null and carrier.is_in_group("player")
	for node in get_tree().get_nodes_in_group("interactable"):
		if node is ContainerPlaceable:
			var chest := node as ContainerPlaceable
			# Player: use the precise Area2D detection (has_player_nearby).
			# Others: fall back to distance check.
			var nearby := (carrier_is_player and chest.has_player_nearby()) \
				or chest.is_position_nearby(pos)
			if nearby:
				return chest
	return null

func _dump_to_chest(chest: ContainerPlaceable, origin_pos: Vector2) -> void:
	var to_deposit := get_carried_nodes()
	const FALL_TIME:   float = 0.25   # CarryableComponent.drop tween duration
	const SFX_STAGGER: float = 0.07

	var idx := 0
	for node in to_deposit:
		if not is_instance_valid(node):
			continue
		if node is CharacterBase:
			continue
		if not (node is ItemDrop):
			continue
		var item_drop := node as ItemDrop
		if item_drop.item_id == "" or item_drop.amount <= 0:
			continue

		var cap_item_id := item_drop.item_id
		var cap_amount  := item_drop.amount
		# Usar sfx del item; si es null, AudioSystem.play_2d usará su propio fallback
		var cap_sfx: AudioStream = item_drop.pickup_sfx

		# Dispara la caída: CarryableComponent.drop(false) reparenta al mundo en
		# posición elevada y hace tween de caída de 0.25 s hacia el suelo.
		consume_node(node)

		# Congelar el magnet para que el item no se re-colecte durante la caída.
		item_drop.set("_magnet_on", false)
		var magnet_timer := item_drop.get_node_or_null("MagnetDelay") as Timer
		if magnet_timer != null:
			magnet_timer.stop()
		item_drop.set_deferred("monitoring", false)

		# Al aterrizar: sfx (tururur) + depositar en cofre + liberar nodo.
		var land_delay := FALL_TIME + idx * SFX_STAGGER
		var cap_drop   := item_drop
		get_tree().create_timer(land_delay).timeout.connect(func() -> void:
			if not is_instance_valid(cap_drop) or cap_drop.is_queued_for_deletion():
				return
			var inserted := chest.try_insert_item(cap_item_id, cap_amount)
			if inserted > 0:
				var sfx := cap_sfx if cap_sfx != null else AudioSystem.default_pickup_sfx
				AudioSystem.play_2d(sfx, origin_pos)
				cap_drop.queue_free()
			else:
				# Cofre lleno — re-activar el item para recoger manualmente
				cap_drop.set_deferred("monitoring", true)
		)
		idx += 1

func _update_stack_positions() -> void:
	for i in range(_carried_nodes.size()):
		var node = _carried_nodes[i]
		if is_instance_valid(node):
			var carryable = node.get_node_or_null("CarryableComponent")
			if carryable != null and carryable.has_method("update_carry_position"):
				var target_offset = stack_item_offset * i
				carryable.update_carry_position(target_offset)
