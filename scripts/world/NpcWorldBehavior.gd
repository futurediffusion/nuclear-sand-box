extends RefCounted
class_name NpcWorldBehavior

# ── NpcWorldBehavior ─────────────────────────────────────────────────────────
# Reusable world-layer state machine for sleeping / lite-mode NPCs.
# Does NOT touch any node directly — returns desired_velocity via get_desired_velocity().
# A coordinator (e.g. BanditBehaviorLayer) is responsible for reading the velocity
# and applying it to the node each physics frame.
#
# Lifecycle:
#   1. setup(cfg)              — called once on creation
#   2. tick(delta, ctx)        — called periodically (e.g. every 0.5 s)
#   3. get_desired_velocity()  — polled every physics frame by the coordinator
#
# ctx keys accepted by tick():
#   "node_pos":           Vector2               — current NPC world position (required)
#   "leader_pos":         Vector2               — group leader position      (FOLLOW_LEADER)
#   "nearby_drops_info":  Array[Dictionary]     — [{id,pos,amount}]          (LOOT_APPROACH)
#   "nearby_res_info":    Array[Dictionary]     — [{pos}]                    (RESOURCE_WATCH)
#
# Coordinator output properties (read after tick()):
#   pending_collect_id: int  — instance_id of ItemDrop to collect (0 = none)
#
# Subclass API:
#   _get_patrol_radius() -> float   — override for role-specific radius
#   _get_speed()         -> float   — override for role-specific speed

enum State {
	IDLE_AT_HOME,
	PATROL,
	HOLD_POSITION,
	RETURN_HOME,
	APPROACH_INTEREST,
	FOLLOW_LEADER,
	LOOT_APPROACH,     # moving toward a visible ItemDrop
	RESOURCE_WATCH,    # patrolling tight area around a resource node
}

# ── Spatial ──────────────────────────────────────────────────────────────────
const ARRIVED_DIST_SQ: float     = 12.0 * 12.0
const COLLECT_DIST_SQ: float     = 16.0 * 16.0  # close enough to collect a drop
const FOLLOW_STOP_DIST_SQ: float = 20.0 * 20.0
const DEFAULT_HOME_RETURN_DIST: float = 192.0

# ── Timing ───────────────────────────────────────────────────────────────────
const DEFAULT_MAX_PATROL_TIME: float = 14.0
const RESOURCE_WATCH_DURATION: float = 10.0   # s before giving up a watch position
const IDLE_WAIT_MIN: float         = 2.0
const IDLE_WAIT_MAX: float         = 6.0

# ── Identity ─────────────────────────────────────────────────────────────────
var state: State    = State.IDLE_AT_HOME
var home_pos: Vector2  = Vector2.ZERO
var role: String       = "scavenger"
var group_id: String   = ""
var member_id: String  = ""

# ── Cargo (simple counter — no item details) ─────────────────────────────────
var cargo_count: int    = 0
var cargo_capacity: int = 3

# ── Coordinator output ───────────────────────────────────────────────────────
# Set by behavior when arriving at a loot target; BanditBehaviorLayer reads + clears.
var pending_collect_id: int = 0

# ── Internal ─────────────────────────────────────────────────────────────────
var _move_target: Vector2       = Vector2.ZERO
var _idle_timer: float          = 0.0
var _state_timer: float         = 0.0
var _desired_velocity: Vector2  = Vector2.ZERO
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

# LOOT_APPROACH
var _loot_target_id: int = 0   # instance_id of target ItemDrop

# RESOURCE_WATCH
var _resource_watch_pos: Vector2   = Vector2.ZERO
var _resource_watch_timer: float   = 0.0


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

func setup(cfg: Dictionary) -> void:
	home_pos       = cfg.get("home_pos",       Vector2.ZERO)
	role           = cfg.get("role",           "scavenger")
	group_id       = cfg.get("group_id",       "")
	member_id      = cfg.get("member_id",      "")
	cargo_capacity = cfg.get("cargo_capacity", 3)
	cargo_count    = cfg.get("cargo_count",    0)
	_rng.randomize()
	_move_target = home_pos
	state        = State.IDLE_AT_HOME
	_idle_timer  = _rng.randf_range(IDLE_WAIT_MIN, IDLE_WAIT_MAX)


# ---------------------------------------------------------------------------
# Tick
# ---------------------------------------------------------------------------

func tick(delta: float, ctx: Dictionary) -> void:
	_state_timer += delta
	_desired_velocity = Vector2.ZERO
	var node_pos: Vector2 = ctx.get("node_pos", home_pos)

	# Safety: force RETURN_HOME if strayed too far from home
	var _home_dist: float = _get_home_return_dist()
	if state != State.RETURN_HOME and state != State.IDLE_AT_HOME \
			and state != State.LOOT_APPROACH:
		if node_pos.distance_squared_to(home_pos) > _home_dist * _home_dist:
			_enter_return_home()

	_tick_state(delta, ctx, node_pos)


func get_desired_velocity() -> Vector2:
	return _desired_velocity


# ---------------------------------------------------------------------------
# Public helpers
# ---------------------------------------------------------------------------

func is_cargo_full() -> bool:
	return cargo_count >= cargo_capacity

func is_cargo_empty() -> bool:
	return cargo_count <= 0

## Enter LOOT_APPROACH for a specific drop (by instance_id).
func enter_loot_approach(drop_id: int) -> void:
	_loot_target_id = drop_id
	pending_collect_id = 0
	state        = State.LOOT_APPROACH
	_state_timer = 0.0
	_invalidate_npc_path()

## Enter RESOURCE_WATCH, patrolling tightly around resource_pos.
func enter_resource_watch(resource_pos: Vector2) -> void:
	_resource_watch_pos   = resource_pos
	_resource_watch_timer = 0.0
	var angle: float = _rng.randf_range(0.0, TAU)
	_move_target = resource_pos + Vector2(cos(angle), sin(angle)) * 18.0
	state        = State.RESOURCE_WATCH
	_state_timer = 0.0


# ---------------------------------------------------------------------------
# Virtual overrides for subclasses
# ---------------------------------------------------------------------------

func _get_patrol_radius() -> float:
	return 64.0

func _get_speed() -> float:
	return 55.0

func _get_home_return_dist() -> float:
	return DEFAULT_HOME_RETURN_DIST

func _get_max_patrol_time() -> float:
	return DEFAULT_MAX_PATROL_TIME


# ---------------------------------------------------------------------------
# Pathfinding helpers
# ---------------------------------------------------------------------------

## Returns a normalised direction toward goal, using NpcPathService waypoints
## when available. Falls back to direct direction if service is not ready.
func _pathfind_dir(node_pos: Vector2, goal: Vector2) -> Vector2:
	if member_id == "" or not NpcPathService.is_ready():
		return _move_dir(node_pos, goal)
	var wp: Vector2 = NpcPathService.get_next_waypoint(member_id, node_pos, goal)
	return _move_dir(node_pos, wp)

## Discard cached path for this NPC (call on state transitions with new goals).
func _invalidate_npc_path() -> void:
	if member_id != "" and NpcPathService.is_ready():
		NpcPathService.invalidate_path(member_id)


# ---------------------------------------------------------------------------
# State machine
# ---------------------------------------------------------------------------

func _tick_state(delta: float, ctx: Dictionary, node_pos: Vector2) -> void:
	match state:
		State.IDLE_AT_HOME:
			_idle_timer -= delta
			if _idle_timer <= 0.0:
				_enter_patrol(ctx)

		State.PATROL:
			_desired_velocity = _pathfind_dir(node_pos, _move_target) * _get_speed()
			if node_pos.distance_squared_to(_move_target) < ARRIVED_DIST_SQ \
					or _state_timer > _get_max_patrol_time():
				_enter_idle_at_home()

		State.RETURN_HOME:
			_desired_velocity = _pathfind_dir(node_pos, home_pos) * _get_speed()
			if node_pos.distance_squared_to(home_pos) < ARRIVED_DIST_SQ:
				cargo_count = 0   # unload cargo at home
				_enter_idle_at_home()

		State.HOLD_POSITION:
			pass

		State.APPROACH_INTEREST:
			_desired_velocity = _pathfind_dir(node_pos, _move_target) * _get_speed()
			if node_pos.distance_squared_to(_move_target) < ARRIVED_DIST_SQ \
					or _state_timer > _get_max_patrol_time():
				_enter_idle_at_home()

		State.FOLLOW_LEADER:
			var leader_pos: Vector2 = ctx.get("leader_pos", home_pos)
			if node_pos.distance_squared_to(leader_pos) > FOLLOW_STOP_DIST_SQ:
				_desired_velocity = _pathfind_dir(node_pos, leader_pos) * _get_speed()

		State.LOOT_APPROACH:
			_tick_loot_approach(node_pos)

		State.RESOURCE_WATCH:
			_tick_resource_watch(delta, node_pos)


func _tick_loot_approach(node_pos: Vector2) -> void:
	if _loot_target_id == 0 or not is_instance_id_valid(_loot_target_id):
		_loot_target_id = 0
		_enter_idle_at_home()
		return
	var drop_obj: Object = instance_from_id(_loot_target_id)
	if drop_obj == null or not is_instance_valid(drop_obj):
		_loot_target_id = 0
		_enter_idle_at_home()
		return
	var drop_node := drop_obj as Node2D
	if drop_node == null or drop_node.is_queued_for_deletion():
		_loot_target_id = 0
		_enter_idle_at_home()
		return

	var drop_pos: Vector2 = drop_node.global_position
	_desired_velocity = _pathfind_dir(node_pos, drop_pos) * _get_speed()

	if node_pos.distance_squared_to(drop_pos) < COLLECT_DIST_SQ:
		# Signal coordinator to do the actual collection
		pending_collect_id = _loot_target_id
		_loot_target_id    = 0
		# Coordinator increments cargo_count; we decide next state after cargo is updated
		# For now transition to idle; subclass may override via post-collect logic
		_enter_idle_at_home()

	# Abort if taking too long (drop might be unreachable)
	elif _state_timer > _get_max_patrol_time():
		_loot_target_id = 0
		_enter_idle_at_home()


func _tick_resource_watch(delta: float, node_pos: Vector2) -> void:
	_resource_watch_timer += delta

	# Slowly orbit the resource position
	_desired_velocity = _move_dir(node_pos, _move_target) * (_get_speed() * 0.55)
	if node_pos.distance_squared_to(_move_target) < ARRIVED_DIST_SQ:
		# Pick next orbit point
		var angle: float = _rng.randf_range(0.0, TAU)
		_move_target = _resource_watch_pos + Vector2(cos(angle), sin(angle)) * _rng.randf_range(10.0, 28.0)

	if _resource_watch_timer >= RESOURCE_WATCH_DURATION:
		_resource_watch_timer = 0.0
		if cargo_count > 0:
			_enter_return_home()
		else:
			_enter_idle_at_home()


# ---------------------------------------------------------------------------
# Transition helpers
# ---------------------------------------------------------------------------

func _enter_idle_at_home() -> void:
	state             = State.IDLE_AT_HOME
	_idle_timer       = _rng.randf_range(IDLE_WAIT_MIN, IDLE_WAIT_MAX)
	_desired_velocity = Vector2.ZERO
	_state_timer      = 0.0


func _enter_patrol(ctx: Dictionary) -> void:
	var radius: float = _get_patrol_radius()
	var angle: float  = _rng.randf_range(0.0, TAU)
	var dist: float   = _rng.randf_range(radius * 0.3, radius)
	_move_target  = home_pos + Vector2(cos(angle), sin(angle)) * dist
	state         = State.PATROL
	_state_timer  = 0.0
	_invalidate_npc_path()


func _enter_return_home() -> void:
	state        = State.RETURN_HOME
	_state_timer = 0.0
	_invalidate_npc_path()


# ---------------------------------------------------------------------------
# Utilities
# ---------------------------------------------------------------------------

func _move_dir(from: Vector2, to: Vector2) -> Vector2:
	var d: Vector2    = to - from
	var len_sq: float = d.length_squared()
	if len_sq < 0.0001:
		return Vector2.ZERO
	return d / sqrt(len_sq)


# ---------------------------------------------------------------------------
# Serialization — export / import for offscreen continuity
# ---------------------------------------------------------------------------

## Exports the current behavior state to a flat Dictionary safe for WorldSave.
## Call before handing off to data-only mode or before despawning.
func export_state() -> Dictionary:
	return {
		"wb_state":           int(state),
		"wb_move_target":     _move_target,
		"wb_idle_timer":      _idle_timer,
		"wb_state_timer":     _state_timer,
		"wb_cargo_count":     cargo_count,
		"wb_cargo_cap":       cargo_capacity,
		"wb_res_watch_pos":   _resource_watch_pos,
		"wb_res_watch_timer": _resource_watch_timer,
		"wb_rng_state":       str(_rng.state),
	}

## Restores behavior state from a previously exported dictionary.
## LOOT_APPROACH resets to IDLE — loot node refs cannot survive sessions.
func import_state(data: Dictionary) -> void:
	if data.is_empty():
		return
	var s: int = int(data.get("wb_state", int(State.IDLE_AT_HOME)))
	if s == int(State.LOOT_APPROACH):
		s = int(State.IDLE_AT_HOME)
	state        = s
	var mt = data.get("wb_move_target", home_pos)
	_move_target = mt if mt is Vector2 else home_pos
	_idle_timer           = float(data.get("wb_idle_timer",      0.0))
	_state_timer          = float(data.get("wb_state_timer",     0.0))
	cargo_count           = int(data.get("wb_cargo_count",       cargo_count))
	cargo_capacity        = int(data.get("wb_cargo_cap",         cargo_capacity))
	var rwp = data.get("wb_res_watch_pos", Vector2.ZERO)
	_resource_watch_pos   = rwp if rwp is Vector2 else Vector2.ZERO
	_resource_watch_timer = float(data.get("wb_res_watch_timer", 0.0))
	_loot_target_id    = 0
	pending_collect_id = 0
	if data.has("wb_rng_state"):
		var rs: int = int(str(data.get("wb_rng_state", "0")))
		if rs != 0:
			_rng.state = rs
