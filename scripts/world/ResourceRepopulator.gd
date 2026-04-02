extends Node
class_name ResourceRepopulator

# ── ResourceRepopulator ────────────────────────────────────────────────────────
# Tracks resource depletion and respawns new nodes at random valid map positions
# after a configurable cooldown.
#
# Each depleted resource adds one "pending respawn" timer. When the timer
# expires a new node is spawned at a random floor tile, respecting the max cap.
# The cap (max_stone / max_copper) is the inspector-set ceiling — the live count
# can drop below it while timers are running.
#
# Setup: call setup(stone_scene, copper_scene, tilemap) from world.gd after
# the tilemap is ready. Resources call on_resource_depleted("stone"|"copper")
# by finding nodes in the "resource_repopulator" group.

@export_group("Stone Repop")
@export var max_stone: int = 10
@export var stone_respawn_cooldown: float = 45.0

@export_group("Copper Repop")
@export var max_copper: int = 6
@export var copper_respawn_cooldown: float = 80.0
@export_group("")

const FLOOR_LAYER: int        = 1           # tilemap layer with walkable ground
const PLAYER_MIN_DIST_SQ: float = 280.0 * 280.0  # keep respawns away from player
const MAX_PICK_RETRIES: int   = 80          # attempts to find a valid tile

var _stone_scene:  PackedScene = null
var _copper_scene: PackedScene = null
var _tilemap: TileMap          = null
var _floor_cells: Array[Vector2i] = []
var _player_world_pos: Vector2 = Vector2.INF
var _live_counts := {
	"stone": 0,
	"copper": 0,
}

# Each entry = seconds remaining before a spawn attempt
var _stone_pending:  Array[float] = []
var _copper_pending: Array[float] = []


# ---------------------------------------------------------------------------
# Setup — called once by world.gd after tilemap is ready
# ---------------------------------------------------------------------------

func setup(stone_scene: PackedScene, copper_scene: PackedScene, tilemap: TileMap) -> void:
	_stone_scene  = stone_scene
	_copper_scene = copper_scene
	_tilemap      = tilemap
	_rebuild_floor_cache()
	_sync_live_counts_from_world()
	add_to_group("resource_repopulator")


func set_player_world_pos(pos: Vector2) -> void:
	_player_world_pos = pos


# ---------------------------------------------------------------------------
# Depletion notification — called by stone_ore / copper_ore on queue_free
# ---------------------------------------------------------------------------

func on_resource_depleted(kind: String) -> void:
	match kind:
		"stone":
			_stone_pending.append(stone_respawn_cooldown)
			_adjust_live_count("stone", -1)
		"copper":
			_copper_pending.append(copper_respawn_cooldown)
			_adjust_live_count("copper", -1)
	Debug.log("resource_repop", "[Repop] depleted %s → cooldown %.0fs pending=%d" % [
		kind,
		stone_respawn_cooldown if kind == "stone" else copper_respawn_cooldown,
		_stone_pending.size() if kind == "stone" else _copper_pending.size(),
	])


# ---------------------------------------------------------------------------
# Process — tick timers and attempt spawns
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	_tick(delta, _stone_pending,  _stone_scene,  max_stone,  "world_stone",  "stone")
	_tick(delta, _copper_pending, _copper_scene, max_copper, "world_copper", "copper")


func _tick(delta: float, timers: Array[float],
		scene: PackedScene, cap: int, _group: String, kind: String) -> void:
	if timers.is_empty():
		return
	for i in timers.size():
		timers[i] -= delta
	var i := 0
	while i < timers.size():
		if timers[i] > 0.0:
			i += 1
			continue
		# Timer expired — check if we're still below cap
		var live: int = _get_live_count(kind)
		if live >= cap:
			# Cap already met (maybe the world has originals still loaded).
			# Discard this pending spawn — no need for another.
			timers.remove_at(i)
			Debug.log("resource_repop", "[Repop] %s cap met (%d/%d), pending discarded" % [kind, live, cap])
			continue
		var pos := _pick_random_floor_pos()
		if pos == Vector2.INF:
			# No valid tile found right now — retry in a few seconds
			timers[i] = 8.0
			i += 1
			Debug.log("resource_repop", "[Repop] %s no valid tile, retry in 8s" % kind)
			continue
		_spawn(scene, pos, kind)
		timers.remove_at(i)


# ---------------------------------------------------------------------------
# Spawn
# ---------------------------------------------------------------------------

func _spawn(scene: PackedScene, pos: Vector2, kind: String) -> void:
	if scene == null or _tilemap == null:
		return
	var node := scene.instantiate()
	_tilemap.add_child(node)
	(node as Node2D).global_position = pos
	_adjust_live_count(kind, 1)
	Debug.log("resource_repop", "[Repop] spawned %s at %s" % [kind, str(pos)])


# ---------------------------------------------------------------------------
# Random valid floor position
# ---------------------------------------------------------------------------

func _pick_random_floor_pos() -> Vector2:
	if _tilemap == null:
		return Vector2.INF
	if _floor_cells.is_empty():
		_rebuild_floor_cache()
	if _floor_cells.is_empty():
		return Vector2.INF

	for _attempt in MAX_PICK_RETRIES:
		var cell: Vector2i = _floor_cells[randi() % _floor_cells.size()]
		var local_pos: Vector2 = _tilemap.map_to_local(cell)
		var world_pos: Vector2 = _tilemap.to_global(local_pos)

		if _player_world_pos != Vector2.INF \
				and world_pos.distance_squared_to(_player_world_pos) < PLAYER_MIN_DIST_SQ:
			continue  # too close to player

		return world_pos

	return Vector2.INF


func _rebuild_floor_cache() -> void:
	_floor_cells.clear()
	if _tilemap == null:
		return
	_floor_cells = _tilemap.get_used_cells(FLOOR_LAYER)


func _sync_live_counts_from_world() -> void:
	_live_counts["stone"] = get_tree().get_nodes_in_group("world_stone").size()
	_live_counts["copper"] = get_tree().get_nodes_in_group("world_copper").size()


func _get_live_count(kind: String) -> int:
	return int(_live_counts.get(kind, 0))


func _adjust_live_count(kind: String, delta: int) -> void:
	var current: int = int(_live_counts.get(kind, 0))
	_live_counts[kind] = maxi(0, current + delta)
