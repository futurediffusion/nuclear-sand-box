extends Node
class_name BanditBehaviorLayer

# ── BanditBehaviorLayer ──────────────────────────────────────────────────────
# Node child of World. Owns and ticks all BanditWorldBehavior instances for
# active bandit enemies.
#
# Every TICK_INTERVAL seconds:
#   1. Lazily creates behaviors for new sleeping bandits (group_id required).
#   2. Builds a ctx dict with nearby drops / resources for each enemy.
#   3. Ticks each behavior.
#   4. Handles pending_collect_id (does the actual node interaction so behaviors
#      stay pure RefCounted — no node access inside them).
#   5. Prunes behaviors for enemies that have despawned.
#
# Every physics frame:
#   Applies desired_velocity (+ friction compensation) to sleeping non-lite enemies.
#
# Carry preference: NPCs carry drops to base (cargo_count) rather than
# putting them in inventory. Inventory is not touched here.

const TICK_INTERVAL: float = 0.5

# enemy.gd default friction = 1500; at 60 fps delta≈0.0167 → ≈25 px/s per frame.
# We add this so net movement ≈ behavior's intended speed after friction.
const FRICTION_COMPENSATION: float = 25.0

# Scan radii for finding world objects per tick
const LOOT_SCAN_RADIUS_SQ: float    = 144.0 * 144.0   # 144 px
const RESOURCE_SCAN_RADIUS_SQ: float = 288.0 * 288.0  # 288 px

const BanditGroupIntelScript := preload("res://scripts/world/BanditGroupIntel.gd")

var _npc_simulator: NpcSimulator    = null
var _group_intel: BanditGroupIntel  = null
var _behaviors: Dictionary = {}   # enemy_id (String) -> BanditWorldBehavior
var _tick_timer: float = 0.0

# Cached world-level item/resource lists (rebuilt once per tick, shared across all enemies)
var _all_drops_cache: Array    = []   # Array of ItemDrop nodes
var _all_resources_cache: Array = []  # Array of world_resource nodes


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

func setup(ctx: Dictionary) -> void:
	_npc_simulator = ctx.get("npc_simulator")

## Called from world.gd after SettlementIntel is ready.
func setup_group_intel(ctx: Dictionary) -> void:
	_group_intel = BanditGroupIntelScript.new()
	_group_intel.setup({
		"npc_simulator":             _npc_simulator,
		"get_interest_markers_near": ctx.get("get_interest_markers_near", Callable()),
		"get_detected_bases_near":   ctx.get("get_detected_bases_near",   Callable()),
	})


# ---------------------------------------------------------------------------
# Physics frame — apply velocity to sleeping, non-lite enemies
# ---------------------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	if _npc_simulator == null:
		return
	for enemy_id in _behaviors:
		var behavior: BanditWorldBehavior = _behaviors[enemy_id]
		var node = _npc_simulator._get_active_enemy_node(enemy_id)
		if node == null or not node.is_sleeping() or node.is_lite_mode():
			continue
		var vel: Vector2 = behavior.get_desired_velocity()
		if vel.length_squared() > 0.01:
			node.velocity = vel.normalized() * (vel.length() + FRICTION_COMPENSATION)
		# Idle (vel == 0): don't override, let enemy friction decelerate naturally


# ---------------------------------------------------------------------------
# Process tick — behavior maintenance
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _npc_simulator == null:
		return
	if _group_intel != null:
		_group_intel.tick(delta)
	_tick_timer += delta
	if _tick_timer < TICK_INTERVAL:
		return
	_tick_timer = 0.0

	_refresh_world_caches()
	_ensure_behaviors_for_active_enemies()
	_tick_behaviors()
	_prune_behaviors()


# ---------------------------------------------------------------------------
# World caches (rebuilt once per tick — shared across all enemy tick calls)
# ---------------------------------------------------------------------------

func _refresh_world_caches() -> void:
	_all_drops_cache     = get_tree().get_nodes_in_group("item_drop")
	_all_resources_cache = get_tree().get_nodes_in_group("world_resource")


# ---------------------------------------------------------------------------
# Behavior tick
# ---------------------------------------------------------------------------

func _tick_behaviors() -> void:
	# Collect leader positions by group_id for FOLLOW_LEADER support
	var leader_pos_by_group: Dictionary = {}
	for enemy_id in _behaviors:
		var beh: BanditWorldBehavior = _behaviors[enemy_id]
		if beh.role != "leader" or beh.group_id == "":
			continue
		var node = _npc_simulator._get_active_enemy_node(enemy_id)
		if node != null:
			leader_pos_by_group[beh.group_id] = node.global_position

	for enemy_id in _behaviors:
		var beh: BanditWorldBehavior = _behaviors[enemy_id]
		var node = _npc_simulator._get_active_enemy_node(enemy_id)
		if node == null or not node.is_sleeping() or node.is_lite_mode():
			continue

		var node_pos: Vector2 = node.global_position
		var ctx: Dictionary = {
			"node_pos":          node_pos,
			"nearby_drops_info": _build_drops_info(node_pos),
			"nearby_res_info":   _build_res_info(node_pos),
		}
		if beh.group_id != "":
			ctx["leader_pos"] = leader_pos_by_group.get(beh.group_id, beh.home_pos)

		beh.tick(TICK_INTERVAL, ctx)

		# Handle collection (actual node interaction lives here, not in behavior)
		if beh.pending_collect_id != 0:
			_handle_collection(beh)


# ---------------------------------------------------------------------------
# Collection — called when behavior arrives at a drop
# ---------------------------------------------------------------------------

func _handle_collection(beh: BanditWorldBehavior) -> void:
	var drop_id: int = beh.pending_collect_id
	beh.pending_collect_id = 0

	if drop_id == 0 or not is_instance_id_valid(drop_id):
		return
	var drop_obj: Object = instance_from_id(drop_id)
	if drop_obj == null or not is_instance_valid(drop_obj):
		return
	var drop_node: Node = drop_obj as Node
	if drop_node == null or drop_node.is_queued_for_deletion():
		return

	# Read amount before freeing
	var collected_amount: int = 1
	if drop_node.has_method("get") and drop_node.get("amount") != null:
		collected_amount = int(drop_node.get("amount"))

	# Increment cargo (clamp to capacity)
	var prev: int = beh.cargo_count
	beh.cargo_count = mini(beh.cargo_count + collected_amount, beh.cargo_capacity)
	drop_node.queue_free()

	Debug.log("bandit_ai", "[BanditBL] collected drop id=%s role=%s cargo=%d→%d/%d" % [
		beh.member_id, beh.role, prev, beh.cargo_count, beh.cargo_capacity])

	# If now full, the behavior's next tick will trigger RETURN_HOME
	# (BanditWorldBehavior checks is_cargo_full() at the top of tick())


# ---------------------------------------------------------------------------
# ctx builders — filter world-cache lists by proximity
# ---------------------------------------------------------------------------

func _build_drops_info(node_pos: Vector2) -> Array:
	var result: Array = []
	for drop in _all_drops_cache:
		var drop_node := drop as Node2D
		if drop_node == null or not is_instance_valid(drop_node) \
				or drop_node.is_queued_for_deletion():
			continue
		if node_pos.distance_squared_to(drop_node.global_position) > LOOT_SCAN_RADIUS_SQ:
			continue
		result.append({
			"id":     drop_node.get_instance_id(),
			"pos":    drop_node.global_position,
			"amount": int(drop_node.get("amount") if drop_node.get("amount") != null else 1),
		})
	return result


func _build_res_info(node_pos: Vector2) -> Array:
	var result: Array = []
	for res in _all_resources_cache:
		var res_node := res as Node2D
		if res_node == null or not is_instance_valid(res_node) \
				or res_node.is_queued_for_deletion():
			continue
		if node_pos.distance_squared_to(res_node.global_position) > RESOURCE_SCAN_RADIUS_SQ:
			continue
		result.append({"pos": res_node.global_position})
	return result


# ---------------------------------------------------------------------------
# Lazy behavior creation
# ---------------------------------------------------------------------------

func _ensure_behaviors_for_active_enemies() -> void:
	for enemy_id in _npc_simulator.active_enemies:
		var enemy_id_str: String = String(enemy_id)
		if _behaviors.has(enemy_id_str):
			continue
		var node = _npc_simulator._get_active_enemy_node(enemy_id_str)
		if node == null or not node.is_sleeping():
			continue
		var save_state: Dictionary = _get_save_state_for(enemy_id_str)
		if save_state.is_empty() or String(save_state.get("group_id", "")) == "":
			continue
		var beh := BanditWorldBehavior.new()
		beh.setup({
			"home_pos":  _get_home_pos(save_state),
			"role":      String(save_state.get("role", "scavenger")),
			"group_id":  String(save_state.get("group_id", "")),
			"member_id": enemy_id_str,
		})
		_behaviors[enemy_id_str] = beh
		Debug.log("bandit_ai", "[BanditBL] behavior created id=%s role=%s group=%s cargo_cap=%d home=%s" % [
			enemy_id_str, beh.role, beh.group_id, beh.cargo_capacity, str(beh.home_pos)])


# ---------------------------------------------------------------------------
# Pruning
# ---------------------------------------------------------------------------

func _prune_behaviors() -> void:
	var to_remove: Array = []
	for enemy_id in _behaviors:
		if _npc_simulator._get_active_enemy_node(enemy_id) == null:
			to_remove.append(enemy_id)
	for enemy_id in to_remove:
		_behaviors.erase(enemy_id)
		Debug.log("bandit_ai", "[BanditBL] behavior pruned id=%s" % enemy_id)


# ---------------------------------------------------------------------------
# Save-state helpers
# ---------------------------------------------------------------------------

func _get_save_state_for(enemy_id: String) -> Dictionary:
	var chunk_key: String = _npc_simulator._get_active_enemy_chunk_key(enemy_id)
	if chunk_key == "":
		return {}
	var chunk_states: Dictionary = WorldSave.enemy_state_by_chunk.get(chunk_key, {})
	var state_v = chunk_states.get(enemy_id, {})
	if state_v is Dictionary:
		return state_v as Dictionary
	return {}


func _get_home_pos(save_state: Dictionary) -> Vector2:
	var hp = save_state.get("home_world_pos", null)
	if hp is Vector2:
		return hp
	if hp is Dictionary:
		return Vector2(float((hp as Dictionary).get("x", 0.0)), float((hp as Dictionary).get("y", 0.0)))
	return Vector2.ZERO
