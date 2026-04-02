extends Node
class_name BanditBehaviorLayer

# Ã¢ï¿½?ï¿½ï¿½,ï¿½Ã¢ï¿½?ï¿½ï¿½,ï¿½ BanditBehaviorLayer Ã¢ï¿½?ï¿½ï¿½,ï¿½Ã¢ï¿½?ï¿½ï¿½,ï¿½Ã¢ï¿½?ï¿½ï¿½,ï¿½Ã¢ï¿½?ï¿½ï¿½,ï¿½Ã¢ï¿½?ï¿½ï¿½,ï¿½Ã¢ï¿½?ï¿½ï¿½,ï¿½Ã¢ï¿½?ï¿½ï¿½,ï¿½Ã¢ï¿½?ï¿½ï¿½,ï¿½Ã¢ï¿½?ï¿½ï¿½,ï¿½Ã¢ï¿½?ï¿½ï¿½,ï¿½Ã¢ï¿½?ï¿½ï¿½,ï¿½Ã¢ï¿½?ï¿½ï¿½,ï¿½Ã¢ï¿½?ï¿½ï¿½,ï¿½Ã¢ï¿½?ï¿½ï¿½,ï¿½Ã¢ï¿½?ï¿½ï¿½,ï¿½Ã¢ï¿½?ï¿½ï¿½,ï¿½Ã¢ï¿½?ï¿½ï¿½,ï¿½Ã¢ï¿½?ï¿½ï¿½,ï¿½Ã¢ï¿½?ï¿½ï¿½,ï¿½Ã¢ï¿½?ï¿½ï¿½,ï¿½Ã¢ï¿½?ï¿½ï¿½,ï¿½Ã¢ï¿½?ï¿½ï¿½,ï¿½Ã¢ï¿½?ï¿½ï¿½,ï¿½Ã¢ï¿½?ï¿½ï¿½,ï¿½Ã¢ï¿½?ï¿½ï¿½,ï¿½Ã¢ï¿½?ï¿½ï¿½,ï¿½Ã¢ï¿½?ï¿½ï¿½,ï¿½Ã¢ï¿½?ï¿½ï¿½,ï¿½Ã¢ï¿½?ï¿½ï¿½,ï¿½Ã¢ï¿½?ï¿½ï¿½,ï¿½Ã¢ï¿½?ï¿½ï¿½,ï¿½Ã¢ï¿½?ï¿½ï¿½,ï¿½Ã¢ï¿½?ï¿½ï¿½,ï¿½Ã¢ï¿½?ï¿½ï¿½,ï¿½Ã¢ï¿½?ï¿½ï¿½,ï¿½Ã¢ï¿½?ï¿½ï¿½,ï¿½Ã¢ï¿½?ï¿½ï¿½,ï¿½Ã¢ï¿½?ï¿½ï¿½,ï¿½Ã¢ï¿½?ï¿½ï¿½,ï¿½Ã¢ï¿½?ï¿½ï¿½,ï¿½Ã¢ï¿½?ï¿½ï¿½,ï¿½Ã¢ï¿½?ï¿½ï¿½,ï¿½Ã¢ï¿½?ï¿½ï¿½,ï¿½Ã¢ï¿½?ï¿½ï¿½,ï¿½Ã¢ï¿½?ï¿½ï¿½,ï¿½Ã¢ï¿½?ï¿½ï¿½,ï¿½Ã¢ï¿½?ï¿½ï¿½,ï¿½Ã¢ï¿½?ï¿½ï¿½,ï¿½Ã¢ï¿½?ï¿½ï¿½,ï¿½Ã¢ï¿½?ï¿½ï¿½,ï¿½Ã¢ï¿½?ï¿½ï¿½,ï¿½Ã¢ï¿½?ï¿½ï¿½,ï¿½Ã¢ï¿½?ï¿½ï¿½,ï¿½Ã¢ï¿½?ï¿½ï¿½,ï¿½
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
const SimulationLODPolicyScript     := preload("res://scripts/world/SimulationLODPolicy.gd")
const CombatStateServiceScript      := preload("res://scripts/world/CombatStateService.gd")
const BanditDomainPortsScript      := preload("res://scripts/world/BanditDomainPorts.gd")

# ---------------------------------------------------------------------------
# Camp layout constants Ã¢ï¿½,ï¿½ï¿½?ï¿½ local geometry, not cross-system gameplay tuning.
# These control how NPCs distribute themselves around the barrel; a designer
# would tune pickup radii / speeds in BanditTuning, not these.
# ---------------------------------------------------------------------------
const DEPOSIT_SLOT_COUNT:        int   = 36      # posiciones angulares alrededor del barril
const DEPOSIT_SLOT_RADIUS_MIN:   float = 32.0    # px mï¿½fÂ­nimo desde el centro del barril
const DEPOSIT_SLOT_RADIUS_RANGE: int   = 20      # varianza adicional (hash % N)
const DEPOSIT_REASSIGN_GUARD_SQ: float = 72.0 * 72.0  # no reasignar si ya estï¿½fÂ¡ cerca

signal debug_observation_emitted(channel: StringName, payload: Dictionary)

const DEBUG_ALERTED_CHASE_OBSERVATION: bool = true
const DEBUG_ALLY_SEP_COMPARISONS: bool = false
const STRUCTURE_ASSAULT_FOCUS_SECONDS: float = 24.0
const STRUCTURE_MEMBER_QUERY_RADIUS: float = 320.0
const STRUCTURE_MEMBER_QUERY_RING_RADIUS: float = 96.0
const STRUCTURE_MEMBER_TARGET_SEPARATION_SQ: float = 96.0 * 96.0
const STRUCTURE_ASSAULT_STANDBY_DIST: float = 180.0
const STRUCTURE_MEMBER_CANDIDATE_LIMIT: int = 24
const STRUCTURE_TARGET_TEAM_SIZE: int = 3
const STRUCTURE_WALL_SAMPLE_STEP: float = 72.0
const STRUCTURE_WALL_SAMPLE_GRID_HALF_STEPS: int = 2
const STRUCTURE_WALL_SUPPORT_RADIUS_SQ: float = 84.0 * 84.0
const STRUCTURE_STICKY_TEAM_TARGET_TTL: float = 4.5
const STRUCTURE_TARGET_VALIDATION_RADIUS: float = 72.0
const STRUCTURE_WALL_TARGET_VALIDATION_RADIUS: float = 42.0
const STRUCTURE_POOL_SAMPLE_MIN_SEPARATION_SQ: float = 64.0 * 64.0
const STRUCTURE_WALL_SAMPLE_MAX_POINTS: int = 16
const STRUCTURE_TARGET_POOL_CACHE_TTL: float = 0.45
const STRUCTURE_TARGET_VALID_CACHE_TTL: float = 0.20
const STRUCTURE_TARGET_CACHE_POS_QUANTUM: float = 24.0
const STRUCTURE_DISPATCH_SYNC_BUDGET: int = 3
const STRUCTURE_DISPATCH_FRAME_BUDGET: int = 4
const STRUCTURE_DISPATCH_MAX_PENDING_JOBS: int = 12
const INVALID_STRUCTURE_TARGET: Vector2 = Vector2(-1.0, -1.0)

# ---------------------------------------------------------------------------
# Frases de reconocimiento Ã¢ï¿½,ï¿½ï¿½?ï¿½ cuando la banda te tiene fichado y te ve venir
# ---------------------------------------------------------------------------
## Clave = nivel mï¿½fÂ­nimo de hostilidad. Se usa el mayor nivel que no supere el actual.
const RECOGNITION_PHRASES: Dictionary = {
	3: [
		"Sigues apareciendo por aquï¿½fÂ­...",
		"Otro dï¿½fÂ­a. Otro problema.",
		"No aprendes, ï¿½,Â¿verdad?",
		"Vaya. Tï¿½fÂº de nuevo.",
		"Quï¿½fÂ© puntual. Como siempre.",
	],
	5: [
		"Ya sï¿½fÂ© quiï¿½fÂ©n eres. Y lo que has hecho.",
		"Te tenemos en la lista. Lleva tiempo.",
		"No te hagas el desconocido. Nos acordamos.",
		"Sabes perfectamente que no eres bienvenido aquï¿½fÂ­.",
		"De todos los sitios. Tienes que aparecer aquï¿½fÂ­.",
	],
	7: [
		"Precisamente tï¿½fÂº. Quï¿½fÂ© mala suerte la tuya.",
		"Mal momento para aparecer. O quizï¿½fÂ¡ el peor.",
		"No te iba a pasar nada. Hasta que apareciste.",
		"Hoy me alegra verte. Por primera vez.",
		"Llevas tiempo mereciï¿½fÂ©ndote esto.",
	],
	9: [
		"Buscï¿½fÂ¡bamos una excusa. Gracias por darnos una.",
		"No sï¿½fÂ© si eres valiente o estï¿½fÂºpido. Hoy da igual.",
		"Ya no hay negociaciï¿½fÂ³n. Solo cuentas que saldar.",
		"Querï¿½fÂ­an que apareciera alguien como tï¿½fÂº. Y aquï¿½fÂ­ estï¿½fÂ¡s.",
		"Esta vez no hay opciï¿½fÂ³n de pagar.",
	],
}

## Distancia mï¿½fÂ¡xima (pxï¿½,Â²) al jugador para que se dispare el reconocimiento.
const RECOGNITION_RANGE_SQ: float = 350.0 * 350.0
## Cooldown mï¿½fÂ­nimo (s) entre burbujas de reconocimiento por NPC.
const RECOGNITION_COOLDOWN: float = 45.0

# ---------------------------------------------------------------------------
# Diï¿½fÂ¡logo ambiental Ã¢ï¿½,ï¿½ï¿½?ï¿½ frases de mundo mientras el NPC estï¿½fÂ¡ ocioso o patrullando
# ---------------------------------------------------------------------------
const IDLE_CHAT_PHRASES: Array[String] = [
	# Aburrimiento de guardia
	"Otro dï¿½fÂ­a mï¿½fÂ¡s vigilando piedras.",
	"ï¿½,Â¿Cuï¿½fÂ¡ntas veces he dado esta vuelta? No sï¿½fÂ©. Muchas.",
	"El jefe dijo 'vigilancia discreta'. Llevamos aquï¿½fÂ­ tres dï¿½fÂ­as.",
	"Nadie me dijo que este trabajo iba a ser tan aburrido.",
	"ï¿½,Â¿Cuï¿½fÂ¡nto falta para que me releven? Demasiado. Siempre demasiado.",
	"Si alguien me pregunta quï¿½fÂ© hora es, le cobro.",
	# Reflexiones sobre el oficio
	"Buena zona. Mala paga.",
	"Si aparece alguien, cobro. Si no aparece nadie, cobro igual. No estï¿½fÂ¡ mal.",
	"Mi madre querï¿½fÂ­a que fuera carpintero. No sï¿½fÂ© por quï¿½fÂ© no la escuchï¿½fÂ©.",
	"El ï¿½fÂºltimo que intentï¿½fÂ³ pasar sin pagar... bueno. Al menos ya no tiene ese problema.",
	"Dicen que hay gente que trabaja en oficinas. Quï¿½fÂ© raro debe ser eso.",
	"Algï¿½fÂºn dï¿½fÂ­a me jubilo. Me compro una cabaï¿½fÂ±a. Lejos de todo esto.",
	"Llevo aï¿½fÂ±os en esto y todavï¿½fÂ­a me sorprende la gente que dice que no.",
	"El jefe habla mucho de 'expansiï¿½fÂ³n territorial'. Nosotros caminamos.",
	# Territorio y orgullo
	"Por aquï¿½fÂ­ no pasa nadie sin que yo me entere. Nadie.",
	"Buena visibilidad hoy. Cosa rara.",
	"Esta zona es nuestra. Ha sido nuestra siempre. Lo seguirï¿½fÂ¡ siendo.",
	"A veces me pregunto quiï¿½fÂ©n estaba aquï¿½fÂ­ antes que nosotros. Y luego me dejo de preguntar.",
	# Observaciones random
	"Me duelen los pies. A nadie mï¿½fÂ¡s le duelen los pies. Solo a mï¿½fÂ­.",
	"Hace frï¿½fÂ­o. O calor. Siempre algo.",
	"ï¿½,Â¿Comemos hoy? Mejor que ayer, espero.",
	"Me prometieron que esto iba a ser temporal. Eso fue hace cuatro aï¿½fÂ±os.",
	"Tengo una teorï¿½fÂ­a sobre por quï¿½fÂ© la gente siempre lleva menos dinero del que parece.",
	"Si me dieran un perro por cada idiota que he visto pasar... tendrï¿½fÂ­a muchos perros.",
	"El suelo de aquï¿½fÂ­ es mï¿½fÂ¡s cï¿½fÂ³modo que el del campamento. Eso dice algo.",
	# Humor seco / oscuro
	"A veces los trabajo bonitos no son tan bonitos. Este sï¿½fÂ­ que no lo es.",
	"Lo bueno de este trabajo: si alguien te fastidia, le fastidias tï¿½fÂº a ï¿½fÂ©l.",
	"Hay dï¿½fÂ­as que no pasa nadie. Hay dï¿½fÂ­as que pasan demasiados. Hoy todavï¿½fÂ­a no sï¿½fÂ©.",
	"Zona tranquila. Eso o nadie quiere pasar. Ambas opciones me vienen bien.",
	"Que no se me olvide: cobrar primero, preguntar despuï¿½fÂ©s.",
	"Dicen que los bandidos no tenemos honor. Los que lo dicen nunca han visto cï¿½fÂ³mo nos pagamos los unos a los otros.",
	"He visto gente que miraba mal y acabï¿½fÂ³ mirando al suelo. Asï¿½fÂ­ funciona.",
	"A este paso, me voy a conocer cada piedra de aquï¿½fÂ­ de nombre.",
	"Alguno cree que si corre mï¿½fÂ¡s rï¿½fÂ¡pido no le alcanzamos. Se equivoca siempre.",
]

## Cooldown entre frases idle (segundos). Se aï¿½fÂ±ade variaciï¿½fÂ³n aleatoria por NPC.
const IDLE_CHAT_COOLDOWN_MIN: float = 90.0
const IDLE_CHAT_COOLDOWN_MAX: float = 200.0
## Distancia mï¿½fÂ­nima al jugador para soltar frases ambientales (que no suene a reacciï¿½fÂ³n).
const IDLE_CHAT_PLAYER_DIST_MIN_SQ: float = 280.0 * 280.0

var _npc_simulator:  NpcSimulator             = null
var _group_intel:    BanditGroupIntel         = null
var _player:         Node2D                   = null
var _bubble_manager: WorldSpeechBubbleManager = null
var _cadence:        WorldCadenceCoordinator  = null

var _behaviors: Dictionary = {}   # enemy_id (String) -> BanditWorldBehavior
var _behavior_elapsed: Dictionary = {}
var _warned_missing_director_scheduler: bool = false

var _extortion_director: BanditExtortionDirector = null
var _raid_director:      BanditRaidDirector      = null
var _stash:              BanditCampStashSystem   = null
var _territory_response: BanditTerritoryResponse = null
var _work_coordinator:   BanditWorkCoordinator   = null
var _find_wall_cb:       Callable                = Callable()
var _find_wall_samples_cb: Callable              = Callable()
var _find_workbench_cb:  Callable                = Callable()
var _find_storage_cb:    Callable                = Callable()
var _find_placeable_cb:  Callable                = Callable()
var _world_node:         Node                    = null
var _world_spatial_index: WorldSpatialIndex      = null
var _extortion_queue_port: Dictionary            = {}
var _raid_queue_port: Dictionary                 = {}
var _pending_structure_dispatches: Array[Dictionary] = []
var _group_team_target_cache: Dictionary         = {}
var _group_target_pool_cache: Dictionary         = {}
var _structure_target_valid_cache: Dictionary    = {}
var _structure_cache_gc_at: float                = 0.0
var _dispatch_log_next_at: Dictionary            = {}
var _lod_debug_last_npc: Dictionary              = {}
var _lod_debug_npc_counts: Dictionary            = {"fast": 0, "medium": 0, "slow": 0}
var _domain_ports: BanditDomainPorts             = null
var _ally_sep_debug_last_comparisons: int        = 0
var _tick_perf_samples: int                       = 0
var _tick_perf_total_ms: float                    = 0.0
var _tick_perf_last_ms: float                     = 0.0
var _tick_perf_avg_ms: float                      = 0.0
var _tick_perf_last_query_delta: int              = 0
var _tick_perf_query_delta_total: int             = 0
var _tick_perf_query_delta_avg: float             = 0.0
var _director_perf_last_ms: float                 = 0.0
var _director_perf_avg_ms: float                  = 0.0
var _behavior_lane_last_ms: float                 = 0.0
var _behavior_lane_avg_ms: float                  = 0.0
var _temp_alloc_est_last: int                     = 0
var _temp_alloc_est_avg: float                    = 0.0
var _livetree_scan_calls: int                     = 0
var _livetree_scan_nodes_last: int                = 0
var _livetree_scan_nodes_total: int               = 0


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

func setup(ctx: Dictionary) -> void:
	_cadence        = ctx.get("cadence") as WorldCadenceCoordinator
	_npc_simulator  = ctx.get("npc_simulator")
	_player         = ctx.get("player")
	_bubble_manager = ctx.get("speech_bubble_manager")
	_world_spatial_index = ctx.get("world_spatial_index") as WorldSpatialIndex
	_world_node = ctx.get("world_node")
	_domain_ports = ctx.get("domain_ports") as BanditDomainPorts
	if _domain_ports == null:
		_domain_ports = BanditDomainPortsScript.new() as BanditDomainPorts
		_domain_ports.setup()
	# Temporal governance boundary:
	# world cadence drives cross-system directors so extortion/raid orchestration
	# shares the same world pulse grid as chunk/autosave maintenance.

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
		"domain_ports": _domain_ports,
	})

	# Raid director
	if _raid_director != null and is_instance_valid(_raid_director):
		_raid_director.queue_free()
	_raid_director = BanditRaidDirectorScript.new() as BanditRaidDirector
	_raid_director.name = "BanditRaidDirector"
	add_child(_raid_director)
	_raid_director.setup({
		"npc_simulator": _npc_simulator,
		"dispatch_group_to_target_cb": Callable(self, "dispatch_group_to_target"),
	})

	if _territory_response == null:
		_territory_response = BanditTerritoryResponseScript.new()
	_territory_response.setup({
		"npc_simulator": _npc_simulator,
		"speech_bubble_manager": _bubble_manager,
		"domain_ports": _domain_ports,
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
		"world_node": _world_node,
		"world_spatial_index": _world_spatial_index,
	})


## Called from world.gd after SettlementIntel is ready.
func setup_group_intel(ctx: Dictionary) -> void:
	_extortion_queue_port = ctx.get("extortion_queue_port", {}) as Dictionary
	_raid_queue_port = ctx.get("raid_queue_port", {}) as Dictionary
	_group_intel = BanditGroupIntelScript.new()
	_group_intel.setup({
		"npc_simulator":             _npc_simulator,
		"player":                    _player,
		"cadence":                   _cadence,
		"get_interest_markers_near": ctx.get("get_interest_markers_near", Callable()),
		"get_detected_bases_near":   ctx.get("get_detected_bases_near",   Callable()),
		"extortion_queue_port":      ctx.get("extortion_queue_port", {}),
		"raid_queue_port":           ctx.get("raid_queue_port", {}),
		"dispatch_group_action_cb":  Callable(self, "_dispatch_group_intel_action"),
	})

	# Guardar query callables Ã¢ï¿½,ï¿½ï¿½?ï¿½ se pasan al RaidDirector y tambiï¿½fÂ©n al ctx de cada tick
	var wall_cb: Callable = ctx.get("find_nearest_player_wall_world_pos", Callable())
	_find_wall_cb = wall_cb
	if _raid_director != null and wall_cb.is_valid():
		_raid_director.set_wall_query(wall_cb)
	_find_wall_samples_cb = ctx.get("find_player_wall_samples_world_pos", Callable())
	_find_workbench_cb = ctx.get("find_nearest_player_workbench_world_pos", Callable())
	_find_storage_cb   = ctx.get("find_nearest_player_storage_world_pos",   Callable())
	_find_placeable_cb = ctx.get("find_nearest_player_placeable_world_pos", Callable())
	if _raid_director != null:
		if _find_workbench_cb.is_valid():
			_raid_director.set_workbench_query(_find_workbench_cb)
		if _find_storage_cb.is_valid():
			_raid_director.set_storage_query(_find_storage_cb)
		if _find_placeable_cb.is_valid():
			_raid_director.set_placeable_query(_find_placeable_cb)


func _dispatch_group_intel_action(action: Dictionary) -> void:
	if action.is_empty():
		return
	var group_id: String = String(action.get("group_id", ""))
	var kind: String = String(action.get("kind", ""))
	match kind:
		"enqueue_extortion":
			var payload: Dictionary = action.get("payload", {}) as Dictionary
			if not payload.is_empty():
				_queue_port_call(_extortion_queue_port, "enqueue", [payload])
				BanditGroupMemory.issue_execution_intent(
					group_id, "extorting", "BanditBehaviorLayer",
					float(action.get("execution_ttl", 120.0)), {"source": "extortion_queue"})
				BanditGroupMemory.push_social_cooldown(group_id, float(action.get("social_cooldown", 4.0)))
				BanditGroupMemory.update_intent(group_id, "extorting")
				Debug.log("bandit_intel", "[BGI→BBL] extortion enqueued group=%s leader=%s kind=%s" % [
					group_id,
					String(payload.get("source_npc_id", "")),
					String(payload.get("trigger_kind", "")),
				])
		"enqueue_wall_probe":
			var probe_args: Array = action.get("args", [])
			if probe_args.size() >= 6:
				_queue_port_call(_raid_queue_port, "enqueue_wall_probe", [
					probe_args[0], probe_args[1], probe_args[2], probe_args[3], probe_args[4], int(probe_args[5])
				])
				_finalize_group_raid_dispatch(group_id, action, "wall_probe")
		"enqueue_light_raid":
			var light_args: Array = action.get("args", [])
			if light_args.size() >= 5:
				_queue_port_call(_raid_queue_port, "enqueue_light_raid", [
					light_args[0], light_args[1], light_args[2], light_args[3], light_args[4]
				])
				_finalize_group_raid_dispatch(group_id, action, "light_raid")
		"enqueue_full_raid":
			var raid_args: Array = action.get("args", [])
			if raid_args.size() >= 5:
				_queue_port_call(_raid_queue_port, "enqueue_raid", [
					raid_args[0], raid_args[1], raid_args[2], raid_args[3], raid_args[4]
				])
				_finalize_group_raid_dispatch(group_id, action, "full_raid")


func _queue_port_call(port: Dictionary, key: String, args: Array = []) -> Variant:
	var cb: Callable = port.get(key, Callable())
	if not cb.is_valid():
		push_warning("BanditBehaviorLayer missing queue port callable '%s'" % key)
		return null
	return cb.callv(args)


func _finalize_group_raid_dispatch(group_id: String, action: Dictionary, source: String) -> void:
	BanditGroupMemory.issue_execution_intent(
		group_id, "raiding", "BanditBehaviorLayer",
		float(action.get("execution_ttl", 240.0)), {"source": source})
	BanditGroupMemory.push_social_cooldown(group_id, float(action.get("social_cooldown", 8.0)))
	BanditGroupMemory.update_intent(group_id, "raiding")
	var base_center: Vector2 = action.get("base_center", Vector2.ZERO) as Vector2
	if base_center != Vector2.ZERO:
		BanditGroupMemory.record_interest(group_id, base_center, "base_detected")
	Debug.log("bandit_intel", "[BGI→BBL] %s enqueued group=%s" % [source, group_id])


# ---------------------------------------------------------------------------
# Physics frame Ã¢ï¿½,ï¿½ï¿½?ï¿½ apply velocity to sleeping, non-lite enemies
# ---------------------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	if _npc_simulator == null:
		return
	_ally_sep_debug_last_comparisons = 0

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
		_apply_group_ally_separation(members)

	if DEBUG_ALLY_SEP_COMPARISONS:
		debug_observation_emitted.emit(
			&"ally_sep_grid_debug",
			{"comparisons": _ally_sep_debug_last_comparisons}
		)

	if _extortion_director != null:
		_extortion_director.apply_extortion_movement(BanditTuningScript.friction_compensation())

	# Debug observation only: never mutate runtime velocity from telemetry/debug.
	if DEBUG_ALERTED_CHASE_OBSERVATION and _player != null and is_instance_valid(_player):
		var ap: Vector2 = _player.global_position
		for gid in _domain_ports.bandit_group_memory().get_all_group_ids():
			var g: Dictionary = _domain_ports.bandit_group_memory().get_group(gid)
			if String(g.get("current_group_intent", "")) != "alerted":
				continue
			var scout_id: String = _domain_ports.bandit_group_memory().get_scout(gid)
			if scout_id == "":
				continue
			var snode = _npc_simulator.get_enemy_node(scout_id)
			if snode == null or not snode.has_method("is_world_behavior_eligible") \
					or not snode.is_world_behavior_eligible():
				continue
			var to_p: Vector2 = ap - snode.global_position
			if to_p.length() > 1.0:
				var suggested_speed: float = (
					BanditTuningScript.alerted_scout_chase_speed(gid) + BanditTuningScript.friction_compensation()
				)
				debug_observation_emitted.emit(
					&"alerted_scout_chase_candidate",
					{
						"group_id": gid,
						"scout_id": scout_id,
						"distance_to_player": to_p.length(),
						"suggested_speed": suggested_speed,
					}
				)


func _apply_group_ally_separation(members: Array) -> void:
	var sep_radius: float = BanditTuningScript.ally_sep_radius()
	if sep_radius <= 0.0:
		return
	var sep_force: float = BanditTuningScript.ally_sep_force()
	var cell_size: float = sep_radius
	var grid: Dictionary = {}
	for idx in members.size():
		var pos: Vector2 = members[idx]["pos"] as Vector2
		var cell: Vector2i = _ally_sep_grid_cell(pos, cell_size)
		if not grid.has(cell):
			grid[cell] = []
		grid[cell].append(idx)

	for i in members.size():
		var a: Dictionary = members[i]
		var a_pos: Vector2 = a["pos"] as Vector2
		var a_cell: Vector2i = _ally_sep_grid_cell(a_pos, cell_size)
		var sep: Vector2 = Vector2.ZERO
		for oy in range(-1, 2):
			for ox in range(-1, 2):
				var neigh_cell := Vector2i(a_cell.x + ox, a_cell.y + oy)
				var bucket: Array = grid.get(neigh_cell, [])
				for j in bucket:
					if i == j:
						continue
					_ally_sep_debug_last_comparisons += 1
					var diff: Vector2 = a_pos - (members[j]["pos"] as Vector2)
					var d: float = diff.length()
					if d < sep_radius and d > 0.5:
						sep += diff.normalized() * (sep_radius - d) / sep_radius * sep_force
		if sep.length_squared() > 0.01:
			a["node"].velocity += sep


func _ally_sep_grid_cell(pos: Vector2, cell_size: float) -> Vector2i:
	return Vector2i(floori(pos.x / cell_size), floori(pos.y / cell_size))


# ---------------------------------------------------------------------------
# Process tick Ã¢ï¿½,ï¿½ï¿½?ï¿½ behavior maintenance
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _npc_simulator == null:
		return
	var input_ctx: Dictionary = _domain_ports.capture_input_context({"delta": delta})
	var now: float = float(input_ctx.get("now", 0.0))
	if now >= _structure_cache_gc_at:
		_structure_cache_gc_at = now + 1.5
		_prune_structure_target_caches()
	if _group_intel != null:
		_group_intel.tick(delta)
	var director_pulses: int = 0
	if _cadence != null:
		director_pulses = _cadence.consume_lane(&"director_pulse")
	elif not _warned_missing_director_scheduler:
		_warned_missing_director_scheduler = true
		push_warning("BanditBehaviorLayer has no cadence or director pulse adapter; directors are paused until a scheduler is injected.")
	for _pulse in director_pulses:
		var director_started_usec: int = Time.get_ticks_usec()
		if _extortion_director != null:
			_extortion_director.process_extortion(now)
		if _raid_director != null:
			_raid_director.process_raid()
		_record_director_perf(Time.get_ticks_usec() - director_started_usec)
	_process_pending_structure_dispatches()
	var behavior_pulses: int = 0
	if _cadence != null:
		behavior_pulses = _cadence.consume_lane(&"bandit_behavior_tick")
	if behavior_pulses <= 0:
		return

	for _pulse in behavior_pulses:
		var behavior_started_usec: int = Time.get_ticks_usec()
		_ensure_behaviors_for_active_enemies()
		_stash.ensure_barrels()
		_tick_behaviors()
		_prune_behaviors()
		_record_behavior_lane_perf(Time.get_ticks_usec() - behavior_started_usec)


# ---------------------------------------------------------------------------
# Behavior tick
# ---------------------------------------------------------------------------

func _tick_behaviors() -> void:
	var tick_started_usec: int = Time.get_ticks_usec()
	var query_total_before: int = _get_spatial_query_total()
	_prune_behavior_timers()
	_lod_debug_last_npc.clear()
	_lod_debug_npc_counts = {"fast": 0, "medium": 0, "slow": 0}
	var use_runtime_spatial_index: bool = _world_spatial_index != null and is_instance_valid(_world_spatial_index)
	var drop_nodes_snapshot: Array = []
	var res_nodes_snapshot: Array = []
	if not use_runtime_spatial_index:
		drop_nodes_snapshot = _get_all_drop_nodes()
		res_nodes_snapshot = _get_all_resource_nodes()
	var leader_pos_by_group: Dictionary = {}
	var drop_nodes_by_group: Dictionary = {}
	var resource_nodes_by_group: Dictionary = {}
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
		var node_pos_for_work: Vector2 = (node as Node2D).global_position if node is Node2D else Vector2.ZERO
		var work_drop_candidates: Array = drop_nodes_snapshot
		if use_runtime_spatial_index and node is Node2D:
			work_drop_candidates = _get_runtime_nodes_for_behavior(
				beh,
				node_pos_for_work,
				leader_pos_by_group,
				drop_nodes_by_group,
				WorldSpatialIndex.KIND_ITEM_DROP,
				BanditTuningScript.runtime_index_drop_query_radius()
			)
		if node == null or not node.has_method("is_world_behavior_eligible") \
				or not node.is_world_behavior_eligible():
			if _work_coordinator != null:
				var cmd_idle: Dictionary = beh.issue_execution_intent({"now": RunClock.now()})
				_work_coordinator.process_post_behavior(beh, node, work_drop_candidates, cmd_idle, _get_runtime_lod_signals(node))
			continue

		var node_pos: Vector2 = node.global_position
		var tick_interval: float = _get_behavior_tick_interval(beh, node, node_pos)
		var elapsed: float = float(_behavior_elapsed.get(enemy_id, 0.0)) + BanditTuningScript.behavior_tick_interval()
		_behavior_elapsed[enemy_id] = elapsed
		if elapsed < tick_interval:
			if _work_coordinator != null:
				var cmd_slow: Dictionary = beh.issue_execution_intent({
					"node_pos": node_pos,
					"now": RunClock.now(),
				})
				_work_coordinator.process_post_behavior(beh, node, work_drop_candidates, cmd_slow, _get_runtime_lod_signals(node))
			continue
		# Resetear a 0 en vez de acumular residual para evitar que elapsed crezca
		# indefinidamente cuando tick_interval es corto (ej. 0.25s con jugador cerca).
		# Un elapsed creciente pasado a beh.tick() como delta hace que _stuck_timer
		# supere STUCK_CHECK_INTERVAL en el primer tick de PATROL, antes de que el
		# NPC haya movido, disparando stuck detection de forma falsa.
		_behavior_elapsed[enemy_id] = 0.0

		var drop_candidates: Array = drop_nodes_snapshot
		var resource_candidates: Array = res_nodes_snapshot
		if use_runtime_spatial_index:
			drop_candidates = _get_runtime_nodes_for_behavior(
				beh,
				node_pos,
				leader_pos_by_group,
				drop_nodes_by_group,
				WorldSpatialIndex.KIND_ITEM_DROP,
				BanditTuningScript.runtime_index_drop_query_radius()
			)
			resource_candidates = _get_runtime_nodes_for_behavior(
				beh,
				node_pos,
				leader_pos_by_group,
				resource_nodes_by_group,
				WorldSpatialIndex.KIND_WORLD_RESOURCE,
				BanditTuningScript.runtime_index_resource_query_radius()
			)

		var ctx: Dictionary = {
			"node_pos":                       node_pos,
			"nearby_drops_info":              _build_drops_info(node_pos, drop_candidates),
			"nearby_res_info":                _build_res_info(node_pos, resource_candidates),
			"find_nearest_player_wall":       _find_wall_cb,
			"find_nearest_player_workbench":  _find_workbench_cb,
			"find_nearest_player_storage":    _find_storage_cb,
			"find_nearest_player_placeable":  _find_placeable_cb,
		}
		if beh.group_id != "":
			ctx["leader_pos"] = leader_pos_by_group.get(beh.group_id, beh.home_pos)

		# Pasar tick_interval como delta (tiempo real desde ï¿½fÂºltimo tick),
		# no elapsed que puede ser mayor que tick_interval.
		beh.tick(tick_interval, ctx)
		_maybe_show_recognition_bubble(beh, node, node_pos)
		_maybe_show_idle_chat(beh, node, node_pos)

		# Sync save-state: cargo y behavior para continuidad data-only
		var save_state_ref: Dictionary = _get_save_state_for(enemy_id)
		if not save_state_ref.is_empty():
			save_state_ref["cargo_count"]    = beh.cargo_count
			save_state_ref["world_behavior"] = beh.export_state()

		if _work_coordinator != null:
			var cmd: Dictionary = beh.issue_execution_intent({
				"node_pos": node_pos,
				"now": RunClock.now(),
			})
			_work_coordinator.process_post_behavior(beh, node, work_drop_candidates, cmd, _get_runtime_lod_signals(node))
	var query_total_after: int = _get_spatial_query_total()
	_record_tick_perf(Time.get_ticks_usec() - tick_started_usec, query_total_before, query_total_after)


# ---------------------------------------------------------------------------
# ctx builders
# ---------------------------------------------------------------------------

func _build_drops_info(node_pos: Vector2, all_drops: Array) -> Array:
	var result: Array = []
	var r2: float = BanditTuningScript.loot_scan_radius_sq()
	for drop in all_drops:
		var drop_node := drop as Node2D
		if drop_node == null or not is_instance_valid(drop_node) \
				or drop_node.is_queued_for_deletion():
			continue
		if node_pos.distance_squared_to(drop_node.global_position) > r2:
			continue
		result.append({
			"id":     drop_node.get_instance_id(),
			"pos":    drop_node.global_position,
			"amount": int(drop_node.get("amount") if drop_node.get("amount") != null else 1),
		})
	return result


func _build_res_info(node_pos: Vector2, all_resources: Array) -> Array:
	var result: Array = []
	var r2: float = BanditTuningScript.resource_scan_radius_sq()
	for res in all_resources:
		var res_node := res as Node2D
		if res_node == null or not is_instance_valid(res_node) \
				or res_node.is_queued_for_deletion():
			continue
		if node_pos.distance_squared_to(res_node.global_position) > r2:
			continue
		result.append({"pos": res_node.global_position, "id": res_node.get_instance_id()})
	return result


func _get_all_drop_nodes() -> Array:
	# Runtime truth for tactical loot decisions is the live scene tree.
	# Spatial index remains an optimization, never the semantic owner.
	var nodes: Array = get_tree().get_nodes_in_group("item_drop")
	_record_livetree_scan(nodes.size())
	return nodes


func _get_all_resource_nodes() -> Array:
	# Runtime truth for resource watch is the live world_resource group.
	var nodes: Array = get_tree().get_nodes_in_group("world_resource")
	_record_livetree_scan(nodes.size())
	return nodes


func _get_runtime_nodes_for_behavior(
		beh: BanditWorldBehavior,
		node_pos: Vector2,
		leader_pos_by_group: Dictionary,
		cache: Dictionary,
		kind: StringName,
		radius: float) -> Array:
	if _world_spatial_index == null or not is_instance_valid(_world_spatial_index):
		return []
	var cache_key: String = String(beh.member_id)
	var anchor_pos: Vector2 = node_pos
	if beh.group_id != "":
		cache_key = "group:%s" % beh.group_id
		anchor_pos = leader_pos_by_group.get(beh.group_id, node_pos)
	if cache.has(cache_key):
		return cache[cache_key]
	var runtime_nodes: Array = _world_spatial_index.get_runtime_nodes_near(kind, anchor_pos, radius)
	cache[cache_key] = runtime_nodes
	return runtime_nodes


func _get_spatial_query_total() -> int:
	if _world_spatial_index == null or not is_instance_valid(_world_spatial_index):
		return -1
	var snapshot: Dictionary = _world_spatial_index.get_debug_snapshot()
	return int(snapshot.get("query_total", -1))


func _record_tick_perf(elapsed_usec: int, query_total_before: int, query_total_after: int) -> void:
	_tick_perf_last_ms = maxf(float(elapsed_usec) / 1000.0, 0.0)
	_tick_perf_samples += 1
	_tick_perf_total_ms += _tick_perf_last_ms
	_tick_perf_avg_ms = _tick_perf_total_ms / float(maxi(_tick_perf_samples, 1))
	var query_delta: int = -1
	if query_total_before >= 0 and query_total_after >= query_total_before:
		query_delta = query_total_after - query_total_before
	_tick_perf_last_query_delta = query_delta
	if query_delta >= 0:
		_tick_perf_query_delta_total += query_delta
		_tick_perf_query_delta_avg = float(_tick_perf_query_delta_total) / float(maxi(_tick_perf_samples, 1))
	_temp_alloc_est_last = _behaviors.size() + _behavior_elapsed.size() + _lod_debug_last_npc.size()
	_temp_alloc_est_avg = lerpf(_temp_alloc_est_avg, float(_temp_alloc_est_last), 1.0 / float(maxi(_tick_perf_samples, 1)))


func _record_director_perf(elapsed_usec: int) -> void:
	_director_perf_last_ms = maxf(float(elapsed_usec) / 1000.0, 0.0)
	_director_perf_avg_ms = lerpf(_director_perf_avg_ms, _director_perf_last_ms, 0.1)


func _record_behavior_lane_perf(elapsed_usec: int) -> void:
	_behavior_lane_last_ms = maxf(float(elapsed_usec) / 1000.0, 0.0)
	_behavior_lane_avg_ms = lerpf(_behavior_lane_avg_ms, _behavior_lane_last_ms, 0.1)


func _record_livetree_scan(node_count: int) -> void:
	_livetree_scan_calls += 1
	_livetree_scan_nodes_last = node_count
	_livetree_scan_nodes_total += maxi(node_count, 0)


# ---------------------------------------------------------------------------
# Lazy behavior creation
# ---------------------------------------------------------------------------

func _ensure_behavior_for_enemy(enemy_id_str: String, node: Node = null) -> BanditWorldBehavior:
	if _behaviors.has(enemy_id_str):
		return _behaviors.get(enemy_id_str, null) as BanditWorldBehavior
	if _npc_simulator == null:
		return null

	var enemy_node: Node = node if node != null else _npc_simulator.get_enemy_node(enemy_id_str)
	if enemy_node == null:
		return null

	var save_state: Dictionary = _get_save_state_for(enemy_id_str)
	var group_id: String = String(save_state.get("group_id", ""))
	if group_id == "":
		return null

	var role: String = String(save_state.get("role", ""))
	if role == "":
		role = "scavenger"

	var faction_id: String = String(save_state.get("faction_id", ""))
	if faction_id == "":
		var g_fallback: Dictionary = _domain_ports.bandit_group_memory().get_group(group_id)
		faction_id = String(g_fallback.get("faction_id", "bandits"))

	var home_pos: Vector2 = _get_home_pos(save_state)
	if home_pos == Vector2.ZERO and enemy_node is Node2D:
		home_pos = (enemy_node as Node2D).global_position

	var beh := BanditWorldBehavior.new()
	beh.setup({
		"home_pos": home_pos,
		"role": role,
		"group_id": group_id,
		"member_id": enemy_id_str,
		"cargo_count": int(save_state.get("cargo_count", 0)),
		"faction_id": faction_id,
	})
	var wb = save_state.get("world_behavior", {})
	if wb is Dictionary and not (wb as Dictionary).is_empty():
		beh.import_state(wb as Dictionary)
	else:
		beh._rng.seed = absi(int(save_state.get("seed", 0)) ^ hash(enemy_id_str))
		beh._idle_timer = beh._rng.randf_range(NpcWorldBehavior.IDLE_WAIT_MIN, NpcWorldBehavior.IDLE_WAIT_MAX)

	_behaviors[enemy_id_str] = beh
	_behavior_elapsed[enemy_id_str] = randf() * BanditTuningScript.behavior_tick_interval()
	Debug.log("bandit_ai", "[BanditBL] behavior created id=%s role=%s group=%s cargo_cap=%d home=%s" % [
		enemy_id_str, beh.role, beh.group_id, beh.cargo_capacity, str(beh.home_pos)])
	return beh


func _ensure_behaviors_for_active_enemies() -> void:
	for enemy_id in _npc_simulator.active_enemies:
		var enemy_id_str: String = String(enemy_id)
		if _behaviors.has(enemy_id_str):
			continue
		var node = _npc_simulator.get_enemy_node(enemy_id_str)
		if node == null or not node.has_method("is_world_behavior_eligible") \
				or not node.is_world_behavior_eligible():
			continue
		var beh: BanditWorldBehavior = _ensure_behavior_for_enemy(enemy_id_str, node)
		if beh == null:
			continue
		# Si el grupo tiene un assault pendiente (colocaciï¿½fÂ³n de estructura mientras no estaban spawneados)
		var assault_target: Vector2 = _domain_ports.bandit_group_memory().get_assault_target(beh.group_id)
		if assault_target.x >= 0.0:
			beh.enter_wall_assault(assault_target)
			_apply_structure_assault_focus(node)
			Debug.log("placement_react", "[BBL] pending assault applied on spawn id=%s group=%s target=%s" % [
				enemy_id_str, beh.group_id, str(assault_target)])


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
		_behavior_elapsed.erase(enemy_id)
		if NpcPathService.is_ready():
			NpcPathService.clear_agent(enemy_id)
		Debug.log("bandit_ai", "[BanditBL] behavior pruned id=%s" % enemy_id)


# ---------------------------------------------------------------------------
# Recognition bubbles Ã¢ï¿½,ï¿½ï¿½?ï¿½ feedback "te tienen fichado"
# ---------------------------------------------------------------------------

## Muestra una burbuja de reconocimiento si el NPC ve al jugador mientras
## la hostilidad es alta. Cooldown por NPC para evitar spam.
func _maybe_show_recognition_bubble(beh: BanditWorldBehavior,
		node: Node, node_pos: Vector2) -> void:
	if _bubble_manager == null or _player == null:
		return
	if beh.group_id == "":
		return
	# Solo si estï¿½fÂ¡ cazando activamente
	var g: Dictionary = _domain_ports.bandit_group_memory().get_group(beh.group_id)
	if String(g.get("current_group_intent", "")) != "hunting":
		return
	# Cooldown por NPC
	if _domain_ports.now() < beh.recognition_bubble_until:
		return
	# Solo si el jugador estï¿½fÂ¡ cerca
	if _player.global_position.distance_squared_to(node_pos) > RECOGNITION_RANGE_SQ:
		return
	# Nivel de hostilidad suficiente
	var faction_id: String = String(g.get("faction_id", ""))
	if faction_id == "":
		return
	var h_level: int = _domain_ports.faction_hostility().get_hostility_level(faction_id)
	if h_level < 3:
		return
	# Elegir el tier de frases mï¿½fÂ¡s alto que no supere el nivel actual
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
	beh.recognition_bubble_until = _domain_ports.now() + RECOGNITION_COOLDOWN
	Debug.log("bandit_ai", "[BBL] recognition bubble npc=%s h_level=%d tier=%d" % [
		beh.member_id, h_level, phrase_tier])


# ---------------------------------------------------------------------------
# Idle chat Ã¢ï¿½,ï¿½ï¿½?ï¿½ diï¿½fÂ¡logo ambiental de mundo
# ---------------------------------------------------------------------------

## Dispara una frase ambiental ocasional cuando el NPC estï¿½fÂ¡ ocioso o patrullando,
## sin que el jugador estï¿½fÂ© cerca. Crea sensaciï¿½fÂ³n de mundo vivo.
func _maybe_show_idle_chat(beh: BanditWorldBehavior,
		node: Node, node_pos: Vector2) -> void:
	if _bubble_manager == null:
		return
	# Cooldown por NPC (escalonado desde setup para que no hablen todos a la vez)
	if _domain_ports.now() < beh.idle_chat_until:
		return
	# Solo en estados ociosos Ã¢ï¿½,ï¿½ï¿½?ï¿½ no mientras caza, extorsiona, carga material ni vuelve al camp
	var state_ok: bool = beh.state == NpcWorldBehavior.State.IDLE_AT_HOME \
		or beh.state == NpcWorldBehavior.State.PATROL
	if not state_ok:
		return
	# No chatear si el grupo estï¿½fÂ¡ en intenciï¿½fÂ³n activa
	if beh.group_id != "":
		var g: Dictionary = _domain_ports.bandit_group_memory().get_group(beh.group_id)
		var intent: String = String(g.get("current_group_intent", ""))
		if intent == "hunting" or intent == "extorting" or intent == "raiding":
			return
	# No chatear si el jugador estï¿½fÂ¡ demasiado cerca (que no suene a reacciï¿½fÂ³n)
	if _player != null and is_instance_valid(_player):
		if _player.global_position.distance_squared_to(node_pos) < IDLE_CHAT_PLAYER_DIST_MIN_SQ:
			return
	# Baja probabilidad por tick para que no salga en cada tick elegible
	# (tick interval ~0.5s Ã¢ï¿½?ï¿½ï¿½?T ~1.5% chance por tick elegible Ã¢ï¿½?ï¿½ï¿½?T frase cada ~33s en ventana)
	if randf() > 0.015:
		beh.idle_chat_until = _domain_ports.now() + 2.0  # micro-cooldown para no re-tirar cada frame
		return
	var phrase: String = IDLE_CHAT_PHRASES[randi() % IDLE_CHAT_PHRASES.size()]
	_bubble_manager.show_actor_bubble(node as Node2D, phrase, 3.5)
	# Cooldown aleatorio para que cada NPC hable a su propio ritmo
	beh.idle_chat_until = _domain_ports.now() + randf_range(IDLE_CHAT_COOLDOWN_MIN, IDLE_CHAT_COOLDOWN_MAX)


func _get_behavior(enemy_id: String) -> BanditWorldBehavior:
	return _behaviors.get(enemy_id, null) as BanditWorldBehavior


# ---------------------------------------------------------------------------
# Territory reaction Ã¢ï¿½,ï¿½ï¿½?ï¿½ NPC mï¿½fÂ¡s cercano reacciona cuando el jugador invade
# ---------------------------------------------------------------------------

## Bridge pequeï¿½fÂ±o para que world.gd dispare reacciones sin cargar polï¿½fÂ­tica social.
func notify_territory_reaction(_faction_id: String, group_id: String,
		intrusion_pos: Vector2, kind: String) -> void:
	if _territory_response == null:
		return
	_territory_response.notify_reaction(group_id, intrusion_pos, kind)


## Envï¿½fÂ­a directamente N miembros del grupo a atacar target_pos.
## Funciona tanto en lite-mode (BanditWorldBehavior en _behaviors) como en
## modo activo (WorldBehavior child node). Retorna cuï¿½fÂ¡ntos fueron redirigidos.
func dispatch_group_to_target(group_id: String, target_pos: Vector2, squad_size: int = -1) -> int:
	if _npc_simulator == null:
		return 0
	# Colectar miembros de la oleada de ataque (capeado al squad_size real)
	var g_total: int = (_domain_ports.bandit_group_memory().get_group(group_id).get("member_ids", []) as Array).size()
	var wave_cap: int = squad_size if squad_size > 0 else g_total
	var member_ids: Array[String] = _collect_live_structure_dispatch_member_ids(group_id, target_pos, wave_cap)
	if member_ids.is_empty():
		_domain_ports.bandit_group_memory().set_assault_target(group_id, target_pos)
		if _can_emit_dispatch_log(group_id, 0.8):
			Debug.log("placement_react", "[BBL] dispatch queued (no spawneados) group=%s target=%s" % [
				group_id, str(target_pos)])
		return 0

	# Colectar overflow: miembros del grupo con nodo válido que no están en la oleada
	var overflow_ids: Array[String] = []
	if member_ids.size() < g_total:
		overflow_ids = _collect_overflow_ids(group_id, member_ids)
	# Los overflow van a una zona de espera detrás de la pared para no apiñarse
	if not overflow_ids.is_empty():
		_redirect_overflow_to_staging(group_id, overflow_ids, target_pos)

	var target_pool: Array[Vector2] = _build_structure_target_pool_cached(group_id, target_pos)
	var claimed_targets: Array[Vector2] = []
	var team_targets: Dictionary = _load_group_sticky_team_targets(group_id)
	var immediate_count: int = mini(STRUCTURE_DISPATCH_SYNC_BUDGET, member_ids.size())
	var immediate_redirected: int = _dispatch_structure_members_slice(
		group_id,
		member_ids,
		0,
		immediate_count,
		target_pos,
		target_pool,
		claimed_targets,
		team_targets
	)

	if immediate_count < member_ids.size():
		_enqueue_pending_structure_dispatch(
			group_id,
			target_pos,
			member_ids,
			immediate_count,
			target_pool,
			claimed_targets,
			team_targets
		)
		if _can_emit_dispatch_log(group_id, 0.8):
			Debug.log("placement_react", "[BBL] dispatch deferred group=%s anchor=%s now=%d later=%d budget=%d" % [
				group_id,
				str(target_pos),
				immediate_redirected,
				member_ids.size() - immediate_count,
				STRUCTURE_DISPATCH_FRAME_BUDGET,
			])

	_domain_ports.bandit_group_memory().clear_assault_target(group_id)
	_save_group_sticky_team_targets(group_id, team_targets)
	var requested: String = "ALL" if squad_size <= 0 else str(squad_size)
	var team_count: int = int(ceili(float(member_ids.size()) / float(maxi(1, STRUCTURE_TARGET_TEAM_SIZE))))
	if _can_emit_dispatch_log(group_id, 0.8):
		Debug.log("placement_react", "[BBL] dispatch group=%s anchor=%s redirected=%d/%s teams=%d unique_targets=%d" % [
			group_id,
			str(target_pos),
			member_ids.size(),
			requested,
			team_count,
			_count_unique_structure_targets(claimed_targets),
		])
	return member_ids.size()


func _process_pending_structure_dispatches() -> void:
	if _pending_structure_dispatches.is_empty():
		return
	var budget: int = STRUCTURE_DISPATCH_FRAME_BUDGET
	var idx: int = 0
	while idx < _pending_structure_dispatches.size() and budget > 0:
		var job: Dictionary = _pending_structure_dispatches[idx] as Dictionary
		var gid: String = String(job.get("group_id", ""))
		if gid == "" or _domain_ports.bandit_group_memory().get_group(gid).is_empty():
			_save_group_sticky_team_targets(gid, {})
			_pending_structure_dispatches.remove_at(idx)
			continue
		var member_ids: Array = job.get("member_ids", []) as Array
		var next_idx: int = int(job.get("next_idx", 0))
		var anchor: Vector2 = job.get("target_pos", INVALID_STRUCTURE_TARGET) as Vector2
		var target_pool: Array = job.get("target_pool", []) as Array
		var claimed_targets: Array = job.get("claimed_targets", []) as Array
		var team_targets: Dictionary = job.get("team_targets", {}) as Dictionary
		if next_idx >= member_ids.size():
			_pending_structure_dispatches.remove_at(idx)
			continue
		var chunk: int = mini(budget, member_ids.size() - next_idx)
		_dispatch_structure_members_slice(
			gid,
			member_ids,
			next_idx,
			chunk,
			anchor,
			target_pool,
			claimed_targets,
			team_targets
		)
		next_idx += chunk
		budget -= chunk
		job["next_idx"] = next_idx
		job["claimed_targets"] = claimed_targets
		job["team_targets"] = team_targets
		_save_group_sticky_team_targets(gid, team_targets)
		_pending_structure_dispatches[idx] = job
		if next_idx >= member_ids.size():
			if _can_emit_dispatch_log(gid, 0.8):
				Debug.log("placement_react", "[BBL] deferred dispatch finished group=%s total=%d" % [
					String(job.get("group_id", "")), member_ids.size()])
			_save_group_sticky_team_targets(gid, team_targets)
			_pending_structure_dispatches.remove_at(idx)
			continue
		idx += 1


func _dispatch_structure_members_slice(group_id: String, member_ids: Array, start_idx: int,
		count: int, anchor_pos: Vector2, target_pool: Array,
		claimed_targets: Array, team_targets: Dictionary) -> int:
	if _npc_simulator == null:
		return 0
	if count <= 0:
		return 0
	var redirected: int = 0
	var end_idx: int = mini(start_idx + count, member_ids.size())
	var validated_team_keys: Dictionary = {}
	for idx in range(start_idx, end_idx):
		var member_id: String = String(member_ids[idx])
		var node = _npc_simulator.get_enemy_node(member_id)
		if node == null:
			continue
		var member_pos: Vector2 = (node as Node2D).global_position if node is Node2D else anchor_pos
		var team_key: String = str(int(floor(float(idx) / float(maxi(1, STRUCTURE_TARGET_TEAM_SIZE)))))
		var member_target: Vector2 = team_targets.get(team_key, INVALID_STRUCTURE_TARGET) as Vector2
		var reselect: bool = not _is_valid_structure_target(member_target)
		if not reselect and not validated_team_keys.has(team_key):
			reselect = not _is_structure_target_still_valid(member_target)
			validated_team_keys[team_key] = true
		if reselect:
			member_target = _pick_member_target_from_pool(member_pos, anchor_pos, target_pool, claimed_targets)
			team_targets[team_key] = member_target
			claimed_targets.append(member_target)
		_apply_structure_assault_focus(node)
		var beh_force: BanditWorldBehavior = _ensure_behavior_for_enemy(member_id, node)
		if beh_force != null and beh_force.group_id == group_id:
			beh_force.enter_wall_assault(member_target)
			redirected += 1
			continue
	return redirected


func _pick_member_target_from_pool(member_pos: Vector2, anchor_pos: Vector2,
		target_pool: Array, claimed_targets: Array) -> Vector2:
	if target_pool.is_empty():
		return _resolve_member_assault_target(member_pos, anchor_pos, claimed_targets)
	var fallback_best: Vector2 = target_pool[0]
	var fallback_best_dsq: float = member_pos.distance_squared_to(fallback_best)
	var best_unclaimed: Vector2 = INVALID_STRUCTURE_TARGET
	var best_unclaimed_dsq: float = INF
	for candidate in target_pool:
		var dsq: float = member_pos.distance_squared_to(candidate)
		if dsq < fallback_best_dsq:
			fallback_best_dsq = dsq
			fallback_best = candidate
		var crowded: bool = false
		for claimed in claimed_targets:
			if candidate.distance_squared_to(claimed) <= STRUCTURE_MEMBER_TARGET_SEPARATION_SQ:
				crowded = true
				break
		if crowded:
			continue
		if dsq < best_unclaimed_dsq:
			best_unclaimed_dsq = dsq
			best_unclaimed = candidate
	if _is_valid_structure_target(best_unclaimed):
		return best_unclaimed
	return fallback_best


func _build_structure_target_pool_cached(group_id: String, anchor_pos: Vector2) -> Array[Vector2]:
	if group_id == "":
		return _build_structure_target_pool(anchor_pos)
	var key: String = _get_target_pool_cache_key(anchor_pos)
	var now: float = _domain_ports.now()
	var entry: Dictionary = _group_target_pool_cache.get(group_id, {}) as Dictionary
	if not entry.is_empty() \
			and now <= float(entry.get("until", 0.0)) \
			and String(entry.get("key", "")) == key:
		var cached_pool: Array = entry.get("pool", []) as Array
		if not cached_pool.is_empty():
			var out_cached: Array[Vector2] = []
			for raw_pos in cached_pool:
				if raw_pos is Vector2:
					out_cached.append(raw_pos as Vector2)
			if not out_cached.is_empty():
				return out_cached
	var built: Array[Vector2] = _build_structure_target_pool(anchor_pos)
	_group_target_pool_cache[group_id] = {
		"key": key,
		"pool": built.duplicate(true),
		"until": now + STRUCTURE_TARGET_POOL_CACHE_TTL,
	}
	return built


func _build_structure_target_pool(anchor_pos: Vector2) -> Array[Vector2]:
	var pool: Array[Vector2] = []
	# Prioridad: primero distribuir puntos de pared reales para evitar
	# convergencia artificial en una sola punta/ancla.
	_append_scored_wall_samples(pool, _collect_wall_samples(anchor_pos), anchor_pos)
	for center in _build_structure_query_centers(anchor_pos, anchor_pos):
		# Los walls ya vienen del sampler dedicado; aquí solo sumar
		# placeables/contenedores para evitar queries redundantes de pared.
		_append_structure_candidates_for_center(pool, center, STRUCTURE_MEMBER_QUERY_RADIUS, false)
		if pool.size() >= STRUCTURE_MEMBER_CANDIDATE_LIMIT:
			break
	if pool.is_empty():
		pool.append(anchor_pos)
	return pool


func _collect_wall_samples(anchor_pos: Vector2) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if _find_wall_samples_cb.is_valid():
		var sampled: Variant = _find_wall_samples_cb.call(
			anchor_pos,
			STRUCTURE_MEMBER_QUERY_RADIUS,
			STRUCTURE_WALL_SAMPLE_MAX_POINTS,
			48.0
		)
		if sampled is Array:
			for raw_pos in sampled as Array:
				if not (raw_pos is Vector2):
					continue
				var pos: Vector2 = raw_pos as Vector2
				if not _is_valid_structure_target(pos):
					continue
				out.append(pos)
	if not out.is_empty():
		return out
	if not _find_wall_cb.is_valid():
		return out
	for gy in range(-STRUCTURE_WALL_SAMPLE_GRID_HALF_STEPS, STRUCTURE_WALL_SAMPLE_GRID_HALF_STEPS + 1):
		for gx in range(-STRUCTURE_WALL_SAMPLE_GRID_HALF_STEPS, STRUCTURE_WALL_SAMPLE_GRID_HALF_STEPS + 1):
			var center: Vector2 = anchor_pos + Vector2(float(gx), float(gy)) * STRUCTURE_WALL_SAMPLE_STEP
			var wall_pos: Vector2 = _find_wall_cb.call(center, STRUCTURE_MEMBER_QUERY_RADIUS) as Vector2
			if not _is_valid_structure_target(wall_pos):
				continue
			var duplicate: bool = false
			for existing in out:
				if existing.distance_squared_to(wall_pos) <= STRUCTURE_POOL_SAMPLE_MIN_SEPARATION_SQ:
					duplicate = true
					break
			if duplicate:
				continue
			out.append(wall_pos)
	return out


func _append_scored_wall_samples(pool: Array[Vector2], wall_samples: Array[Vector2], anchor_pos: Vector2) -> void:
	if wall_samples.is_empty():
		return
	var rows: Array[Dictionary] = []
	for i in range(wall_samples.size()):
		var pos: Vector2 = wall_samples[i]
		var support: int = 0
		for j in range(wall_samples.size()):
			if i == j:
				continue
			if pos.distance_squared_to(wall_samples[j]) <= STRUCTURE_WALL_SUPPORT_RADIUS_SQ:
				support += 1
		rows.append({
			"pos": pos,
			"support": support,
			"anchor_dsq": anchor_pos.distance_squared_to(pos),
		})
	_sort_wall_rows_by_priority(rows)

	# Colapsa muestreo denso en celdas para repartir objetivos por segmentos,
	# no por pixeles contiguos en una misma punta.
	var clustered: Dictionary = {}
	for row in rows:
		var row_pos: Vector2 = (row as Dictionary).get("pos", INVALID_STRUCTURE_TARGET) as Vector2
		if not _is_valid_structure_target(row_pos):
			continue
		var cx: int = int(floor(row_pos.x / STRUCTURE_WALL_SAMPLE_STEP))
		var cy: int = int(floor(row_pos.y / STRUCTURE_WALL_SAMPLE_STEP))
		var key: String = "%d:%d" % [cx, cy]
		if not clustered.has(key):
			clustered[key] = row
			continue
		var prev: Dictionary = clustered[key] as Dictionary
		var prev_support: int = int(prev.get("support", -1))
		var row_support: int = int((row as Dictionary).get("support", -1))
		if row_support > prev_support:
			clustered[key] = row
			continue
		if row_support == prev_support:
			var prev_dsq: float = float(prev.get("anchor_dsq", INF))
			var row_dsq: float = float((row as Dictionary).get("anchor_dsq", INF))
			if row_dsq < prev_dsq:
				clustered[key] = row

	var clustered_rows: Array[Dictionary] = []
	for raw_key in clustered.keys():
		var row_any: Variant = clustered.get(raw_key)
		if row_any is Dictionary:
			clustered_rows.append(row_any as Dictionary)
	_sort_wall_rows_by_priority(clustered_rows)

	for row in clustered_rows:
		if pool.size() >= STRUCTURE_MEMBER_CANDIDATE_LIMIT:
			return
		var pos: Vector2 = (row as Dictionary).get("pos", INVALID_STRUCTURE_TARGET) as Vector2
		if not _is_valid_structure_target(pos):
			continue
		var duplicate: bool = false
		for existing in pool:
			if existing.distance_squared_to(pos) <= STRUCTURE_POOL_SAMPLE_MIN_SEPARATION_SQ:
				duplicate = true
				break
		if duplicate:
			continue
		pool.append(pos)


func _sort_wall_rows_by_priority(rows: Array[Dictionary]) -> void:
	for i in range(1, rows.size()):
		var key: Dictionary = rows[i]
		var key_support: int = int(key.get("support", 0))
		var key_dsq: float = float(key.get("anchor_dsq", INF))
		var j: int = i - 1
		while j >= 0:
			var cur: Dictionary = rows[j]
			var cur_support: int = int(cur.get("support", 0))
			var cur_dsq: float = float(cur.get("anchor_dsq", INF))
			var should_shift: bool = false
			if key_support > cur_support:
				should_shift = true
			elif key_support == cur_support and key_dsq < cur_dsq:
				should_shift = true
			if not should_shift:
				break
			rows[j + 1] = rows[j]
			j -= 1
		rows[j + 1] = key


func _collect_live_structure_dispatch_member_ids(group_id: String, target_pos: Vector2,
		cap: int) -> Array[String]:
	var rows: Array[Dictionary] = []
	var seen: Dictionary = {}
	for eid in _behaviors:
		var beh: BanditWorldBehavior = _behaviors[eid]
		if beh.group_id != group_id:
			continue
		var eid_str: String = String(eid)
		if seen.has(eid_str):
			continue
		var node = _npc_simulator.get_enemy_node(eid_str)
		if node == null or not (node is Node2D):
			continue
		seen[eid_str] = true
		rows.append({
			"member_id": eid_str,
			"anchor_dsq": (node as Node2D).global_position.distance_squared_to(target_pos),
		})
	if rows.size() < cap:
		var g: Dictionary = _domain_ports.bandit_group_memory().get_group(group_id)
		for mid in g.get("member_ids", []):
			var mid_str: String = String(mid)
			if seen.has(mid_str):
				continue
			var node = _npc_simulator.get_enemy_node(mid_str)
			if node == null or not (node is Node2D):
				continue
			seen[mid_str] = true
			rows.append({
				"member_id": mid_str,
				"anchor_dsq": (node as Node2D).global_position.distance_squared_to(target_pos),
			})
	_sort_dispatch_rows_by_anchor_dsq(rows)
	var out: Array[String] = []
	for row in rows:
		if out.size() >= cap:
			break
		out.append(String((row as Dictionary).get("member_id", "")))
	return out


## Retorna los IDs del grupo con nodo válido que no están en exclude_ids.
func _collect_overflow_ids(group_id: String, exclude_ids: Array[String]) -> Array[String]:
	var exclude: Dictionary = {}
	for eid in exclude_ids:
		exclude[eid] = true
	var out: Array[String] = []
	var g: Dictionary = _domain_ports.bandit_group_memory().get_group(group_id)
	for mid in g.get("member_ids", []):
		var mid_str: String = String(mid)
		if exclude.has(mid_str):
			continue
		var node = _npc_simulator.get_enemy_node(mid_str)
		if node == null or not (node is Node2D):
			continue
		out.append(mid_str)
	return out


func _sort_dispatch_rows_by_anchor_dsq(rows: Array[Dictionary]) -> void:
	for i in range(1, rows.size()):
		var key: Dictionary = rows[i]
		var key_dsq: float = float(key.get("anchor_dsq", INF))
		var j: int = i - 1
		while j >= 0 and float(rows[j].get("anchor_dsq", INF)) > key_dsq:
			rows[j + 1] = rows[j]
			j -= 1
		rows[j + 1] = key


func _enqueue_pending_structure_dispatch(group_id: String, target_pos: Vector2,
		member_ids: Array[String], start_idx: int, target_pool: Array[Vector2],
		claimed_targets: Array[Vector2], team_targets: Dictionary) -> void:
	for i in range(_pending_structure_dispatches.size() - 1, -1, -1):
		var existing: Dictionary = _pending_structure_dispatches[i] as Dictionary
		if String(existing.get("group_id", "")) == group_id:
			_pending_structure_dispatches.remove_at(i)
	if _pending_structure_dispatches.size() >= STRUCTURE_DISPATCH_MAX_PENDING_JOBS:
		_pending_structure_dispatches.remove_at(0)
	_pending_structure_dispatches.append({
		"group_id": group_id,
		"target_pos": target_pos,
		"member_ids": member_ids,
		"next_idx": start_idx,
		"target_pool": target_pool,
		"claimed_targets": claimed_targets,
		"team_targets": team_targets,
	})


func _get_target_pool_cache_key(anchor_pos: Vector2) -> String:
	var q: float = maxf(1.0, STRUCTURE_TARGET_CACHE_POS_QUANTUM)
	var qx: int = int(floor(anchor_pos.x / q))
	var qy: int = int(floor(anchor_pos.y / q))
	return "%d:%d" % [qx, qy]


func _get_target_valid_cache_key(target_pos: Vector2) -> String:
	var q: float = maxf(1.0, STRUCTURE_TARGET_CACHE_POS_QUANTUM)
	var qx: int = int(floor(target_pos.x / q))
	var qy: int = int(floor(target_pos.y / q))
	return "%d:%d" % [qx, qy]


func _prune_structure_target_caches() -> void:
	var now: float = _domain_ports.now()
	if not _group_target_pool_cache.is_empty():
		for gid in _group_target_pool_cache.keys():
			var entry: Dictionary = _group_target_pool_cache.get(gid, {}) as Dictionary
			if entry.is_empty() or now > float(entry.get("until", 0.0)):
				_group_target_pool_cache.erase(gid)
	if not _structure_target_valid_cache.is_empty():
		for key in _structure_target_valid_cache.keys():
			var entry: Dictionary = _structure_target_valid_cache.get(key, {}) as Dictionary
			if entry.is_empty() or now > float(entry.get("until", 0.0)):
				_structure_target_valid_cache.erase(key)
	if not _dispatch_log_next_at.is_empty():
		for gid in _dispatch_log_next_at.keys():
			if now > float(_dispatch_log_next_at.get(gid, 0.0)):
				_dispatch_log_next_at.erase(gid)


func _can_emit_dispatch_log(group_id: String, cooldown: float = 1.0) -> bool:
	if group_id == "":
		return false
	var now: float = _domain_ports.now()
	var next_at: float = float(_dispatch_log_next_at.get(group_id, 0.0))
	if now < next_at:
		return false
	_dispatch_log_next_at[group_id] = now + maxf(0.1, cooldown)
	return true


func _load_group_sticky_team_targets(group_id: String) -> Dictionary:
	if group_id == "":
		return {}
	var entry: Dictionary = _group_team_target_cache.get(group_id, {}) as Dictionary
	if entry.is_empty():
		return {}
	var now: float = _domain_ports.now()
	if now > float(entry.get("until", 0.0)):
		_group_team_target_cache.erase(group_id)
		return {}
	var raw_targets: Dictionary = entry.get("targets", {}) as Dictionary
	if raw_targets.is_empty():
		_group_team_target_cache.erase(group_id)
		return {}
	var valid_targets: Dictionary = {}
	for raw_key in raw_targets.keys():
		var key: String = String(raw_key)
		var pos: Variant = raw_targets.get(raw_key, INVALID_STRUCTURE_TARGET)
		if not (pos is Vector2):
			continue
		var target_pos: Vector2 = pos as Vector2
		if not _is_structure_target_still_valid(target_pos):
			continue
		valid_targets[key] = target_pos
	if valid_targets.is_empty():
		_group_team_target_cache.erase(group_id)
		return {}
	return valid_targets


func _save_group_sticky_team_targets(group_id: String, team_targets: Dictionary) -> void:
	if group_id == "":
		return
	if team_targets.is_empty():
		_group_team_target_cache.erase(group_id)
		return
	_group_team_target_cache[group_id] = {
		"targets": team_targets.duplicate(true),
		"until": _domain_ports.now() + STRUCTURE_STICKY_TEAM_TARGET_TTL,
	}


func _is_structure_target_still_valid(target_pos: Vector2) -> bool:
	if not _is_valid_structure_target(target_pos):
		return false
	var cache_key: String = _get_target_valid_cache_key(target_pos)
	var now: float = _domain_ports.now()
	var cached: Dictionary = _structure_target_valid_cache.get(cache_key, {}) as Dictionary
	if not cached.is_empty() and now <= float(cached.get("until", 0.0)):
		return bool(cached.get("valid", false))
	var structure_radius: float = STRUCTURE_TARGET_VALIDATION_RADIUS
	var structure_radius_sq: float = structure_radius * structure_radius
	var structure_finders: Array = [_find_storage_cb, _find_placeable_cb, _find_workbench_cb]
	for raw_finder in structure_finders:
		var finder: Callable = raw_finder as Callable
		if not finder.is_valid():
			continue
		var near: Vector2 = finder.call(target_pos, structure_radius) as Vector2
		if not _is_valid_structure_target(near):
			continue
		if near.distance_squared_to(target_pos) <= structure_radius_sq:
			_structure_target_valid_cache[cache_key] = {
				"valid": true,
				"until": now + STRUCTURE_TARGET_VALID_CACHE_TTL,
			}
			return true
	if _find_wall_cb.is_valid():
		var wall_radius: float = STRUCTURE_WALL_TARGET_VALIDATION_RADIUS
		var wall_radius_sq: float = wall_radius * wall_radius
		var near_wall: Vector2 = _find_wall_cb.call(target_pos, wall_radius) as Vector2
		if _is_valid_structure_target(near_wall) and near_wall.distance_squared_to(target_pos) <= wall_radius_sq:
			_structure_target_valid_cache[cache_key] = {
				"valid": true,
				"until": now + STRUCTURE_TARGET_VALID_CACHE_TTL,
			}
			return true
	_structure_target_valid_cache[cache_key] = {
		"valid": false,
		"until": now + STRUCTURE_TARGET_VALID_CACHE_TTL,
	}
	return false


func _resolve_member_assault_target(member_pos: Vector2, anchor_pos: Vector2,
		claimed_targets: Array) -> Vector2:
	var query_centers: Array[Vector2] = _build_structure_query_centers(member_pos, anchor_pos)
	var candidates: Array[Vector2] = []
	for center in query_centers:
		_append_structure_candidates_for_center(candidates, center, STRUCTURE_MEMBER_QUERY_RADIUS)
		if candidates.size() >= STRUCTURE_MEMBER_CANDIDATE_LIMIT:
			break
	if candidates.is_empty():
		return anchor_pos
	var fallback_best: Vector2 = candidates[0]
	var fallback_best_dsq: float = member_pos.distance_squared_to(fallback_best)
	var best_unclaimed: Vector2 = INVALID_STRUCTURE_TARGET
	var best_unclaimed_dsq: float = INF
	for candidate in candidates:
		var dsq: float = member_pos.distance_squared_to(candidate)
		if dsq < fallback_best_dsq:
			fallback_best_dsq = dsq
			fallback_best = candidate
		var crowded: bool = false
		for claimed in claimed_targets:
			if candidate.distance_squared_to(claimed) <= STRUCTURE_MEMBER_TARGET_SEPARATION_SQ:
				crowded = true
				break
		if crowded:
			continue
		if dsq < best_unclaimed_dsq:
			best_unclaimed_dsq = dsq
			best_unclaimed = candidate
	if _is_valid_structure_target(best_unclaimed):
		return best_unclaimed
	return fallback_best


func _append_structure_candidates_for_center(out: Array[Vector2], center: Vector2, radius: float,
		include_walls: bool = true) -> void:
	if out.size() >= STRUCTURE_MEMBER_CANDIDATE_LIMIT:
		return
	_try_append_structure_candidate(out, _find_storage_cb, center, radius)
	_try_append_structure_candidate(out, _find_placeable_cb, center, radius)
	_try_append_structure_candidate(out, _find_workbench_cb, center, radius)
	if include_walls:
		_try_append_structure_candidate(out, _find_wall_cb, center, radius)


func _build_structure_query_centers(member_pos: Vector2, anchor_pos: Vector2) -> Array[Vector2]:
	var centers: Array[Vector2] = [member_pos]
	if member_pos.distance_squared_to(anchor_pos) > 1.0:
		centers.append(anchor_pos)
	var ring_dirs: Array[Vector2] = [
		Vector2.RIGHT,
		Vector2.LEFT,
		Vector2.UP,
		Vector2.DOWN,
		Vector2(1.0, 1.0).normalized(),
		Vector2(-1.0, 1.0).normalized(),
		Vector2(1.0, -1.0).normalized(),
		Vector2(-1.0, -1.0).normalized(),
	]
	for dir in ring_dirs:
		centers.append(member_pos + dir * STRUCTURE_MEMBER_QUERY_RING_RADIUS)
		if member_pos.distance_squared_to(anchor_pos) > 1.0:
			centers.append(anchor_pos + dir * STRUCTURE_MEMBER_QUERY_RING_RADIUS)
	return centers


func _try_append_structure_candidate(out: Array[Vector2], finder: Callable, center: Vector2,
		radius: float) -> void:
	if out.size() >= STRUCTURE_MEMBER_CANDIDATE_LIMIT:
		return
	if not finder.is_valid():
		return
	var pos: Vector2 = finder.call(center, radius) as Vector2
	if not _is_valid_structure_target(pos):
		return
	for existing in out:
		if existing.distance_squared_to(pos) <= 4.0:
			return
	out.append(pos)


func _is_valid_structure_target(pos: Vector2) -> bool:
	return pos.is_finite() and not pos.is_equal_approx(INVALID_STRUCTURE_TARGET)


func _count_unique_structure_targets(targets: Array[Vector2]) -> int:
	var unique: Array[Vector2] = []
	for pos in targets:
		var merged: bool = false
		for existing in unique:
			if existing.distance_squared_to(pos) <= STRUCTURE_MEMBER_TARGET_SEPARATION_SQ:
				merged = true
				break
		if not merged:
			unique.append(pos)
	return unique.size()


func _apply_structure_assault_focus(enemy_node: Node) -> void:
	if enemy_node == null or not is_instance_valid(enemy_node):
		return
	var ai = enemy_node.get_node_or_null("AIComponent")
	if ai == null:
		return
	if ai.has_method("wake_now"):
		ai.call("wake_now")
	if ai.has_method("focus_on_structure_for"):
		ai.call("focus_on_structure_for", STRUCTURE_ASSAULT_FOCUS_SECONDS)


# ---------------------------------------------------------------------------
# Deposit pos distribution Ã¢ï¿½,ï¿½ï¿½?ï¿½ callback usado por BanditCampStashSystem
# ---------------------------------------------------------------------------

## Propaga la posiciï¿½fÂ³n del barril a todos los behaviors del grupo.
## Cada NPC recibe un slot personal (ï¿½fÂ¡ngulo determinista por member_id).
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
# Overflow staging — miembros no en la oleada de asalto esperan atrás
# ---------------------------------------------------------------------------

## Redirige miembros overflow a una zona de espera detrás de la pared.
## Esto evita que todos se amontonen en la misma baldosa mientras atacan otros.
func _redirect_overflow_to_staging(group_id: String, overflow_ids: Array[String],
		target_pos: Vector2) -> void:
	# Resolver nodos una sola vez para evitar doble get_enemy_node (aquí + en staging center)
	var resolved: Dictionary = {}
	for mid in overflow_ids:
		var beh: BanditWorldBehavior = _behaviors.get(mid) as BanditWorldBehavior
		if beh != null and beh.group_id == group_id:
			resolved[mid] = null  # ruta beh — no necesita nodo
		else:
			resolved[mid] = _npc_simulator.get_enemy_node(mid)

	var staging_center: Vector2 = _compute_assault_staging_center(resolved, target_pos)
	for idx in range(overflow_ids.size()):
		var mid: String = overflow_ids[idx]
		var staging_pos: Vector2 = _jitter_staging_pos(staging_center, mid, idx)
		var beh: BanditWorldBehavior = _behaviors.get(mid) as BanditWorldBehavior
		if beh != null and beh.group_id == group_id:
			beh.enter_wall_assault(staging_pos)
			continue
		var node: Node = resolved.get(mid, null)
		if node == null:
			continue
		var forced_beh: BanditWorldBehavior = _ensure_behavior_for_enemy(mid, node)
		if forced_beh != null and forced_beh.group_id == group_id:
			forced_beh.enter_wall_assault(staging_pos)


## Centro de la zona de espera: STRUCTURE_ASSAULT_STANDBY_DIST px en la dirección
## "grupo → pared" invertida, para que esperen detrás de la línea de ataque.
func _compute_assault_staging_center(resolved: Dictionary, target_pos: Vector2) -> Vector2:
	var sum: Vector2 = Vector2.ZERO
	var count: int = 0
	for mid in resolved:
		var node = resolved[mid]
		if node is Node2D:
			sum += (node as Node2D).global_position
			count += 1
	if count == 0:
		return target_pos + Vector2(0.0, -STRUCTURE_ASSAULT_STANDBY_DIST)
	var avg: Vector2 = sum / float(count)
	var away: Vector2 = avg - target_pos
	if away.length_squared() < 4.0:
		away = Vector2(0.0, -1.0)
	else:
		away = away.normalized()
	return target_pos + away * STRUCTURE_ASSAULT_STANDBY_DIST


## Desplazamiento por miembro para que no se apilen en el mismo punto de espera.
func _jitter_staging_pos(center: Vector2, member_id: String, idx: int) -> Vector2:
	var h: int = absi(hash(member_id))
	var angle: float = float((h + idx * 7) % 24) * (TAU / 24.0)
	var radius: float = float(h % 32) + 16.0
	return center + Vector2(cos(angle), sin(angle)) * radius


# ---------------------------------------------------------------------------
# Save-state helpers
# ---------------------------------------------------------------------------

func _get_save_state_for(enemy_id: String) -> Dictionary:
	var chunk_key: String = _npc_simulator.get_enemy_chunk_key(enemy_id)
	if chunk_key == "":
		return {}
	var chunk_states: Dictionary = _domain_ports.world_save().enemy_state_by_chunk.get(chunk_key, {})
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


func _prune_behavior_timers() -> void:
	for enemy_id in _behavior_elapsed.keys():
		if not _behaviors.has(enemy_id):
			_behavior_elapsed.erase(enemy_id)


func _get_behavior_tick_interval(beh: BanditWorldBehavior, node: Node, node_pos: Vector2) -> float:
	var distance_to_player: float = INF
	if _player != null and is_instance_valid(_player):
		distance_to_player = node_pos.distance_to(_player.global_position)
	var group_intent: String = "idle"
	if beh.group_id != "":
		group_intent = String(_domain_ports.bandit_group_memory().get_group(beh.group_id).get("current_group_intent", "idle"))
	var ai_state_name: String = ""
	if beh.state >= 0 and beh.state < NpcWorldBehavior.State.size():
		ai_state_name = NpcWorldBehavior.State.keys()[beh.state]
	var runtime_signals: Dictionary = _get_runtime_lod_signals(node)
	var lod_debug: Dictionary = SimulationLODPolicyScript.get_behavior_tick_debug({
		"base_interval": BanditTuningScript.behavior_tick_interval(),
		"distance_to_player": distance_to_player,
		"intent": group_intent,
		"role": beh.role,
		"state_name": ai_state_name,
		"has_cargo": beh.cargo_count > 0,
		"is_visible": (node as CanvasItem).is_visible_in_tree() if node is CanvasItem else false,
		"is_sleeping": bool(node.has_method("is_sleeping") and node.is_sleeping()),
		"in_combat": bool(runtime_signals.get("is_in_direct_combat", false)),
		"recently_engaged": bool(runtime_signals.get("was_recently_engaged", false)),
	})
	_record_npc_lod_debug(beh, node, lod_debug, runtime_signals)
	return float(lod_debug.get("interval", BanditTuningScript.behavior_tick_interval()))


func _get_runtime_lod_signals(node: Node) -> Dictionary:
	if node == null or not is_instance_valid(node):
		return CombatStateServiceScript.read_actor_state(node)
	var ai_comp = node.get("ai_component")
	var current_state: int = int(ai_comp.get("current_state")) if ai_comp != null else -1
	var current_target = ai_comp.get_current_target() if ai_comp != null and ai_comp.has_method("get_current_target") else null
	var has_active_target: bool = current_target != null and is_instance_valid(current_target)
	var _let: Variant = node.get("last_engaged_time")
	return CombatStateServiceScript.update_actor_state(node, {
		"current_state": current_state,
		"has_active_target": has_active_target,
		"is_world_behavior_eligible": bool(node.has_method("is_world_behavior_eligible") and node.is_world_behavior_eligible()),
		"last_engaged_time": float(_let) if _let != null else 0.0,
	})


func _record_npc_lod_debug(beh: BanditWorldBehavior, node: Node, lod_debug: Dictionary, runtime_signals: Dictionary) -> void:
	var bucket: String = String(lod_debug.get("bucket", "medium"))
	_lod_debug_npc_counts[bucket] = int(_lod_debug_npc_counts.get(bucket, 0)) + 1
	_lod_debug_last_npc[beh.member_id] = {
		"group_id": beh.group_id,
		"role": beh.role,
		"state": NpcWorldBehavior.State.keys()[beh.state] if beh.state >= 0 and beh.state < NpcWorldBehavior.State.size() else "",
		"interval": float(lod_debug.get("interval", BanditTuningScript.behavior_tick_interval())),
		"bucket": bucket,
		"dominant_reason": String(lod_debug.get("dominant_reason", "baseline")),
		"is_in_direct_combat": bool(runtime_signals.get("is_in_direct_combat", false)),
		"was_recently_engaged": bool(runtime_signals.get("was_recently_engaged", false)),
		"is_runtime_busy_but_not_combat": bool(runtime_signals.get("is_runtime_busy_but_not_combat", false)),
		"is_world_behavior_eligible": bool(node.has_method("is_world_behavior_eligible") and node.is_world_behavior_eligible()),
	}
	if _is_lod_debug_logging_enabled():
		Debug.log("bandit_lod", "[BanditLOD][npc] id=%s group=%s interval=%.2f bucket=%s reason=%s combat=%s engaged=%s busy=%s" % [
			beh.member_id,
			beh.group_id,
			float(lod_debug.get("interval", 0.0)),
			bucket,
			String(lod_debug.get("dominant_reason", "baseline")),
			str(bool(runtime_signals.get("is_in_direct_combat", false))),
			str(bool(runtime_signals.get("was_recently_engaged", false))),
			str(bool(runtime_signals.get("is_runtime_busy_but_not_combat", false))),
		])


func get_lod_debug_snapshot() -> Dictionary:
	return {
		"npc_counts": _lod_debug_npc_counts.duplicate(true),
		"npc_intervals": _lod_debug_last_npc.duplicate(true),
		"group_scan": _group_intel.get_lod_debug_snapshot() if _group_intel != null else {},
		"tick_perf": {
			"samples": _tick_perf_samples,
			"last_ms": _tick_perf_last_ms,
			"avg_ms": _tick_perf_avg_ms,
			"last_query_delta": _tick_perf_last_query_delta,
			"avg_query_delta": _tick_perf_query_delta_avg,
		},
		"lane_perf": {
			"director_pulse": {
				"last_ms": _director_perf_last_ms,
				"avg_ms": _director_perf_avg_ms,
			},
			"bandit_behavior_tick": {
				"last_ms": _behavior_lane_last_ms,
				"avg_ms": _behavior_lane_avg_ms,
			},
		},
		"temp_alloc_estimate_per_tick": {
			"last_objects": _temp_alloc_est_last,
			"avg_objects": _temp_alloc_est_avg,
		},
		"live_tree_scans": {
			"calls": _livetree_scan_calls,
			"last_node_count": _livetree_scan_nodes_last,
			"avg_node_count": float(_livetree_scan_nodes_total) / float(maxi(_livetree_scan_calls, 1)),
		},
	}


func _is_lod_debug_logging_enabled() -> bool:
	return Debug.is_enabled("ai") and Debug.is_enabled("bandit_lod")
