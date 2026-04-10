extends RefCounted
class_name WorldSnapshot


## Canonical root world snapshot contract for save/load boundaries.
##
## This DTO is intentionally explicit for current architecture and does not try
## to be a generic persistence framework.
##
## Canonical:
## - save metadata (version/seed)
## - player/session state currently owned by SaveManager systems
## - global world flags and domain-system serialized state
## - chunk snapshots with chunk-owned canonical state
##
## Derived / non-canonical and intentionally excluded:
## - tilemap/collider/index projection state
## - runtime queues/caches/debug telemetry
## - live node references in scene tree

var snapshot_version: int = WorldSnapshotVersioning.LATEST_SNAPSHOT_VERSION
var save_version: int = 1
var world_seed: int = 0
var persistence_meta: Dictionary = {}

var player_pos: Vector2 = Vector2.ZERO
var player_inv: Array = []
var player_gold: int = 0

var run_clock: Dictionary = {}
var world_time: Dictionary = {}
var global_flags: Dictionary = {}

## Domain/system sections that are already canonical in SaveManager.
var faction_system: Dictionary = {}
var site_system: Dictionary = {}
var npc_profile_system: Dictionary = {}
var bandit_group_memory: Dictionary = {}
var extortion_queue: Variant = {}
var faction_hostility: Dictionary = {}

var chunks: Array[ChunkSnapshot] = []

static func from_dict(data: Dictionary) -> WorldSnapshot:
	var snapshot := WorldSnapshot.new()
	snapshot.snapshot_version = int(data.get("snapshot_version", 1))
	snapshot.save_version = int(data.get("save_version", 1))
	snapshot.world_seed = int(data.get("seed", 0))
	snapshot.persistence_meta = _dict_or_empty(data.get("persistence_meta", {}))
	var player_pos_raw: Variant = data.get("player_pos", Vector2.ZERO)
	if player_pos_raw is Vector2:
		snapshot.player_pos = player_pos_raw
	elif player_pos_raw is String:
		snapshot.player_pos = str_to_var(player_pos_raw) if str_to_var(player_pos_raw) is Vector2 else Vector2.ZERO
	else:
		snapshot.player_pos = Vector2.ZERO

	var player_inv_raw: Variant = data.get("player_inv", [])
	if player_inv_raw is Array:
		snapshot.player_inv = (player_inv_raw as Array).duplicate(true)
	else:
		snapshot.player_inv = []

	snapshot.player_gold = int(data.get("player_gold", 0))

	var run_clock_raw: Variant = data.get("run_clock", {})
	if run_clock_raw is Dictionary:
		snapshot.run_clock = (run_clock_raw as Dictionary).duplicate(true)

	var world_time_raw: Variant = data.get("world_time", {})
	if world_time_raw is Dictionary:
		snapshot.world_time = (world_time_raw as Dictionary).duplicate(true)

	var global_flags_raw: Variant = data.get("global_flags", {})
	if global_flags_raw is Dictionary:
		snapshot.global_flags = (global_flags_raw as Dictionary).duplicate(true)

	snapshot.faction_system = _dict_or_empty(data.get("faction_system", {}))
	snapshot.site_system = _dict_or_empty(data.get("site_system", {}))
	snapshot.npc_profile_system = _dict_or_empty(data.get("npc_profile_system", {}))
	snapshot.bandit_group_memory = _dict_or_empty(data.get("bandit_group_memory", {}))
	snapshot.extortion_queue = data.get("extortion_queue", {})
	snapshot.faction_hostility = _dict_or_empty(data.get("faction_hostility", {}))

	var chunks_raw: Variant = data.get("chunks", [])
	if chunks_raw is Array:
		for entry in chunks_raw:
			if entry is Dictionary:
				snapshot.chunks.append(ChunkSnapshot.from_dict(entry as Dictionary))

	return snapshot

func to_dict() -> Dictionary:
	var serialized_chunks: Array[Dictionary] = []
	for chunk_snapshot: ChunkSnapshot in chunks:
		if chunk_snapshot == null:
			continue
		serialized_chunks.append(chunk_snapshot.to_dict())

	return {
		"snapshot_version": snapshot_version,
		"save_version": save_version,
		"seed": world_seed,
		"persistence_meta": persistence_meta.duplicate(true),
		"player_pos": player_pos,
		"player_inv": player_inv.duplicate(true),
		"player_gold": player_gold,
		"run_clock": run_clock.duplicate(true),
		"world_time": world_time.duplicate(true),
		"global_flags": global_flags.duplicate(true),
		"faction_system": faction_system.duplicate(true),
		"site_system": site_system.duplicate(true),
		"npc_profile_system": npc_profile_system.duplicate(true),
		"bandit_group_memory": bandit_group_memory.duplicate(true),
		"extortion_queue": extortion_queue,
		"faction_hostility": faction_hostility.duplicate(true),
		"chunks": serialized_chunks,
	}

static func _dict_or_empty(value: Variant) -> Dictionary:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return {}
