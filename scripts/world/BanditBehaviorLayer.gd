extends Node
class_name BanditBehaviorLayer

# ── BanditBehaviorLayer ──────────────────────────────────────────────────────
# Responsibility boundary:
# BanditBehaviorLayer owns runtime coordination for active bandit NPC nodes:
# behavior ticking, movement application, carrying, stash interaction, and the
# hand-off between world-layer systems. Social scanning/policy stays outside
# here; this layer consumes group intent instead of deciding faction politics.
#
# Every TICK_INTERVAL seconds:
#   1. Lazily creates behaviors for new sleeping bandits (group_id required).
#   2. Ensures camp barrels exist (delegates to BanditCampStashSystem).
#   3. Builds a ctx dict with nearby drops / resources for each enemy.
#   4. Ticks each behavior.
#   5. Handles pending_collect_id, mining, cargo deposit (via BanditCampStashSystem).
#   6. Prunes behaviors for enemies that have despawned.
#
# Every physics frame:
#   Applies desired_velocity (+ friction compensation) to sleeping non-lite enemies.
#
# Carry preference: NPCs carry drops to base (cargo_count) rather than
# putting them in inventory. Inventory is not touched here.
#
# Future tavern note:
# local civil reactions (keeper, guards, sanctions, memory) must stay outside
# this runtime layer. NPC actors may consume those directives later, but this
# node should keep orchestrating active bandit runtime only.

const BanditTuningScript            := preload("res://scripts/world/BanditTuning.gd")
const BanditGroupIntelScript        := preload("res://scripts/world/BanditGroupIntel.gd")
const BanditExtortionDirectorScript := preload("res://scripts/world/BanditExtortionDirector.gd")
const BanditRaidDirectorScript      := preload("res://scripts/world/BanditRaidDirector.gd")
const BanditCampStashSystemScript   := preload("res://scripts/world/BanditCampStashSystem.gd")
const BanditTerritoryResponseScript := preload("res://scripts/world/BanditTerritoryResponse.gd")
const BanditWorkCoordinatorScript   := preload("res://scripts/world/BanditWorkCoordinator.gd")

# ---------------------------------------------------------------------------
# Camp layout constants — local geometry, not cross-system gameplay tuning.
# These control how NPCs distribute themselves around the barrel; a designer
# would tune pickup radii / speeds in BanditTuning, not these.
# ---------------------------------------------------------------------------
const DEPOSIT_SLOT_COUNT:        int   = 36      # posiciones angulares alrededor del barril
const DEPOSIT_SLOT_RADIUS_MIN:   float = 32.0    # px mínimo desde el centro del barril
const DEPOSIT_SLOT_RADIUS_RANGE: int   = 20      # varianza adicional (hash % N)
const DEPOSIT_REASSIGN_GUARD_SQ: float = 72.0 * 72.0  # no reasignar si ya está cerca

const DEBUG_ALERTED_CHASE: bool = true

# ---------------------------------------------------------------------------
# Frases de reconocimiento — cuando la banda te tiene fichado y te ve venir
# ---------------------------------------------------------------------------
## Clave = nivel mínimo de hostilidad. Se usa el mayor nivel que no supere el actual.
const RECOGNITION_PHRASES: Dictionary = {
	3: [
		"Sigues apareciendo por aquí...",
		"Otro día. Otro problema.",
		"No aprendes, ¿verdad?",
		"Vaya. Tú de nuevo.",
		"Qué puntual. Como siempre.",
	],
	5: [
		"Ya sé quién eres. Y lo que has hecho.",
		"Te tenemos en la lista. Lleva tiempo.",
		"No te hagas el desconocido. Nos acordamos.",
		"Sabes perfectamente que no eres bienvenido aquí.",
		"De todos los sitios. Tienes que aparecer aquí.",
	],
	7: [
		"Precisamente tú. Qué mala suerte la tuya.",
		"Mal momento para aparecer. O quizá el peor.",
		"No te iba a pasar nada. Hasta que apareciste.",
		"Hoy me alegra verte. Por primera vez.",
		"Llevas tiempo mereciéndote esto.",
	],
	9: [
		"Buscábamos una excusa. Gracias por darnos una.",
		"No sé si eres valiente o estúpido. Hoy da igual.",
		"Ya no hay negociación. Solo cuentas que saldar.",
		"Querían que apareciera alguien como tú. Y aquí estás.",
		"Esta vez no hay opción de pagar.",
	],
}

## Distancia máxima (px²) al jugador para que se dispare el reconocimiento.
const RECOGNITION_RANGE_SQ: float = 350.0 * 350.0
## Cooldown mínimo (s) entre burbujas de reconocimiento por NPC.
const RECOGNITION_COOLDOWN: float = 45.0

# ---------------------------------------------------------------------------
# Diálogo ambiental — frases de mundo mientras el NPC está ocioso o patrullando
# ---------------------------------------------------------------------------
const IDLE_CHAT_PHRASES: Array[String] = [
	# Aburrimiento de guardia
	"Otro día más vigilando piedras.",
	"¿Cuántas veces he dado esta vuelta? No sé. Muchas.",
	"El jefe dijo 'vigilancia discreta'. Llevamos aquí tres días.",
	"Nadie me dijo que este trabajo iba a ser tan aburrido.",
	"¿Cuánto falta para que me releven? Demasiado. Siempre demasiado.",
	"Si alguien me pregunta qué hora es, le cobro.",
	# Reflexiones sobre el oficio
	"Buena zona. Mala paga.",
	"Si aparece alguien, cobro. Si no aparece nadie, cobro igual. No está mal.",
	"Mi madre quería que fuera carpintero. No sé por qué no la escuché.",
	"El último que intentó pasar sin pagar... bueno. Al menos ya no tiene ese problema.",
	"Dicen que hay gente que trabaja en oficinas. Qué raro debe ser eso.",
	"Algún día me jubilo. Me compro una cabaña. Lejos de todo esto.",
	"Llevo años en esto y todavía me sorprende la gente que dice que no.",
	"El jefe habla mucho de 'expansión territorial'. Nosotros caminamos.",
	# Territorio y orgullo
	"Por aquí no pasa nadie sin que yo me entere. Nadie.",
	"Buena visibilidad hoy. Cosa rara.",
	"Esta zona es nuestra. Ha sido nuestra siempre. Lo seguirá siendo.",
	"A veces me pregunto quién estaba aquí antes que nosotros. Y luego me dejo de preguntar.",
	# Observaciones random
	"Me duelen los pies. A nadie más le duelen los pies. Solo a mí.",
	"Hace frío. O calor. Siempre algo.",
	"¿Comemos hoy? Mejor que ayer, espero.",
	"Me prometieron que esto iba a ser temporal. Eso fue hace cuatro años.",
	"Tengo una teoría sobre por qué la gente siempre lleva menos dinero del que parece.",
	"Si me dieran un perro por cada idiota que he visto pasar... tendría muchos perros.",
	"El suelo de aquí es más cómodo que el del campamento. Eso dice algo.",
	# Humor seco / oscuro
	"A veces los trabajo bonitos no son tan bonitos. Este sí que no lo es.",
	"Lo bueno de este trabajo: si alguien te fastidia, le fastidias tú a él.",
	"Hay días que no pasa nadie. Hay días que pasan demasiados. Hoy todavía no sé.",
	"Zona tranquila. Eso o nadie quiere pasar. Ambas opciones me vienen bien.",
	"Que no se me olvide: cobrar primero, preguntar después.",
	"Dicen que los bandidos no tenemos honor. Los que lo dicen nunca han visto cómo nos pagamos los unos a los otros.",
	"He visto gente que miraba mal y acabó mirando al suelo. Así funciona.",
	"A este paso, me voy a conocer cada piedra de aquí de nombre.",
	"Alguno cree que si corre más rápido no le alcanzamos. Se equivoca siempre.",
]

## Cooldown entre frases idle (segundos). Se añade variación aleatoria por NPC.
const IDLE_CHAT_COOLDOWN_MIN: float = 90.0
const IDLE_CHAT_COOLDOWN_MAX: float = 200.0
## Distancia mínima al jugador para soltar frases ambientales (que no suene a reacción).
const IDLE_CHAT_PLAYER_DIST_MIN_SQ: float = 280.0 * 280.0

var _npc_simulator:  NpcSimulator             = null
var _group_intel:    BanditGroupIntel         = null
var _player:         Node2D                   = null
var _bubble_manager: WorldSpeechBubbleManager = null

var _behaviors: Dictionary = {}   # enemy_id (String) -> BanditWorldBehavior
var _tick_timer: float     = 0.0

var _extortion_director: BanditExtortionDirector = null
var _raid_director:      BanditRaidDirector      = null
var _stash:              BanditCampStashSystem   = null
var _territory_response: BanditTerritoryResponse = null
var _work_coordinator:   BanditWorkCoordinator   = null
var _find_wall_cb:       Callable                = Callable()
var _find_workbench_cb:  Callable                = Callable()
var _find_storage_cb:    Callable                = Callable()

# Cached world-level lists (rebuilt once per tick, shared across all enemies)
var _all_drops_cache:     Array = []
var _all_resources_cache: Array = []


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

func setup(ctx: Dictionary) -> void:
	_npc_simulator  = ctx.get("npc_simulator")
	_player         = ctx.get("player")
	_bubble_manager = ctx.get("speech_bubble_manager")

	# Extortion director
	if _extortion_director != null and is_instance_valid(_extortion_director):
		_extortion_director.queue_free()
	_extortion_director = BanditExtortionDirectorScript.new()
	add_child(_extortion_director)
	_extortion_director.setup({
		"npc_simulator":         _npc_simulator,
		"player":                _player,
		"speech_bubble_manager": _bubble_manager,
		"get_behavior_for_enemy": Callable(self, "_get_behavior"),
	})

	# Raid director
	if _raid_director != null and is_instance_valid(_raid_director):
		_raid_director.queue_free()
	_raid_director = BanditRaidDirectorScript.new() as BanditRaidDirector
	_raid_director.name = "BanditRaidDirector"
	add_child(_raid_director)
	_raid_director.setup({
		"npc_simulator": _npc_simulator,
	})

	if _territory_response == null:
		_territory_response = BanditTerritoryResponseScript.new()
	_territory_response.setup({
		"npc_simulator": _npc_simulator,
		"speech_bubble_manager": _bubble_manager,
	})

	# Camp stash system
	if _stash != null and is_instance_valid(_stash):
		_stash.queue_free()
	_stash = BanditCampStashSystemScript.new() as BanditCampStashSystem
	_stash.name = "BanditCampStashSystem"
	add_child(_stash)
	_stash.setup({
		"update_deposit_pos_cb": Callable(self, "_update_deposit_pos"),
	})

	if _work_coordinator != null and is_instance_valid(_work_coordinator):
		_work_coordinator.queue_free()
	_work_coordinator = BanditWorkCoordinatorScript.new() as BanditWorkCoordinator
	_work_coordinator.name = "BanditWorkCoordinator"
	add_child(_work_coordinator)
	_work_coordinator.setup({
		"stash": _stash,
	})


## Called from world.gd after SettlementIntel is ready.
func setup_group_intel(ctx: Dictionary) -> void:
	_group_intel = BanditGroupIntelScript.new()
	_group_intel.setup({
		"npc_simulator":             _npc_simulator,
		"get_interest_markers_near": ctx.get("get_interest_markers_near", Callable()),
		"get_detected_bases_near":   ctx.get("get_detected_bases_near",   Callable()),
	})

	# Guardar query callables — se pasan al RaidDirector y también al ctx de cada tick
	var wall_cb: Callable = ctx.get("find_nearest_player_wall_world_pos", Callable())
	_find_wall_cb = wall_cb
	if _raid_director != null and wall_cb.is_valid():
		_raid_director.set_wall_query(wall_cb)
	_find_workbench_cb = ctx.get("find_nearest_player_workbench_world_pos", Callable())
	_find_storage_cb   = ctx.get("find_nearest_player_storage_world_pos",   Callable())
	if _raid_director != null:
		if _find_workbench_cb.is_valid():
			_raid_director.set_workbench_query(_find_workbench_cb)
		if _find_storage_cb.is_valid():
			_raid_director.set_storage_query(_find_storage_cb)


# ---------------------------------------------------------------------------
# Physics frame — apply velocity to sleeping, non-lite enemies
# ---------------------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	if _npc_simulator == null:
		return

	# Pass 1: apply desired velocities + collect per-group node positions
	var group_nodes: Dictionary = {}
	for enemy_id in _behaviors:
		var behavior: BanditWorldBehavior = _behaviors[enemy_id]
		var node = _npc_simulator.get_enemy_node(enemy_id)
		if node == null or not node.has_method("is_world_behavior_eligible") \
				or not node.is_world_behavior_eligible():
			continue
		var vel: Vector2 = behavior.get_desired_velocity()
		if vel.length_squared() > 0.01:
			node.velocity = vel.normalized() * (vel.length() + BanditTuningScript.friction_compensation())
		if behavior.group_id != "":
			if not group_nodes.has(behavior.group_id):
				group_nodes[behavior.group_id] = []
			group_nodes[behavior.group_id].append({"node": node, "pos": node.global_position})

	# Pass 2: ally separation
	for gid in group_nodes:
		var members: Array = group_nodes[gid]
		if members.size() < 2:
			continue
		for i in members.size():
			var a: Dictionary = members[i]
			var sep: Vector2 = Vector2.ZERO
			for j in members.size():
				if i == j:
					continue
				var diff: Vector2 = (a["pos"] as Vector2) - (members[j]["pos"] as Vector2)
				var d: float = diff.length()
				if d < BanditTuningScript.ally_sep_radius() and d > 0.5:
					sep += diff.normalized() * (BanditTuningScript.ally_sep_radius() - d) \
						/ BanditTuningScript.ally_sep_radius() * BanditTuningScript.ally_sep_force()
			if sep.length_squared() > 0.01:
				a["node"].velocity += sep

	if _extortion_director != null:
		_extortion_director.apply_extortion_movement(BanditTuningScript.friction_compensation())

	# Debug: alerted scout sigue al player
	if DEBUG_ALERTED_CHASE and _player != null and is_instance_valid(_player):
		var ap: Vector2 = _player.global_position
		for gid in BanditGroupMemory.get_all_group_ids():
			var g: Dictionary = BanditGroupMemory.get_group(gid)
			if String(g.get("current_group_intent", "")) != "alerted":
				continue
			var scout_id: String = BanditGroupMemory.get_scout(gid)
			if scout_id == "":
				continue
			var snode = _npc_simulator.get_enemy_node(scout_id)
			if snode == null or not snode.has_method("is_world_behavior_eligible") \
					or not snode.is_world_behavior_eligible():
				continue
			var to_p: Vector2 = ap - snode.global_position
			if to_p.length() > 1.0:
				snode.velocity = to_p.normalized() * (
					BanditTuningScript.alerted_scout_chase_speed(gid) + BanditTuningScript.friction_compensation()
				)


# ---------------------------------------------------------------------------
# Process tick — behavior maintenance
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _npc_simulator == null:
		return
	if _group_intel != null:
		_group_intel.tick(delta)
	if _extortion_director != null:
		_extortion_director.process_extortion()
	if _raid_director != null:
		_raid_director.process_raid()
	_tick_timer += delta
	if _tick_timer < BanditTuningScript.behavior_tick_interval():
		return
	_tick_timer = 0.0

	_refresh_world_caches()
	_ensure_behaviors_for_active_enemies()
	_stash.ensure_barrels()
	_tick_behaviors()
	_prune_behaviors()


# ---------------------------------------------------------------------------
# World caches (rebuilt once per tick)
# ---------------------------------------------------------------------------

func _refresh_world_caches() -> void:
	_all_drops_cache     = get_tree().get_nodes_in_group("item_drop")
	_all_resources_cache = get_tree().get_nodes_in_group("world_resource")


# ---------------------------------------------------------------------------
# Behavior tick
# ---------------------------------------------------------------------------

func _tick_behaviors() -> void:
	var leader_pos_by_group: Dictionary = {}
	for enemy_id in _behaviors:
		var beh: BanditWorldBehavior = _behaviors[enemy_id]
		if beh.role != "leader" or beh.group_id == "":
			continue
		var node = _npc_simulator.get_enemy_node(enemy_id)
		if node != null:
			leader_pos_by_group[beh.group_id] = node.global_position

	for enemy_id in _behaviors:
		var beh: BanditWorldBehavior = _behaviors[enemy_id]
		var node = _npc_simulator.get_enemy_node(enemy_id)
		if node == null or not node.has_method("is_world_behavior_eligible") \
				or not node.is_world_behavior_eligible():
			if _work_coordinator != null:
				_work_coordinator.process_post_behavior(beh, node, _all_drops_cache)
			continue

		var node_pos: Vector2 = node.global_position
		var ctx: Dictionary = {
			"node_pos":                       node_pos,
			"nearby_drops_info":              _build_drops_info(node_pos),
			"nearby_res_info":                _build_res_info(node_pos),
			"find_nearest_player_wall":       _find_wall_cb,
			"find_nearest_player_workbench":  _find_workbench_cb,
			"find_nearest_player_storage":    _find_storage_cb,
		}
		if beh.group_id != "":
			ctx["leader_pos"] = leader_pos_by_group.get(beh.group_id, beh.home_pos)

		beh.tick(BanditTuningScript.behavior_tick_interval(), ctx)
		_maybe_show_recognition_bubble(beh, node, node_pos)
		_maybe_show_idle_chat(beh, node, node_pos)

		# Sync save-state: cargo y behavior para continuidad data-only
		var save_state_ref: Dictionary = _get_save_state_for(enemy_id)
		if not save_state_ref.is_empty():
			save_state_ref["cargo_count"]    = beh.cargo_count
			save_state_ref["world_behavior"] = beh.export_state()

		if _work_coordinator != null:
			_work_coordinator.process_post_behavior(beh, node, _all_drops_cache)


# ---------------------------------------------------------------------------
# ctx builders
# ---------------------------------------------------------------------------

func _build_drops_info(node_pos: Vector2) -> Array:
	var result: Array = []
	for drop in _all_drops_cache:
		var drop_node := drop as Node2D
		if drop_node == null or not is_instance_valid(drop_node) \
				or drop_node.is_queued_for_deletion():
			continue
		if node_pos.distance_squared_to(drop_node.global_position) > BanditTuningScript.loot_scan_radius_sq():
			continue
		result.append({
			"id":     drop_node.get_instance_id(),
			"pos":    drop_node.global_position,
			"amount": int(drop_node.get("amount") if drop_node.get("amount") != null else 1),
		})
	return result


func _build_res_info(node_pos: Vector2) -> Array:
	var result: Array = []
	for res in _all_resources_cache:
		var res_node := res as Node2D
		if res_node == null or not is_instance_valid(res_node) \
				or res_node.is_queued_for_deletion():
			continue
		if node_pos.distance_squared_to(res_node.global_position) > BanditTuningScript.resource_scan_radius_sq():
			continue
		result.append({"pos": res_node.global_position, "id": res_node.get_instance_id()})
	return result


# ---------------------------------------------------------------------------
# Lazy behavior creation
# ---------------------------------------------------------------------------

func _ensure_behaviors_for_active_enemies() -> void:
	for enemy_id in _npc_simulator.active_enemies:
		var enemy_id_str: String = String(enemy_id)
		if _behaviors.has(enemy_id_str):
			continue
		var node = _npc_simulator.get_enemy_node(enemy_id_str)
		if node == null or not node.has_method("is_world_behavior_eligible") \
				or not node.is_world_behavior_eligible():
			continue
		var save_state: Dictionary = _get_save_state_for(enemy_id_str)
		if save_state.is_empty() or String(save_state.get("group_id", "")) == "":
			continue
		var beh := BanditWorldBehavior.new()
		beh.setup({
			"home_pos":    _get_home_pos(save_state),
			"role":        String(save_state.get("role", "scavenger")),
			"group_id":    String(save_state.get("group_id", "")),
			"member_id":   enemy_id_str,
			"cargo_count": int(save_state.get("cargo_count", 0)),
		})
		var wb = save_state.get("world_behavior", {})
		if wb is Dictionary and not (wb as Dictionary).is_empty():
			beh.import_state(wb as Dictionary)
		else:
			beh._rng.seed = absi(int(save_state.get("seed", 0)) ^ hash(enemy_id_str))
			beh._idle_timer = beh._rng.randf_range(NpcWorldBehavior.IDLE_WAIT_MIN, NpcWorldBehavior.IDLE_WAIT_MAX)
		_behaviors[enemy_id_str] = beh
		Debug.log("bandit_ai", "[BanditBL] behavior created id=%s role=%s group=%s cargo_cap=%d home=%s" % [
			enemy_id_str, beh.role, beh.group_id, beh.cargo_capacity, str(beh.home_pos)])


# ---------------------------------------------------------------------------
# Pruning
# ---------------------------------------------------------------------------

func _prune_behaviors() -> void:
	var to_remove: Array = []
	for enemy_id in _behaviors:
		if _npc_simulator.get_enemy_node(enemy_id) == null:
			to_remove.append(enemy_id)
	for enemy_id in to_remove:
		_behaviors.erase(enemy_id)
		if NpcPathService.is_ready():
			NpcPathService.clear_agent(enemy_id)
		Debug.log("bandit_ai", "[BanditBL] behavior pruned id=%s" % enemy_id)


# ---------------------------------------------------------------------------
# Recognition bubbles — feedback "te tienen fichado"
# ---------------------------------------------------------------------------

## Muestra una burbuja de reconocimiento si el NPC ve al jugador mientras
## la hostilidad es alta. Cooldown por NPC para evitar spam.
func _maybe_show_recognition_bubble(beh: BanditWorldBehavior,
		node: Node, node_pos: Vector2) -> void:
	if _bubble_manager == null or _player == null:
		return
	if beh.group_id == "":
		return
	# Solo si está cazando activamente
	var g: Dictionary = BanditGroupMemory.get_group(beh.group_id)
	if String(g.get("current_group_intent", "")) != "hunting":
		return
	# Cooldown por NPC
	if RunClock.now() < beh.recognition_bubble_until:
		return
	# Solo si el jugador está cerca
	if _player.global_position.distance_squared_to(node_pos) > RECOGNITION_RANGE_SQ:
		return
	# Nivel de hostilidad suficiente
	var faction_id: String = String(g.get("faction_id", ""))
	if faction_id == "":
		return
	var h_level: int = FactionHostilityManager.get_hostility_level(faction_id)
	if h_level < 3:
		return
	# Elegir el tier de frases más alto que no supere el nivel actual
	var phrase_tier: int = 3
	for tier: int in [9, 7, 5, 3]:
		if h_level >= tier:
			phrase_tier = tier
			break
	var phrases: Array = RECOGNITION_PHRASES.get(phrase_tier, []) as Array
	if phrases.is_empty():
		return
	var phrase: String = phrases[randi() % phrases.size()] as String
	_bubble_manager.show_actor_bubble(node as Node2D, phrase, 3.5)
	beh.recognition_bubble_until = RunClock.now() + RECOGNITION_COOLDOWN
	Debug.log("bandit_ai", "[BBL] recognition bubble npc=%s h_level=%d tier=%d" % [
		beh.member_id, h_level, phrase_tier])


# ---------------------------------------------------------------------------
# Idle chat — diálogo ambiental de mundo
# ---------------------------------------------------------------------------

## Dispara una frase ambiental ocasional cuando el NPC está ocioso o patrullando,
## sin que el jugador esté cerca. Crea sensación de mundo vivo.
func _maybe_show_idle_chat(beh: BanditWorldBehavior,
		node: Node, node_pos: Vector2) -> void:
	if _bubble_manager == null:
		return
	# Cooldown por NPC (escalonado desde setup para que no hablen todos a la vez)
	if RunClock.now() < beh.idle_chat_until:
		return
	# Solo en estados ociosos — no mientras caza, extorsiona, carga material ni vuelve al camp
	var state_ok: bool = beh.state == NpcWorldBehavior.State.IDLE_AT_HOME \
		or beh.state == NpcWorldBehavior.State.PATROL
	if not state_ok:
		return
	# No chatear si el grupo está en intención activa
	if beh.group_id != "":
		var g: Dictionary = BanditGroupMemory.get_group(beh.group_id)
		var intent: String = String(g.get("current_group_intent", ""))
		if intent == "hunting" or intent == "extorting" or intent == "raiding":
			return
	# No chatear si el jugador está demasiado cerca (que no suene a reacción)
	if _player != null and is_instance_valid(_player):
		if _player.global_position.distance_squared_to(node_pos) < IDLE_CHAT_PLAYER_DIST_MIN_SQ:
			return
	# Baja probabilidad por tick para que no salga en cada tick elegible
	# (tick interval ~0.5s → ~1.5% chance por tick elegible → frase cada ~33s en ventana)
	if randf() > 0.015:
		beh.idle_chat_until = RunClock.now() + 2.0  # micro-cooldown para no re-tirar cada frame
		return
	var phrase: String = IDLE_CHAT_PHRASES[randi() % IDLE_CHAT_PHRASES.size()]
	_bubble_manager.show_actor_bubble(node as Node2D, phrase, 3.5)
	# Cooldown aleatorio para que cada NPC hable a su propio ritmo
	beh.idle_chat_until = RunClock.now() + randf_range(IDLE_CHAT_COOLDOWN_MIN, IDLE_CHAT_COOLDOWN_MAX)


func _get_behavior(enemy_id: String) -> BanditWorldBehavior:
	return _behaviors.get(enemy_id, null) as BanditWorldBehavior


# ---------------------------------------------------------------------------
# Territory reaction — NPC más cercano reacciona cuando el jugador invade
# ---------------------------------------------------------------------------

## Bridge pequeño para que world.gd dispare reacciones sin cargar política social.
func notify_territory_reaction(_faction_id: String, group_id: String,
		intrusion_pos: Vector2, kind: String) -> void:
	if _territory_response == null:
		return
	_territory_response.notify_reaction(group_id, intrusion_pos, kind)


# ---------------------------------------------------------------------------
# Deposit pos distribution — callback usado por BanditCampStashSystem
# ---------------------------------------------------------------------------

## Propaga la posición del barril a todos los behaviors del grupo.
## Cada NPC recibe un slot personal (ángulo determinista por member_id).
func _update_deposit_pos(group_id: String, barrel_pos: Vector2) -> void:
	for eid in _behaviors:
		var beh: BanditWorldBehavior = _behaviors[eid]
		if beh.group_id != group_id:
			continue
		if beh.deposit_pos != Vector2.ZERO \
				and beh.deposit_pos.distance_squared_to(barrel_pos) < DEPOSIT_REASSIGN_GUARD_SQ:
			continue
		var h      := absi(hash(beh.member_id))
		var angle  := (h % DEPOSIT_SLOT_COUNT) * (TAU / DEPOSIT_SLOT_COUNT)
		var radius := DEPOSIT_SLOT_RADIUS_MIN + float(h % DEPOSIT_SLOT_RADIUS_RANGE)
		beh.deposit_pos = barrel_pos + Vector2(cos(angle), sin(angle)) * radius


# ---------------------------------------------------------------------------
# Save-state helpers
# ---------------------------------------------------------------------------

func _get_save_state_for(enemy_id: String) -> Dictionary:
	var chunk_key: String = _npc_simulator.get_enemy_chunk_key(enemy_id)
	if chunk_key == "":
		return {}
	var chunk_states: Dictionary = WorldSave.enemy_state_by_chunk.get(chunk_key, {})
	var state_v = chunk_states.get(enemy_id, {})
	if state_v is Dictionary:
		return state_v as Dictionary
	return {}


func _get_home_pos(save_state: Dictionary) -> Vector2:
	var hp = save_state.get("home_world_pos", null)
	if hp is Vector2:
		return hp
	if hp is Dictionary:
		return Vector2(float((hp as Dictionary).get("x", 0.0)), float((hp as Dictionary).get("y", 0.0)))
	return Vector2.ZERO
