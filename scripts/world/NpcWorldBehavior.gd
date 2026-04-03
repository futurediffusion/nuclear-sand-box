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
	LOOT_APPROACH,      # moving toward a visible ItemDrop
	RESOURCE_WATCH,     # orbiting a resource node
	EXTORT_APPROACH,    # moving toward extortion target (data-only + live)
	EXTORT_RETREAT,     # returning home after extortion attempt
}

# ── Spatial ──────────────────────────────────────────────────────────────────
const ARRIVED_DIST_SQ: float        = 12.0 * 12.0
# Radio ampliado para depositar en barril: cualquier tile alrededor cuenta (~3 tiles)
const DEPOSIT_ARRIVED_DIST_SQ: float = 52.0 * 52.0
const COLLECT_DIST_SQ: float     = 44.0 * 44.0  # must exceed ally separation so LOOT_APPROACH can actually collect
const FOLLOW_STOP_DIST_SQ: float = 20.0 * 20.0
const FOLLOW_SLOT_RADIUS_DEFAULT: float = 28.0
const DEFAULT_HOME_RETURN_DIST: float = 192.0

# ── Timing ───────────────────────────────────────────────────────────────────
const DEFAULT_MAX_PATROL_TIME: float = 14.0
const RESOURCE_WATCH_DURATION: float = 10.0   # s before giving up a watch position
# Máximo tiempo en RETURN_HOME antes de aceptar la posición actual y disparar el depósito.
# Previene NPCs bloqueados indefinidamente si el camino al barril está obstruido.
const RETURN_HOME_TIMEOUT: float = 18.0
const IDLE_WAIT_MIN: float         = 2.0
const IDLE_WAIT_MAX: float         = 6.0
const MINE_TICK_INTERVAL: float    = 0.9      # s between mining hits during RESOURCE_WATCH

# ── Stuck detection ───────────────────────────────────────────────────────────
const STUCK_CHECK_INTERVAL: float    = 1.5    # s between progress checks
const STUCK_MIN_PROGRESS_SQ: float   = 20.0 * 20.0  # must move 20 px per interval
const DETOUR_DURATION: float         = 1.5    # s of perpendicular detour after NPC-collision

# ── Identity ─────────────────────────────────────────────────────────────────
var state: State    = State.IDLE_AT_HOME
var home_pos: Vector2     = Vector2.ZERO
## When non-zero, RETURN_HOME navigates here instead of home_pos (used for barrel deposit).
var deposit_pos: Vector2  = Vector2.ZERO
var role: String          = "scavenger"
var group_id: String   = ""
var member_id: String  = ""

# ── Cargo (simple counter — no item details) ─────────────────────────────────
var cargo_count: int    = 0
var cargo_capacity: int = 3
var deposit_lock_active: bool = false

# ── Coordinator output ───────────────────────────────────────────────────────
# Set by behavior when arriving at a loot target; BanditBehaviorLayer reads + clears.
var pending_collect_id: int = 0
# Set each mine tick; layer calls resource.hit() then clears.
var pending_mine_id: int = 0
# One-shot flag: layer spawns drops at home_pos + zeros cargo after detecting this.
var _just_arrived_home_with_cargo: bool = false
# Manifest of collected items [{item_id, amount}] — cleared on deposit.
var _cargo_manifest: Array = []

# ── Internal ─────────────────────────────────────────────────────────────────
var _move_target: Vector2       = Vector2.ZERO
var _idle_timer: float          = 0.0
var _state_timer: float         = 0.0
var _desired_velocity: Vector2  = Vector2.ZERO
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

# LOOT_APPROACH
var _loot_target_id: int = 0   # instance_id of target ItemDrop

# RESOURCE_WATCH — orbit state
var _resource_watch_pos: Vector2    = Vector2.ZERO
var _resource_watch_timer: float    = 0.0
var _resource_orbit_radius: float   = 38.0   # px; fixed per session
var _resource_orbit_angle: float    = 0.0    # current angle (radians)
var _resource_orbit_dir: float      = 1.0    # +1 CCW, -1 CW
var _resource_orbit_step: float     = 0.6    # rad advanced per waypoint
var _resource_node_id: int          = 0      # instance_id of resource being orbited
var _mine_tick_timer: float         = 0.0    # countdown to next mine hit
var last_valid_resource_node_id: int = 0
var last_resource_hit_tick: int      = 0

# Last known node position — lets enter_resource_watch compute initial angle
var _last_node_pos: Vector2 = Vector2.ZERO

# STUCK detection (PATROL / APPROACH_INTEREST / RETURN_HOME / FOLLOW_LEADER)
var _stuck_check_pos: Vector2 = Vector2.ZERO
var _stuck_timer: float       = 0.0
# Detour state: perpendicular nudge when blocked by another NPC
var _detour_dir: Vector2      = Vector2.ZERO
var _detour_timer: float      = 0.0


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
	_last_node_pos = node_pos

	# Safety: force RETURN_HOME if strayed too far from home
	var _home_dist: float = _get_home_return_dist()
	if state != State.RETURN_HOME and state != State.IDLE_AT_HOME \
			and state != State.LOOT_APPROACH \
			and state != State.EXTORT_APPROACH and state != State.EXTORT_RETREAT:
		if node_pos.distance_squared_to(home_pos) > _home_dist * _home_dist:
			_enter_return_home()

	_tick_state(delta, ctx, node_pos)
	_check_stuck(delta, node_pos)

	# Apply perpendicular detour nudge when blocked by another NPC
	if _detour_timer > 0.0:
		_detour_timer -= delta
		_desired_velocity += _detour_dir * (_get_speed() * 0.65)


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

## Begin moving toward an extortion target position.
func enter_extort_approach(target_pos: Vector2) -> void:
	_move_target = target_pos
	state        = State.EXTORT_APPROACH
	_state_timer = 0.0
	_invalidate_npc_path()

## Enter RESOURCE_WATCH, orbiting resource_pos at a fixed radius.
func enter_resource_watch(resource_pos: Vector2, resource_id: int = 0) -> void:
	_resource_node_id     = resource_id
	if resource_id != 0:
		last_valid_resource_node_id = resource_id
	_mine_tick_timer      = 0.0
	pending_mine_id       = 0
	_resource_watch_pos   = resource_pos
	_resource_watch_timer = 0.0
	state                 = State.RESOURCE_WATCH
	_state_timer          = 0.0

	# Orbit parameters — fixed for the duration of this watch session
	_resource_orbit_radius = _rng.randf_range(32.0, 44.0)
	_resource_orbit_dir    = 1.0 if _rng.randf() > 0.5 else -1.0
	_resource_orbit_step   = _rng.randf_range(0.45, 0.75)

	# Initial angle: from resource center toward the NPC (place first waypoint
	# near where we already are so we don't cut through the center)
	var from_res: Vector2 = _last_node_pos - resource_pos
	if from_res.length_squared() > 4.0:
		_resource_orbit_angle = atan2(from_res.y, from_res.x)
	else:
		_resource_orbit_angle = _rng.randf_range(0.0, TAU)

	_move_target = resource_pos + Vector2(cos(_resource_orbit_angle), sin(_resource_orbit_angle)) * _resource_orbit_radius


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
# Stuck detection
# ---------------------------------------------------------------------------

## Detects NPCs that haven't progressed and either resets them to idle
## (PATROL/APPROACH) or starts a perpendicular detour (RETURN_HOME/FOLLOW_LEADER).
func _check_stuck(delta: float, node_pos: Vector2) -> void:
	match state:
		State.PATROL:
			_stuck_timer += delta
			if _stuck_timer >= STUCK_CHECK_INTERVAL:
				var moved_sq: float = node_pos.distance_squared_to(_stuck_check_pos)
				_stuck_check_pos = node_pos
				_stuck_timer     = 0.0
				if moved_sq < STUCK_MIN_PROGRESS_SQ:
					_invalidate_npc_path()
					_enter_idle_at_home()

		State.APPROACH_INTEREST:
			_stuck_timer += delta
			if _stuck_timer >= STUCK_CHECK_INTERVAL:
				var moved_sq: float = node_pos.distance_squared_to(_stuck_check_pos)
				_stuck_check_pos = node_pos
				_stuck_timer     = 0.0
				if moved_sq < STUCK_MIN_PROGRESS_SQ:
					_invalidate_npc_path()
					# En aproximación a objetivos, evitar caer a IDLE inmediato.
					# Aplicamos un pequeño desvío para romper atascos en esquinas.
					if _detour_timer <= 0.0:
						var forward: Vector2 = (_move_target - node_pos).normalized()
						if forward.length_squared() < 0.01:
							forward = Vector2(1.0, 0.0)
						var perp: Vector2 = Vector2(-forward.y, forward.x)
						if _rng.randf() > 0.5:
							perp = -perp
						_detour_dir   = perp
						_detour_timer = DETOUR_DURATION

		State.RETURN_HOME, State.FOLLOW_LEADER:
			_stuck_timer += delta
			if _stuck_timer >= STUCK_CHECK_INTERVAL:
				var moved_sq: float = node_pos.distance_squared_to(_stuck_check_pos)
				_stuck_check_pos = node_pos
				_stuck_timer     = 0.0
				if moved_sq < STUCK_MIN_PROGRESS_SQ and _detour_timer <= 0.0:
					# Pick perpendicular direction to current heading to go around obstacle
					var forward: Vector2 = _desired_velocity.normalized()
					if forward.length_squared() < 0.01:
						forward = Vector2(1.0, 0.0)
					# Alternate left/right based on rng to avoid always going same side
					var perp: Vector2 = Vector2(-forward.y, forward.x)
					if _rng.randf() > 0.5:
						perp = -perp
					_detour_dir   = perp
					_detour_timer = DETOUR_DURATION
					_invalidate_npc_path()

		_:
			_stuck_check_pos = node_pos
			_stuck_timer     = 0.0


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
			# Only navigate to the barrel when actually carrying cargo.
			# Empty returns go straight to home_pos so NPCs don't crowd the barrel.
			var carrying: bool = cargo_count > 0
			var return_target := (deposit_pos if deposit_pos != Vector2.ZERO else home_pos) \
				if carrying else home_pos
			_desired_velocity = _pathfind_dir(node_pos, return_target) * _get_speed()
			var arrive_sq := DEPOSIT_ARRIVED_DIST_SQ if carrying else ARRIVED_DIST_SQ
			# Timeout: si lleva demasiado tiempo, ampliar radio progresivamente y
			# eventualmente aceptar la posición actual para disparar el depósito.
			# Evita NPCs bloqueados infinitamente cuando el barril está contra una pared.
			if _state_timer > RETURN_HOME_TIMEOUT:
				_enter_idle_at_home()
			elif carrying and _state_timer > RETURN_HOME_TIMEOUT * 0.55:
				# Radio ampliado al 55% del timeout: acepta posición si está razonablemente cerca
				var relaxed_sq := arrive_sq * 4.0
				if node_pos.distance_squared_to(return_target) < relaxed_sq:
					_enter_idle_at_home()
			elif node_pos.distance_squared_to(return_target) < arrive_sq:
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
			var follow_target: Vector2 = ctx.get("follow_slot_pos", leader_pos)
			var stop_radius: float = float(ctx.get("follow_slot_radius", FOLLOW_SLOT_RADIUS_DEFAULT))
			var stop_dist_sq: float = maxf(stop_radius, 1.0)
			stop_dist_sq *= stop_dist_sq
			# Compat fallback: if no slot is assigned, use legacy leader stop distance.
			if not ctx.has("follow_slot_pos"):
				stop_dist_sq = FOLLOW_STOP_DIST_SQ
			if node_pos.distance_squared_to(follow_target) > stop_dist_sq:
				_desired_velocity = _pathfind_dir(node_pos, follow_target) * _get_speed()

		State.LOOT_APPROACH:
			_tick_loot_approach(node_pos)

		State.RESOURCE_WATCH:
			_tick_resource_watch(delta, node_pos)

		State.EXTORT_APPROACH:
			_desired_velocity = _pathfind_dir(node_pos, _move_target) * _get_speed()
			# Arrived or timed out → fall back home
			if node_pos.distance_squared_to(_move_target) < ARRIVED_DIST_SQ \
					or _state_timer > _get_max_patrol_time() * 0.4:
				_enter_extort_retreat()

		State.EXTORT_RETREAT:
			_desired_velocity = _pathfind_dir(node_pos, home_pos) * (_get_speed() * 0.7)
			if node_pos.distance_squared_to(home_pos) < ARRIVED_DIST_SQ:
				_enter_idle_at_home()


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
	# Drop ya recogido por otro NPC (sacado del grupo) — abandonar persecución
	if not drop_node.is_in_group("item_drop"):
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

	# Mine tick — signal coordinator to call resource.hit()
	_mine_tick_timer += delta
	if _mine_tick_timer >= MINE_TICK_INTERVAL and _resource_node_id != 0:
		_mine_tick_timer = 0.0
		pending_mine_id  = _resource_node_id

	# Move toward current orbit waypoint at reduced speed
	_desired_velocity = _move_dir(node_pos, _move_target) * (_get_speed() * 0.55)

	# On arrival, step the orbit angle and place the next waypoint on the circumference
	if node_pos.distance_squared_to(_move_target) < ARRIVED_DIST_SQ:
		_resource_orbit_angle += _resource_orbit_step * _resource_orbit_dir
		_move_target = _resource_watch_pos + \
				Vector2(cos(_resource_orbit_angle), sin(_resource_orbit_angle)) * _resource_orbit_radius

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
	# Solo marcar depósito cuando venimos explícitamente de RETURN_HOME,
	# no cuando pasamos por idle tras recoger un drop en el campo.
	if cargo_count > 0 and state == State.RETURN_HOME:
		_just_arrived_home_with_cargo = true
	state             = State.IDLE_AT_HOME
	_idle_timer       = _rng.randf_range(IDLE_WAIT_MIN, IDLE_WAIT_MAX)
	_desired_velocity = Vector2.ZERO
	_state_timer      = 0.0
	_detour_timer     = 0.0
	_detour_dir       = Vector2.ZERO


func _enter_patrol(ctx: Dictionary) -> void:
	var radius: float = _get_patrol_radius()
	var angle: float  = _rng.randf_range(0.0, TAU)
	var dist: float   = _rng.randf_range(radius * 0.3, radius)
	_move_target  = home_pos + Vector2(cos(angle), sin(angle)) * dist
	state         = State.PATROL
	_state_timer  = 0.0
	_invalidate_npc_path()


func _enter_return_home() -> void:
	if cargo_count > 0:
		deposit_lock_active = true
	state         = State.RETURN_HOME
	_state_timer  = 0.0
	_detour_timer = 0.0
	_detour_dir   = Vector2.ZERO
	_invalidate_npc_path()

func force_return_home() -> void:
	_enter_return_home()

func _enter_extort_retreat() -> void:
	state        = State.EXTORT_RETREAT
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
		"wb_state":            int(state),
		"wb_move_target":      _move_target,
		"wb_idle_timer":       _idle_timer,
		"wb_state_timer":      _state_timer,
		"wb_cargo_count":      cargo_count,
		"wb_cargo_cap":        cargo_capacity,
		"wb_deposit_lock_active": deposit_lock_active,
		"wb_res_watch_pos":    _resource_watch_pos,
		"wb_res_watch_timer":  _resource_watch_timer,
		"wb_orbit_radius":     _resource_orbit_radius,
		"wb_orbit_angle":      _resource_orbit_angle,
		"wb_orbit_dir":        _resource_orbit_dir,
		"wb_orbit_step":       _resource_orbit_step,
		"wb_rng_state":        str(_rng.state),
		"pending_mine_id":     pending_mine_id,
		"resource_node_id":    _resource_node_id,
		"last_valid_resource_node_id": last_valid_resource_node_id,
		"last_resource_hit_tick":      last_resource_hit_tick,
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
	deposit_lock_active   = bool(data.get("wb_deposit_lock_active", false))
	var rwp = data.get("wb_res_watch_pos", Vector2.ZERO)
	_resource_watch_pos    = rwp if rwp is Vector2 else Vector2.ZERO
	_resource_watch_timer  = float(data.get("wb_res_watch_timer",  0.0))
	_resource_orbit_radius = float(data.get("wb_orbit_radius",     38.0))
	_resource_orbit_angle  = float(data.get("wb_orbit_angle",      0.0))
	_resource_orbit_dir    = float(data.get("wb_orbit_dir",        1.0))
	_resource_orbit_step   = float(data.get("wb_orbit_step",       0.6))
	_loot_target_id    = 0
	pending_collect_id = 0
	_cargo_manifest    = []
	# instance IDs are invalid after reload — reset to 0
	pending_mine_id   = int(data.get("pending_mine_id",  0))
	_resource_node_id = int(data.get("resource_node_id", 0))
	last_valid_resource_node_id = int(data.get("last_valid_resource_node_id", _resource_node_id))
	last_resource_hit_tick = int(data.get("last_resource_hit_tick", 0))
	if data.has("wb_rng_state"):
		var rs: int = int(str(data.get("wb_rng_state", "0")))
		if rs != 0:
			_rng.state = rs
