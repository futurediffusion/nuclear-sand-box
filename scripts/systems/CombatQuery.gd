class_name CombatQuery
extends RefCounted

const CollisionLayersScript := preload("res://scripts/systems/CollisionLayers.gd")

static func has_wall_between(context: Node, from_pos: Vector2, to_pos: Vector2, excluded_nodes: Array = []) -> bool:
	if context == null:
		return false
	if from_pos == to_pos:
		return false
	# Tilemap-based check (primary): cubre toda el área del tile, no solo las bandas delgadas de CollisionBuilder
	if WorldSave.wall_tile_blocker_fn.is_valid():
		if WorldSave.wall_tile_blocker_fn.call(from_pos, to_pos):
			return true
	# Raycast de físicas (fallback): para cuerpos de pared que no son tiles
	return not find_first_wall_hit(context, from_pos, to_pos, excluded_nodes).is_empty()

static func is_owner_related(owner_node: Node, candidate: Node) -> bool:
	if owner_node == null or candidate == null:
		return false
	if candidate == owner_node:
		return true

	var current: Node = candidate
	while current != null:
		if current == owner_node:
			return true
		current = current.get_parent()

	if candidate.owner == owner_node:
		return true

	return false

static func resolve_damage_target(raw_target: Node) -> Dictionary:
	if raw_target == null:
		return {}

	var hurtbox: Area2D = null
	if raw_target is CharacterHurtbox:
		hurtbox = raw_target as Area2D

	var entity := _resolve_entity_with_damage_methods(raw_target)
	if entity == null and hurtbox != null:
		entity = _resolve_entity_with_damage_methods(hurtbox.get_parent())

	if entity == null:
		return {}

	return {
		"entity": entity,
		"hurtbox": hurtbox,
		"raw": raw_target,
	}

static func is_melee_target_blocked_by_wall(
		context: Node,
		from_pos: Vector2,
		target_entity: Node,
		target_hurtbox: Area2D = null,
		excluded_nodes: Array = []
	) -> bool:
	if context == null or not (target_entity is Node2D):
		return false

	var target_points := _collect_melee_target_points(target_entity as Node2D, target_hurtbox)
	for point in target_points:
		if not has_wall_between(context, from_pos, point, excluded_nodes):
			return false

	return true

static func find_first_wall_hit(
		context: Node,
		from_pos: Vector2,
		to_pos: Vector2,
		excluded_nodes: Array = [],
		hit_from_inside: bool = false
	) -> Dictionary:
	if context == null:
		return {}
	if from_pos == to_pos:
		return {}

	var query := PhysicsRayQueryParameters2D.create(from_pos, to_pos)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.collision_mask = CollisionLayersScript.WORLD_WALL_LAYER_MASK
	query.exclude = _collect_excluded_rids(context, excluded_nodes)
	query.hit_from_inside = hit_from_inside

	var world_2d: World2D = context.get_world_2d()
	if world_2d == null:
		return {}

	var space_state: PhysicsDirectSpaceState2D = world_2d.direct_space_state
	var hit: Dictionary = space_state.intersect_ray(query)
	if hit.is_empty():
		return {}

	var collider: Variant = hit.get("collider", null)
	if not is_wall_collider(collider):
		return {}
	return hit

static func shape_overlaps_wall(
		context: Node,
		shape_node: CollisionShape2D,
		excluded_nodes: Array = []
	) -> bool:
	if context == null or shape_node == null or shape_node.shape == null:
		return false

	var world_2d: World2D = context.get_world_2d()
	if world_2d == null:
		return false

	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = shape_node.shape
	params.transform = shape_node.global_transform
	params.collide_with_areas = true
	params.collide_with_bodies = true
	params.collision_mask = CollisionLayersScript.WORLD_WALL_LAYER_MASK
	params.exclude = _collect_excluded_rids(context, excluded_nodes)

	var space_state: PhysicsDirectSpaceState2D = world_2d.direct_space_state
	var results := space_state.intersect_shape(params, 32)
	for result in results:
		var collider: Variant = result.get("collider", null)
		if collider is CollisionObject2D:
			# Props destructibles (WALLPROPS + Resources) no bloquean el slash — solo muros reales
			if not (collider as CollisionObject2D).get_collision_layer_value(CollisionLayersScript.RESOURCES_LAYER_BIT):
				return true
	return false

static func is_wall_collider(collider: Variant) -> bool:
	if not (collider is CollisionObject2D):
		return false
	var collision_object := collider as CollisionObject2D
	return collision_object.get_collision_layer_value(CollisionLayersScript.WORLD_WALL_LAYER_BIT)

static func _resolve_entity_with_damage_methods(start_node: Node) -> Node:
	var current := start_node
	while current != null:
		if current.has_method("take_damage") or current.has_method("hit"):
			return current
		current = current.get_parent()
	return null

static func _collect_melee_target_points(target_entity: Node2D, target_hurtbox: Area2D = null) -> Array[Vector2]:
	var points: Array[Vector2] = [target_entity.global_position]

	if target_hurtbox != null:
		points.append(target_hurtbox.global_position)
		var shape_node := target_hurtbox.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if shape_node != null and shape_node.shape != null:
			points.append_array(_sample_points_from_shape(shape_node))

	return _dedupe_points(points)

static func _sample_points_from_shape(shape_node: CollisionShape2D) -> Array[Vector2]:
	var shape := shape_node.shape
	var samples: Array[Vector2] = [shape_node.global_position]

	if shape is RectangleShape2D:
		var extents := (shape as RectangleShape2D).size * 0.5
		samples.append(shape_node.to_global(Vector2(extents.x, 0.0)))
		samples.append(shape_node.to_global(Vector2(-extents.x, 0.0)))
		samples.append(shape_node.to_global(Vector2(0.0, extents.y)))
		samples.append(shape_node.to_global(Vector2(0.0, -extents.y)))
	elif shape is CircleShape2D:
		var radius := (shape as CircleShape2D).radius
		samples.append(shape_node.to_global(Vector2(radius, 0.0)))
		samples.append(shape_node.to_global(Vector2(-radius, 0.0)))
		samples.append(shape_node.to_global(Vector2(0.0, radius)))
		samples.append(shape_node.to_global(Vector2(0.0, -radius)))
	elif shape is CapsuleShape2D:
		var capsule := shape as CapsuleShape2D
		var half_height := capsule.height * 0.5
		samples.append(shape_node.to_global(Vector2(capsule.radius, 0.0)))
		samples.append(shape_node.to_global(Vector2(-capsule.radius, 0.0)))
		samples.append(shape_node.to_global(Vector2(0.0, half_height)))
		samples.append(shape_node.to_global(Vector2(0.0, -half_height)))

	return samples

static func _dedupe_points(points: Array[Vector2]) -> Array[Vector2]:
	var deduped: Array[Vector2] = []
	for point in points:
		var exists := false
		for stored in deduped:
			if stored.distance_squared_to(point) <= 0.25:
				exists = true
				break
		if not exists:
			deduped.append(point)
	return deduped

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
