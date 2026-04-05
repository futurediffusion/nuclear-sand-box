extends Node

# ── NpcPathService ────────────────────────────────────────────────────────────
# Autoload. Local tile-based A* pathfinding shared by NpcWorldBehavior and
# AIComponent.CHASE. Same service, same cache, same blockers for both.
#
# Blockers (in order):
#   1. Cliff tiles        — TileMap_Cliffs layer 0, source_id != -1
#   2. Player/struct walls— StructureWallsMap layer 0, source_id == SRC_WALLS
#   3. Solid placeables   — WorldSave entities; all except floorwood block movement
#   4. Doors (hook live)  — closed doorwood blocks; open doorwood is passable
#   5. Hook: future gate/custom blockers in _is_placeable_blocked()
#
# Window strategy: adaptive padding based on start→goal distance.
# If first A* attempt fails, retries once with MAX_WINDOW_RETRY tiles.
# Fast path: if Bresenham is clear (any distance), skips A* entirely.
#
# Cache: per agent_id. Repath on goal change (>GOAL_CHANGED_DIST_SQ) or timeout.
# Chase uses shorter interval via opts dict: {"repath_interval": 0.5}

# ── Window constants ──────────────────────────────────────────────────────────
const BASE_PAD: int        = 7    # min side padding around bbox
const MAX_PAD: int         = 14   # max side padding (for long routes)
const MAX_WINDOW: int      = 48   # normal max window side (tiles)
const MAX_WINDOW_RETRY: int = 64  # retry window when first attempt fails

# ── Timing constants ──────────────────────────────────────────────────────────
const REPATH_INTERVAL: float      = 1.5        # default s between recalcs
const GOAL_CHANGED_DIST_SQ: float = 16.0*16.0  # repath when goal moves > 16 px
const WAYPOINT_ARRIVE_SQ: float   = 18.0*18.0  # advance WP within 18 px
const INVALIDATE_DEBOUNCE_DIST_SQ: float = 20.0 * 20.0
const INVALIDATE_DEBOUNCE_WINDOW_SEC: float = 0.35

# ── Tilemap / WorldSave constants ─────────────────────────────────────────────
const CLIFFS_LAYER: int    = 0
const WALLS_MAP_LAYER: int = 0
const SRC_WALLS: int       = 2      # StructureWallsMap source_id for walls
const CHUNK_SIZE: int      = 32     # must match world.gd chunk_size

# Item IDs that are PASSABLE (everything else in placed_entities is solid)
const PASSABLE_ITEM_IDS: Array = ["floorwood", "woodfloor"]

# ── State ─────────────────────────────────────────────────────────────────────
var _cliffs_tilemap: TileMap    = null
var _walls_tilemap: TileMap     = null
var _world_to_tile_cb: Callable
var _tile_to_world_cb: Callable
var _is_ready: bool             = false
var _world_spatial_index: WorldSpatialIndex = null

# Optional world bounds in tile coords — tiles outside are treated as blocked.
# Set via setup ctx key "world_tile_rect" (Rect2i). Left unset = no bounds check.
var _world_tile_rect: Rect2i = Rect2i()
var _has_world_bounds: bool  = false

# agent_id → {goal, waypoints, index, timestamp, path_failed}
var _cache: Dictionary = {}
var _line_clear_pulse_id: int = -1
var _line_clear_pulse_cache: Dictionary = {}
var _line_clear_checks_used_in_pulse: int = 0
var _line_clear_budget_exhausted_in_pulse: int = 0
var _line_clear_cache_hits_in_pulse: int = 0
var _line_clear_cache_misses_in_pulse: int = 0
var _invalidate_metrics_by_agent: Dictionary = {}


# ─────────────────────────────────────────────────────────────────────────────
# Setup — called from world.gd in _ready() after tilemaps are ready
# ─────────────────────────────────────────────────────────────────────────────

func setup(ctx: Dictionary) -> void:
	_cliffs_tilemap   = ctx.get("cliffs_tilemap")
	_walls_tilemap    = ctx.get("walls_tilemap")
	_world_to_tile_cb = ctx.get("world_to_tile", Callable())
	_tile_to_world_cb = ctx.get("tile_to_world", Callable())
	_world_spatial_index = ctx.get("world_spatial_index") as WorldSpatialIndex
	_is_ready = (
		_cliffs_tilemap != null and is_instance_valid(_cliffs_tilemap) and
		_walls_tilemap  != null and is_instance_valid(_walls_tilemap)  and
		_world_to_tile_cb.is_valid() and _tile_to_world_cb.is_valid()
	)
	if ctx.has("world_tile_rect"):
		var r = ctx["world_tile_rect"]
		if r is Rect2i and (r as Rect2i).size != Vector2i.ZERO:
			_world_tile_rect   = r as Rect2i
			_has_world_bounds  = true
	Debug.log("npc_path", "[NPS] setup ready=%s bounds=%s" % [str(_is_ready), str(_world_tile_rect)])


func is_ready() -> bool:
	return _is_ready


# ─────────────────────────────────────────────────────────────────────────────
# Public API
# ─────────────────────────────────────────────────────────────────────────────

## Returns the next world-space waypoint toward goal for agent_id.
## opts keys:
##   "repath_interval" : float  — override repath timer (default REPATH_INTERVAL)
##                                use 0.5 for CHASE, 1.5 for patrol/world behavior
func get_next_waypoint(agent_id: String, current_pos: Vector2,
		goal: Vector2, opts: Dictionary = {}) -> Vector2:
	if not _is_ready or agent_id == "":
		return goal

	var c: Dictionary     = _ensure_cache(agent_id)
	var wpts: Array       = c["waypoints"]
	var interval: float   = float(opts.get("repath_interval", REPATH_INTERVAL))

	var needs_repath: bool = (
		wpts.is_empty() and not c.get("path_failed", false)
		or (c["goal"] as Vector2).distance_squared_to(goal) > GOAL_CHANGED_DIST_SQ
		or (RunClock.now() - float(c["timestamp"])) >= interval
	)

	if needs_repath:
		_compute_path(agent_id, current_pos, goal, c)

	# No valid path found — stay put rather than walking into a wall
	if c.get("path_failed", false):
		return current_pos

	return _advance_and_get(c, current_pos, goal)


## True when Bresenham tile line start→goal has no blockers (including placeables).
## No distance limit — cheap enough for any reasonable NPC range.
func has_line_clear(start: Vector2, goal: Vector2, query_ctx: Dictionary = {}) -> bool:
	if not _is_ready:
		return true
	var st: Vector2i      = _world_to_tile_cb.call(start)
	var gt: Vector2i      = _world_to_tile_cb.call(goal)
	var pulse_id: int = int(query_ctx.get("pulse_id", -1))
	_begin_line_clear_pulse_if_needed(pulse_id)
	var pair_key: String = _line_clear_pair_key(st, gt)
	if pulse_id >= 0 and _line_clear_pulse_cache.has(pair_key):
		_line_clear_cache_hits_in_pulse += 1
		return bool(_line_clear_pulse_cache.get(pair_key, false))
	var remaining_budget: int = maxi(int(query_ctx.get("blocking_checks_budget", -1)), -1)
	if remaining_budget == 0:
		_line_clear_budget_exhausted_in_pulse += 1
		return false
	if remaining_budget > 0:
		query_ctx["blocking_checks_budget"] = remaining_budget - 1
	_line_clear_checks_used_in_pulse += 1
	var placed: Dictionary = _collect_placed_blockers_for_line(st, gt)
	var result: bool = not _bresenham_blocked(st, gt, placed)
	if pulse_id >= 0:
		_line_clear_pulse_cache[pair_key] = result
		_line_clear_cache_misses_in_pulse += 1
	return result


func get_line_clear_budget_metrics() -> Dictionary:
	return {
		"pulse_id": _line_clear_pulse_id,
		"checks_used": _line_clear_checks_used_in_pulse,
		"budget_exhausted": _line_clear_budget_exhausted_in_pulse,
		"cache_hits": _line_clear_cache_hits_in_pulse,
		"cache_misses": _line_clear_cache_misses_in_pulse,
		"cache_size": _line_clear_pulse_cache.size(),
	}


## Force next get_next_waypoint() call to recompute path for agent.
func invalidate_path(agent_id: String, reason: String = "state_change",
		target_pos: Variant = null, force: bool = false) -> bool:
	if agent_id == "":
		return false
	var now: float = RunClock.now()
	var normalized_reason: String = _normalize_invalidate_reason(reason)
	if _should_debounce_invalidate(agent_id, normalized_reason, target_pos, now, force):
		_record_invalidate_metric(agent_id, normalized_reason, true, now)
		return false
	if _cache.has(agent_id):
		(_cache[agent_id]["waypoints"] as Array).clear()
	if target_pos is Vector2:
		var st: Dictionary = _ensure_invalidate_metric(agent_id, now)
		st["last_target"] = target_pos as Vector2
	_record_invalidate_metric(agent_id, normalized_reason, false, now)
	return true


## Remove all path data for agent (call when NPC despawns / behavior pruned).
func clear_agent(agent_id: String) -> void:
	_cache.erase(agent_id)
	_invalidate_metrics_by_agent.erase(agent_id)


func _begin_line_clear_pulse_if_needed(pulse_id: int) -> void:
	if pulse_id < 0:
		return
	if _line_clear_pulse_id == pulse_id:
		return
	_line_clear_pulse_id = pulse_id
	_line_clear_pulse_cache.clear()
	_line_clear_checks_used_in_pulse = 0
	_line_clear_budget_exhausted_in_pulse = 0
	_line_clear_cache_hits_in_pulse = 0
	_line_clear_cache_misses_in_pulse = 0


func _line_clear_pair_key(st: Vector2i, gt: Vector2i) -> String:
	return "%d:%d>%d:%d" % [st.x, st.y, gt.x, gt.y]


func _normalize_invalidate_reason(reason: String) -> String:
	match reason:
		"new_target", "state_change", "forced_reset":
			return reason
		_:
			return "state_change"


func _should_debounce_invalidate(agent_id: String, reason: String, target_pos: Variant,
		now: float, force: bool) -> bool:
	if force:
		return false
	if reason != "new_target":
		return false
	if not (target_pos is Vector2):
		return false
	var st: Dictionary = _ensure_invalidate_metric(agent_id, now)
	var next_target: Vector2 = target_pos as Vector2
	var prev_target: Vector2 = st.get("last_target", Vector2(INF, INF)) as Vector2
	var last_time: float = float(st.get("last_invalidate_time", -9999.0))
	if not next_target.is_finite() or not prev_target.is_finite():
		return false
	if now - last_time > INVALIDATE_DEBOUNCE_WINDOW_SEC:
		return false
	return prev_target.distance_squared_to(next_target) <= INVALIDATE_DEBOUNCE_DIST_SQ


func _ensure_invalidate_metric(agent_id: String, now: float) -> Dictionary:
	if not _invalidate_metrics_by_agent.has(agent_id):
		_invalidate_metrics_by_agent[agent_id] = {
			"sec_bucket": int(floor(now)),
			"counts": {"new_target": 0, "state_change": 0, "forced_reset": 0},
			"suppressed_counts": {"new_target": 0, "state_change": 0, "forced_reset": 0},
			"last_invalidate_time": -9999.0,
			"last_target": Vector2(INF, INF),
		}
	return _invalidate_metrics_by_agent[agent_id]


func _record_invalidate_metric(agent_id: String, reason: String, suppressed: bool, now: float) -> void:
	var st: Dictionary = _ensure_invalidate_metric(agent_id, now)
	var sec_bucket_now: int = int(floor(now))
	var sec_bucket_old: int = int(st.get("sec_bucket", sec_bucket_now))
	if sec_bucket_now != sec_bucket_old:
		var old_counts: Dictionary = st.get("counts", {})
		var old_suppressed: Dictionary = st.get("suppressed_counts", {})
		Debug.log("npc_path",
			"[NPS][invalidate_rate] npc=%s sec=%d new_target=%d state_change=%d forced_reset=%d suppressed_new_target=%d suppressed_state_change=%d suppressed_forced_reset=%d" % [
			agent_id,
			sec_bucket_old,
			int(old_counts.get("new_target", 0)),
			int(old_counts.get("state_change", 0)),
			int(old_counts.get("forced_reset", 0)),
			int(old_suppressed.get("new_target", 0)),
			int(old_suppressed.get("state_change", 0)),
			int(old_suppressed.get("forced_reset", 0)),
		])
		st["sec_bucket"] = sec_bucket_now
		st["counts"] = {"new_target": 0, "state_change": 0, "forced_reset": 0}
		st["suppressed_counts"] = {"new_target": 0, "state_change": 0, "forced_reset": 0}
	var key: String = _normalize_invalidate_reason(reason)
	var bucket_key: String = "suppressed_counts" if suppressed else "counts"
	var bucket: Dictionary = st.get(bucket_key, {})
	bucket[key] = int(bucket.get(key, 0)) + 1
	st[bucket_key] = bucket
	if not suppressed:
		st["last_invalidate_time"] = now


# ─────────────────────────────────────────────────────────────────────────────
# Internal — path computation
# ─────────────────────────────────────────────────────────────────────────────

func _ensure_cache(agent_id: String) -> Dictionary:
	if not _cache.has(agent_id):
		_cache[agent_id] = {
			"goal":        Vector2.ZERO,
			"waypoints":   [],
			"index":       0,
			"timestamp":   -999.0,
			"path_failed": false,
		}
	return _cache[agent_id]


func _compute_path(agent_id: String, start: Vector2, goal: Vector2, c: Dictionary) -> void:
	c["goal"]        = goal
	c["index"]       = 0
	c["timestamp"]   = RunClock.now()
	c["path_failed"] = false
	(c["waypoints"] as Array).clear()

	var st: Vector2i = _world_to_tile_cb.call(start)
	var gt: Vector2i = _world_to_tile_cb.call(goal)

	# Clamp start/goal to world bounds so A* never receives out-of-world tiles
	if _has_world_bounds:
		var bx0: int = _world_tile_rect.position.x
		var by0: int = _world_tile_rect.position.y
		var bx1: int = _world_tile_rect.end.x - 1
		var by1: int = _world_tile_rect.end.y - 1
		st = Vector2i(clampi(st.x, bx0, bx1), clampi(st.y, by0, by1))
		gt = Vector2i(clampi(gt.x, bx0, bx1), clampi(gt.y, by0, by1))

	# Fast path: Bresenham clear at any distance → skip A* entirely
	# Build a small placed-blocker set just for the corridor to keep this cheap
	var los_blockers: Dictionary = _collect_placed_blockers_for_line(st, gt)
	if not _bresenham_blocked(st, gt, los_blockers):
		(c["waypoints"] as Array).append(goal)
		return

	# Adaptive padding: more room when origin→goal is far
	var dist_max: int = maxi(absi(gt.x - st.x), absi(gt.y - st.y))
	var pad: int      = clampi(dist_max / 2, BASE_PAD, MAX_PAD)

	# First A* attempt with adaptive window
	var raw: PackedVector2Array = _run_astar(st, gt, pad, MAX_WINDOW)

	# Retry with larger window if first attempt failed
	if raw.is_empty():
		Debug.log("npc_path", "[NPS] retry wider window agent=%s" % agent_id)
		raw = _run_astar(st, gt, MAX_PAD, MAX_WINDOW_RETRY)

	if raw.is_empty():
		# No path found — mark failed so caller stays put instead of walking into walls.
		# Next repath cycle will retry automatically.
		c["path_failed"] = true
		Debug.log("npc_path", "[NPS] no path agent=%s %s→%s" % [agent_id, str(st), str(gt)])
		return

	# Convert tile coords → world positions; skip first point (= current tile).
	# Replace last waypoint with exact goal world position for precision.
	var wpts: Array = c["waypoints"]
	var first: bool = true
	for pt in raw:
		if first:
			first = false
			continue
		wpts.append(_tile_to_world_cb.call(Vector2i(int(pt.x), int(pt.y))))

	if wpts.is_empty():
		wpts.append(goal)
	else:
		wpts[wpts.size() - 1] = goal


func _run_astar(st: Vector2i, gt: Vector2i,
		pad: int, max_w: int) -> PackedVector2Array:
	var min_x: int = mini(st.x, gt.x) - pad
	var min_y: int = mini(st.y, gt.y) - pad
	var w: int     = mini(absi(gt.x - st.x) + 1 + pad * 2, max_w)
	var h: int     = mini(absi(gt.y - st.y) + 1 + pad * 2, max_w)

	var cs: Vector2i = Vector2i(
		clampi(st.x, min_x, min_x + w - 1),
		clampi(st.y, min_y, min_y + h - 1))
	var cg: Vector2i = Vector2i(
		clampi(gt.x, min_x, min_x + w - 1),
		clampi(gt.y, min_y, min_y + h - 1))

	# Collect placed-entity blockers for this window once (O(entities_in_chunks))
	var placed: Dictionary = _collect_placed_blockers(min_x, min_y, w, h)

	var grid := AStarGrid2D.new()
	grid.region        = Rect2i(min_x, min_y, w, h)
	grid.cell_size     = Vector2(1.0, 1.0)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()

	for tx in range(min_x, min_x + w):
		for ty in range(min_y, min_y + h):
			if _is_blocked(Vector2i(tx, ty), placed):
				grid.set_point_solid(Vector2i(tx, ty), true)

	# Force-clear start/goal so NPC is never trapped on a solid cell
	if grid.is_point_solid(cs):
		grid.set_point_solid(cs, false)
	if grid.is_point_solid(cg):
		grid.set_point_solid(cg, false)

	return grid.get_point_path(cs, cg)


# ─────────────────────────────────────────────────────────────────────────────
# Internal — waypoint advancement
# ─────────────────────────────────────────────────────────────────────────────

func _advance_and_get(c: Dictionary, current_pos: Vector2, goal: Vector2) -> Vector2:
	var wpts: Array = c["waypoints"]
	if wpts.is_empty():
		return goal

	var idx: int = int(c["index"])
	if idx >= wpts.size():
		return goal

	var wp: Vector2 = wpts[idx]
	if current_pos.distance_squared_to(wp) < WAYPOINT_ARRIVE_SQ:
		idx += 1
		c["index"] = idx
		if idx >= wpts.size():
			return goal
		wp = wpts[idx]
	return wp


# ─────────────────────────────────────────────────────────────────────────────
# Internal — tile blocking
# ─────────────────────────────────────────────────────────────────────────────

## Returns true if tile is blocked by any static obstacle.
## placed_blockers is a pre-built set (Dictionary{Vector2i→bool}) for efficiency.
func _is_blocked(tile: Vector2i, placed_blockers: Dictionary) -> bool:
	# Tiles outside the valid world area are always blocked
	if _has_world_bounds and not _world_tile_rect.has_point(tile):
		return true
	# Cliff tiles
	if is_instance_valid(_cliffs_tilemap) \
			and _cliffs_tilemap.get_cell_source_id(CLIFFS_LAYER, tile) != -1:
		return true
	# Player / structural walls
	if is_instance_valid(_walls_tilemap) \
			and _walls_tilemap.get_cell_source_id(WALLS_MAP_LAYER, tile) == SRC_WALLS:
		return true
	# Placed entities (chests, barrels, tables, stools, workbenches, closed doors…)
	if placed_blockers.has(tile):
		return true
	return false


## Returns true if a placed entity at tile_id blocks movement.
## All placeables are solid EXCEPT: floorwood/woodfloor (no collision shape)
## and doorwood when open (collision shape disabled while open).
func _placeable_blocks_movement(item_id: String, uid: String) -> bool:
	if _world_spatial_index != null:
		return _world_spatial_index.placeable_blocks_movement(item_id, uid)
	if item_id == "":
		return false
	if item_id in PASSABLE_ITEM_IDS:
		return false
	if item_id == "doorwood":
		var data: Dictionary = WorldSave.get_placed_entity_data(uid)
		return not bool(data.get("is_open", false))
	return true


## Build a {Vector2i→true} dict of all blocking placed-entity tiles
## inside the given tile-coordinate window [min_x..min_x+w, min_y..min_y+h].
## Called once per A* solve — O(entities in affected chunks).
func _collect_placed_blockers(min_x: int, min_y: int, w: int, h: int) -> Dictionary:
	if _world_spatial_index != null:
		return _world_spatial_index.get_blocker_tiles_in_rect(min_x, min_y, w, h)
	var blockers: Dictionary = {}
	var min_cx: int = int(floor(float(min_x) / CHUNK_SIZE))
	var max_cx: int = int(floor(float(min_x + w - 1) / CHUNK_SIZE))
	var min_cy: int = int(floor(float(min_y) / CHUNK_SIZE))
	var max_cy: int = int(floor(float(min_y + h - 1) / CHUNK_SIZE))

	for cx in range(min_cx, max_cx + 1):
		for cy in range(min_cy, max_cy + 1):
			for entry in WorldSave.get_placed_entities_in_chunk(cx, cy):
				var tx: int = int(entry.get("tile_pos_x", 0))
				var ty: int = int(entry.get("tile_pos_y", 0))
				if tx < min_x or tx >= min_x + w or ty < min_y or ty >= min_y + h:
					continue
				var item_id: String = String(entry.get("item_id", ""))
				var uid: String     = String(entry.get("uid", ""))
				if _placeable_blocks_movement(item_id, uid):
					blockers[Vector2i(tx, ty)] = true
	return blockers


## Lightweight variant: collect placed blockers only along the Bresenham line
## from st to gt (used for the fast-path LOS check before running A*).
## Much cheaper than the full window scan for the direct-line test.
func _collect_placed_blockers_for_line(st: Vector2i, gt: Vector2i) -> Dictionary:
	var min_x: int = mini(st.x, gt.x)
	var max_x: int = maxi(st.x, gt.x)
	var min_y: int = mini(st.y, gt.y)
	var max_y: int = maxi(st.y, gt.y)
	var w: int = max_x - min_x + 1
	var h: int = max_y - min_y + 1
	return _collect_placed_blockers(min_x, min_y, w, h)


func _bresenham_blocked(from_tile: Vector2i, to_tile: Vector2i,
		placed_blockers: Dictionary) -> bool:
	var x0: int = from_tile.x
	var y0: int = from_tile.y
	var x1: int = to_tile.x
	var y1: int = to_tile.y
	var dx: int = absi(x1 - x0)
	var dy: int = absi(y1 - y0)
	var sx: int = 1 if x0 < x1 else -1
	var sy: int = 1 if y0 < y1 else -1
	var err: int = dx - dy
	while true:
		if _is_blocked(Vector2i(x0, y0), placed_blockers):
			return true
		if x0 == x1 and y0 == y1:
			break
		var e2: int = err * 2
		if e2 > -dy:
			err -= dy
			x0  += sx
		if e2 < dx:
			err += dx
			y0  += sy
	return false
