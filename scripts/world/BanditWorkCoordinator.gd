extends Node
class_name BanditWorkCoordinator

## Low-level runtime coordinator for already-ticked bandits.
## Keeps concrete world interactions here and delegates carry logistics to CampStash.

const BanditTuningScript := preload("res://scripts/world/BanditTuning.gd")
const CombatStateServiceScript := preload("res://scripts/world/CombatStateService.gd")

const RAID_ATTACK_RANGE_SQ: float = 96.0 * 96.0
const RAID_LOOT_RANGE_SQ: float = 76.0 * 76.0
const RAID_TARGET_SEARCH_RADIUS: float = 180.0
const RAID_ATTACK_COOLDOWN: float = 0.45
const RAID_LOOT_COOLDOWN: float = 1.10

const INVALID_TARGET: Vector2 = Vector2(-1.0, -1.0)

var _stash: BanditCampStashSystem = null
var _world_node: Node = null
var _world_spatial_index: WorldSpatialIndex = null

var _raid_attack_next_at: Dictionary = {}  # member_id -> RunClock.now()
var _raid_loot_next_at: Dictionary = {}  # member_id -> RunClock.now()


func setup(ctx: Dictionary) -> void:
	_stash = ctx.get("stash") as BanditCampStashSystem
	_world_node = ctx.get("world_node")
	_world_spatial_index = ctx.get("world_spatial_index") as WorldSpatialIndex


func process_post_behavior(beh: BanditWorldBehavior, enemy_node: Node, drops_cache: Array, combat_state: Dictionary = {}) -> void:
	if beh == null:
		return
	if enemy_node == null or not is_instance_valid(enemy_node):
		_handle_missing_enemy(beh)
		return

	_maybe_drop_carry_on_aggro(beh, enemy_node, combat_state)
	_handle_mining(beh, enemy_node)
	_handle_structure_assault(beh, enemy_node)
	_handle_collection_and_deposit(beh, enemy_node, drops_cache)


func _handle_missing_enemy(beh: BanditWorldBehavior) -> void:
	if _stash != null and not beh._cargo_manifest.is_empty():
		_stash.drop_carry_on_aggro(beh, null)
	if beh.pending_mine_id != 0 and not is_instance_id_valid(beh.pending_mine_id):
		beh.pending_mine_id = 0
		beh._resource_node_id = 0
	if beh.pending_collect_id != 0 and not is_instance_id_valid(beh.pending_collect_id):
		beh.pending_collect_id = 0
	_raid_attack_next_at.erase(beh.member_id)
	_raid_loot_next_at.erase(beh.member_id)


func _maybe_drop_carry_on_aggro(beh: BanditWorldBehavior, enemy_node: Node, combat_state: Dictionary) -> void:
	if _stash == null or beh._cargo_manifest.is_empty():
		return
	var canonical: Dictionary = combat_state
	if canonical.is_empty():
		canonical = CombatStateServiceScript.read_actor_state(enemy_node)
	var events: Array = canonical.get("events", []) as Array
	if events.has(CombatStateServiceScript.EVENT_COMBAT_STARTED):
		_stash.drop_carry_on_aggro(beh, enemy_node)


func _handle_collection_and_deposit(beh: BanditWorldBehavior, enemy_node: Node,
		drops_cache: Array) -> void:
	if _stash == null:
		return

	if beh.state == NpcWorldBehavior.State.RESOURCE_WATCH:
		var res_center := _resolve_resource_center(beh, enemy_node)
		_stash.sweep_collect_orbit(beh, enemy_node, res_center, drops_cache)
	elif beh.pending_collect_id != 0:
		_stash.sweep_collect_arrive(beh, enemy_node,
			(enemy_node as Node2D).global_position, drops_cache)

	_stash.handle_cargo_deposit(beh, enemy_node)


func _resolve_resource_center(beh: BanditWorldBehavior, enemy_node: Node) -> Vector2:
	var fallback := (enemy_node as Node2D).global_position
	if beh._resource_node_id == 0 or not is_instance_id_valid(beh._resource_node_id):
		if beh._resource_node_id != 0:
			beh._resource_node_id = 0
		return fallback
	var res := instance_from_id(beh._resource_node_id) as Node2D
	if res == null or not is_instance_valid(res) or res.is_queued_for_deletion():
		beh._resource_node_id = 0
		return fallback
	return res.global_position


func _handle_mining(beh: BanditWorldBehavior, enemy_node: Node) -> void:
	var mine_id: int = beh.pending_mine_id
	if mine_id == 0:
		return
	beh.pending_mine_id = 0
	if not is_instance_id_valid(mine_id):
		beh._resource_node_id = 0
		return

	var res_node: Node = instance_from_id(mine_id) as Node
	if res_node == null or not is_instance_valid(res_node) or res_node.is_queued_for_deletion():
		beh._resource_node_id = 0
		return

	var enemy_pos: Vector2 = (enemy_node as Node2D).global_position
	var res_pos: Vector2 = (res_node as Node2D).global_position
	if enemy_pos.distance_squared_to(res_pos) > BanditTuningScript.mine_range_sq():
		return

	var wc: WeaponComponent = enemy_node.get_node_or_null("WeaponComponent") as WeaponComponent
	if wc != null and wc.current_weapon_id != "ironpipe":
		wc.equip_weapon_id("ironpipe")
		if wc.current_weapon_id != "ironpipe":
			return
		beh.pending_mine_id = mine_id
		return

	res_node.hit(enemy_node)
	if enemy_node.has_method("queue_ai_attack_press"):
		enemy_node.call("queue_ai_attack_press", res_pos)


func _handle_structure_assault(beh: BanditWorldBehavior, enemy_node: Node) -> void:
	if _stash == null:
		return
	if _world_node == null or not is_instance_valid(_world_node):
		return
	if beh.group_id == "":
		return

	var g: Dictionary = BanditGroupMemory.get_group(beh.group_id)
	if g.is_empty():
		return
	var intent: String = String(g.get("current_group_intent", ""))
	var assault_active: bool = BanditGroupMemory.is_structure_assault_active(beh.group_id)
	var has_raid_context: bool = assault_active \
			or intent == "raiding" \
			or BanditGroupMemory.has_placement_react_lock(beh.group_id)

	var group_anchor: Vector2 = _resolve_assault_anchor(beh.group_id, g)
	var member_anchor: Vector2 = _resolve_member_assault_anchor(beh, group_anchor)
	var attack_anchor: Vector2 = member_anchor if _is_valid_target(member_anchor) else group_anchor

	var enemy_pos: Vector2 = (enemy_node as Node2D).global_position

	var now: float = RunClock.now()
	var member_id: String = beh.member_id

	if now >= float(_raid_loot_next_at.get(member_id, 0.0)):
		var looted: bool = _try_loot_nearby_container(beh, enemy_node, attack_anchor, enemy_pos)
		if looted:
			_raid_loot_next_at[member_id] = now + RAID_LOOT_COOLDOWN
			_raid_attack_next_at[member_id] = now + RAID_ATTACK_COOLDOWN
			return

	if now < float(_raid_attack_next_at.get(member_id, 0.0)):
		return

	var directive: Dictionary = BanditWallAssaultPolicy.evaluate_structure_directive({
		"world_node": _world_node,
		"has_raid_context": has_raid_context,
		"now": now,
		"attack_next_at": float(_raid_attack_next_at.get(member_id, 0.0)),
		"enemy_pos": enemy_pos,
		"group_anchor": group_anchor,
		"member_anchor": member_anchor,
	})
	if not bool(directive.get("allow", false)):
		if String(directive.get("reason", "")) == "no_attack_target" and beh.cargo_count > 0:
			beh.force_return_home()
			Debug.log("raid", "[BWC] structure no-target → return home with cargo npc=%s group=%s cargo=%d" % [
				beh.member_id, beh.group_id, beh.cargo_count
			])
		return

	var target: Dictionary = directive
	var target_pos: Vector2 = target.get("pos", INVALID_TARGET) as Vector2
	if not _is_valid_target(target_pos):
		return
	if enemy_pos.distance_squared_to(target_pos) > RAID_ATTACK_RANGE_SQ:
		return

	var attacked: bool = false
	var target_kind: String = String(target.get("kind", ""))
	if target_kind == "placeable":
		var node: Node = target.get("node") as Node
		if node != null and is_instance_valid(node) and not node.is_queued_for_deletion() \
				and node.has_method("hit"):
			if enemy_node.has_method("queue_ai_attack_press"):
				enemy_node.call("queue_ai_attack_press", target_pos)
			node.call("hit", enemy_node)
			attacked = true
	elif target_kind == "wall":
		attacked = _try_wall_slash_strike(enemy_node, target_pos)

	if not attacked:
		return

	if target_kind != "wall":
		if enemy_node.has_method("queue_ai_attack_press"):
			enemy_node.call("queue_ai_attack_press", target_pos)
	_raid_attack_next_at[member_id] = float(target.get("next_attack_at", now + RAID_ATTACK_COOLDOWN))
	Debug.log("raid", "[BWC] structure hit npc=%s group=%s kind=%s pos=%s" % [
		beh.member_id, beh.group_id, target_kind, str(target_pos)
	])


func _resolve_assault_anchor(group_id: String, g: Dictionary) -> Vector2:
	var anchor: Vector2 = g.get("last_interest_pos", INVALID_TARGET) as Vector2
	if _is_valid_target(anchor):
		return anchor
	var pending: Vector2 = BanditGroupMemory.get_assault_target(group_id)
	return pending if _is_valid_target(pending) else INVALID_TARGET


func _resolve_member_assault_anchor(beh: BanditWorldBehavior, group_anchor: Vector2) -> Vector2:
	if beh != null and beh.has_method("get_structure_assault_focus_target"):
		var focus_raw: Variant = beh.call("get_structure_assault_focus_target")
		if focus_raw is Vector2:
			var focus: Vector2 = focus_raw as Vector2
			if _is_valid_target(focus):
				return focus
	return group_anchor if _is_valid_target(group_anchor) else INVALID_TARGET


func _try_loot_nearby_container(beh: BanditWorldBehavior, enemy_node: Node,
		assault_anchor: Vector2, enemy_pos: Vector2) -> bool:
	if beh.is_cargo_full():
		return false

	var container: ContainerPlaceable = _find_nearest_raidable_container(enemy_pos, assault_anchor)
	if container == null:
		return false

	var chest_pos: Vector2 = container.global_position
	if enemy_pos.distance_squared_to(chest_pos) > RAID_LOOT_RANGE_SQ:
		return false

	var capacity_left: int = maxi(0, beh.cargo_capacity - beh.cargo_count)
	if capacity_left <= 0:
		return false

	var extracted: Array[Dictionary] = container.extract_items_for_raid(capacity_left)
	if extracted.is_empty():
		return false

	var cargo_result: Dictionary = _stash.collect_entries_canonical(beh, extracted, "raid_container")
	var added: int = int(cargo_result.get("added", 0))
	var leftovers: Array = cargo_result.get("leftovers", []) as Array
	if not leftovers.is_empty():
		for raw_left in leftovers:
			if not (raw_left is Dictionary):
				continue
			var left: Dictionary = raw_left as Dictionary
			container.try_insert_item(String(left.get("item_id", "")), int(left.get("amount", 0)))

	if added <= 0:
		for raw_entry in extracted:
			if not (raw_entry is Dictionary):
				continue
			var entry: Dictionary = raw_entry as Dictionary
			container.try_insert_item(String(entry.get("item_id", "")), int(entry.get("amount", 0)))
		return false

	beh.force_return_home()
	Debug.log("raid", "[BWC] chest looted npc=%s group=%s chest_uid=%s +%d cargo=%d/%d items=%s" % [
		beh.member_id,
		beh.group_id,
		container.placed_uid,
		added,
		beh.cargo_count,
		beh.cargo_capacity,
		_format_loot_entries(cargo_result.get("taken", []) as Array),
	])
	return true


func _find_nearest_raidable_container(enemy_pos: Vector2, assault_anchor: Vector2) -> ContainerPlaceable:
	var best: ContainerPlaceable = null
	var best_dsq: float = INF
	var search_centers: Array[Vector2] = [assault_anchor]
	if enemy_pos.distance_squared_to(assault_anchor) > 1.0:
		search_centers.append(enemy_pos)

	var runtime_nodes: Array = []
	if _world_spatial_index != null:
		for center in search_centers:
			if not _is_valid_target(center):
				continue
			runtime_nodes.append_array(_world_spatial_index.get_runtime_nodes_near(
				WorldSpatialIndex.KIND_STORAGE,
				center,
				RAID_TARGET_SEARCH_RADIUS
			))
	for raw_node in runtime_nodes:
		var container := raw_node as ContainerPlaceable
		if container == null:
			continue
		if not _is_valid_raid_container(container):
			continue
		var dsq: float = enemy_pos.distance_squared_to(container.global_position)
		if dsq < best_dsq:
			best_dsq = dsq
			best = container

	if best != null:
		return best

	for raw_node in get_tree().get_nodes_in_group("interactable"):
		var container := raw_node as ContainerPlaceable
		if container == null:
			continue
		if not _is_valid_raid_container(container):
			continue
		var near_any_center: bool = false
		for center in search_centers:
			if not _is_valid_target(center):
				continue
			if container.global_position.distance_squared_to(center) <= RAID_TARGET_SEARCH_RADIUS * RAID_TARGET_SEARCH_RADIUS:
				near_any_center = true
				break
		if not near_any_center:
			continue
		var dsq: float = enemy_pos.distance_squared_to(container.global_position)
		if dsq < best_dsq:
			best_dsq = dsq
			best = container
	return best


func _is_valid_raid_container(container: ContainerPlaceable) -> bool:
	if container == null or not is_instance_valid(container) or container.is_queued_for_deletion():
		return false
	if not container.is_raid_lootable():
		return false
	if container.get_raid_loot_total_units() <= 0:
		return false
	return true


func _damage_player_wall_at(world_pos: Vector2) -> bool:
	if _world_node == null:
		return false
	if _world_node.has_method("hit_wall_at_world_pos"):
		return bool(_world_node.call("hit_wall_at_world_pos", world_pos, 1, 24.0, true))
	if _world_node.has_method("damage_player_wall_at_world_pos"):
		return bool(_world_node.call("damage_player_wall_at_world_pos", world_pos, 1))
	return false


func _try_wall_slash_strike(enemy_node: Node, world_pos: Vector2) -> bool:
	if enemy_node == null or not is_instance_valid(enemy_node):
		return false
	# Animar primero — así el slash apunta a la pared antes del daño.
	if enemy_node.has_method("queue_ai_attack_press"):
		enemy_node.call("queue_ai_attack_press", world_pos)
	# Daño directo confiable: funciona también en lite-mode donde IronPipeWeapon
	# no tickea y el slash físico nunca se spawna.
	return _damage_player_wall_at(world_pos)


func _is_valid_target(pos: Vector2) -> bool:
	return pos.is_finite() and not pos.is_equal_approx(INVALID_TARGET)


func _format_loot_entries(entries: Array) -> String:
	if entries.is_empty():
		return "[]"
	var parts: Array[String] = []
	for raw in entries:
		if not (raw is Dictionary):
			continue
		var e: Dictionary = raw as Dictionary
		parts.append("%s×%d" % [String(e.get("item_id", "")), int(e.get("amount", 0))])
	return "[" + ", ".join(parts) + "]"
