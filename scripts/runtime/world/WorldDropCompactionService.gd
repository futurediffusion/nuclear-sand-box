extends RefCounted
class_name WorldDropCompactionService

const HOTSPOT_MAX_TRACKED: int = 32

var _world_spatial_index: WorldSpatialIndex
var _drop_pressure_service: WorldDropPressureService
var _world_to_tile: Callable = Callable()
var _tile_to_world: Callable = Callable()
var _now_msec_provider: Callable = Callable(Time, "get_ticks_msec")

var _drop_compaction_enabled: bool = true
var _drop_compaction_radius_px: float = 44.0
var _drop_compaction_max_nodes_inspected: int = 96
var _drop_compaction_max_merges_per_exec: int = 16
var _drop_compaction_hotspot_ttl_sec: float = 12.0
var _drop_compaction_hotspot_radius_px: float = 220.0
var _drop_compaction_min_cluster_size: int = 3
var _drop_pressure_high_merge_radius_mult: float = 1.55
var _drop_pressure_high_nodes_mult: float = 1.55
var _drop_pressure_high_merges_mult: float = 1.80
var _drop_pressure_critical_merge_radius_mult: float = 2.25
var _drop_pressure_critical_nodes_mult: float = 2.00
var _drop_pressure_critical_merges_mult: float = 2.40
var _chunk_size: int = 32

var _merged_drop_events: int = 0
var _drop_compaction_hotspots: Array[Dictionary] = []

func setup(ctx: Dictionary) -> void:
	_world_spatial_index = ctx.get("world_spatial_index", null) as WorldSpatialIndex
	_drop_pressure_service = ctx.get("drop_pressure_service", null) as WorldDropPressureService
	_world_to_tile = ctx.get("world_to_tile", Callable()) as Callable
	_tile_to_world = ctx.get("tile_to_world", Callable()) as Callable
	var now_msec_provider: Callable = ctx.get("now_msec_provider", Callable()) as Callable
	if now_msec_provider.is_valid():
		_now_msec_provider = now_msec_provider
	_drop_compaction_enabled = bool(ctx.get("drop_compaction_enabled", _drop_compaction_enabled))
	_drop_compaction_radius_px = float(ctx.get("drop_compaction_radius_px", _drop_compaction_radius_px))
	_drop_compaction_max_nodes_inspected = int(ctx.get("drop_compaction_max_nodes_inspected", _drop_compaction_max_nodes_inspected))
	_drop_compaction_max_merges_per_exec = int(ctx.get("drop_compaction_max_merges_per_exec", _drop_compaction_max_merges_per_exec))
	_drop_compaction_hotspot_ttl_sec = float(ctx.get("drop_compaction_hotspot_ttl_sec", _drop_compaction_hotspot_ttl_sec))
	_drop_compaction_hotspot_radius_px = float(ctx.get("drop_compaction_hotspot_radius_px", _drop_compaction_hotspot_radius_px))
	_drop_compaction_min_cluster_size = int(ctx.get("drop_compaction_min_cluster_size", _drop_compaction_min_cluster_size))
	_drop_pressure_high_merge_radius_mult = float(ctx.get("drop_pressure_high_merge_radius_mult", _drop_pressure_high_merge_radius_mult))
	_drop_pressure_high_nodes_mult = float(ctx.get("drop_pressure_high_nodes_mult", _drop_pressure_high_nodes_mult))
	_drop_pressure_high_merges_mult = float(ctx.get("drop_pressure_high_merges_mult", _drop_pressure_high_merges_mult))
	_drop_pressure_critical_merge_radius_mult = float(ctx.get("drop_pressure_critical_merge_radius_mult", _drop_pressure_critical_merge_radius_mult))
	_drop_pressure_critical_nodes_mult = float(ctx.get("drop_pressure_critical_nodes_mult", _drop_pressure_critical_nodes_mult))
	_drop_pressure_critical_merges_mult = float(ctx.get("drop_pressure_critical_merges_mult", _drop_pressure_critical_merges_mult))
	_chunk_size = int(ctx.get("chunk_size", _chunk_size))

func register_hotspot(world_pos: Vector2, score: int = 1) -> void:
	if world_pos == Vector2.INF:
		return
	var now_sec: float = float(_resolve_now_msec()) / 1000.0
	var ttl: float = maxf(1.0, _drop_compaction_hotspot_ttl_sec)
	var merge_radius: float = maxf(16.0, _drop_compaction_hotspot_radius_px)
	var merge_radius_sq: float = merge_radius * merge_radius
	for i in _drop_compaction_hotspots.size():
		var entry: Dictionary = _drop_compaction_hotspots[i]
		var pos: Vector2 = entry.get("pos", Vector2.INF)
		if pos == Vector2.INF:
			continue
		if pos.distance_squared_to(world_pos) <= merge_radius_sq:
			entry["score"] = int(entry.get("score", 1)) + maxi(1, score)
			entry["last_seen"] = now_sec
			entry["expires_at"] = now_sec + ttl
			_drop_compaction_hotspots[i] = entry
			return
	_drop_compaction_hotspots.append({
		"pos": world_pos,
		"score": maxi(1, score),
		"last_seen": now_sec,
		"expires_at": now_sec + ttl,
	})
	while _drop_compaction_hotspots.size() > HOTSPOT_MAX_TRACKED:
		_drop_compaction_hotspots.pop_front()

func get_hotspots() -> Array[Dictionary]:
	return _drop_compaction_hotspots.duplicate(true)

func execute_compaction_pass() -> int:
	if not _drop_compaction_enabled or _world_spatial_index == null:
		return 0
	var max_inspect: int = maxi(_drop_pressure_scaled_int(
		_drop_compaction_max_nodes_inspected,
		_drop_pressure_high_nodes_mult,
		_drop_pressure_critical_nodes_mult
	), 0)
	var max_merges: int = maxi(_drop_pressure_scaled_int(
		_drop_compaction_max_merges_per_exec,
		_drop_pressure_high_merges_mult,
		_drop_pressure_critical_merges_mult
	), 0)
	if max_inspect <= 0 or max_merges <= 0:
		return 0
	var anchors: Array[Vector2] = _build_anchor_list()
	if anchors.is_empty():
		return 0
	var inspected: int = 0
	var merges: int = 0
	var consumed_ids: Dictionary = {}
	var scan_radius: float = maxf(8.0, _drop_pressure_scaled_float(
		_drop_compaction_radius_px,
		_drop_pressure_high_merge_radius_mult,
		_drop_pressure_critical_merge_radius_mult
	))
	var scan_radius_sq: float = scan_radius * scan_radius
	for anchor in anchors:
		if inspected >= max_inspect or merges >= max_merges:
			break
		var candidates: Array = _world_spatial_index.get_runtime_nodes_near(
			WorldSpatialIndex.KIND_ITEM_DROP,
			anchor,
			scan_radius,
			{"max_candidates_eval": max_inspect - inspected}
		)
		var by_item_id: Dictionary = {}
		for raw_node in candidates:
			if inspected >= max_inspect:
				break
			var drop_node := raw_node as ItemDrop
			if drop_node == null or not is_instance_valid(drop_node) or drop_node.is_queued_for_deletion():
				continue
			inspected += 1
			var iid: int = drop_node.get_instance_id()
			if consumed_ids.has(iid):
				continue
			var id_key: String = String(drop_node.item_id).strip_edges()
			if id_key == "":
				continue
			if not by_item_id.has(id_key):
				by_item_id[id_key] = []
			(by_item_id[id_key] as Array).append(drop_node)
		for item_id in by_item_id.keys():
			if merges >= max_merges:
				break
			var cluster: Array = by_item_id[item_id]
			if cluster.size() < 2:
				continue
			cluster.sort_custom(func(a: ItemDrop, b: ItemDrop) -> bool:
				var ad: float = a.global_position.distance_squared_to(anchor)
				var bd: float = b.global_position.distance_squared_to(anchor)
				return ad < bd
			)
			var target := cluster[0] as ItemDrop
			if target == null or not is_instance_valid(target) or target.is_queued_for_deletion():
				continue
			for idx in range(1, cluster.size()):
				if merges >= max_merges:
					break
				var source := cluster[idx] as ItemDrop
				if source == null or not is_instance_valid(source) or source.is_queued_for_deletion():
					continue
				if consumed_ids.has(source.get_instance_id()) or source == target:
					continue
				if target.global_position.distance_squared_to(source.global_position) > scan_radius_sq:
					continue
				var src_amount: int = maxi(int(source.amount), 0)
				if src_amount <= 0:
					continue
				target.amount = maxi(0, int(target.amount)) + src_amount
				consumed_ids[source.get_instance_id()] = true
				if source.is_in_group("item_drop"):
					source.remove_from_group("item_drop")
				_world_spatial_index.unregister_runtime_node(source)
				source.queue_free()
				merges += 1
				_merged_drop_events += 1
				register_hotspot(target.global_position, 1)
				if merges >= max_merges:
					break
	return merges

func get_metrics_snapshot() -> Dictionary:
	return {
		"merged_drop_events": _merged_drop_events,
		"hotspots": _drop_compaction_hotspots.size(),
		"radius_px": _drop_compaction_radius_px,
		"max_nodes_inspected": _drop_compaction_max_nodes_inspected,
		"max_merges_per_exec": _drop_compaction_max_merges_per_exec,
	}

func _build_anchor_list() -> Array[Vector2]:
	var anchors: Array[Vector2] = []
	var seen_tiles: Dictionary = {}
	var now_sec: float = float(_resolve_now_msec()) / 1000.0
	_prune_hotspots(now_sec)
	var weighted_hotspots: Array[Dictionary] = []
	for entry in _drop_compaction_hotspots:
		var pos: Vector2 = entry.get("pos", Vector2.INF)
		if pos == Vector2.INF:
			continue
		var age: float = maxf(0.0, now_sec - float(entry.get("last_seen", now_sec)))
		var freshness: float = maxf(0.10, 1.0 - (age / maxf(1.0, _drop_compaction_hotspot_ttl_sec)))
		weighted_hotspots.append({
			"pos": pos,
			"weight": float(entry.get("score", 1)) * freshness,
		})
	weighted_hotspots.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("weight", 0.0)) > float(b.get("weight", 0.0))
	)
	for entry in weighted_hotspots:
		var pos: Vector2 = entry.get("pos", Vector2.INF)
		if pos == Vector2.INF:
			continue
		var tile: Vector2i = _call_world_to_tile(pos)
		if seen_tiles.has(tile):
			continue
		seen_tiles[tile] = true
		anchors.append(pos)
	var density_by_chunk: Dictionary = _world_spatial_index.get_runtime_node_count_by_chunk(WorldSpatialIndex.KIND_ITEM_DROP)
	var density_rank: Array[Dictionary] = []
	for cpos in density_by_chunk.keys():
		var count: int = int(density_by_chunk[cpos])
		if count < maxi(_drop_compaction_min_cluster_size, 2):
			continue
		var _chunk_half: int = int(_chunk_size * 0.5)
		density_rank.append({
			"pos": _call_tile_to_world(cpos * _chunk_size + Vector2i(_chunk_half, _chunk_half)),
			"count": count,
		})
	density_rank.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("count", 0)) > int(b.get("count", 0))
	)
	for entry in density_rank:
		var pos: Vector2 = entry.get("pos", Vector2.INF)
		if pos == Vector2.INF:
			continue
		var tile: Vector2i = _call_world_to_tile(pos)
		if seen_tiles.has(tile):
			continue
		seen_tiles[tile] = true
		anchors.append(pos)
	var max_anchors: int = maxi(4, int(float(maxi(0, _drop_compaction_max_nodes_inspected)) / 12.0))
	if anchors.size() > max_anchors:
		anchors.resize(max_anchors)
	return anchors

func _prune_hotspots(now_sec: float) -> void:
	for i in range(_drop_compaction_hotspots.size() - 1, -1, -1):
		var entry: Dictionary = _drop_compaction_hotspots[i]
		if now_sec > float(entry.get("expires_at", -1.0)):
			_drop_compaction_hotspots.remove_at(i)

func _drop_pressure_scaled_int(base_value: int, high_mult: float, critical_mult: float) -> int:
	if _drop_pressure_service == null:
		return maxi(int(ceil(float(base_value))), 1)
	return _drop_pressure_service.scale_int(base_value, high_mult, critical_mult)

func _drop_pressure_scaled_float(base_value: float, high_mult: float, critical_mult: float) -> float:
	if _drop_pressure_service == null:
		return base_value
	return _drop_pressure_service.scale_float(base_value, high_mult, critical_mult)

func _call_world_to_tile(world_pos: Vector2) -> Vector2i:
	if _world_to_tile.is_valid():
		return _world_to_tile.call(world_pos) as Vector2i
	return Vector2i(int(floor(world_pos.x)), int(floor(world_pos.y)))

func _call_tile_to_world(tile_pos: Vector2i) -> Vector2:
	if _tile_to_world.is_valid():
		return _tile_to_world.call(tile_pos) as Vector2
	return Vector2(tile_pos.x, tile_pos.y)

func _resolve_now_msec() -> int:
	if _now_msec_provider.is_valid():
		return int(_now_msec_provider.call())
	return Time.get_ticks_msec()
