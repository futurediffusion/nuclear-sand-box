extends Node

# ── NpcPathService ────────────────────────────────────────────────────────────
# Autoload. Local tile-based A* pathfinding for sleeping/world-layer NPCs.
#
# Design:
#   • One AStarGrid2D per request, built over a local tile window (≤MAX_WINDOW²).
#   • Per-agent path cache keyed by member_id; recalculated on goal change or
#     after REPATH_INTERVAL seconds.
#   • Fast path: if start→goal is ≤ LOS_MAX_TILES and line is clear, returns
#     direct direction without running A*.
#   • Graceful fallback: returns goal directly if A* fails or service not ready.
#
# Blockers:
#   • Cliff tiles: TileMap_Cliffs layer 0, any cell != -1.
#   • Player/structural walls: StructureWallsMap layer 0, source_id == SRC_WALLS.
#   • Hook: _is_blocked() has a clearly marked section for future door blockers.
#
# Setup: world.gd calls NpcPathService.setup(ctx) once tilemaps are ready.

# ── Thresholds ────────────────────────────────────────────────────────────────
const REPATH_INTERVAL: float      = 1.5       # s between forced recalcs
const GOAL_CHANGED_DIST_SQ: float = 16.0*16.0 # re-path when goal moves > 16 px
const WAYPOINT_ARRIVE_SQ: float   = 18.0*18.0 # advance to next WP within 18 px
const LOS_MAX_TILES: int          = 5         # skip A* below this tile-distance
const WINDOW_PAD: int             = 7         # padding tiles around bbox
const MAX_WINDOW: int             = 26        # max window side in tiles

# ── Tilemap constants (must match world.gd) ───────────────────────────────────
const CLIFFS_LAYER: int    = 0
const WALLS_MAP_LAYER: int = 0
const SRC_WALLS: int       = 2  # source_id for player/structural walls

# ── State ─────────────────────────────────────────────────────────────────────
var _cliffs_tilemap: TileMap    = null
var _walls_tilemap: TileMap     = null
var _world_to_tile_cb: Callable
var _tile_to_world_cb: Callable
var _is_ready: bool             = false

# agent_id → {goal:Vector2, waypoints:Array[Vector2], index:int, timestamp:float}
var _cache: Dictionary = {}


# ─────────────────────────────────────────────────────────────────────────────
# Setup — called from world.gd in _ready() after tilemaps are available
# ─────────────────────────────────────────────────────────────────────────────

func setup(ctx: Dictionary) -> void:
	_cliffs_tilemap   = ctx.get("cliffs_tilemap")
	_walls_tilemap    = ctx.get("walls_tilemap")
	_world_to_tile_cb = ctx.get("world_to_tile", Callable())
	_tile_to_world_cb = ctx.get("tile_to_world", Callable())
	_is_ready = (
		_cliffs_tilemap   != null and is_instance_valid(_cliffs_tilemap)  and
		_walls_tilemap    != null and is_instance_valid(_walls_tilemap)   and
		_world_to_tile_cb.is_valid() and _tile_to_world_cb.is_valid()
	)
	Debug.log("npc_path", "[NPS] setup ready=%s" % str(_is_ready))


func is_ready() -> bool:
	return _is_ready


# ─────────────────────────────────────────────────────────────────────────────
# Public API
# ─────────────────────────────────────────────────────────────────────────────

## Returns the next world-space waypoint toward goal for agent_id.
## Recomputes path only when goal changed materially or REPATH_INTERVAL elapsed.
## Falls back to returning goal directly when service unavailable or A* fails.
func get_next_waypoint(agent_id: String, current_pos: Vector2, goal: Vector2) -> Vector2:
	if not _is_ready or agent_id == "":
		return goal

	var c: Dictionary = _ensure_cache(agent_id)
	var wpts: Array   = c["waypoints"]

	var needs_repath: bool = (
		wpts.is_empty()
		or (c["goal"] as Vector2).distance_squared_to(goal) > GOAL_CHANGED_DIST_SQ
		or (RunClock.now() - float(c["timestamp"])) >= REPATH_INTERVAL
	)

	if needs_repath:
		_compute_path(agent_id, current_pos, goal, c)

	return _advance_and_get(c, current_pos, goal)


## True when straight tile line from start to goal has no cliff/wall blockers.
## Only checked for short distances (≤ LOS_MAX_TILES) to keep it cheap.
func has_line_clear(start: Vector2, goal: Vector2) -> bool:
	if not _is_ready:
		return true
	var st: Vector2i = _world_to_tile_cb.call(start)
	var gt: Vector2i = _world_to_tile_cb.call(goal)
	if maxi(absi(gt.x - st.x), absi(gt.y - st.y)) > LOS_MAX_TILES:
		return false
	return not _bresenham_blocked(st, gt)


## Force next get_next_waypoint() call to recompute path for agent.
func invalidate_path(agent_id: String) -> void:
	if _cache.has(agent_id):
		(_cache[agent_id]["waypoints"] as Array).clear()


## Remove all path data for agent (call when NPC despawns / behavior destroyed).
func clear_agent(agent_id: String) -> void:
	_cache.erase(agent_id)


# ─────────────────────────────────────────────────────────────────────────────
# Internal — path computation
# ─────────────────────────────────────────────────────────────────────────────

func _ensure_cache(agent_id: String) -> Dictionary:
	if not _cache.has(agent_id):
		_cache[agent_id] = {
			"goal":      Vector2.ZERO,
			"waypoints": [],
			"index":     0,
			"timestamp": -999.0,
		}
	return _cache[agent_id]


func _compute_path(agent_id: String, start: Vector2, goal: Vector2, c: Dictionary) -> void:
	c["goal"]      = goal
	c["index"]     = 0
	c["timestamp"] = RunClock.now()
	(c["waypoints"] as Array).clear()

	var st: Vector2i = _world_to_tile_cb.call(start)
	var gt: Vector2i = _world_to_tile_cb.call(goal)

	# Fast path: direct line is short and clear — skip A*
	if maxi(absi(gt.x - st.x), absi(gt.y - st.y)) <= LOS_MAX_TILES \
			and not _bresenham_blocked(st, gt):
		(c["waypoints"] as Array).append(goal)
		return

	# Build local tile window around the bounding box of start + goal
	var min_x: int = mini(st.x, gt.x) - WINDOW_PAD
	var min_y: int = mini(st.y, gt.y) - WINDOW_PAD
	var w: int     = mini(absi(gt.x - st.x) + 1 + WINDOW_PAD * 2, MAX_WINDOW)
	var h: int     = mini(absi(gt.y - st.y) + 1 + WINDOW_PAD * 2, MAX_WINDOW)

	# Clamp start/goal into the (possibly truncated) window
	var cs: Vector2i = Vector2i(
		clampi(st.x, min_x, min_x + w - 1),
		clampi(st.y, min_y, min_y + h - 1)
	)
	var cg: Vector2i = Vector2i(
		clampi(gt.x, min_x, min_x + w - 1),
		clampi(gt.y, min_y, min_y + h - 1)
	)

	var grid := AStarGrid2D.new()
	grid.region        = Rect2i(min_x, min_y, w, h)
	grid.cell_size     = Vector2(1.0, 1.0)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()

	# Mark blocked tiles (cliffs, walls, future hooks)
	for tx in range(min_x, min_x + w):
		for ty in range(min_y, min_y + h):
			if _is_blocked(Vector2i(tx, ty)):
				grid.set_point_solid(Vector2i(tx, ty), true)

	# Force-clear start/goal so the NPC is never stuck on a solid cell
	if grid.is_point_solid(cs):
		grid.set_point_solid(cs, false)
	if grid.is_point_solid(cg):
		grid.set_point_solid(cg, false)

	var raw: PackedVector2Array = grid.get_point_path(cs, cg)

	if raw.is_empty():
		# A* could not find a path — fall back to direct movement
		(c["waypoints"] as Array).append(goal)
		Debug.log("npc_path", "[NPS] no path agent=%s %s→%s" % [agent_id, str(st), str(gt)])
		return

	# Convert tile coords (Vector2 from AStarGrid2D) → world positions.
	# Skip first point (= current tile). Replace last with exact goal.
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
		wpts[wpts.size() - 1] = goal   # snap to exact goal position


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

func _is_blocked(tile: Vector2i) -> bool:
	# Cliff tiles
	if is_instance_valid(_cliffs_tilemap) \
			and _cliffs_tilemap.get_cell_source_id(CLIFFS_LAYER, tile) != -1:
		return true
	# Player/structural walls
	if is_instance_valid(_walls_tilemap) \
			and _walls_tilemap.get_cell_source_id(WALLS_MAP_LAYER, tile) == SRC_WALLS:
		return true
	# ── Hook: future door / gate blockers ────────────────────────────────────
	# if DoorSystem != null and DoorSystem.is_tile_blocked(tile):
	#     return true
	# ─────────────────────────────────────────────────────────────────────────
	return false


func _bresenham_blocked(from_tile: Vector2i, to_tile: Vector2i) -> bool:
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
		if _is_blocked(Vector2i(x0, y0)):
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
