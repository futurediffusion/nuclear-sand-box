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
const REPOP_LOG_SAMPLE_HEAVY: int = 6

var _stone_scene:  PackedScene = null
var _copper_scene: PackedScene = null
var _tilemap: TileMap          = null
var _cadence_enabled: bool = false
var _cadence_tick_interval: float = 0.50

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
	add_to_group("resource_repopulator")

func configure_cadence(tick_interval: float) -> void:
	_cadence_enabled = tick_interval > 0.0
	_cadence_tick_interval = maxf(0.05, tick_interval)
	set_process(not _cadence_enabled)


# ---------------------------------------------------------------------------
# Depletion notification — called by stone_ore / copper_ore on queue_free
# ---------------------------------------------------------------------------

func on_resource_depleted(kind: String) -> void:
	match kind:
		"stone":  _stone_pending.append(stone_respawn_cooldown)
		"copper": _copper_pending.append(copper_respawn_cooldown)
	if _can_log_repop():
		Debug.log("resource_repop", "[Repop] depleted %s → cooldown %.0fs pending=%d" % [
			kind,
			stone_respawn_cooldown if kind == "stone" else copper_respawn_cooldown,
			_stone_pending.size() if kind == "stone" else _copper_pending.size(),
		])


# ---------------------------------------------------------------------------
# Process — tick timers and attempt spawns
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _cadence_enabled:
		return
	_tick(delta, _stone_pending,  _stone_scene,  max_stone,  "world_stone",  "stone")
	_tick(delta, _copper_pending, _copper_scene, max_copper, "world_copper", "copper")

func tick_from_cadence(pulses: int) -> int:
	if not _cadence_enabled or pulses <= 0:
		return 0
	var total_ops: int = 0
	for _pulse in pulses:
		total_ops += _tick(_cadence_tick_interval, _stone_pending,  _stone_scene,  max_stone,  "world_stone",  "stone")
		total_ops += _tick(_cadence_tick_interval, _copper_pending, _copper_scene, max_copper, "world_copper", "copper")
	return total_ops


func _tick(delta: float, timers: Array[float],
		scene: PackedScene, cap: int, group: String, kind: String) -> int:
	if timers.is_empty():
		return 0
	var ops: int = 0
	for i in timers.size():
		timers[i] -= delta
		ops += 1
	var i := 0
	while i < timers.size():
		if timers[i] > 0.0:
			i += 1
			continue
		# Timer expired — check if we're still below cap
		var live: int = get_tree().get_nodes_in_group(group).size()
		if live >= cap:
			# Cap already met (maybe the world has originals still loaded).
			# Discard this pending spawn — no need for another.
			timers.remove_at(i)
			if _should_log_repop("%s_cap_met" % kind, REPOP_LOG_SAMPLE_HEAVY):
				Debug.log("resource_repop", "[Repop] %s cap met (%d/%d), pending discarded" % [kind, live, cap])
			ops += 1
			continue
		var pos := _pick_random_floor_pos()
		if pos == Vector2.INF:
			# No valid tile found right now — retry in a few seconds
			timers[i] = 8.0
			i += 1
			if _should_log_repop("%s_retry_no_tile" % kind, REPOP_LOG_SAMPLE_HEAVY):
				Debug.log("resource_repop", "[Repop] %s no valid tile, retry in 8s" % kind)
			ops += 1
			continue
		_spawn(scene, pos, kind)
		timers.remove_at(i)
		ops += 1
	return ops


# ---------------------------------------------------------------------------
# Spawn
# ---------------------------------------------------------------------------

func _spawn(scene: PackedScene, pos: Vector2, kind: String) -> void:
	if scene == null or _tilemap == null:
		return
	var node := scene.instantiate()
	_tilemap.add_child(node)
	(node as Node2D).global_position = pos
	if _can_log_repop():
		Debug.log("resource_repop", "[Repop] spawned %s at %s" % [kind, str(pos)])


# ---------------------------------------------------------------------------
# Random valid floor position
# ---------------------------------------------------------------------------

func _pick_random_floor_pos() -> Vector2:
	if _tilemap == null:
		return Vector2.INF
	var cells: Array[Vector2i] = _tilemap.get_used_cells(FLOOR_LAYER)
	if cells.is_empty():
		return Vector2.INF

	var player_pos := Vector2.INF
	var players := get_tree().get_nodes_in_group("player")
	if not players.is_empty():
		player_pos = (players[0] as Node2D).global_position

	for _attempt in MAX_PICK_RETRIES:
		var cell: Vector2i = cells[randi() % cells.size()]
		var local_pos: Vector2 = _tilemap.map_to_local(cell)
		var world_pos: Vector2 = _tilemap.to_global(local_pos)

		if player_pos != Vector2.INF \
				and world_pos.distance_squared_to(player_pos) < PLAYER_MIN_DIST_SQ:
			continue  # too close to player

		return world_pos

	return Vector2.INF


func _can_log_repop() -> bool:
	return Debug.is_enabled("resource_repop")


func _should_log_repop(sample_key: String, every_n: int) -> bool:
	return Debug.should_sample("resource_repop", "resource_repop:%s" % sample_key, every_n)
