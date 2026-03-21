extends Node
class_name BanditBehaviorLayer

# ── BanditBehaviorLayer ──────────────────────────────────────────────────────
# Node child of World. Owns and ticks all BanditWorldBehavior instances for
# active bandit enemies.
#
# Every TICK_INTERVAL seconds:
#   1. Lazily creates behaviors for new sleeping bandits (group_id required).
#   2. Ensures camp barrels exist (delegates to BanditCampStashSystem).
#   3. Builds a ctx dict with nearby drops / resources for each enemy.
#   4. Ticks each behavior.
#   5. Handles pending_collect_id, mining, cargo deposit (via BanditCampStashSystem).
#   6. Prunes behaviors for enemies that have despawned.
#
# Every physics frame:
#   Applies desired_velocity (+ friction compensation) to sleeping non-lite enemies.
#
# Carry preference: NPCs carry drops to base (cargo_count) rather than
# putting them in inventory. Inventory is not touched here.

const BanditTuningScript            := preload("res://scripts/world/BanditTuning.gd")
const BanditGroupIntelScript        := preload("res://scripts/world/BanditGroupIntel.gd")
const BanditExtortionDirectorScript := preload("res://scripts/world/BanditExtortionDirector.gd")
const BanditRaidDirectorScript      := preload("res://scripts/world/BanditRaidDirector.gd")
const BanditCampStashSystemScript   := preload("res://scripts/world/BanditCampStashSystem.gd")

# ---------------------------------------------------------------------------
# Camp layout constants — local geometry, not cross-system gameplay tuning.
# These control how NPCs distribute themselves around the barrel; a designer
# would tune pickup radii / speeds in BanditTuning, not these.
# ---------------------------------------------------------------------------
const DEPOSIT_SLOT_COUNT:        int   = 36      # posiciones angulares alrededor del barril
const DEPOSIT_SLOT_RADIUS_MIN:   float = 32.0    # px mínimo desde el centro del barril
const DEPOSIT_SLOT_RADIUS_RANGE: int   = 20      # varianza adicional (hash % N)
const DEPOSIT_REASSIGN_GUARD_SQ: float = 72.0 * 72.0  # no reasignar si ya está cerca

const DEBUG_ALERTED_CHASE: bool = true

var _npc_simulator:  NpcSimulator             = null
var _group_intel:    BanditGroupIntel         = null
var _player:         Node2D                   = null
var _bubble_manager: WorldSpeechBubbleManager = null

var _behaviors: Dictionary = {}   # enemy_id (String) -> BanditWorldBehavior
var _tick_timer: float     = 0.0

var _extortion_director: BanditExtortionDirector = null
var _raid_director:      BanditRaidDirector      = null
var _stash:              BanditCampStashSystem   = null
var _find_wall_cb:       Callable                = Callable()

# Cached world-level lists (rebuilt once per tick, shared across all enemies)
var _all_drops_cache:     Array = []
var _all_resources_cache: Array = []


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

func setup(ctx: Dictionary) -> void:
	_npc_simulator  = ctx.get("npc_simulator")
	_player         = ctx.get("player")
	_bubble_manager = ctx.get("speech_bubble_manager")

	# Extortion director
	if _extortion_director != null and is_instance_valid(_extortion_director):
		_extortion_director.queue_free()
	_extortion_director = BanditExtortionDirectorScript.new()
	add_child(_extortion_director)
	_extortion_director.setup({
		"npc_simulator":         _npc_simulator,
		"player":                _player,
		"speech_bubble_manager": _bubble_manager,
		"get_behavior_for_enemy": Callable(self, "_get_behavior"),
	})

	# Raid director
	if _raid_director != null and is_instance_valid(_raid_director):
		_raid_director.queue_free()
	_raid_director = BanditRaidDirectorScript.new() as BanditRaidDirector
	_raid_director.name = "BanditRaidDirector"
	add_child(_raid_director)
	_raid_director.setup({
		"npc_simulator": _npc_simulator,
	})

	# Camp stash system
	if _stash != null and is_instance_valid(_stash):
		_stash.queue_free()
	_stash = BanditCampStashSystemScript.new() as BanditCampStashSystem
	_stash.name = "BanditCampStashSystem"
	add_child(_stash)
	_stash.setup({
		"update_deposit_pos_cb": Callable(self, "_update_deposit_pos"),
	})


## Called from world.gd after SettlementIntel is ready.
func setup_group_intel(ctx: Dictionary) -> void:
	_group_intel = BanditGroupIntelScript.new()
	_group_intel.setup({
		"npc_simulator":             _npc_simulator,
		"get_interest_markers_near": ctx.get("get_interest_markers_near", Callable()),
		"get_detected_bases_near":   ctx.get("get_detected_bases_near",   Callable()),
	})

	# Guardar wall query callable — se pasa al RaidDirector y también al ctx de cada tick
	var wall_cb: Callable = ctx.get("find_nearest_player_wall_world_pos", Callable())
	_find_wall_cb = wall_cb
	if _raid_director != null and wall_cb.is_valid():
		_raid_director.set_wall_query(wall_cb)


# ---------------------------------------------------------------------------
# Physics frame — apply velocity to sleeping, non-lite enemies
# ---------------------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	if _npc_simulator == null:
		return

	# Pass 1: apply desired velocities + collect per-group node positions
	var group_nodes: Dictionary = {}
	for enemy_id in _behaviors:
		var behavior: BanditWorldBehavior = _behaviors[enemy_id]
		var node = _npc_simulator.get_enemy_node(enemy_id)
		if node == null or not node.has_method("is_world_behavior_eligible") \
				or not node.is_world_behavior_eligible():
			continue
		var vel: Vector2 = behavior.get_desired_velocity()
		if vel.length_squared() > 0.01:
			node.velocity = vel.normalized() * (vel.length() + BanditTuningScript.friction_compensation())
		if behavior.group_id != "":
			if not group_nodes.has(behavior.group_id):
				group_nodes[behavior.group_id] = []
			group_nodes[behavior.group_id].append({"node": node, "pos": node.global_position})

	# Pass 2: ally separation
	for gid in group_nodes:
		var members: Array = group_nodes[gid]
		if members.size() < 2:
			continue
		for i in members.size():
			var a: Dictionary = members[i]
			var sep: Vector2 = Vector2.ZERO
			for j in members.size():
				if i == j:
					continue
				var diff: Vector2 = (a["pos"] as Vector2) - (members[j]["pos"] as Vector2)
				var d: float = diff.length()
				if d < BanditTuningScript.ally_sep_radius() and d > 0.5:
					sep += diff.normalized() * (BanditTuningScript.ally_sep_radius() - d) \
						/ BanditTuningScript.ally_sep_radius() * BanditTuningScript.ally_sep_force()
			if sep.length_squared() > 0.01:
				a["node"].velocity += sep

	if _extortion_director != null:
		_extortion_director.apply_extortion_movement(BanditTuningScript.friction_compensation())

	# Debug: alerted scout sigue al player
	if DEBUG_ALERTED_CHASE and _player != null and is_instance_valid(_player):
		var ap: Vector2 = _player.global_position
		for gid in BanditGroupMemory.get_all_group_ids():
			var g: Dictionary = BanditGroupMemory.get_group(gid)
			if String(g.get("current_group_intent", "")) != "alerted":
				continue
			var scout_id: String = BanditGroupMemory.get_scout(gid)
			if scout_id == "":
				continue
			var snode = _npc_simulator.get_enemy_node(scout_id)
			if snode == null or not snode.has_method("is_world_behavior_eligible") \
					or not snode.is_world_behavior_eligible():
				continue
			var to_p: Vector2 = ap - snode.global_position
			if to_p.length() > 1.0:
				snode.velocity = to_p.normalized() * (
					BanditTuningScript.alerted_scout_chase_speed(gid) + BanditTuningScript.friction_compensation()
				)


# ---------------------------------------------------------------------------
# Process tick — behavior maintenance
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _npc_simulator == null:
		return
	if _group_intel != null:
		_group_intel.tick(delta)
	if _extortion_director != null:
		_extortion_director.process_extortion()
	if _raid_director != null:
		_raid_director.process_raid()
	_tick_timer += delta
	if _tick_timer < BanditTuningScript.behavior_tick_interval():
		return
	_tick_timer = 0.0

	_refresh_world_caches()
	_ensure_behaviors_for_active_enemies()
	_stash.ensure_barrels()
	_tick_behaviors()
	_prune_behaviors()


# ---------------------------------------------------------------------------
# World caches (rebuilt once per tick)
# ---------------------------------------------------------------------------

func _refresh_world_caches() -> void:
	_all_drops_cache     = get_tree().get_nodes_in_group("item_drop")
	_all_resources_cache = get_tree().get_nodes_in_group("world_resource")


# ---------------------------------------------------------------------------
# Behavior tick
# ---------------------------------------------------------------------------

func _tick_behaviors() -> void:
	var leader_pos_by_group: Dictionary = {}
	for enemy_id in _behaviors:
		var beh: BanditWorldBehavior = _behaviors[enemy_id]
		if beh.role != "leader" or beh.group_id == "":
			continue
		var node = _npc_simulator.get_enemy_node(enemy_id)
		if node != null:
			leader_pos_by_group[beh.group_id] = node.global_position

	for enemy_id in _behaviors:
		var beh: BanditWorldBehavior = _behaviors[enemy_id]
		var node = _npc_simulator.get_enemy_node(enemy_id)
		if node == null or not node.has_method("is_world_behavior_eligible") \
				or not node.is_world_behavior_eligible():
			if not beh._cargo_manifest.is_empty():
				_stash.drop_carry_on_aggro(beh, node)
			continue

		var node_pos: Vector2 = node.global_position
		var ctx: Dictionary = {
			"node_pos":              node_pos,
			"nearby_drops_info":     _build_drops_info(node_pos),
			"nearby_res_info":       _build_res_info(node_pos),
			"find_nearest_player_wall": _find_wall_cb,
		}
		if beh.group_id != "":
			ctx["leader_pos"] = leader_pos_by_group.get(beh.group_id, beh.home_pos)

		beh.tick(BanditTuningScript.behavior_tick_interval(), ctx)

		# Detección de aggro mientras aún es eligible
		if not beh._cargo_manifest.is_empty():
			var ai_comp := node.get_node_or_null("AIComponent")
			if ai_comp != null and ai_comp.get("target") != null:
				_stash.drop_carry_on_aggro(beh, node)

		# Sync save-state: cargo y behavior para continuidad data-only
		var save_state_ref: Dictionary = _get_save_state_for(enemy_id)
		if not save_state_ref.is_empty():
			save_state_ref["cargo_count"]    = beh.cargo_count
			save_state_ref["world_behavior"] = beh.export_state()

		_handle_mining(beh, node)

		if beh.state == NpcWorldBehavior.State.RESOURCE_WATCH:
			var res_center := node_pos
			if beh._resource_node_id != 0 and is_instance_id_valid(beh._resource_node_id):
				var res := instance_from_id(beh._resource_node_id) as Node2D
				if res != null and is_instance_valid(res):
					res_center = res.global_position
			_stash.sweep_collect_orbit(beh, node, res_center, _all_drops_cache)
		elif beh.pending_collect_id != 0:
			_stash.sweep_collect_arrive(beh, node, node_pos, _all_drops_cache)

		_stash.handle_cargo_deposit(beh, node)


# ---------------------------------------------------------------------------
# Mining
# ---------------------------------------------------------------------------

func _handle_mining(beh: BanditWorldBehavior, enemy_node: Node) -> void:
	var mine_id: int = beh.pending_mine_id
	if mine_id == 0:
		return
	beh.pending_mine_id = 0
	if not is_instance_id_valid(mine_id):
		beh._resource_node_id = 0
		return
	var res_node: Node = instance_from_id(mine_id) as Node
	if res_node == null or not is_instance_valid(res_node):
		beh._resource_node_id = 0
		return
	var enemy_pos: Vector2 = (enemy_node as Node2D).global_position
	var res_pos:   Vector2 = (res_node   as Node2D).global_position
	if enemy_pos.distance_squared_to(res_pos) > BanditTuningScript.mine_range_sq():
		return

	# La minería requiere ironpipe. Si tiene otra arma activa, cambiar primero.
	# Esto garantiza que el swing visual y el daño sean siempre del arma cuerpo a cuerpo.
	var wc: WeaponComponent = enemy_node.get_node_or_null("WeaponComponent") as WeaponComponent
	if wc != null:
		if wc.current_weapon_id != "ironpipe":
			wc.equip_weapon_id("ironpipe")
			# Aplazar el golpe al siguiente tick para que la animación de cambio se muestre.
			# Si no tiene ironpipe en inventario, abortar la minería.
			if wc.current_weapon_id != "ironpipe":
				return
			beh.pending_mine_id = mine_id  # re-queue para el próximo tick
			return

	res_node.hit(enemy_node)
	# queue_ai_attack_press en lugar de spawn_slash directo para que
	# IronPipeWeapon procese el ataque: swingea el arma (attacking=true +
	# target_attack_angle) y spawnea el slash visual por su propio flujo.
	if enemy_node.has_method("queue_ai_attack_press"):
		enemy_node.call("queue_ai_attack_press", res_pos)


# ---------------------------------------------------------------------------
# ctx builders
# ---------------------------------------------------------------------------

func _build_drops_info(node_pos: Vector2) -> Array:
	var result: Array = []
	for drop in _all_drops_cache:
		var drop_node := drop as Node2D
		if drop_node == null or not is_instance_valid(drop_node) \
				or drop_node.is_queued_for_deletion():
			continue
		if node_pos.distance_squared_to(drop_node.global_position) > BanditTuningScript.loot_scan_radius_sq():
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
		if node_pos.distance_squared_to(res_node.global_position) > BanditTuningScript.resource_scan_radius_sq():
			continue
		result.append({"pos": res_node.global_position, "id": res_node.get_instance_id()})
	return result


# ---------------------------------------------------------------------------
# Lazy behavior creation
# ---------------------------------------------------------------------------

func _ensure_behaviors_for_active_enemies() -> void:
	for enemy_id in _npc_simulator.active_enemies:
		var enemy_id_str: String = String(enemy_id)
		if _behaviors.has(enemy_id_str):
			continue
		var node = _npc_simulator.get_enemy_node(enemy_id_str)
		if node == null or not node.has_method("is_world_behavior_eligible") \
				or not node.is_world_behavior_eligible():
			continue
		var save_state: Dictionary = _get_save_state_for(enemy_id_str)
		if save_state.is_empty() or String(save_state.get("group_id", "")) == "":
			continue
		var beh := BanditWorldBehavior.new()
		beh.setup({
			"home_pos":    _get_home_pos(save_state),
			"role":        String(save_state.get("role", "scavenger")),
			"group_id":    String(save_state.get("group_id", "")),
			"member_id":   enemy_id_str,
			"cargo_count": int(save_state.get("cargo_count", 0)),
		})
		var wb = save_state.get("world_behavior", {})
		if wb is Dictionary and not (wb as Dictionary).is_empty():
			beh.import_state(wb as Dictionary)
		else:
			beh._rng.seed = absi(int(save_state.get("seed", 0)) ^ hash(enemy_id_str))
			beh._idle_timer = beh._rng.randf_range(NpcWorldBehavior.IDLE_WAIT_MIN, NpcWorldBehavior.IDLE_WAIT_MAX)
		_behaviors[enemy_id_str] = beh
		Debug.log("bandit_ai", "[BanditBL] behavior created id=%s role=%s group=%s cargo_cap=%d home=%s" % [
			enemy_id_str, beh.role, beh.group_id, beh.cargo_capacity, str(beh.home_pos)])


# ---------------------------------------------------------------------------
# Pruning
# ---------------------------------------------------------------------------

func _prune_behaviors() -> void:
	var to_remove: Array = []
	for enemy_id in _behaviors:
		if _npc_simulator.get_enemy_node(enemy_id) == null:
			to_remove.append(enemy_id)
	for enemy_id in to_remove:
		_behaviors.erase(enemy_id)
		if NpcPathService.is_ready():
			NpcPathService.clear_agent(enemy_id)
		Debug.log("bandit_ai", "[BanditBL] behavior pruned id=%s" % enemy_id)


func _get_behavior(enemy_id: String) -> BanditWorldBehavior:
	return _behaviors.get(enemy_id, null) as BanditWorldBehavior


# ---------------------------------------------------------------------------
# Deposit pos distribution — callback usado por BanditCampStashSystem
# ---------------------------------------------------------------------------

## Propaga la posición del barril a todos los behaviors del grupo.
## Cada NPC recibe un slot personal (ángulo determinista por member_id).
func _update_deposit_pos(group_id: String, barrel_pos: Vector2) -> void:
	for eid in _behaviors:
		var beh: BanditWorldBehavior = _behaviors[eid]
		if beh.group_id != group_id:
			continue
		if beh.deposit_pos != Vector2.ZERO \
				and beh.deposit_pos.distance_squared_to(barrel_pos) < DEPOSIT_REASSIGN_GUARD_SQ:
			continue
		var h      := absi(hash(beh.member_id))
		var angle  := (h % DEPOSIT_SLOT_COUNT) * (TAU / DEPOSIT_SLOT_COUNT)
		var radius := DEPOSIT_SLOT_RADIUS_MIN + float(h % DEPOSIT_SLOT_RADIUS_RANGE)
		beh.deposit_pos = barrel_pos + Vector2(cos(angle), sin(angle)) * radius


# ---------------------------------------------------------------------------
# Save-state helpers
# ---------------------------------------------------------------------------

func _get_save_state_for(enemy_id: String) -> Dictionary:
	var chunk_key: String = _npc_simulator.get_enemy_chunk_key(enemy_id)
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
