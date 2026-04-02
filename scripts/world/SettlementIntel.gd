class_name SettlementIntel
extends RefCounted

# --- Interest marker constants ---
const MERGE_RADIUS: float = 96.0
const WORKBENCH_RESCAN_INTERVAL: float = 120.0
const TTL_BY_KIND: Dictionary = {
	"copper_mined":      150.0,
	"stone_mined":       150.0,
	"wood_chopped":      150.0,
	"structure_placed":  180.0,
	"workbench":          -1.0,
}

# --- Base detection constants ---
# 25×25 tile window around each door. At 32px/tile → 800×800px max room.
const BASE_SCAN_WINDOW_HALF: int = 12
const MIN_INTERIOR_TILES: int = 4
const MIN_WALL_COUNT: int = 4
const MIN_DOOR_WALL_ADJACENCY: int = 2
const BASE_RESCAN_INTERVAL: float = 10.0
const BASE_SCAN_RADIUS_DEFAULT: float = 576.0  # ~18 tiles from player
const BASE_SCAN_DOOR_BUDGET_PER_PULSE: int = 4
const BASE_SCAN_PHASE_RATIO: float = 0.28
const WORKBENCH_SCAN_PHASE_RATIO: float = 0.61
const INTEL_LOG_SAMPLE_HEAVY: int = 8
const BASE_SCAN_CHUNK_RADIUS_MULT: float = 1.75

# Cardinal directions used in flood fill and adjacency checks
const _CARDINALS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
]

class FloodFillResult:
	var tiles: Array[Vector2i] = []
	var escaped: bool = false

# --- Interest marker state ---
var _markers: Array[Dictionary] = []
var _elapsed: float = 0.0
var _rescan_timer: float = 0.0
var _dirty: bool = false

# --- Base detection state ---
var _bases: Array[Dictionary] = []
var _base_scan_dirty: bool = false
var _base_rescan_timer: float = 0.0
var _pending_base_scan: Dictionary = {}

var _world_to_tile_cb: Callable
var _tile_to_world_cb: Callable
var _player_pos_getter: Callable
var _cadence: WorldCadenceCoordinator
var _world_spatial_index: WorldSpatialIndex
var _flood_result: FloodFillResult = FloodFillResult.new()
var _last_placeables_change_serial: int = 0
var _dirty_workbench_chunks: Dictionary = {}
var _dirty_base_chunks: Dictionary = {}
var _pending_base_scan_jobs: Array[Dictionary] = []
var _partial_workbench_rescans: int = 0
var _full_workbench_rescans: int = 0
var _partial_base_scan_jobs_enqueued: int = 0
var _global_scan_fallbacks: int = 0


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

func setup(ctx: Dictionary) -> void:
	_world_to_tile_cb  = ctx.get("world_to_tile",    Callable())
	_tile_to_world_cb  = ctx.get("tile_to_world",    Callable())
	_player_pos_getter = ctx.get("player_pos_getter", Callable())
	_cadence = ctx.get("cadence") as WorldCadenceCoordinator
	_world_spatial_index = ctx.get("world_spatial_index") as WorldSpatialIndex
	# Cadence only schedules when expensive rescans run.
	# The data boundary stays the same: runtime markers here, persistence in WorldSave.
	# Without cadence, fall back to local timers.

	if PlacementSystem != null \
			and not PlacementSystem.placement_completed.is_connected(_on_placement_completed):
		PlacementSystem.placement_completed.connect(_on_placement_completed)

	if GameEvents != null \
			and not GameEvents.resource_harvested.is_connected(_on_resource_harvested):
		GameEvents.resource_harvested.connect(_on_resource_harvested)

	_dirty = true
	_base_scan_dirty = true
	_last_placeables_change_serial = int(WorldSave.placed_entities_change_serial)


# ---------------------------------------------------------------------------
# Tick
# ---------------------------------------------------------------------------

func process(delta: float) -> void:
	_elapsed += delta
	var use_world_cadence: bool = _cadence != null
	if not use_world_cadence:
		_rescan_timer += delta
	_base_rescan_timer += delta

	# --- TTL expiry ---
	var i := _markers.size() - 1
	while i >= 0:
		var m: Dictionary = _markers[i]
		if not bool(m.get("persistent", false)):
			if _elapsed >= float(m.get("expires_at", 0.0)):
				if _should_log_intel("marker_expired", INTEL_LOG_SAMPLE_HEAVY):
					Debug.log("intel", "[MARKER] expired kind=%s tile=%s" % [
						m.get("kind", "?"), str(m.get("tile_pos", Vector2i.ZERO))])
				_markers.remove_at(i)
		i -= 1

	var next_placeable_serial: int = int(WorldSave.placed_entities_change_serial)
	if next_placeable_serial != _last_placeables_change_serial:
		_collect_placeable_chunk_deltas(next_placeable_serial)

	var workbench_pulses: int = _cadence.consume_lane(&"settlement_workbench_scan") if use_world_cadence else 0
	var rescan_interval_elapsed: bool = _rescan_timer >= WORKBENCH_RESCAN_INTERVAL
	if _dirty or not _dirty_workbench_chunks.is_empty() or workbench_pulses > 0 or rescan_interval_elapsed:
		_rescan_timer = 0.0
		var force_full: bool = _dirty or rescan_interval_elapsed
		var changed_chunks: Array[Vector2i] = _collect_dirty_chunk_keys(_dirty_workbench_chunks)
		_dirty = false
		_scan_workbenches(changed_chunks, force_full)
		_dirty_workbench_chunks.clear()

	var base_scan_pulses: int = _cadence.consume_lane(&"settlement_base_scan") if use_world_cadence else 0
	if _player_pos_getter.is_valid() and (_base_scan_dirty or base_scan_pulses > 0 or _base_rescan_timer >= BASE_RESCAN_INTERVAL):
		_base_rescan_timer = 0.0
		_base_scan_dirty = false
		_pending_base_scan_jobs.clear()
		_ensure_base_scan_job(_player_pos_getter.call(), BASE_SCAN_RADIUS_DEFAULT)
	elif not _dirty_base_chunks.is_empty():
		_enqueue_base_scans_for_dirty_chunks()

	_process_pending_base_scan(BASE_SCAN_DOOR_BUDGET_PER_PULSE)


# ---------------------------------------------------------------------------
# Interest marker API
# ---------------------------------------------------------------------------

func record_interest_event(kind: String, world_pos: Vector2, meta: Dictionary = {}) -> void:
	var tile_pos := _world_to_tile(world_pos)
	var ttl: float = float(TTL_BY_KIND.get(kind, 150.0))
	var persistent: bool = ttl < 0.0

	for m in _markers:
		if m.get("kind", "") != kind:
			continue
		var mpos: Vector2 = m.get("world_pos", Vector2.ZERO)
		if mpos.distance_to(world_pos) < MERGE_RADIUS:
			m["world_pos"] = world_pos
			m["tile_pos"]  = tile_pos
			if not persistent:
				m["expires_at"] = _elapsed + ttl
			if not meta.is_empty():
				m["metadata"] = meta
			if _should_log_intel("marker_refreshed", INTEL_LOG_SAMPLE_HEAVY):
				Debug.log("intel", "[MARKER] refreshed kind=%s tile=%s" % [kind, str(tile_pos)])
			return

	var marker: Dictionary = {
		"id":         kind + "_" + str(tile_pos.x) + "_" + str(tile_pos.y),
		"kind":       kind,
		"world_pos":  world_pos,
		"tile_pos":   tile_pos,
		"created_at": _elapsed,
		"expires_at": -1.0 if persistent else _elapsed + ttl,
		"persistent": persistent,
		"metadata":   meta,
	}
	_markers.append(marker)
	if _can_log_intel():
		Debug.log("intel", "[MARKER] created kind=%s tile=%s persistent=%s" % [
			kind, str(tile_pos), str(persistent)])


func get_interest_markers_near(world_pos: Vector2, radius: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var r2 := radius * radius
	for m in _markers:
		if (m.get("world_pos", Vector2.ZERO) as Vector2).distance_squared_to(world_pos) <= r2:
			result.append(m)
	return result


## Re-scan WorldSave for workbench placeables and sync persistent markers.
## Call this when a workbench may have been placed or removed outside a signal.
func rescan_workbench_markers() -> void:
	_scan_workbenches()


## Mark the workbench scan as dirty so it runs on the next process() tick.
## Note: scope is global (no per-zone filtering currently).
func mark_interest_scan_dirty() -> void:
	_dirty = true


# ---------------------------------------------------------------------------
# Base detection API
# ---------------------------------------------------------------------------

## Force an immediate base rescan around `world_pos` within `radius` pixels.
func rescan_bases_near(world_pos: Vector2, radius: float) -> void:
	_ensure_base_scan_job(world_pos, radius, true)
	_process_pending_base_scan(maxi(BASE_SCAN_DOOR_BUDGET_PER_PULSE * 2, 1))


## Return all detected bases whose center is within `radius` of `world_pos`.
func get_detected_bases_near(world_pos: Vector2, radius: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var r2 := radius * radius
	for b in _bases:
		if (b.get("center_world_pos", Vector2.ZERO) as Vector2).distance_squared_to(world_pos) <= r2:
			result.append(b)
	return result


## True if any detected base center is within `radius` of `world_pos`.
func has_detected_base_near(world_pos: Vector2, radius: float) -> bool:
	var r2 := radius * radius
	for b in _bases:
		if (b.get("center_world_pos", Vector2.ZERO) as Vector2).distance_squared_to(world_pos) <= r2:
			return true
	return false


## Mark base scan dirty (triggers rescan within BASE_RESCAN_INTERVAL or sooner).
func mark_base_scan_dirty_near(_world_pos: Vector2) -> void:
	_base_scan_dirty = true


# ---------------------------------------------------------------------------
# Interest marker internals
# ---------------------------------------------------------------------------

func _scan_workbenches(changed_chunks: Array[Vector2i] = [], force_full: bool = false) -> void:
	if changed_chunks.is_empty():
		force_full = true
	var live_uids: Dictionary = {}
	if force_full and _world_spatial_index != null:
		# Honest boundary: workbench persistence is still canonical in WorldSave.
		# WorldSpatialIndex only gives us a derived item-id view so we do not walk every chunk here.
		for entry in _world_spatial_index.get_all_placeables_by_item_id("workbench"):
			var uid := String(entry.get("uid", ""))
			if uid != "":
				live_uids[uid] = entry
	elif force_full:
		for ckey in WorldSave.placed_entities_by_chunk:
			var chunk_dict: Dictionary = WorldSave.placed_entities_by_chunk[ckey]
			for uid in chunk_dict:
				var entry: Dictionary = chunk_dict[uid]
				if String(entry.get("item_id", "")).strip_edges() == "workbench":
					live_uids[uid] = entry
	else:
		for chunk_pos in changed_chunks:
			var entries: Array[Dictionary] = []
			if _world_spatial_index != null:
				entries = _world_spatial_index.get_placeables_in_chunk(chunk_pos.x, chunk_pos.y, ["workbench"])
			else:
				entries = _get_worldsave_placeables_in_chunk(chunk_pos.x, chunk_pos.y, "workbench")
			for entry in entries:
				var uid := String(entry.get("uid", ""))
				if uid != "":
					live_uids[uid] = entry

	# Remove stale workbench markers
	var i := _markers.size() - 1
	while i >= 0:
		var m: Dictionary = _markers[i]
		if m.get("kind", "") == "workbench":
			var metadata_variant: Variant = m.get("metadata", null)
			var uid: String = String((metadata_variant as Dictionary).get("uid", "")) if metadata_variant is Dictionary else ""
			var marker_tile: Vector2i = m.get("tile_pos", Vector2i.ZERO)
			var marker_chunk: Vector2i = _tile_to_chunk(marker_tile)
			var should_consider: bool = force_full or _contains_chunk(changed_chunks, marker_chunk)
			if should_consider and uid != "" and not live_uids.has(uid):
				if _can_log_intel():
					Debug.log("intel", "[MARKER] persistent removed kind=workbench uid=%s" % uid)
				_markers.remove_at(i)
		i -= 1

	# Add missing workbench markers
	var existing_uids: Dictionary = {}
	for m in _markers:
		if m.get("kind", "") == "workbench":
			var metadata_variant: Variant = m.get("metadata", null)
			var uid: String = String((metadata_variant as Dictionary).get("uid", "")) if metadata_variant is Dictionary else ""
			if uid != "":
				existing_uids[uid] = true

	for uid in live_uids:
		if existing_uids.has(uid):
			continue
		var entry: Dictionary = live_uids[uid]
		var tile := Vector2i(int(entry.get("tile_pos_x", 0)), int(entry.get("tile_pos_y", 0)))
		var wpos := _tile_to_world(tile)
		if _can_log_intel():
			Debug.log("intel", "[MARKER] workbench found uid=%s tile=%s" % [str(uid), str(tile)])
		_markers.append({
			"id":         "workbench_" + str(uid),
			"kind":       "workbench",
			"world_pos":  wpos,
			"tile_pos":   tile,
			"created_at": _elapsed,
			"expires_at": -1.0,
			"persistent": true,
			"metadata":   {"uid": uid},
		})
	if force_full:
		_full_workbench_rescans += 1
	else:
		_partial_workbench_rescans += 1


# ---------------------------------------------------------------------------
# Base detection internals
# ---------------------------------------------------------------------------

func _ensure_base_scan_job(center: Vector2, radius: float, force_restart: bool = false) -> void:
	if not force_restart and not _pending_base_scan.is_empty():
		var existing_center: Vector2 = _pending_base_scan.get("center", Vector2.INF) as Vector2
		var existing_radius: float = float(_pending_base_scan.get("radius", -1.0))
		if existing_center.distance_squared_to(center) <= 1.0 and is_equal_approx(existing_radius, radius):
			return
	_pending_base_scan = {
		"center": center,
		"radius": radius,
		"doors": _collect_candidate_doors(center, radius),
		"cursor": 0,
		"results": [],
	}


func _collect_candidate_doors(center: Vector2, radius: float) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var entries: Array[Dictionary] = []
	if _world_spatial_index != null:
		entries = _world_spatial_index.get_placeables_by_item_ids_near(center, radius, ["doorwood"])
	else:
		var r2 := radius * radius
		for ckey in WorldSave.placed_entities_by_chunk:
			var chunk_dict: Dictionary = WorldSave.placed_entities_by_chunk[ckey]
			for uid in chunk_dict:
				var entry: Dictionary = chunk_dict[uid]
				if String(entry.get("item_id", "")).strip_edges() != "doorwood":
					continue
				var door_tile := Vector2i(int(entry.get("tile_pos_x", 0)), int(entry.get("tile_pos_y", 0)))
				var door_world := _tile_to_world(door_tile)
				if r2 > 0.0 and door_world.distance_squared_to(center) > r2:
					continue
				entries.append(entry)
	for entry in entries:
		result.append(Vector2i(int(entry.get("tile_pos_x", 0)), int(entry.get("tile_pos_y", 0))))
	return result


func _process_pending_base_scan(door_budget: int) -> void:
	if _pending_base_scan.is_empty() and not _pending_base_scan_jobs.is_empty():
		var next_job: Dictionary = _pending_base_scan_jobs.pop_front()
		_ensure_base_scan_job(
			next_job.get("center", Vector2.ZERO),
			float(next_job.get("radius", BASE_SCAN_RADIUS_DEFAULT)),
			true
		)
	if _pending_base_scan.is_empty():
		return
	var doors: Array[Vector2i] = _pending_base_scan.get("doors", [])
	var cursor: int = int(_pending_base_scan.get("cursor", 0))
	var results: Array = _pending_base_scan.get("results", [])
	var processed: int = 0
	while cursor < doors.size() and processed < maxi(door_budget, 1):
		var base_data := _try_detect_base_at_door(doors[cursor])
		if not base_data.is_empty():
			results.append(base_data)
		cursor += 1
		processed += 1
	_pending_base_scan["cursor"] = cursor
	_pending_base_scan["results"] = results
	if cursor < doors.size():
		return
	var old_count := _bases.size()
	_bases.assign(results)
	_pending_base_scan.clear()
	var new_count := _bases.size()
	if new_count > old_count:
		for b in _bases:
			if _can_log_intel():
				Debug.log("intel", "[BASE] detected id=%s interior=%d walls=%d" % [
					b.get("id", "?"), b.get("interior_tile_count", 0), b.get("wall_count", 0)])
	elif new_count < old_count:
		if _can_log_intel():
			Debug.log("intel", "[BASE] lost %d base(s), now=%d" % [old_count - new_count, new_count])




func _try_detect_base_at_door(door_tile: Vector2i) -> Dictionary:
	var min_tile := door_tile - Vector2i(BASE_SCAN_WINDOW_HALF, BASE_SCAN_WINDOW_HALF)
	var max_tile := door_tile + Vector2i(BASE_SCAN_WINDOW_HALF, BASE_SCAN_WINDOW_HALF)

	var wall_set := _build_wall_set_in_window(min_tile, max_tile)

	if wall_set.size() < MIN_WALL_COUNT:
		if _should_log_intel("base_skip_walls", INTEL_LOG_SAMPLE_HEAVY):
			Debug.log("intel", "[BASE] door=%s skip: walls=%d < %d" % [
				str(door_tile), wall_set.size(), MIN_WALL_COUNT])
		return {}

	# Count walls directly adjacent to door
	var adj_walls := 0
	var free_neighbors: Array[Vector2i] = []
	for d in _CARDINALS:
		var nb := door_tile + d
		if wall_set.has(nb):
			adj_walls += 1
		elif nb.x >= min_tile.x and nb.x <= max_tile.x \
				and nb.y >= min_tile.y and nb.y <= max_tile.y:
			free_neighbors.append(nb)

	if adj_walls < MIN_DOOR_WALL_ADJACENCY:
		if _should_log_intel("base_skip_adj_walls", INTEL_LOG_SAMPLE_HEAVY):
			Debug.log("intel", "[BASE] door=%s skip: adj_walls=%d < %d" % [
				str(door_tile), adj_walls, MIN_DOOR_WALL_ADJACENCY])
		return {}

	# Flood fill from each free neighbor — keep the largest contained region
	var best_tiles: Array[Vector2i] = []
	for start in free_neighbors:
		_flood_fill(start, wall_set, door_tile, min_tile, max_tile, _flood_result)
		if not _flood_result.escaped \
				and _flood_result.tiles.size() >= MIN_INTERIOR_TILES \
				and _flood_result.tiles.size() > best_tiles.size():
			best_tiles = _flood_result.tiles.duplicate()

	if best_tiles.is_empty():
		return {}

	var bounds := _compute_bounds(best_tiles)
	var center_tile := Vector2i(
		bounds.position.x + bounds.size.x / 2,
		bounds.position.y + bounds.size.y / 2,
	)

	return {
		"id":                 "base_" + str(door_tile.x) + "_" + str(door_tile.y),
		"center_world_pos":  _tile_to_world(center_tile),
		"center_tile":       center_tile,
		"door_tile":         door_tile,
		"interior_tile_count": best_tiles.size(),
		"bounds":            bounds,
		"wall_count":        wall_set.size(),
		"updated_at":        _elapsed,
	}


# Builds a set of Vector2i tiles that have player walls within the given tile window.
func _build_wall_set_in_window(min_tile: Vector2i, max_tile: Vector2i) -> Dictionary:
	var wall_set: Dictionary = {}
	var cs := WorldSave.chunk_size
	if cs <= 0:
		cs = 32

	var cx_min := int(floor(float(min_tile.x) / float(cs)))
	var cx_max := int(floor(float(max_tile.x) / float(cs)))
	var cy_min := int(floor(float(min_tile.y) / float(cs)))
	var cy_max := int(floor(float(max_tile.y) / float(cs)))

	for cy in range(cy_min, cy_max + 1):
		for cx in range(cx_min, cx_max + 1):
			var ckey := "%d,%d" % [cx, cy]
			if not WorldSave.player_walls_by_chunk.has(ckey):
				continue
			var chunk_dict: Dictionary = WorldSave.player_walls_by_chunk[ckey]
			for tile_key in chunk_dict:
				var parts := (tile_key as String).split(",")
				if parts.size() != 2:
					continue
				var tp := Vector2i(int(parts[0]), int(parts[1]))
				if tp.x >= min_tile.x and tp.x <= max_tile.x \
						and tp.y >= min_tile.y and tp.y <= max_tile.y:
					wall_set[tp] = true
	return wall_set


# BFS flood fill from `start`. Treats wall_set tiles and door_tile as blockers.
# "escaped" = true if the fill reached outside [min_tile, max_tile].
func _flood_fill(start: Vector2i, wall_set: Dictionary, door_tile: Vector2i,
		min_tile: Vector2i, max_tile: Vector2i, out: FloodFillResult) -> void:
	out.tiles.clear()
	out.escaped = false
	if wall_set.has(start) or start == door_tile:
		return

	var visited: Dictionary = {}
	visited[start] = true
	out.tiles.append(start)
	var head := 0

	while head < out.tiles.size() and not out.escaped:
		var curr := out.tiles[head]
		head += 1
		for d in _CARDINALS:
			var nb := curr + d
			if visited.has(nb) or wall_set.has(nb) or nb == door_tile:
				continue
			if nb.x < min_tile.x or nb.x > max_tile.x \
					or nb.y < min_tile.y or nb.y > max_tile.y:
				out.escaped = true
				break
			visited[nb] = true
			out.tiles.append(nb)


func _compute_bounds(tiles: Array[Vector2i]) -> Rect2i:
	if tiles.is_empty():
		return Rect2i()
	var min_x := tiles[0].x
	var min_y := tiles[0].y
	var max_x := tiles[0].x
	var max_y := tiles[0].y
	for t in tiles:
		if t.x < min_x: min_x = t.x
		if t.y < min_y: min_y = t.y
		if t.x > max_x: max_x = t.x
		if t.y > max_y: max_y = t.y
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)


# ---------------------------------------------------------------------------
# Signal handlers
# ---------------------------------------------------------------------------

func _on_resource_harvested(kind: String, world_pos: Vector2) -> void:
	record_interest_event(kind, world_pos)


func _on_placement_completed(item_id: String, tile_pos: Vector2i) -> void:
	var wpos := _tile_to_world(tile_pos)
	var chunk_pos: Vector2i = _tile_to_chunk(tile_pos)
	_dirty_workbench_chunks[chunk_pos] = true
	_dirty_base_chunks[chunk_pos] = true
	if _world_spatial_index != null:
		_world_spatial_index.notify_placeables_changed(item_id, tile_pos)
	# Workbench: trigger workbench scan
	if item_id == "workbench":
		_dirty = true
	# doorwood or wallwood placement may close or open a room
	if item_id == "doorwood" or item_id == "wallwood":
		_base_scan_dirty = true
	record_interest_event("structure_placed", wpos, {"item_id": item_id})


func _collect_placeable_chunk_deltas(next_serial: int) -> void:
	var delta: Dictionary = WorldSave.get_placed_entities_changes_since(_last_placeables_change_serial)
	_last_placeables_change_serial = next_serial
	var overflow: bool = bool(delta.get("overflow", true))
	if overflow:
		_dirty = true
		_base_scan_dirty = true
		_global_scan_fallbacks += 1
		return
	for raw_change in delta.get("changes", []):
		var change: Dictionary = raw_change as Dictionary
		var op: String = String(change.get("op", "")).strip_edges()
		if op == "clear":
			_dirty = true
			_base_scan_dirty = true
			_global_scan_fallbacks += 1
			continue
		_mark_dirty_chunk_for_entry(change.get("entry", {}))
		_mark_dirty_chunk_for_entry(change.get("prev_entry", {}))


func _mark_dirty_chunk_for_entry(entry: Dictionary) -> void:
	if entry.is_empty():
		return
	var item_id: String = String(entry.get("item_id", "")).strip_edges()
	var chunk_pos := Vector2i(
		int(floor(float(int(entry.get("tile_pos_x", 0))) / float(maxi(WorldSave.chunk_size, 1)))),
		int(floor(float(int(entry.get("tile_pos_y", 0))) / float(maxi(WorldSave.chunk_size, 1))))
	)
	if item_id == "workbench":
		_dirty_workbench_chunks[chunk_pos] = true
	if item_id == "doorwood" or item_id == "wallwood":
		_dirty_base_chunks[chunk_pos] = true


func _collect_dirty_chunk_keys(source: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for key in source.keys():
		out.append(key as Vector2i)
	return out


func _contains_chunk(chunks: Array[Vector2i], chunk_pos: Vector2i) -> bool:
	for test_pos in chunks:
		if test_pos == chunk_pos:
			return true
	return false


func _get_worldsave_placeables_in_chunk(cx: int, cy: int, item_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in WorldSave.get_placed_entities_in_chunk(cx, cy):
		if String(entry.get("item_id", "")).strip_edges() == item_id:
			out.append(entry)
	return out


func _tile_to_chunk(tile_pos: Vector2i) -> Vector2i:
	var cs: int = maxi(WorldSave.chunk_size, 1)
	return Vector2i(
		int(floor(float(tile_pos.x) / float(cs))),
		int(floor(float(tile_pos.y) / float(cs)))
	)


func _enqueue_base_scans_for_dirty_chunks() -> void:
	if not _pending_base_scan.is_empty() or not _pending_base_scan_jobs.is_empty():
		return
	var cs: int = maxi(WorldSave.chunk_size, 1)
	var radius: float = float(cs) * 32.0 * BASE_SCAN_CHUNK_RADIUS_MULT
	for key in _dirty_base_chunks.keys():
		var chunk_pos: Vector2i = key as Vector2i
		var center_tile := Vector2i(chunk_pos.x * cs + int(cs / 2), chunk_pos.y * cs + int(cs / 2))
		_pending_base_scan_jobs.append({
			"center": _tile_to_world(center_tile),
			"radius": radius,
		})
	_partial_base_scan_jobs_enqueued += _pending_base_scan_jobs.size()
	_dirty_base_chunks.clear()


# ---------------------------------------------------------------------------
# Coordinate helpers
# ---------------------------------------------------------------------------

func _world_to_tile(world_pos: Vector2) -> Vector2i:
	if _world_to_tile_cb.is_valid():
		return _world_to_tile_cb.call(world_pos)
	return Vector2i(int(world_pos.x / 32), int(world_pos.y / 32))


func _tile_to_world(tile_pos: Vector2i) -> Vector2:
	if _tile_to_world_cb.is_valid():
		return _tile_to_world_cb.call(tile_pos)
	return Vector2(tile_pos.x * 32.0 + 16.0, tile_pos.y * 32.0 + 16.0)


func get_debug_snapshot() -> Dictionary:
	var pending_doors: Array[Vector2i] = Array(_pending_base_scan.get("doors", []), TYPE_VECTOR2I, "", null)
	var base_cursor: int = int(_pending_base_scan.get("cursor", 0))
	var persistent_markers: int = 0
	var workbench_markers: int = 0
	for marker in _markers:
		if bool(marker.get("persistent", false)):
			persistent_markers += 1
		if String(marker.get("kind", "")) == "workbench":
			workbench_markers += 1
	return {
		"markers_total": _markers.size(),
		"persistent_markers": persistent_markers,
		"workbench_markers": workbench_markers,
		"interest_scan_dirty": _dirty,
		"base_scan_dirty": _base_scan_dirty,
		"base_scan_running": not _pending_base_scan.is_empty(),
		"pending_base_scan_jobs": _pending_base_scan_jobs.size(),
		"base_scan_progress": {
			"processed": base_cursor,
			"pending": maxi(pending_doors.size() - base_cursor, 0),
			"total": pending_doors.size(),
		},
		"bases_detected": _bases.size(),
		"chunk_invalidations": {
			"dirty_workbench_chunks": _dirty_workbench_chunks.size(),
			"dirty_base_chunks": _dirty_base_chunks.size(),
			"partial_workbench_rescans": _partial_workbench_rescans,
			"full_workbench_rescans": _full_workbench_rescans,
			"partial_base_scan_jobs_enqueued": _partial_base_scan_jobs_enqueued,
			"global_scan_fallbacks": _global_scan_fallbacks,
		},
		"timers": {
			"elapsed": snappedf(_elapsed, 0.01),
			"workbench_rescan_timer": snappedf(_rescan_timer, 0.01),
			"base_rescan_timer": snappedf(_base_rescan_timer, 0.01),
		},
	}


func _can_log_intel() -> bool:
	return Debug.is_enabled("intel")


func _should_log_intel(sample_key: String, every_n: int) -> bool:
	return Debug.should_sample("intel", "settlement_intel:%s" % sample_key, every_n)
