extends Node
class_name EntitySpawnCoordinator

const _STAGE_ENTITIES: String = "enqueue/spawn entities"

# Asignado por World via setup()
var prop_spawner: PropSpawner = null
var npc_simulator: NpcSimulator = null
var chunk_save: Dictionary = {}      # ref a World.chunk_save
var loaded_chunks: Dictionary = {}   # ref a World.loaded_chunks
var tilemap: TileMap = null
var copper_ore_scene: PackedScene = null
var bandit_camp_scene: PackedScene = null
var bandit_scene: PackedScene = null
var tavern_keeper_scene: PackedScene = null
var current_player_chunk: Vector2i = Vector2i(-999, -999)

var _make_spawn_ctx: Callable
var _tile_to_world: Callable
var _chunk_key_fn: Callable
var _chunk_from_key_fn: Callable
var _enqueue_structure_tile_stage: Callable
var _record_stage_time: Callable

# Estado propio
var chunk_entities: Dictionary = {}      # chunk_pos -> Array[Node]
var chunk_saveables: Dictionary = {}     # chunk_pos -> Array[Node]
var queued_entity_chunks: Dictionary = {}
var entities_spawned_chunks: Dictionary = {}

var _spawn_queue: SpawnBudgetQueue = null

func setup(ctx: Dictionary) -> void:
	prop_spawner = ctx["prop_spawner"]
	npc_simulator = ctx["npc_simulator"]
	chunk_save = ctx["chunk_save"]
	loaded_chunks = ctx["loaded_chunks"]
	tilemap = ctx["tilemap"]
	copper_ore_scene = ctx.get("copper_ore_scene")
	bandit_camp_scene = ctx.get("bandit_camp_scene")
	bandit_scene = ctx.get("bandit_scene")
	tavern_keeper_scene = ctx.get("tavern_keeper_scene")
	_make_spawn_ctx = ctx["make_spawn_ctx"]
	_tile_to_world = ctx["tile_to_world"]
	_chunk_key_fn = ctx["chunk_key"]
	_chunk_from_key_fn = ctx["chunk_from_key"]
	_enqueue_structure_tile_stage = ctx["enqueue_structure_tile_stage"]
	_record_stage_time = ctx["record_stage_time"]

	_spawn_queue = SpawnBudgetQueue.new()
	_spawn_queue.name = "SpawnBudgetQueue"
	_spawn_queue.spawn_parent = tilemap
	_spawn_queue.chunk_active_checker = Callable(self, "_is_chunk_key_loaded")
	_spawn_queue.job_spawned.connect(_on_job_spawned)
	_spawn_queue.job_skipped.connect(_on_job_skipped)
	_spawn_queue.chunk_drained.connect(_on_chunk_drained)
	add_child(_spawn_queue)

func get_spawn_queue() -> SpawnBudgetQueue:
	return _spawn_queue

func _process(delta: float) -> void:
	if _spawn_queue != null:
		_spawn_queue.process_queue(delta)

func set_player_pos(world_pos: Vector2) -> void:
	if _spawn_queue != null:
		_spawn_queue.set_player_world_pos(world_pos)

# ---------------------------------------------------------------------------
# API pública — llamada desde World
# ---------------------------------------------------------------------------

func load_chunk(chunk_pos: Vector2i) -> void:
	chunk_entities[chunk_pos] = []
	chunk_saveables[chunk_pos] = []
	if queued_entity_chunks.has(chunk_pos):
		return
	queued_entity_chunks[chunk_pos] = true
	prop_spawner.rebuild_chunk_occupied_tiles(chunk_pos, _make_spawn_ctx.call())

	if not chunk_save.has(chunk_pos):
		queued_entity_chunks.erase(chunk_pos)
		entities_spawned_chunks[chunk_pos] = true
		return
	_enqueue_structure_tile_stage.call(chunk_pos)

func enqueue_entities(chunk_pos: Vector2i) -> void:
	var t0: int = Time.get_ticks_usec()
	if not chunk_save.has(chunk_pos):
		queued_entity_chunks.erase(chunk_pos)
		entities_spawned_chunks[chunk_pos] = true
		_record_stage_time.call(_STAGE_ENTITIES, chunk_pos, _us_to_ms(t0))
		return

	var cx: int = chunk_pos.x
	var cy: int = chunk_pos.y
	var chunk_key: String = _chunk_key_fn.call(chunk_pos)
	var chunk_ring: int = max(abs(chunk_pos.x - current_player_chunk.x), abs(chunk_pos.y - current_player_chunk.y))
	var jobs: Array[Dictionary] = []

	var ores_count: int = chunk_save[chunk_pos]["ores"].size()
	var camps_count: int = chunk_save[chunk_pos]["camps"].size()
	var placements_count: int = chunk_save[chunk_pos].get("placements", []).size()
	Debug.log("chunk", "LOAD_ENTITIES chunk=(%d,%d) placements=%d ores=%d camps=%d" % [cx, cy, placements_count, ores_count, camps_count])
	WorldSave.get_chunk_save(cx, cy)

	# 1) ORES
	for d in chunk_save[chunk_pos]["ores"]:
		var tpos: Vector2i = d["tile"]
		var ore_uid: String = UID.make_uid("ore_copper", "", tpos)
		var ore_state = WorldSave.get_entity_state(cx, cy, ore_uid)
		var ore_init: Dictionary = {
			"properties": {"entity_uid": ore_uid},
			"worldsave": {
				"cx": cx, "cy": cy, "uid": ore_uid,
				"init_if_missing": ore_state == null,
			}
		}
		if ore_state != null:
			ore_init["save_state"] = ore_state
		elif d.has("remaining") and d["remaining"] != -1:
			ore_init["save_state"] = {"remaining": int(d["remaining"])}
		jobs.append({
			"chunk_key": chunk_key, "kind": "ore",
			"scene": copper_ore_scene, "tile": tpos,
			"global_position": _tile_to_world.call(tpos),
			"init_data": ore_init, "priority": chunk_ring,
			"uid": ore_uid,
		})

	# 2) CAMPS
	for c in chunk_save[chunk_pos]["camps"]:
		var ct: Vector2i = c["tile"]
		jobs.append({
			"chunk_key": chunk_key, "kind": "camp",
			"scene": bandit_camp_scene, "tile": ct,
			"global_position": _tile_to_world.call(ct),
			"init_data": {"properties": {"bandit_scene": bandit_scene, "max_bandits_alive": 0}},
			"priority": chunk_ring,
			"uid": UID.make_uid("camp_bandit", "", ct),
		})
	npc_simulator._ensure_spawn_records(chunk_pos)

	# 3) PLACEMENTS (props + npc_keeper)
	var spawned_count: int = 0
	var spawned_npc_count: int = 0
	var spawned_keeper_uids: Dictionary = {}
	for p in chunk_save[chunk_pos].get("placements", []):
		if typeof(p) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = p
		var kind: String = String(d.get("kind", ""))

		if kind == "prop":
			var prop_id: String = String(d.get("prop_id", ""))
			var path: String = PropDB.scene_path(prop_id)
			if path == "": continue
			var ps: PackedScene = load(path) as PackedScene
			if ps == null: continue
			var ccell: Array = d.get("cell", [0, 0])
			var cell: Vector2i = Vector2i(int(ccell[0]), int(ccell[1]))
			jobs.append({
				"chunk_key": chunk_key, "kind": "prop", "scene": ps, "tile": cell,
				"global_position": _tile_to_world.call(cell),
				"init_data": {"properties": {"z_index": tilemap.z_index + 5}},
				"priority": chunk_ring,
				"uid": UID.make_uid("prop_%s" % prop_id, "", cell),
			})
			spawned_count += 1

		elif kind == "npc_keeper":
			if tavern_keeper_scene == null: continue
			var site_id: String = String(d.get("site_id", ""))
			var keeper_uid: String = UID.make_uid("npc_keeper", site_id)
			if spawned_keeper_uids.has(keeper_uid): continue
			spawned_keeper_uids[keeper_uid] = true
			var keeper_state = WorldSave.get_entity_state(cx, cy, keeper_uid)
			if keeper_state == null:
				WorldSave.set_entity_state(cx, cy, keeper_uid, {"spawned": true})
			var ccell: Array = d.get("cell", [0, 0])
			var counter_cell: Vector2i = Vector2i(int(ccell[0]), int(ccell[1]))
			var imin: Array = d.get("inner_min", [0, 0])
			var imax: Array = d.get("inner_max", [0, 0])
			jobs.append({
				"chunk_key": chunk_key, "kind": "npc_keeper",
				"scene": tavern_keeper_scene, "tile": counter_cell,
				"global_position": _tile_to_world.call(counter_cell),
				"init_data": {"properties": {
					"entity_uid": keeper_uid, "_tilemap": tilemap,
					"tavern_inner_min": Vector2i(int(imin[0]), int(imin[1])),
					"tavern_inner_max": Vector2i(int(imax[0]), int(imax[1])),
					"counter_tile": counter_cell,
				}, "save_state": keeper_state},
				"priority": chunk_ring, "uid": keeper_uid,
			})
			spawned_npc_count += 1
			spawned_count += 1

	if _spawn_queue != null and not jobs.is_empty():
		_spawn_queue.enqueue_many(jobs)
	else:
		queued_entity_chunks.erase(chunk_pos)
		entities_spawned_chunks[chunk_pos] = true

	Debug.log("chunk", "SPAWNED chunk=(%d,%d) props=%d npcs=%d ores=%d camps=%d" % [cx, cy, spawned_count - spawned_npc_count, spawned_npc_count, ores_count, camps_count])
	_record_stage_time.call(_STAGE_ENTITIES, chunk_pos, _us_to_ms(t0))

# Parte de entidades del unload (world.gd gestiona el resto: colas de tiles/colisión)
func unload_entities(chunk_pos: Vector2i) -> void:
	var chunk_key: String = _chunk_key_fn.call(chunk_pos)
	if _spawn_queue != null:
		_spawn_queue.cancel_chunk(chunk_key)
	npc_simulator.on_chunk_unloaded(chunk_key)
	queued_entity_chunks.erase(chunk_pos)

	if not chunk_entities.has(chunk_pos):
		return

	var cx: int = chunk_pos.x
	var cy: int = chunk_pos.y
	if chunk_saveables.has(chunk_pos):
		for entity in chunk_saveables[chunk_pos]:
			if not is_instance_valid(entity): continue
			if not entity.has_method("get_save_state"): continue
			var uid_value = entity.get("entity_uid")
			if uid_value == null: continue
			var uid: String = String(uid_value)
			if uid == "": continue
			WorldSave.set_entity_state(cx, cy, uid, entity.get_save_state())

	if chunk_save.has(chunk_pos):
		var ore_list = chunk_save[chunk_pos]["ores"]
		for e in chunk_entities[chunk_pos]:
			if is_instance_valid(e) and e is CopperOre:
				var tile: Vector2i = _world_to_tile_local(e.global_position)
				for d in ore_list:
					if d["tile"] == tile:
						d["remaining"] = int(e.get("remaining"))
						break

	for e in chunk_entities[chunk_pos]:
		if not is_instance_valid(e): continue
		if e.has_method("enter_lite_mode"):
			e.enter_lite_mode()
		if e.has_node("AIComponent"):
			var ai: Node = e.get_node_or_null("AIComponent")
			if ai != null and ai.has_method("on_owner_exit_tree"):
				ai.on_owner_exit_tree()
		e.queue_free()
	chunk_entities.erase(chunk_pos)
	chunk_saveables.erase(chunk_pos)

func enqueue_prefetched_jobs(chunk_pos: Vector2i, priority_offset: int) -> void:
	if _spawn_queue == null or not chunk_save.has(chunk_pos):
		return
	var jobs: Array[Dictionary] = []
	var chunk_key: String = _chunk_key_fn.call(chunk_pos)
	var chunk_ring: int = max(abs(chunk_pos.x - current_player_chunk.x), abs(chunk_pos.y - current_player_chunk.y))
	var priority: int = chunk_ring + priority_offset
	for d in chunk_save[chunk_pos].get("ores", []):
		var tpos: Vector2i = d["tile"]
		jobs.append({
			"chunk_key": chunk_key, "kind": "ore",
			"scene": copper_ore_scene, "tile": tpos,
			"global_position": _tile_to_world.call(tpos),
			"priority": priority,
			"uid": UID.make_uid("ore_copper", "", tpos),
		})
	for p in chunk_save[chunk_pos].get("placements", []):
		if typeof(p) != TYPE_DICTIONARY or String(p.get("kind", "")) != "prop":
			continue
		var prop_id: String = String(p.get("prop_id", ""))
		var path: String = PropDB.scene_path(prop_id)
		if path == "": continue
		var ps: PackedScene = load(path) as PackedScene
		if ps == null: continue
		var ccell: Array = p.get("cell", [0, 0])
		var cell: Vector2i = Vector2i(int(ccell[0]), int(ccell[1]))
		jobs.append({
			"chunk_key": chunk_key, "kind": "prop", "scene": ps, "tile": cell,
			"global_position": _tile_to_world.call(cell),
			"priority": priority,
			"uid": UID.make_uid("prop_%s" % prop_id, "", cell),
		})
	if not jobs.is_empty():
		_spawn_queue.enqueue_many(jobs)

# ---------------------------------------------------------------------------
# Callbacks del SpawnBudgetQueue
# ---------------------------------------------------------------------------

func _on_job_spawned(job: Dictionary, node: Node) -> void:
	var chunk_pos: Vector2i = _chunk_from_key_fn.call(String(job.get("chunk_key", "")))
	if chunk_pos.x == -99999:
		return
	if not chunk_entities.has(chunk_pos):
		chunk_entities[chunk_pos] = []
	if not chunk_saveables.has(chunk_pos):
		chunk_saveables[chunk_pos] = []
	chunk_entities[chunk_pos].append(node)
	var kind: String = String(job.get("kind", ""))
	if kind == "ore" or kind == "npc_keeper":
		chunk_saveables[chunk_pos].append(node)
	elif kind == "enemy":
		npc_simulator.on_enemy_job_spawned(job, node)
	if kind == "ore":
		var ws: Dictionary = job.get("init_data", {}).get("worldsave", {})
		if bool(ws.get("init_if_missing", false)) and node.has_method("get_save_state"):
			WorldSave.set_entity_state(int(ws.get("cx", chunk_pos.x)), int(ws.get("cy", chunk_pos.y)), String(ws.get("uid", "")), node.call("get_save_state"))

func _on_job_skipped(job: Dictionary, reason: String) -> void:
	var kind: String = String(job.get("kind", ""))
	if kind == "enemy":
		npc_simulator.on_enemy_job_skipped(job)
	if reason != "chunk_inactive":
		return
	var chunk_pos: Vector2i = _chunk_from_key_fn.call(String(job.get("chunk_key", "")))
	if chunk_pos.x == -99999:
		return
	queued_entity_chunks.erase(chunk_pos)
	if loaded_chunks.has(chunk_pos):
		call_deferred("load_chunk", chunk_pos)

func _on_chunk_drained(chunk_key: String) -> void:
	var chunk_pos: Vector2i = _chunk_from_key_fn.call(chunk_key)
	if chunk_pos.x == -99999:
		return
	queued_entity_chunks.erase(chunk_pos)
	entities_spawned_chunks[chunk_pos] = true

# ---------------------------------------------------------------------------
# Internos
# ---------------------------------------------------------------------------

func _is_chunk_key_loaded(chunk_key: String) -> bool:
	var cpos: Vector2i = _chunk_from_key_fn.call(chunk_key)
	return loaded_chunks.has(cpos)

func _world_to_tile_local(world_pos: Vector2) -> Vector2i:
	return tilemap.local_to_map(tilemap.to_local(world_pos))

func _us_to_ms(start_us: int) -> float:
	return float(Time.get_ticks_usec() - start_us) / 1000.0
