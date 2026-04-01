extends RefCounted
class_name BanditWallAssaultPolicy

## Canonical owner for wall-assault intent decisions.
## Consumers must execute returned directives and avoid re-deciding target intent.

const INVALID_TARGET: Vector2 = Vector2(-1.0, -1.0)

const RAID_ENGAGE_RADIUS_SQ: float = 260.0 * 260.0
const RAID_TARGET_SEARCH_RADIUS: float = 180.0
const RAID_LOCAL_WALL_PROBE_RADIUS: float = 180.0
const RAID_LOCAL_WALL_STRIKE_RANGE_SQ: float = 164.0 * 164.0
const STRUCTURE_TARGET_VALIDATION_RADIUS: float = 72.0
const STRUCTURE_WALL_TARGET_VALIDATION_RADIUS: float = 42.0

const STRUCTURE_ATTACK_COOLDOWN: float = 0.45
const STRUCTURE_LOOT_COOLDOWN: float = 1.10
const BREACH_TO_LOOT_DELAY: float = 0.05
const OPPORTUNISTIC_WALL_COOLDOWN: float = 20.0
const PROPERTY_SABOTAGE_COOLDOWN: float = 35.0


static func is_valid_target(pos: Vector2) -> bool:
	return pos.is_finite() and not pos.is_equal_approx(INVALID_TARGET)


static func evaluate_structure_directive(ctx: Dictionary) -> Dictionary:
	var world_node: Node = ctx.get("world_node")
	if world_node == null or not is_instance_valid(world_node):
		return {"allow": false, "reason": "world_unavailable"}

	var has_raid_context: bool = bool(ctx.get("has_raid_context", false))
	if not has_raid_context:
		return {"allow": false, "reason": "no_raid_context"}

	var now: float = float(ctx.get("now", 0.0))
	var attack_next_at: float = float(ctx.get("attack_next_at", 0.0))
	if now < attack_next_at:
		return {"allow": false, "reason": "attack_cooldown"}

	var enemy_pos: Vector2 = ctx.get("enemy_pos", INVALID_TARGET) as Vector2
	var group_anchor: Vector2 = ctx.get("group_anchor", INVALID_TARGET) as Vector2
	var member_anchor: Vector2 = ctx.get("member_anchor", INVALID_TARGET) as Vector2
	var attack_anchor: Vector2 = member_anchor if is_valid_target(member_anchor) else group_anchor
	if not is_valid_target(attack_anchor):
		attack_anchor = enemy_pos
	var canonical_target: Vector2 = ctx.get("canonical_target", INVALID_TARGET) as Vector2
	var consume_canonical_only: bool = bool(ctx.get("consume_canonical_only", false))

	var engaged_by_group: bool = is_valid_target(group_anchor) \
			and enemy_pos.distance_squared_to(group_anchor) <= RAID_ENGAGE_RADIUS_SQ
	var engaged_by_member: bool = is_valid_target(member_anchor) \
			and enemy_pos.distance_squared_to(member_anchor) <= RAID_ENGAGE_RADIUS_SQ
	if not engaged_by_group and not engaged_by_member:
		return {"allow": false, "reason": "out_of_engage_radius"}

	var target: Dictionary = {}
	if is_valid_target(canonical_target):
		target = _resolve_canonical_target(world_node, canonical_target, enemy_pos)
		if target.is_empty() and consume_canonical_only:
			return {"allow": false, "reason": "canonical_target_missing"}
	else:
		target = _resolve_raid_priority_target(world_node, attack_anchor, enemy_pos)
	if not target.is_empty():
		var attack_range_sq: float = float(ctx.get("attack_range_sq", 0.0))
		if attack_range_sq > 0.0:
			var target_pos: Vector2 = target.get("pos", INVALID_TARGET) as Vector2
			if enemy_pos.distance_squared_to(target_pos) > attack_range_sq:
				return {"allow": false, "reason": "out_of_range"}
		target["allow"] = true
		target["reason"] = "target_resolved"
		target["next_attack_at"] = now + STRUCTURE_ATTACK_COOLDOWN
		return target

	if consume_canonical_only:
		return {"allow": false, "reason": "canonical_target_missing"}

	var fallback_wall: Vector2 = _resolve_local_wall_fallback(world_node, enemy_pos, attack_anchor, group_anchor)
	if is_valid_target(fallback_wall):
		return {
			"allow": true,
			"reason": "fallback_wall",
			"kind": "wall",
			"pos": fallback_wall,
			"next_attack_at": now + STRUCTURE_ATTACK_COOLDOWN,
		}

	return {"allow": false, "reason": "no_attack_target"}


static func can_transition_breach_to_loot(ctx: Dictionary) -> Dictionary:
	var has_raid_context: bool = bool(ctx.get("has_raid_context", false))
	if not has_raid_context:
		return {"allow": false, "reason": "no_raid_context"}

	var now: float = float(ctx.get("now", 0.0))
	var breach_resolved_at: float = float(ctx.get("breach_resolved_at", 0.0))
	if breach_resolved_at <= 0.0:
		return {"allow": false, "reason": "breach_unresolved"}
	if now < breach_resolved_at + BREACH_TO_LOOT_DELAY:
		return {"allow": false, "reason": "breach_settling"}

	var loot_next_at: float = float(ctx.get("loot_next_at", 0.0))
	if now < loot_next_at:
		return {"allow": false, "reason": "loot_cooldown"}

	var enemy_pos: Vector2 = ctx.get("enemy_pos", INVALID_TARGET) as Vector2
	var loot_anchor: Vector2 = ctx.get("loot_anchor", INVALID_TARGET) as Vector2
	if not is_valid_target(enemy_pos) or not is_valid_target(loot_anchor):
		return {"allow": false, "reason": "invalid_loot_anchor"}

	var loot_range_sq: float = float(ctx.get("loot_range_sq", 0.0))
	if loot_range_sq > 0.0 and enemy_pos.distance_squared_to(loot_anchor) > loot_range_sq:
		return {"allow": false, "reason": "loot_out_of_range"}

	return {"allow": true, "reason": "breach_resolved"}


static func _resolve_canonical_target(world_node: Node, target_hint: Vector2, enemy_pos: Vector2) -> Dictionary:
	var placeable_node: Node2D = _find_nearest_player_structure_node(world_node, enemy_pos, target_hint)
	var placeable_pos: Vector2 = placeable_node.global_position if placeable_node != null else INVALID_TARGET

	var wall_pos: Vector2 = INVALID_TARGET
	if world_node.has_method("find_nearest_player_wall_world_pos"):
		wall_pos = world_node.call("find_nearest_player_wall_world_pos", target_hint, STRUCTURE_TARGET_VALIDATION_RADIUS) as Vector2

	var has_placeable: bool = placeable_node != null \
			and is_instance_valid(placeable_node) \
			and not placeable_node.is_queued_for_deletion() \
			and is_valid_target(placeable_pos) \
			and placeable_pos.distance_squared_to(target_hint) <= STRUCTURE_TARGET_VALIDATION_RADIUS * STRUCTURE_TARGET_VALIDATION_RADIUS
	var has_wall: bool = is_valid_target(wall_pos) \
			and wall_pos.distance_squared_to(target_hint) <= STRUCTURE_WALL_TARGET_VALIDATION_RADIUS * STRUCTURE_WALL_TARGET_VALIDATION_RADIUS

	if not has_placeable and not has_wall:
		return {}
	if has_placeable and not has_wall:
		return {"kind": "placeable", "pos": placeable_pos, "node": placeable_node}
	if has_wall and not has_placeable:
		return {"kind": "wall", "pos": wall_pos}

	var d_placeable: float = enemy_pos.distance_squared_to(placeable_pos)
	var d_wall: float = enemy_pos.distance_squared_to(wall_pos)
	if d_placeable <= d_wall:
		return {"kind": "placeable", "pos": placeable_pos, "node": placeable_node}
	return {"kind": "wall", "pos": wall_pos}


static func evaluate_opportunistic_wall_order(ctx: Dictionary) -> Dictionary:
	var now: float = float(ctx.get("now", 0.0))
	var cooldown_until: float = float(ctx.get("cooldown_until", 0.0))
	if now < cooldown_until:
		return {"allow": false, "reason": "cooldown"}

	var hostility_level: int = int(ctx.get("hostility_level", 0))
	if hostility_level < 6:
		return {"allow": false, "reason": "hostility_low"}

	var roll: float = float(ctx.get("roll", 1.0))
	var chance: float = float(hostility_level - 5) * 0.03
	if roll > chance:
		return {"allow": false, "reason": "chance_gate"}

	var find_wall: Callable = ctx.get("find_wall", Callable())
	if not find_wall.is_valid():
		return {"allow": false, "reason": "missing_wall_query"}

	var origin: Vector2 = ctx.get("origin", INVALID_TARGET) as Vector2
	var wall_pos: Vector2 = find_wall.call(origin, 300.0) as Vector2
	if not is_valid_target(wall_pos):
		return {"allow": false, "reason": "no_wall_found"}

	return {
		"allow": true,
		"reason": "wall_found",
		"target_pos": wall_pos,
		"cooldown_until": now + OPPORTUNISTIC_WALL_COOLDOWN,
	}


static func evaluate_property_sabotage_order(ctx: Dictionary) -> Dictionary:
	var now: float = float(ctx.get("now", 0.0))
	var cooldown_until: float = float(ctx.get("cooldown_until", 0.0))
	if now < cooldown_until:
		return {"allow": false, "reason": "cooldown"}

	var hostility_level: int = int(ctx.get("hostility_level", 0))
	if hostility_level < 7:
		return {"allow": false, "reason": "hostility_low"}

	var roll: float = float(ctx.get("roll", 1.0))
	var chance: float = float(hostility_level - 6) * 0.02
	if roll > chance:
		return {"allow": false, "reason": "chance_gate"}

	var node_pos: Vector2 = ctx.get("origin", INVALID_TARGET) as Vector2
	var target_pos: Vector2 = INVALID_TARGET
	var target_kind: String = ""

	var find_wb: Callable = ctx.get("find_workbench", Callable())
	if hostility_level >= 7 and find_wb.is_valid():
		var wb_pos: Vector2 = find_wb.call(node_pos, 400.0) as Vector2
		if is_valid_target(wb_pos):
			target_pos = wb_pos
			target_kind = "workbench"

	var find_storage: Callable = ctx.get("find_storage", Callable())
	if hostility_level >= 8 and find_storage.is_valid():
		var st_pos: Vector2 = find_storage.call(node_pos, 400.0) as Vector2
		if is_valid_target(st_pos):
			if not is_valid_target(target_pos) or node_pos.distance_squared_to(st_pos) < node_pos.distance_squared_to(target_pos):
				target_pos = st_pos
				target_kind = "storage"

	if not is_valid_target(target_pos):
		return {"allow": false, "reason": "no_property_target"}

	return {
		"allow": true,
		"reason": "target_found",
		"target_pos": target_pos,
		"target_kind": target_kind,
		"cooldown_until": now + PROPERTY_SABOTAGE_COOLDOWN,
	}


static func _resolve_raid_priority_target(world_node: Node, assault_anchor: Vector2, enemy_pos: Vector2) -> Dictionary:
	var search_centers: Array[Vector2] = [assault_anchor]
	if enemy_pos.distance_squared_to(assault_anchor) > 1.0:
		search_centers.append(enemy_pos)

	var placeable_node: Node2D = null
	for center in search_centers:
		if not is_valid_target(center):
			continue
		placeable_node = _find_nearest_player_structure_node(world_node, enemy_pos, center)
		if placeable_node != null:
			break
	var placeable_pos: Vector2 = placeable_node.global_position if placeable_node != null else INVALID_TARGET

	var wall_pos: Vector2 = INVALID_TARGET
	if world_node.has_method("find_nearest_player_wall_world_pos"):
		for center in search_centers:
			if not is_valid_target(center):
				continue
			wall_pos = world_node.call("find_nearest_player_wall_world_pos", center, RAID_TARGET_SEARCH_RADIUS) as Vector2
			if is_valid_target(wall_pos):
				break

	var has_placeable: bool = placeable_node != null \
			and is_instance_valid(placeable_node) \
			and not placeable_node.is_queued_for_deletion() \
			and is_valid_target(placeable_pos)
	var has_wall: bool = is_valid_target(wall_pos)
	if not has_placeable and not has_wall:
		return {}
	if has_placeable and not has_wall:
		return {"kind": "placeable", "pos": placeable_pos, "node": placeable_node}
	if has_wall and not has_placeable:
		return {"kind": "wall", "pos": wall_pos}

	var d_placeable: float = enemy_pos.distance_squared_to(placeable_pos)
	var d_wall: float = enemy_pos.distance_squared_to(wall_pos)
	if d_placeable <= d_wall:
		return {"kind": "placeable", "pos": placeable_pos, "node": placeable_node}
	return {"kind": "wall", "pos": wall_pos}


static func _find_nearest_player_structure_node(world_node: Node, enemy_pos: Vector2, center: Vector2) -> Node2D:
	if not world_node.has_method("find_nearest_player_placeable_world_pos"):
		return null
	var raw: Variant = world_node.call("find_nearest_player_placeable_world_pos", center, RAID_TARGET_SEARCH_RADIUS)
	if not (raw is Vector2):
		return null
	var pos: Vector2 = raw as Vector2
	if not is_valid_target(pos):
		return null

	var best: Node2D = null
	var best_dsq: float = INF
	for node in world_node.get_tree().get_nodes_in_group("player_placeable"):
		var n2d := node as Node2D
		if n2d == null or not is_instance_valid(n2d) or n2d.is_queued_for_deletion():
			continue
		if n2d.global_position.distance_squared_to(center) > RAID_TARGET_SEARCH_RADIUS * RAID_TARGET_SEARCH_RADIUS:
			continue
		var dsq: float = enemy_pos.distance_squared_to(n2d.global_position)
		if dsq < best_dsq:
			best_dsq = dsq
			best = n2d
	return best


static func _resolve_local_wall_fallback(world_node: Node, enemy_pos: Vector2, primary_anchor: Vector2, secondary_anchor: Vector2) -> Vector2:
	if not world_node.has_method("find_nearest_player_wall_world_pos"):
		return INVALID_TARGET
	var probes: Array[Vector2] = [enemy_pos]
	if is_valid_target(primary_anchor) and enemy_pos.distance_squared_to(primary_anchor) > 1.0:
		probes.append(primary_anchor)
	if is_valid_target(secondary_anchor) and enemy_pos.distance_squared_to(secondary_anchor) > 1.0:
		probes.append(secondary_anchor)

	var best_wall: Vector2 = INVALID_TARGET
	var best_dsq: float = INF
	for probe in probes:
		var wall_pos: Vector2 = world_node.call("find_nearest_player_wall_world_pos", probe, RAID_LOCAL_WALL_PROBE_RADIUS) as Vector2
		if not is_valid_target(wall_pos):
			continue
		var dsq: float = enemy_pos.distance_squared_to(wall_pos)
		if dsq < best_dsq:
			best_dsq = dsq
			best_wall = wall_pos
	if best_dsq > RAID_LOCAL_WALL_STRIKE_RANGE_SQ:
		return INVALID_TARGET
	return best_wall
