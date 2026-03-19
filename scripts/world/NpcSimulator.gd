extends Node
class_name NpcSimulator

@export_group("Lite Mode")
@export var lite_enabled: bool = true
@export var lite_radius: float = 420.0
@export var lite_hysteresis: float = 60.0
@export var lite_check_interval: float = 0.25
@export var lite_debug: bool = false

@export_group("Data-Only Simulation")
@export var data_only_enabled: bool = true
@export var sim_radius: float = 520.0
@export var sim_hysteresis: float = 80.0
@export var sim_check_interval: float = 0.25
@export var despawn_grace_seconds: float = 1.0
@export var debug_counts: bool = false
## Spawn visual node (in lite/sleeping mode) at this radius.
## Must be > (sim_radius - sim_hysteresis) and < (sim_radius + sim_hysteresis).
@export var visual_radius: float = 700.0
## If true, prewarm runs even on enemies that already have a saved world_behavior.
## Useful to re-disperse enemies on existing saves without a full F7 reset.
@export var reprewarm_existing: bool = false
## If true, enemies spawn as nodes as soon as their chunk loads (lite mode when
## outside full-AI radius). Despawn only on chunk unload. Eliminates the
## "empty camp" visual problem for small worlds where all chunks stay loaded.
## Set false to revert to proximity-based spawning (visual_radius).
@export var spawn_with_chunk: bool = true

# Asignado por World via setup()
var player: Node2D = null
var current_player_chunk: Vector2i = Vector2i(-999, -999)
var bandit_scene: PackedScene = null
var _spawn_queue: Node = null        # SpawnBudgetQueue
var _loaded_chunks: Dictionary = {}  # referencia al dict de World
var _chunk_save: Dictionary = {}     # referencia al dict de World
var _tile_to_world: Callable
var _chunk_key_fn: Callable
var _cliff_gen: CliffGenerator = null
var _world_to_tile: Callable
var _entity_root: Node2D = null

# Estado propio
var active_enemies: Dictionary = {}      # enemy_id -> Node
var active_enemy_chunk: Dictionary = {}  # enemy_id -> chunk_key String
var spawning_enemy_ids: Dictionary = {}  # enemy_id -> true

var _lite_timer: float = 0.0
var _sim_timer: float = 0.0

# ── Data-only behaviors ───────────────────────────────────────────────────────
# Owned by NpcSimulator for enemies that are alive but have no active node.
# BanditBehaviorLayer owns behaviors for enemies that DO have an active node.
# Never both at once for the same enemy_id.
var _data_behaviors: Dictionary = {}   # enemy_id -> BanditWorldBehavior
var _prewarmed_chunks: Dictionary = {} # chunk_key -> true (per session)
var _world_w_tiles: int = 64
var _world_h_tiles: int = 64

# ---------------------------------------------------------------------------
# Helpers de Tracking
# ---------------------------------------------------------------------------

func _clear_enemy_tracking(enemy_id: String, clear_spawning: bool = true) -> void:
	active_enemies.erase(enemy_id)
	active_enemy_chunk.erase(enemy_id)
	if clear_spawning:
		spawning_enemy_ids.erase(enemy_id)

func _get_active_enemy_node(enemy_id: String) -> Node:
	if not active_enemies.has(enemy_id):
		return null
	var node_v = active_enemies[enemy_id]
	if typeof(node_v) != TYPE_OBJECT or not is_instance_valid(node_v):
		if debug_counts:
			Debug.log("npc_data", "[NpcSimulator] Cleared stale active enemy ref: %s (invalid)" % enemy_id)
		_clear_enemy_tracking(enemy_id, false)
		return null
	var node: Node = node_v as Node
	if node.is_queued_for_deletion():
		if debug_counts:
			Debug.log("npc_data", "[NpcSimulator] Cleared stale active enemy ref: %s (queued for deletion)" % enemy_id)
		_clear_enemy_tracking(enemy_id, false)
		return null
	return node

func _get_active_enemy_chunk_key(enemy_id: String) -> String:
	return String(active_enemy_chunk.get(enemy_id, ""))

func _has_live_active_enemy(enemy_id: String) -> bool:
	return _get_active_enemy_node(enemy_id) != null

func _register_active_enemy(enemy_id: String, chunk_key: String, node: Node) -> void:
	active_enemies[enemy_id] = node
	active_enemy_chunk[enemy_id] = chunk_key
	spawning_enemy_ids.erase(enemy_id)


func setup(ctx: Dictionary) -> void:
	player = ctx.get("player")
	bandit_scene = ctx.get("bandit_scene")
	_spawn_queue = ctx.get("spawn_queue")
	_loaded_chunks = ctx["loaded_chunks"]
	_chunk_save = ctx["chunk_save"]
	_tile_to_world = ctx["tile_to_world"]
	_chunk_key_fn = ctx["chunk_key"]
	_cliff_gen = ctx.get("cliff_generator")
	_world_to_tile = ctx.get("world_to_tile", Callable())
	_entity_root = ctx.get("entity_root")
	_world_w_tiles = ctx.get("width",  64)
	_world_h_tiles = ctx.get("height", 64)

func _process(delta: float) -> void:
	_tick_lite_mode(delta)
	_tick_data_only(delta)

# ---------------------------------------------------------------------------
# Lite mode — activa/desactiva IA de enemigos según distancia al jugador
# ---------------------------------------------------------------------------
func _tick_lite_mode(delta: float) -> void:
	if get_tree().paused or not lite_enabled:
		return
	_lite_timer += delta
	if _lite_timer < maxf(lite_check_interval, 0.05):
		return
	_lite_timer = 0.0
	if player == null or not is_instance_valid(player):
		return
	var player_pos := player.global_position
	var enter_radius := lite_radius + lite_hysteresis
	var exit_radius := maxf(lite_radius - lite_hysteresis, 0.0)
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if enemy == null or not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
			continue
		if not enemy.has_method("enter_lite_mode") or not enemy.has_method("exit_lite_mode"):
			continue
		if enemy.has_method("is_dead") and enemy.is_dead():
			continue
		var dist: float = enemy.global_position.distance_to(player_pos)
		if data_only_enabled and dist > (sim_radius + sim_hysteresis):
			continue
		if dist > enter_radius:
			enemy.enter_lite_mode()
			if lite_debug:
				Debug.log("npc_lite", "enemy=%s -> enter dist=%.2f" % [String(enemy.name), dist])
		elif dist < exit_radius:
			enemy.exit_lite_mode()
			if lite_debug:
				Debug.log("npc_lite", "enemy=%s -> exit dist=%.2f" % [String(enemy.name), dist])

# ---------------------------------------------------------------------------
# Data-only simulation — spawn/despawn basado en distancia sin nodo activo
# ---------------------------------------------------------------------------
func _tick_data_only(delta: float) -> void:
	if get_tree().paused or not data_only_enabled:
		return
	_sim_timer += delta
	if _sim_timer < maxf(sim_check_interval, 0.05):
		return
	_sim_timer = 0.0
	if player == null or not is_instance_valid(player):
		return
	var full_ai_r := maxf(sim_radius - sim_hysteresis, 0.0)
	var visual_r  := clampf(visual_radius, full_ai_r, sim_radius + sim_hysteresis - 1.0)
	var despawn_r := sim_radius + sim_hysteresis
	var player_pos: Vector2 = player.global_position
	var sim_delta: float = maxf(sim_check_interval, 0.05)
	for cpos in _loaded_chunks.keys():
		var chunk_pos: Vector2i = cpos
		_ensure_spawn_records(chunk_pos)
		var chunk_key: String = _chunk_key_fn.call(chunk_pos)
		for enemy_id in WorldSave.iter_enemy_ids_in_chunk(chunk_key):
			var state_v = WorldSave.get_enemy_state(chunk_key, enemy_id)
			if state_v == null:
				continue
			var state: Dictionary = state_v
			var enemy_pos: Vector2 = Vector2(state.get("pos", Vector2.ZERO))
			var dist: float = enemy_pos.distance_to(player_pos)
			var is_dead: bool = bool(state.get("is_dead", false))
			var node := _get_active_enemy_node(enemy_id)
			var should_spawn: bool = spawn_with_chunk or dist < visual_r
			if should_spawn and not is_dead and node == null and not spawning_enemy_ids.has(enemy_id):
				# spawn_with_chunk: node lives while chunk is loaded; lite when outside full-AI radius
				enqueue_spawn(chunk_pos, enemy_id, state, dist > full_ai_r)
			elif node != null:
				if not spawn_with_chunk and dist > despawn_r:
					if _can_despawn(node, state):
						despawn_enemy(enemy_id)
			elif not is_dead and not spawning_enemy_ids.has(enemy_id):
				# No active node, not spawning — simulate offscreen (data-only)
				_tick_data_behavior(enemy_id, state, sim_delta)
	if debug_counts:
		Debug.log("npc_data", "active=%d queued=%d data_beh=%d" % [
			active_enemies.size(), spawning_enemy_ids.size(), _data_behaviors.size()])

# ---------------------------------------------------------------------------
# API pública — llamada desde World
# ---------------------------------------------------------------------------

func enqueue_spawn(chunk_pos: Vector2i, enemy_id: String, state: Dictionary, start_lite: bool = false) -> void:
	if _spawn_queue == null:
		return
	# Flush data behavior state so the spawned node inherits it via save_state
	if _data_behaviors.has(enemy_id):
		state["world_behavior"] = (_data_behaviors[enemy_id] as BanditWorldBehavior).export_state()
		_remove_data_behavior(enemy_id)
	var chunk_key: String = _chunk_key_fn.call(chunk_pos)
	spawning_enemy_ids[enemy_id] = true
	var ring: int = max(abs(chunk_pos.x - current_player_chunk.x), abs(chunk_pos.y - current_player_chunk.y))
	var job: Dictionary = {
		"chunk_key": chunk_key,
		"kind": "enemy",
		"scene": bandit_scene,
		"global_position": Vector2(state.get("pos", Vector2.ZERO)),
		"init_data": {
			"properties": {"entity_uid": enemy_id, "enemy_chunk_key": chunk_key},
			"save_state": state,
		},
		"priority": ring,
		"uid": enemy_id,
		"start_lite": start_lite,
	}
	if _entity_root != null:
		job["parent_override"] = _entity_root
	_spawn_queue.enqueue(job)

func despawn_enemy(enemy_id: String) -> void:
	var node := _get_active_enemy_node(enemy_id)
	var chunk_key := _get_active_enemy_chunk_key(enemy_id)
	if node != null:
		if node.has_method("capture_save_state"):
			var state: Dictionary = node.call("capture_save_state")
			if node.has_node("DownedComponent"):
				var downed := node.get_node("DownedComponent")
				if downed.has_method("get_save_data"):
					state.merge(downed.call("get_save_data"), true)
			if chunk_key != "":
				WorldSave.set_enemy_state(chunk_key, enemy_id, state)
		if node.has_node("AIComponent"):
			var ai := node.get_node_or_null("AIComponent")
			if ai != null and ai.has_method("on_owner_exit_tree"):
				ai.call("on_owner_exit_tree")
		if node.has_node("AIWeaponController"):
			var ctrl := node.get_node_or_null("AIWeaponController")
			if ctrl != null and ctrl.has_method("clear_transient_input"):
				ctrl.call("clear_transient_input")
		EnemyRegistry.unregister_enemy(node)
		node.queue_free()
	_remove_data_behavior(enemy_id)
	_clear_enemy_tracking(enemy_id, true)

# Llamado desde World._on_spawn_queue_job_spawned cuando kind == "enemy"
func on_enemy_job_spawned(job: Dictionary, node: Node) -> void:
	var enemy_id: String = String(job.get("uid", ""))
	_register_active_enemy(enemy_id, String(job.get("chunk_key", "")), node)

	var save_state: Dictionary = job.get("init_data", {}).get("save_state", {})
	if node.has_node("DownedComponent"):
		var downed := node.get_node("DownedComponent")
		if downed.has_method("load_save_data"):
			downed.call("load_save_data", save_state)

	var start_lite: bool = bool(job.get("start_lite", false))
	if start_lite:
		if node.has_method("enter_lite_mode"):
			node.call("enter_lite_mode")
	else:
		if node.has_method("exit_lite_mode"):
			node.call("exit_lite_mode")
	EnemyRegistry.register_enemy(node)

	var member_role: String = String(save_state.get("role", "scavenger"))
	NpcProfileSystem.ensure_profile(enemy_id, "bandit", member_role)

	var group_id_on_spawn: String = String(save_state.get("group_id", ""))
	if group_id_on_spawn != "":
		var home_pos: Vector2 = Vector2(save_state.get("home_world_pos", Vector2.ZERO))
		BanditGroupMemory.register_member(group_id_on_spawn, enemy_id, member_role, home_pos, "bandits")

	if save_state.get("is_dead", false):
		NpcProfileSystem.set_status(enemy_id, "dead")
	elif save_state.get("is_downed", false):
		NpcProfileSystem.set_status(enemy_id, "downed")
		if node.has_node("AIComponent"):
			node.get_node("AIComponent").call("set_downed")

	# Hydrate AIComponent with tactical memory so the NPC appears "already in process"
	var mode_hint: String = String(save_state.get("ai_mode_hint", ""))
	if mode_hint != "" and mode_hint != "idle":
		var ai_node = node.get_node_or_null("AIComponent")
		if ai_node != null:
			var lsp = save_state.get("ai_last_seen_player_pos", null)
			if lsp is Vector2 and (lsp as Vector2) != Vector2.ZERO:
				ai_node.last_seen_player_pos  = lsp as Vector2
				ai_node.last_seen_target_time = float(save_state.get("ai_last_seen_time", 0.0))
			# Wake the NPC immediately if it spawns close to the player during a hunt
			if (mode_hint == "hunting" or mode_hint == "alerted") and player != null \
					and is_instance_valid(player):
				var spawn_pos: Vector2 = Vector2(save_state.get("pos", Vector2.ZERO))
				if spawn_pos.distance_to(player.global_position) < 600.0:
					if ai_node.has_method("wake_now"):
						ai_node.call("wake_now")

# Llamado desde World._on_spawn_queue_job_skipped cuando kind == "enemy"
func on_enemy_job_skipped(job: Dictionary) -> void:
	spawning_enemy_ids.erase(String(job.get("uid", "")))

# Llamado desde World._on_entity_died
func on_entity_died(uid: String) -> void:
	var chunk_key := _get_active_enemy_chunk_key(uid)
	if chunk_key != "":
		WorldSave.mark_enemy_dead(chunk_key, uid)
		# We do not clear tracking here to allow the corpse to persist if enabled.
		# despawn_enemy() will handle full cleanup when the chunk is unloaded or out of range.
		var dead_state = WorldSave.get_enemy_state(chunk_key, uid)
		if dead_state != null:
			var gid: String = String((dead_state as Dictionary).get("group_id", ""))
			if gid != "":
				BanditGroupMemory.remove_member(gid, uid)
				# If the leader just died, promote the first live non-dead member
				var g_after: Dictionary = BanditGroupMemory.get_group(gid)
				if String(g_after.get("leader_id", "")) == "":
					for mid in g_after.get("member_ids", []):
						var mid_str: String = String(mid)
						if NpcProfileSystem.get_profile(mid_str).get("status", "") != "dead":
							BanditGroupMemory.promote_leader(gid, mid_str)
							break
	_remove_data_behavior(uid)
	spawning_enemy_ids.erase(uid)
	NpcProfileSystem.set_status(uid, "dead")

# Llamado desde World.unload_chunk_entities
func on_chunk_unloaded(chunk_key: String) -> void:
	var ids_to_despawn: Array[String] = []
	for enemy_id in active_enemy_chunk.keys():
		if _get_active_enemy_chunk_key(String(enemy_id)) == chunk_key:
			ids_to_despawn.append(String(enemy_id))
	for enemy_id in ids_to_despawn:
		despawn_enemy(enemy_id)

	var spawning_to_erase: Array[String] = []
	for enemy_id in spawning_enemy_ids.keys():
		if String(enemy_id).begins_with("e:%s:" % chunk_key):
			spawning_to_erase.append(String(enemy_id))
	for enemy_id in spawning_to_erase:
		spawning_enemy_ids.erase(enemy_id)

# ---------------------------------------------------------------------------
# Internos
# ---------------------------------------------------------------------------

func _ensure_spawn_records(chunk_pos: Vector2i) -> void:
	var chunk_key: String = _chunk_key_fn.call(chunk_pos)
	if not WorldSave.get_chunk_enemy_spawns(chunk_key).is_empty():
		if _cliff_gen == null or not _world_to_tile.is_valid():
			return
		var stale := false
		var all_dead := true
		for eid in WorldSave.iter_enemy_ids_in_chunk(chunk_key):
			var st = WorldSave.get_enemy_state(chunk_key, eid)
			if st == null:
				continue
			if not bool((st as Dictionary).get("is_dead", false)):
				all_dead = false
			if _cliff_gen.is_cliff_tile(_world_to_tile.call(Vector2(st.get("pos", Vector2.ZERO)))):
				stale = true
				break
		if not stale and not all_dead:
			return
		Debug.log("npc_data", "[NpcSim] respawn chunk=%s all_dead=%s stale=%s" % [chunk_key, str(all_dead), str(stale)])
		WorldSave.clear_chunk_enemy_spawns(chunk_key)
	if not _chunk_save.has(chunk_pos):
		return
	var records: Array[Dictionary] = []
	var spawn_index: int = 0
	for camp in _chunk_save[chunk_pos].get("camps", []):
		if typeof(camp) != TYPE_DICTIONARY:
			continue
		var camp_tile: Vector2i = camp.get("tile", Vector2i.ZERO)
		var camp_world: Vector2 = _tile_to_world.call(camp_tile)
		var primary_offsets: Array[Vector2] = [
			Vector2(-28, -18), Vector2(32, -10), Vector2(-20, 30), Vector2(28, 24),
			Vector2(-60, -10), Vector2(60, -10), Vector2(-60, 20), Vector2(60, 20),
			Vector2(0, -50), Vector2(0, 50),
			Vector2(-40, -45), Vector2(40, -45), Vector2(-40, 45), Vector2(40, 45),
			Vector2(-80, 0), Vector2(80, 0),
			Vector2(-70, -35), Vector2(70, -35), Vector2(-70, 35), Vector2(70, 35),
		]
		var fallback_offsets: Array[Vector2] = [
			Vector2(-48, 0), Vector2(48, 0), Vector2(0, -48), Vector2(0, 48),
			Vector2(-96, 0), Vector2(96, 0), Vector2(0, -96), Vector2(0, 96),
		]
		var camp_index: int = _chunk_save[chunk_pos].get("camps", []).find(camp)
		var camp_group_id: String = "camp:%s:%03d" % [chunk_key, camp_index]

		var camp_member_index: int = 0
		for offset in primary_offsets:
			var enemy_id: String = "e:%s:%03d" % [chunk_key, spawn_index]
			var chosen_offset: Vector2 = offset
			if _cliff_gen != null and _world_to_tile.is_valid():
				var candidate: Vector2 = camp_world + offset
				if _cliff_gen.is_cliff_tile(_world_to_tile.call(candidate)):
					for fb in fallback_offsets:
						var fb_candidate: Vector2 = camp_world + fb
						if not _cliff_gen.is_cliff_tile(_world_to_tile.call(fb_candidate)):
							chosen_offset = fb
							break
			var enemy_pos: Vector2 = camp_world + chosen_offset
			var member_role: String
			match camp_member_index:
				0:    member_role = "leader"
				_:    member_role = "bodyguard" if camp_member_index <= 9 else "scavenger"

			var record: Dictionary = {
				"spawn_index":    spawn_index,
				"enemy_id":       enemy_id,
				"chunk_key":      chunk_key,
				"pos":            enemy_pos,
				"seed":           Seed.chunk_seed(chunk_pos.x, chunk_pos.y) ^ spawn_index,
				"hp":             3,
				"faction_id":     "bandits",
				"group_id":       camp_group_id,
				"role":           member_role,
				"home_world_pos": camp_world,
				"loadout": {"weapon_ids": ["ironpipe", "bow"], "equipped_weapon_id": "ironpipe"},
			}
			records.append(record)
			WorldSave.get_or_create_enemy_state(chunk_key, enemy_id, {
				"id":             enemy_id,
				"chunk_key":      chunk_key,
				"pos":            enemy_pos,
				"hp":             3,
				"is_dead":        false,
				"seed":           int(record["seed"]),
				"faction_id":     "bandits",
				"group_id":       camp_group_id,
				"role":           member_role,
				"home_world_pos": camp_world,
				"weapon_ids":     ["ironpipe", "bow"],
				"equipped_weapon_id": "ironpipe",
				"alert":          0.0,
				"last_seen_player_pos": Vector2.ZERO,
				"last_active_time":     0.0,
				"version":        1,
			})
			spawn_index += 1
			camp_member_index += 1
	WorldSave.ensure_chunk_enemy_spawns(chunk_key, records)
	# Prewarm fresh records once per session to disperse scavengers from camp center
	if not _prewarmed_chunks.has(chunk_key):
		_prewarmed_chunks[chunk_key] = true
		_prewarm_chunk(chunk_key)

func _can_despawn(node: Node, state: Dictionary) -> bool:
	if node == null or not is_instance_valid(node):
		return true
	if node.has_method("is_attacking") and bool(node.call("is_attacking")):
		return false
	var now: float = RunClock.now()
	var last_active: float = float(state.get("last_active_time", 0.0))
	if node.has_method("capture_save_state"):
		last_active = maxf(last_active, float(node.call("capture_save_state").get("last_active_time", 0.0)))
	return now - last_active >= maxf(despawn_grace_seconds, 0.0)


# ---------------------------------------------------------------------------
# Data-only behavior helpers
# Ownership: NpcSimulator while no active node; BanditBehaviorLayer while active.
# ---------------------------------------------------------------------------

func _get_world_bounds() -> Rect2:
	if not _tile_to_world.is_valid():
		return Rect2(0.0, 0.0, 4096.0, 4096.0)
	var origin: Vector2 = _tile_to_world.call(Vector2i(0, 0))
	var corner: Vector2 = _tile_to_world.call(Vector2i(_world_w_tiles, _world_h_tiles))
	return Rect2(origin, corner - origin)


func _ensure_data_behavior(enemy_id: String, state: Dictionary) -> BanditWorldBehavior:
	if _data_behaviors.has(enemy_id):
		return _data_behaviors[enemy_id] as BanditWorldBehavior
	var beh := BanditWorldBehavior.new()
	beh.setup({
		"home_pos":    Vector2(state.get("home_world_pos", Vector2.ZERO)),
		"role":        String(state.get("role", "scavenger")),
		"group_id":    String(state.get("group_id", "")),
		"member_id":   enemy_id,
		"cargo_count": int(state.get("cargo_count", 0)),
	})
	var wb = state.get("world_behavior", {})
	if wb is Dictionary and not (wb as Dictionary).is_empty():
		beh.import_state(wb as Dictionary)
	else:
		# Seed from enemy save seed for consistent randomness per session
		beh._rng.seed = absi(int(state.get("seed", 0)) ^ hash(enemy_id))
		beh._idle_timer = beh._rng.randf_range(NpcWorldBehavior.IDLE_WAIT_MIN, NpcWorldBehavior.IDLE_WAIT_MAX)
	_data_behaviors[enemy_id] = beh
	return beh


func _remove_data_behavior(enemy_id: String) -> void:
	_data_behaviors.erase(enemy_id)


const _RES_SCAN_RADIUS_SQ: float = 288.0 * 288.0   # matches BanditBehaviorLayer

func _build_data_behavior_ctx(enemy_id: String, state: Dictionary) -> Dictionary:
	var node_pos: Vector2 = Vector2(state.get("pos", Vector2.ZERO))
	var ctx: Dictionary = {
		"node_pos":          node_pos,
		"nearby_drops_info": [],
		"nearby_res_info":   _scan_nearby_resources(node_pos),
	}
	var group_id: String = String(state.get("group_id", ""))
	if group_id == "":
		return ctx
	var chunk_key: String = String(state.get("chunk_key", ""))
	var g: Dictionary = BanditGroupMemory.get_group(group_id)
	var leader_id: String = String(g.get("leader_id", ""))
	if leader_id == "" or leader_id == enemy_id:
		return ctx
	# Leader active?
	var lnode = _get_active_enemy_node(leader_id)
	if lnode != null:
		ctx["leader_pos"] = lnode.global_position
		return ctx
	# Leader data-only?
	var lstate = WorldSave.get_enemy_state(chunk_key, leader_id)
	if lstate != null:
		ctx["leader_pos"] = Vector2((lstate as Dictionary).get("pos", Vector2.ZERO))
	return ctx


func _scan_nearby_resources(node_pos: Vector2) -> Array:
	var result: Array = []
	for res in get_tree().get_nodes_in_group("world_resource"):
		var res_node := res as Node2D
		if res_node == null or not is_instance_valid(res_node) \
				or res_node.is_queued_for_deletion():
			continue
		if node_pos.distance_squared_to(res_node.global_position) <= _RES_SCAN_RADIUS_SQ:
			result.append({"pos": res_node.global_position})
	return result


func _tick_data_behavior(enemy_id: String, state: Dictionary, sim_delta: float) -> void:
	var beh: BanditWorldBehavior = _ensure_data_behavior(enemy_id, state)
	var ctx: Dictionary = _build_data_behavior_ctx(enemy_id, state)
	beh.tick(sim_delta, ctx)
	var vel: Vector2 = beh.get_desired_velocity()
	if vel.length_squared() > 0.01:
		var cur: Vector2  = Vector2(state.get("pos", Vector2.ZERO))
		var next: Vector2 = cur + vel * sim_delta
		var b: Rect2      = _get_world_bounds()
		next.x = clampf(next.x, b.position.x, b.position.x + b.size.x)
		next.y = clampf(next.y, b.position.y, b.position.y + b.size.y)
		state["pos"] = next
	state["world_behavior"] = beh.export_state()
	state["cargo_count"]    = beh.cargo_count

	# Tactical memory — read group intent so the spawned node can hit the ground running
	var gid: String = String(state.get("group_id", ""))
	if gid != "":
		var g: Dictionary = BanditGroupMemory.get_group(gid)
		var intent: String = String(g.get("current_group_intent", "idle"))
		state["ai_mode_hint"] = intent
		if intent == "hunting" or intent == "alerted":
			var lip: Vector2 = g.get("last_interest_pos", Vector2.ZERO)
			if lip != Vector2.ZERO:
				state["ai_last_seen_player_pos"] = lip
				state["ai_last_seen_time"]       = RunClock.now()


func _prewarm_chunk(chunk_key: String) -> void:
	const PREWARM_SECONDS: float = 20.0
	const PREWARM_STEP:    float = 1.0
	var steps: int = int(round(PREWARM_SECONDS / PREWARM_STEP))
	var prewarmed: int = 0
	for enemy_id in WorldSave.iter_enemy_ids_in_chunk(chunk_key):
		var state_v = WorldSave.get_enemy_state(chunk_key, enemy_id)
		if state_v == null:
			continue
		var state: Dictionary = state_v
		if bool(state.get("is_dead", false)):
			continue
		if state.has("world_behavior") and not reprewarm_existing:
			continue   # already has simulated state — loaded from save
		for _i in range(steps):
			_tick_data_behavior(enemy_id, state, PREWARM_STEP)
		prewarmed += 1
	if prewarmed > 0:
		Debug.log("npc_data", "[NpcSim] prewarm chunk=%s enemies=%d steps=%d reprewarm=%s" % [
			chunk_key, prewarmed, steps, str(reprewarm_existing)])
