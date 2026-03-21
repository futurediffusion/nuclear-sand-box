class_name RaidFlow
extends Node

# ── RaidFlow ──────────────────────────────────────────────────────────────────
# Orquestador del ciclo de vida de un raid a la base del jugador.
# Paralelo a ExtortionFlow pero para la capacidad can_raid_base (nivel 10).
#
# Stages per job:
#   approaching  — grupo converge en base_center via APPROACH_INTEREST
#   attacking    — grupo ha llegado; IA normal maneja combate + wall assault
#   (done)       — timer agotado → intent → "idle" → grupo vuelve a casa
#
# Wall assault (can_damage_walls):
#   Cada WALL_ASSAULT_INTERVAL segundos en phase ATTACKING, RaidFlow busca el
#   muro del jugador más cercano al base_center y reorienta a los raiders hacia
#   él. La IA normal (slash.gd) inflige el daño al contacto.
#
# Anti-spam:
#   • Solo un job activo por grupo a la vez.
#   • RaidQueue.has_pending_for_group() + intent == "raiding" evitan reencolas.

const ATTACK_RADIUS:       float = 450.0  # px — distancia al líder que activa ATTACKING
const APPROACH_TIMEOUT:    float = 90.0   # s  — máximo en APPROACHING antes de forzar ATTACKING
const ATTACK_DURATION:     float = 60.0   # s  — duración del phase ATTACKING
const MAX_RAID_DURATION:   float = 150.0  # s  — abort total
const WALL_ASSAULT_INTERVAL: float = 6.0 # s  — cada cuánto redirige raiders al muro más cercano
const WALL_SEARCH_RADIUS:  float = 600.0  # px — radio de búsqueda de muros alrededor del base_center

const LIGHT_ATTACK_DURATION: float = 30.0  # s — duración del phase ATTACKING en light raid
const LIGHT_MAX_DURATION:    float = 75.0  # s — abort total para light raid
const PLACEABLE_SEARCH_RADIUS: float = 700.0  # px — radio de búsqueda de placeables

var _npc_simulator:   NpcSimulator = null
var _find_wall:       Callable     = Callable()  # world.find_nearest_player_wall_world_pos
var _find_workbench:  Callable     = Callable()  # world.find_nearest_player_workbench_world_pos
var _find_storage:    Callable     = Callable()  # world.find_nearest_player_storage_world_pos

var _active_jobs: Dictionary = {}  # group_id → job dict


func setup(ctx: Dictionary) -> void:
	_npc_simulator = ctx.get("npc_simulator")
	set_process(false)  # Se tickea desde BanditRaidDirector.process_raid()


func set_wall_query(cb: Callable) -> void:
	_find_wall = cb

func set_workbench_query(cb: Callable) -> void:
	_find_workbench = cb

func set_storage_query(cb: Callable) -> void:
	_find_storage = cb


# ---------------------------------------------------------------------------
# Main entry point — llamado cada frame desde BanditRaidDirector
# ---------------------------------------------------------------------------

func process_flow() -> void:
	_abort_invalid_jobs()
	_consume_raid_queue()
	_tick_jobs()


# ---------------------------------------------------------------------------
# Queue consumption
# ---------------------------------------------------------------------------

func _consume_raid_queue() -> void:
	for gid in BanditGroupMemory.get_all_group_ids():
		if _has_active_job(gid):
			continue
		var g: Dictionary = BanditGroupMemory.get_group(gid)
		if String(g.get("current_group_intent", "")) != "raiding":
			continue
		var intents: Array = RaidQueue.consume_for_group(gid)
		if intents.is_empty():
			continue
		_create_job(gid, intents[0] as Dictionary)


func _create_job(gid: String, intent: Dictionary) -> void:
	_active_jobs[gid] = {
		"group_id":              gid,
		"faction_id":            String(intent.get("faction_id", "")),
		"leader_id":             String(intent.get("leader_id", "")),
		"base_center":           intent.get("base_center", Vector2.ZERO) as Vector2,
		"raid_type":             String(intent.get("raid_type", "full")),
		"stage":                 "approaching",
		"started_at":            RunClock.now(),
		"attack_started_at":     0.0,
		"wall_assault_next_at":  0.0,
	}
	Debug.log("raid", "[RF] job created — group=%s base=%s type=%s" % [
		gid, str(intent.get("base_center")), intent.get("raid_type", "full")])


# ---------------------------------------------------------------------------
# Per-frame job ticks
# ---------------------------------------------------------------------------

func _tick_jobs() -> void:
	var done_ids: Array[String] = []
	for gid in _active_jobs.keys():
		var job: Dictionary = _active_jobs[gid] as Dictionary
		var raid_type: String = String(job.get("raid_type", "full"))
		match String(job.get("stage", "")):
			"approaching":
				if _tick_approaching(job, gid):
					done_ids.append(gid)
			"attacking":
				if raid_type == "light":
					_tick_placeable_assault(job, gid)
				else:
					_tick_wall_assault(job, gid)
				if _tick_attacking(job, gid):
					done_ids.append(gid)
	for gid in done_ids:
		_finish_raid(gid, "retreat")


# ---------------------------------------------------------------------------
# Stage: APPROACHING
# ---------------------------------------------------------------------------

func _tick_approaching(job: Dictionary, gid: String) -> bool:
	var total: float = RunClock.now() - float(job.get("started_at", RunClock.now()))
	if total >= MAX_RAID_DURATION:
		return true

	var base_center: Vector2 = job.get("base_center", Vector2.ZERO) as Vector2
	var leader_id: String    = String(job.get("leader_id", ""))
	var close_enough: bool   = false

	if leader_id != "" and _npc_simulator != null:
		var leader_node = _npc_simulator.get_enemy_node(leader_id)
		if leader_node != null:
			close_enough = (leader_node as Node2D).global_position.distance_to(base_center) <= ATTACK_RADIUS

	var timed_out: bool = total >= APPROACH_TIMEOUT
	if close_enough or timed_out:
		job["stage"]             = "attacking"
		job["attack_started_at"] = RunClock.now()
		# Primera asignación de muro inmediata al entrar en ATTACKING
		job["wall_assault_next_at"] = RunClock.now()
		Debug.log("raid", "[RF] stage → attacking — group=%s close=%s timeout=%s" % [
			gid, str(close_enough), str(timed_out)])
	return false


# ---------------------------------------------------------------------------
# Stage: ATTACKING — wall assault deliberado
# ---------------------------------------------------------------------------

## Cada WALL_ASSAULT_INTERVAL segundos, busca el muro más cercano al base_center
## y redirige a TODOS los miembros del grupo hacia él via APPROACH_INTEREST.
## La IA normal (slash.gd) inflige el daño al contacto con la geometría del muro.
func _tick_wall_assault(job: Dictionary, gid: String) -> void:
	if not _find_wall.is_valid():
		return
	if RunClock.now() < float(job.get("wall_assault_next_at", 0.0)):
		return

	var base_center: Vector2 = job.get("base_center", Vector2.ZERO) as Vector2
	var wall_pos: Vector2    = _find_wall.call(base_center, WALL_SEARCH_RADIUS) as Vector2

	if wall_pos.x < 0.0:
		# No hay muro en rango — nada que hacer
		return

	# Verificar que el grupo puede dañar muros (can_damage_walls = nivel 9+)
	var faction_id: String = String(job.get("faction_id", ""))
	if faction_id != "":
		var profile: FactionBehaviorProfile = FactionHostilityManager.get_behavior_profile(faction_id)
		if not profile.can_damage_walls:
			return

	# Redirigir a todos los miembros activos del grupo hacia el muro
	var g: Dictionary = BanditGroupMemory.get_group(gid)
	var member_ids: Array = g.get("member_ids", [])
	var redirected: int = 0
	for mid in member_ids:
		var node = _npc_simulator.get_enemy_node(String(mid)) if _npc_simulator != null else null
		if node == null:
			continue
		var bwb = node.get_node_or_null("WorldBehavior")
		if bwb == null:
			continue
		if bwb.has_method("enter_wall_assault"):
			bwb.call("enter_wall_assault", wall_pos)
			redirected += 1

	job["wall_assault_next_at"] = RunClock.now() + WALL_ASSAULT_INTERVAL
	if redirected > 0:
		Debug.log("raid", "[RF] wall assault — group=%s wall=%s redirected=%d" % [
			gid, str(wall_pos), redirected])


# ---------------------------------------------------------------------------
# Stage: ATTACKING — timer
# ---------------------------------------------------------------------------

func _tick_attacking(job: Dictionary, gid: String) -> bool:
	var attack_elapsed: float = RunClock.now() - float(job.get("attack_started_at", RunClock.now()))
	var total_elapsed: float  = RunClock.now() - float(job.get("started_at", RunClock.now()))
	var is_light: bool = String(job.get("raid_type", "full")) == "light"
	var max_attack: float = LIGHT_ATTACK_DURATION if is_light else ATTACK_DURATION
	var max_total: float  = LIGHT_MAX_DURATION    if is_light else MAX_RAID_DURATION
	if attack_elapsed >= max_attack or total_elapsed >= max_total:
		Debug.log("raid", "[RF] attack phase done — group=%s attack_t=%.0f total_t=%.0f type=%s" % [
			gid, attack_elapsed, total_elapsed, job.get("raid_type", "full")])
		return true
	return false


## Raid leve (niveles 7-9): redirige a todos los miembros hacia el workbench o
## storage más cercano al base_center. La IA normal (slash.gd) inflige el daño.
func _tick_placeable_assault(job: Dictionary, gid: String) -> void:
	if RunClock.now() < float(job.get("wall_assault_next_at", 0.0)):
		return

	var base_center: Vector2 = job.get("base_center", Vector2.ZERO) as Vector2
	var faction_id: String   = String(job.get("faction_id", ""))

	# Verificar capacidades de la facción
	var profile: FactionBehaviorProfile = FactionHostilityManager.get_behavior_profile(faction_id)
	if not profile.can_damage_workbenches:
		return

	# Priorizar storage sobre workbench si el nivel lo permite (can_damage_storage = nivel 8+)
	var target_pos: Vector2 = Vector2(-1.0, -1.0)
	if profile.can_damage_storage and _find_storage.is_valid():
		target_pos = _find_storage.call(base_center, PLACEABLE_SEARCH_RADIUS) as Vector2
	if target_pos.x < 0.0 and _find_workbench.is_valid():
		target_pos = _find_workbench.call(base_center, PLACEABLE_SEARCH_RADIUS) as Vector2

	if target_pos.x < 0.0:
		return

	var g: Dictionary = BanditGroupMemory.get_group(gid)
	var member_ids: Array = g.get("member_ids", [])
	var redirected: int = 0
	for mid in member_ids:
		var node = _npc_simulator.get_enemy_node(String(mid)) if _npc_simulator != null else null
		if node == null:
			continue
		var bwb = node.get_node_or_null("WorldBehavior")
		if bwb == null:
			continue
		if bwb.has_method("enter_wall_assault"):
			bwb.call("enter_wall_assault", target_pos)
			redirected += 1

	job["wall_assault_next_at"] = RunClock.now() + WALL_ASSAULT_INTERVAL
	if redirected > 0:
		Debug.log("raid", "[RF] placeable assault — group=%s target=%s redirected=%d" % [
			gid, str(target_pos), redirected])


# ---------------------------------------------------------------------------
# Abort
# ---------------------------------------------------------------------------

func _abort_invalid_jobs() -> void:
	var abort_ids: Array[String] = []
	for gid in _active_jobs.keys():
		var job: Dictionary = _active_jobs[gid] as Dictionary
		var total: float = RunClock.now() - float(job.get("started_at", RunClock.now()))
		if total >= MAX_RAID_DURATION:
			abort_ids.append(gid)
			continue
		var g: Dictionary = BanditGroupMemory.get_group(gid)
		if g.is_empty():
			abort_ids.append(gid)
			continue
		var leader_id: String = String(g.get("leader_id", ""))
		if leader_id == "":
			abort_ids.append(gid)
			continue
		if _npc_simulator != null and _npc_simulator.get_enemy_node(leader_id) == null:
			abort_ids.append(gid)
	for gid in abort_ids:
		_finish_raid(gid, "abort")


# ---------------------------------------------------------------------------
# Finish
# ---------------------------------------------------------------------------

func _finish_raid(gid: String, reason: String) -> void:
	if not _active_jobs.has(gid):
		return
	_active_jobs.erase(gid)
	BanditGroupMemory.update_intent(gid, "idle")
	Debug.log("raid", "[RF] raid finished — group=%s reason=%s" % [gid, reason])


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _has_active_job(gid: String) -> bool:
	return _active_jobs.has(gid)
