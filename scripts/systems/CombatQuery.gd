class_name CombatQuery
extends RefCounted

const CollisionLayersScript := preload("res://scripts/systems/CollisionLayers.gd")

static func has_wall_between(context: Node, from_pos: Vector2, to_pos: Vector2, excluded_nodes: Array = []) -> bool:
	if context == null:
		return false
	if from_pos == to_pos:
		return false
	return not find_first_wall_hit(context, from_pos, to_pos, excluded_nodes).is_empty()

static func find_first_wall_hit(context: Node, from_pos: Vector2, to_pos: Vector2, excluded_nodes: Array = []) -> Dictionary:
	if context == null:
		return {}
	if from_pos == to_pos:
		return {}

	var query := PhysicsRayQueryParameters2D.create(from_pos, to_pos)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.collision_mask = CollisionLayersScript.WORLD_WALL_LAYER_MASK
	query.exclude = _collect_excluded_rids(context, excluded_nodes)

	var space_state := context.get_world_2d().direct_space_state
	var hit := space_state.intersect_ray(query)
	if hit.is_empty():
		return {}

	var collider := hit.get("collider")
	if not is_wall_collider(collider):
		return {}
	return hit

static func is_wall_collider(collider: Variant) -> bool:
	if not (collider is CollisionObject2D):
		return false
	var collision_object := collider as CollisionObject2D
	return collision_object.get_collision_layer_value(CollisionLayersScript.WORLD_WALL_LAYER_BIT)

static func _collect_excluded_rids(context: Node, excluded_nodes: Array) -> Array[RID]:
	var excluded: Array[RID] = []
	if context is CollisionObject2D:
		excluded.append((context as CollisionObject2D).get_rid())

	for item in excluded_nodes:
		if item is CollisionObject2D:
			var rid := (item as CollisionObject2D).get_rid()
			if not excluded.has(rid):
				excluded.append(rid)

	return excluded
