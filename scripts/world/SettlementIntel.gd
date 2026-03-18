class_name SettlementIntel
extends RefCounted

# --- Constants ---
const MERGE_RADIUS: float = 96.0  # px — same kind within this range → refresh, no new marker
const WORKBENCH_RESCAN_INTERVAL: float = 30.0

const TTL_BY_KIND: Dictionary = {
	"copper_mined":      150.0,
	"stone_mined":       150.0,
	"wood_chopped":      150.0,
	"structure_placed":  180.0,
	"workbench":          -1.0,  # persistent
}

# --- State ---
var _markers: Array[Dictionary] = []
var _elapsed: float = 0.0
var _rescan_timer: float = 0.0
var _dirty: bool = false

var _world_to_tile_cb: Callable
var _tile_to_world_cb: Callable


func setup(ctx: Dictionary) -> void:
	_world_to_tile_cb = ctx.get("world_to_tile", Callable())
	_tile_to_world_cb = ctx.get("tile_to_world", Callable())

	if PlacementSystem != null and not PlacementSystem.placement_completed.is_connected(_on_placement_completed):
		PlacementSystem.placement_completed.connect(_on_placement_completed)

	if GameEvents != null and not GameEvents.resource_harvested.is_connected(_on_resource_harvested):
		GameEvents.resource_harvested.connect(_on_resource_harvested)

	# Force an immediate workbench scan
	_dirty = true


func process(delta: float) -> void:
	_elapsed += delta
	_rescan_timer += delta

	# TTL tick — remove expired markers
	var i := _markers.size() - 1
	while i >= 0:
		var m: Dictionary = _markers[i]
		if not bool(m.get("persistent", false)):
			var exp: float = float(m.get("expires_at", 0.0))
			if _elapsed >= exp:
				_markers.remove_at(i)
		i -= 1

	# Periodic / dirty workbench rescan
	if _dirty or _rescan_timer >= WORKBENCH_RESCAN_INTERVAL:
		_rescan_timer = 0.0
		_dirty = false
		_scan_workbenches()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func record_interest_event(kind: String, world_pos: Vector2, meta: Dictionary = {}) -> void:
	var tile_pos := _world_to_tile(world_pos)
	var ttl: float = float(TTL_BY_KIND.get(kind, 150.0))
	var persistent: bool = ttl < 0.0

	# Dedup: find existing marker of same kind within MERGE_RADIUS
	for m in _markers:
		if m.get("kind", "") != kind:
			continue
		var mpos: Vector2 = m.get("world_pos", Vector2.ZERO)
		if mpos.distance_to(world_pos) < MERGE_RADIUS:
			# Refresh
			m["world_pos"] = world_pos
			m["tile_pos"] = tile_pos
			if not persistent:
				m["expires_at"] = _elapsed + ttl
			if not meta.is_empty():
				m["metadata"] = meta
			return

	# New marker
	var marker_id: String = kind + "_" + str(tile_pos.x) + "_" + str(tile_pos.y)
	var marker: Dictionary = {
		"id":         marker_id,
		"kind":       kind,
		"world_pos":  world_pos,
		"tile_pos":   tile_pos,
		"created_at": _elapsed,
		"expires_at": -1.0 if persistent else _elapsed + ttl,
		"persistent": persistent,
		"metadata":   meta,
	}
	_markers.append(marker)


func get_interest_markers_near(world_pos: Vector2, radius: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var r2 := radius * radius
	for m in _markers:
		var mpos: Vector2 = m.get("world_pos", Vector2.ZERO)
		if mpos.distance_squared_to(world_pos) <= r2:
			result.append(m)
	return result


func clear_invalid_persistent_markers() -> void:
	_scan_workbenches()


func mark_interest_scan_dirty_near(_world_pos: Vector2) -> void:
	_dirty = true


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _scan_workbenches() -> void:
	# Build set of all workbench UIDs currently in WorldSave
	var live_uids: Dictionary = {}
	for ckey in WorldSave.placed_entities_by_chunk:
		var chunk_dict: Dictionary = WorldSave.placed_entities_by_chunk[ckey]
		for uid in chunk_dict:
			var entry: Dictionary = chunk_dict[uid]
			var item_id: String = String(entry.get("item_id", "")).strip_edges()
			if item_id == "workbench":
				live_uids[uid] = entry

	# Remove markers whose workbench no longer exists
	var i := _markers.size() - 1
	while i >= 0:
		var m: Dictionary = _markers[i]
		if m.get("kind", "") == "workbench":
			var meta: Dictionary = m.get("metadata", {})
			var uid: String = String(meta.get("uid", ""))
			if uid != "" and not live_uids.has(uid):
				_markers.remove_at(i)
		i -= 1

	# Add markers for workbenches that don't have one yet
	var existing_uids: Dictionary = {}
	for m in _markers:
		if m.get("kind", "") == "workbench":
			var meta: Dictionary = m.get("metadata", {})
			var uid: String = String(meta.get("uid", ""))
			if uid != "":
				existing_uids[uid] = true

	for uid in live_uids:
		if existing_uids.has(uid):
			continue
		var entry: Dictionary = live_uids[uid]
		var tx: int = int(entry.get("tile_pos_x", 0))
		var ty: int = int(entry.get("tile_pos_y", 0))
		var tile := Vector2i(tx, ty)
		var wpos := _tile_to_world(tile)
		var marker_id: String = "workbench_" + str(uid)
		var marker: Dictionary = {
			"id":         marker_id,
			"kind":       "workbench",
			"world_pos":  wpos,
			"tile_pos":   tile,
			"created_at": _elapsed,
			"expires_at": -1.0,
			"persistent": true,
			"metadata":   {"uid": uid},
		}
		_markers.append(marker)


func _world_to_tile(world_pos: Vector2) -> Vector2i:
	if _world_to_tile_cb.is_valid():
		return _world_to_tile_cb.call(world_pos)
	return Vector2i(int(world_pos.x / 32), int(world_pos.y / 32))


func _tile_to_world(tile_pos: Vector2i) -> Vector2:
	if _tile_to_world_cb.is_valid():
		return _tile_to_world_cb.call(tile_pos)
	return Vector2(tile_pos.x * 32.0 + 16.0, tile_pos.y * 32.0 + 16.0)


func _on_resource_harvested(kind: String, world_pos: Vector2) -> void:
	record_interest_event(kind, world_pos)


func _on_placement_completed(item_id: String, tile_pos: Vector2i) -> void:
	var wpos := _tile_to_world(tile_pos)
	if item_id == "workbench":
		_dirty = true
	record_interest_event("structure_placed", wpos, {"item_id": item_id})
