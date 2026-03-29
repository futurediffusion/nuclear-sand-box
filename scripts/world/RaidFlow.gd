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
				elif raid_type == "wall_probe":
					_tick_wall_probe_assault(job, gid)
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

## Full raid (nivel 10): destrucción total — divide el grupo entre el muro más
## cercano y el placeable más cercano simultáneamente. A medida que los objetivos
## se destruyen, find_wall/find_storage/find_workbench retornan el siguiente,
## garantizando que el raid barre toda la base antes de retirarse.
func _tick_wall_assault(job: Dictionary, gid: String) -> void:
	if not _find_wall.is_valid():
		return
	if RunClock.now() < float(job.get("wall_assault_next_at", 0.0)):
		return

	var faction_id: String = String(job.get("faction_id", ""))
	if faction_id != "":
		var profile: FactionBehaviorProfile = FactionHostilityManager.get_behavior_profile(faction_id)
		if not profile.can_damage_walls:
			return

	var base_center: Vector2 = job.get("base_center", Vector2.ZERO) as Vector2
	var wall_pos: Vector2    = _find_wall.call(base_center, WALL_SEARCH_RADIUS) as Vector2

	# Buscar también el placeable más cercano (storage > workbench)
	var placeable_pos: Vector2 = Vector2(-1.0, -1.0)
	if _find_storage.is_valid():
		placeable_pos = _find_storage.call(base_center, PLACEABLE_SEARCH_RADIUS) as Vector2
	if placeable_pos.x < 0.0 and _find_workbench.is_valid():
		placeable_pos = _find_workbench.call(base_center, PLACEABLE_SEARCH_RADIUS) as Vector2

	if wall_pos.x < 0.0 and placeable_pos.x < 0.0:
		return

	var g: Dictionary     = BanditGroupMemory.get_group(gid)
	var member_ids: Array = g.get("member_ids", [])
	var redirected: int   = 0

	if wall_pos.x >= 0.0 and placeable_pos.x >= 0.0:
		# Ambos disponibles: mitad superior del grupo a pared, mitad inferior a placeable
		var half: int = maxi(1, member_ids.size() / 2)
		for i in member_ids.size():
			var node = _npc_simulator.get_enemy_node(String(member_ids[i])) if _npc_simulator != null else null
			if node == null:
				continue
			var bwb = node.get_node_or_null("WorldBehavior")
			if bwb == null or not bwb.has_method("enter_wall_assault"):
				continue
			bwb.call("enter_wall_assault", wall_pos if i < half else placeable_pos)
			redirected += 1
	else:
		# Solo un tipo de objetivo — todos van ahí
		var sole_target: Vector2 = wall_pos if wall_pos.x >= 0.0 else placeable_pos
		for mid in member_ids:
			var node = _npc_simulator.get_enemy_node(String(mid)) if _npc_simulator != null else null
			if node == null:
				continue
			var bwb = node.get_node_or_null("WorldBehavior")
			if bwb == null or not bwb.has_method("enter_wall_assault"):
				continue
			bwb.call("enter_wall_assault", sole_target)
			redirected += 1

	job["wall_assault_next_at"] = RunClock.now() + WALL_ASSAULT_INTERVAL
	if redirected > 0:
		Debug.log("raid", "[RF] full assault — group=%s wall=%s placeable=%s redirected=%d" % [
			gid, str(wall_pos), str(placeable_pos), redirected])


# ---------------------------------------------------------------------------
# Stage: ATTACKING — timer
# ---------------------------------------------------------------------------

func _tick_attacking(job: Dictionary, gid: String) -> bool:
	var attack_elapsed: float = RunClock.now() - float(job.get("attack_started_at", RunClock.now()))
	var total_elapsed: float  = RunClock.now() - float(job.get("started_at", RunClock.now()))
	var max_attack: float
	var max_total: float
	match String(job.get("raid_type", "full")):
		"light":
			max_attack = LIGHT_ATTACK_DURATION
			max_total  = LIGHT_MAX_DURATION
		"wall_probe":
			max_attack = BanditTuning.wall_probe_attack_duration()
			max_total  = BanditTuning.wall_probe_max_duration()
		_:
			max_attack = ATTACK_DURATION
			max_total  = MAX_RAID_DURATION
	if attack_elapsed >= max_attack or total_elapsed >= max_total:
		Debug.log("raid", "[RF] attack phase done — group=%s attack_t=%.0f total_t=%.0f type=%s" % [
			gid, attack_elapsed, total_elapsed, job.get("raid_type", "full")])
		return true
	return false


## Raid leve (niveles 7-9): placeables del jugador + paredes con probabilidad
## creciente por nivel. lv7=25% pared, lv8=45%, lv9=65%.
## Todos los miembros se redirigen al objetivo elegido en cada tick.
func _tick_placeable_assault(job: Dictionary, gid: String) -> void:
	if RunClock.now() < float(job.get("wall_assault_next_at", 0.0)):
		return

	var base_center: Vector2 = job.get("base_center", Vector2.ZERO) as Vector2
	var faction_id: String   = String(job.get("faction_id", ""))

	var profile: FactionBehaviorProfile = FactionHostilityManager.get_behavior_profile(faction_id)
	if not profile.can_damage_workbenches:
		return

	# Probabilidad de atacar pared en lugar de placeable: escala con nivel
	# lv7 → 25%, lv8 → 45%, lv9 → 65%
	var wall_chance: float = clampf((profile.hostility_level - 6) * 0.20 + 0.05, 0.0, 1.0)
	var target_pos: Vector2 = Vector2(-1.0, -1.0)

	if _find_wall.is_valid() and randf() < wall_chance:
		target_pos = _find_wall.call(base_center, WALL_SEARCH_RADIUS) as Vector2

	# Si no tocó el roll de pared (o no hay muros), busca placeable
	if target_pos.x < 0.0:
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
		Debug.log("raid", "[RF] mixed assault lv%d — group=%s target=%s wall_chance=%.0f%% redirected=%d" % [
			profile.hostility_level, gid, str(target_pos), wall_chance * 100.0, redirected])


# ---------------------------------------------------------------------------
# Stage: ATTACKING — wall probe (niveles 1-6)
# ---------------------------------------------------------------------------

## Probe de pared: redirige SOLO probe_squad_size miembros hacia el muro más
## cercano al base_center. El resto del grupo no es enviado a golpear.
## La IA normal (slash.gd) inflige el daño al contacto con la geometría.
func _tick_wall_probe_assault(job: Dictionary, gid: String) -> void:
	if not _find_wall.is_valid():
		return
	if RunClock.now() < float(job.get("wall_assault_next_at", 0.0)):
		return

	var base_center: Vector2 = job.get("base_center", Vector2.ZERO) as Vector2
	var wall_pos: Vector2    = _find_wall.call(base_center, WALL_SEARCH_RADIUS) as Vector2
	if wall_pos.x < 0.0:
		return

	var squad_size: int   = int(job.get("probe_squad_size", 1))
	var g: Dictionary     = BanditGroupMemory.get_group(gid)
	var member_ids: Array = g.get("member_ids", [])
	var redirected: int   = 0
	for mid in member_ids:
		if redirected >= squad_size:
			break
		var node = _npc_simulator.get_enemy_node(String(mid)) if _npc_simulator != null else null
		if node == null:
			continue
		var bwb = node.get_node_or_null("WorldBehavior")
		if bwb == null or not bwb.has_method("enter_wall_assault"):
			continue
		bwb.call("enter_wall_assault", wall_pos)
		redirected += 1

	job["wall_assault_next_at"] = RunClock.now() + BanditTuning.wall_probe_wall_interval()
	if redirected > 0:
		Debug.log("raid", "[RF] wall probe assault — group=%s wall=%s redirected=%d/%d" % [
			gid, str(wall_pos), redirected, squad_size])


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
	var job: Dictionary = _active_jobs[gid] as Dictionary
	_active_jobs.erase(gid)
	var social_cd: float
	match String(job.get("raid_type", "full")):
		"full":       social_cd = 18.0
		"light":      social_cd = 10.0
		"wall_probe": social_cd = 6.0
		_:            social_cd = 10.0
	BanditGroupMemory.push_social_cooldown(gid, social_cd)
	BanditGroupMemory.update_intent(gid, "idle")
	var faction_id: String = String(job.get("faction_id", ""))
	if faction_id != "":
		FactionHostilityManager.add_hostility(faction_id, 0.0, "raid_executed", {"group_id": gid, "entity_id": gid + ":raid"})
	Debug.log("raid", "[RF] raid finished — group=%s reason=%s" % [gid, reason])


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _has_active_job(gid: String) -> bool:
	return _active_jobs.has(gid)
