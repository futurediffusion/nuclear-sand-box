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
# Resource cycle execution contract (coordinator-driven decisions):
#   acquire resource -> hit -> drop candidate -> pickup -> cargo -> return -> deposit
#   - BanditBehaviorLayer: executes behavior tick + supplies sensory context.
#   - BanditWorkCoordinator: validates transition guards + requests intent transitions.
#   - BanditWorldBehavior: executes movement/state changes requested by coordinator.
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
const BanditGroupBrainScript        := preload("res://scripts/world/BanditGroupBrain.gd")
const BanditPerceptionSystemScript  := preload("res://scripts/domain/factions/BanditPerceptionSystem.gd")
const BanditIntentSystemScript      := preload("res://scripts/domain/factions/BanditIntentSystem.gd")
const SimulationLODPolicyScript     := preload("res://scripts/world/SimulationLODPolicy.gd")
const AIComponentScript             := preload("res://scripts/components/AIComponent.gd")
const MethodCapabilityCacheScript   := preload("res://scripts/utils/MethodCapabilityCache.gd")

# ---------------------------------------------------------------------------
# Camp layout constants Ã¢ï¿½,ï¿½ï¿½?ï¿½ local geometry, not cross-system gameplay tuning.
# These control how NPCs distribute themselves around the barrel; a designer
# would tune pickup radii / speeds in BanditTuning, not these.
# ---------------------------------------------------------------------------
const DEPOSIT_SLOT_COUNT:        int   = 36      # posiciones angulares alrededor del barril
const DEPOSIT_SLOT_RADIUS_MIN:   float = 32.0    # px mï¿½fÂ­nimo desde el centro del barril
const DEPOSIT_SLOT_RADIUS_RANGE: int   = 20      # varianza adicional (hash % N)
const DEPOSIT_REASSIGN_GUARD_SQ: float = 72.0 * 72.0  # no reasignar si ya estï¿½fÂ¡ cerca

const DEBUG_ALERTED_CHASE: bool = true
const STRUCTURE_ASSAULT_FOCUS_SECONDS: float = 8.0
const STRUCTURE_MEMBER_QUERY_RADIUS: float = 320.0
const STRUCTURE_MEMBER_QUERY_RING_RADIUS: float = 96.0
const STRUCTURE_MEMBER_TARGET_SEPARATION_SQ: float = 88.0 * 88.0
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
const STRUCTURE_REDISPATCH_NEAR_TARGET_SQ: float = 76.0 * 76.0
const STRUCTURE_MEMBER_REASSIGN_COOLDOWN_S: float = 2.5
const STRUCTURE_REPATHS_PER_PULSE_BUDGET: int = 6
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
const DROP_SCAN_ENOUGH_THRESHOLD: int = 10
const DROP_SCAN_MAX_CANDIDATES_EVAL: int = 40
const drops_per_npc_per_tick_max: int = 2
const drops_global_per_pulse_max: int = 18
const METRICS_WINDOW_SECONDS: float = 5.0
const GUARD_SLOT_RADIUS_DEFAULT: float = 34.0
const GUARD_SLOT_RADIUS_ESCORT: float = 42.0
const GUARD_SLOT_LOCAL_OFFSETS: Dictionary = {
	"frontal": Vector2(68.0, 0.0),
	"lateral_left": Vector2(20.0, -54.0),
	"lateral_right": Vector2(20.0, 54.0),
	"rearguard": Vector2(-64.0, 0.0),
	"escort_left": Vector2(-10.0, -92.0),
	"escort_right": Vector2(-10.0, 92.0),
}
const GUARD_SLOT_PRIORITY: Array[String] = [
	"frontal",
	"lateral_left",
	"lateral_right",
	"rearguard",
	"escort_left",
	"escort_right",
]
const LOCAL_SEPARATION_NEIGHBOR_LIMIT: int = 6
const CROWD_SEPARATION_NEIGHBOR_LIMIT: int = 3
const CROWD_SEPARATION_GUARD_NEIGHBOR_LIMIT: int = 4
const CROWD_SEPARATION_EVERY_N_TICKS: int = 3
const CROWD_REPULSION_SCALE: float = 0.55
const CROWD_REPULSION_GUARD_SCALE: float = 0.85
const CROWD_REPULSION_MAX_MAGNITUDE: float = 42.0
const CROWD_REPULSION_GUARD_MAX_MAGNITUDE: float = 58.0
const CROWD_DENSITY_MIN_MEMBERS: int = 5
const CROWD_DENSITY_PAIR_DISTANCE_SCALE: float = 0.72
const CROWD_DENSITY_PAIR_RATIO_THRESHOLD: float = 0.42
const CROWD_ASSAULT_TARGET_NEAR_DIST_SQ: float = 136.0 * 136.0
const CROWD_STALL_CENTROID_EPSILON_SQ: float = 7.0 * 7.0
const CROWD_STALL_GUARD_TICKS: int = 8
const SIM_PROFILE_FULL: StringName = &"full"
const SIM_PROFILE_OBEDIENT: StringName = &"obedient"
const SIM_PROFILE_DECORATIVE: StringName = &"decorative"
const OBEDIENT_PLAYER_NEAR_DISTANCE_SQ: float = 460.0 * 460.0
const DECORATIVE_PLAYER_FAR_DISTANCE_SQ: float = 980.0 * 980.0
const LOD_MAX_FULL_PER_GROUP: int = 3

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

class GroupMemberBuffer:
	var nodes: Array = []
	var positions: Array[Vector2] = []

class TickScanBuffers:
	var drops: Array[Dictionary] = []
	var resources: Array[Dictionary] = []
	var ctx: Dictionary = {}

class StructureWorkBuffers:
	var wall_samples: Array[Vector2] = []
	var wall_rows: Array[Dictionary] = []
	var clustered_rows: Array[Dictionary] = []
	var dispatch_rows: Array[Dictionary] = []
	var member_query_centers: Array[Vector2] = []
	var member_candidates: Array[Vector2] = []

class DispatchWorkBuffers:
	var prune_ids: Array[String] = []

var _npc_simulator:  NpcSimulator             = null
var _group_intel:    BanditGroupIntel         = null
var _player:         Node2D                   = null
var _bubble_manager: WorldSpeechBubbleManager = null
var _cadence:        WorldCadenceCoordinator  = null

var _behaviors: Dictionary = {}   # enemy_id (String) -> BanditWorldBehavior
var _behavior_elapsed: Dictionary = {}
var _work_loop_fallback_timer: float = 0.0
var _director_fallback_timer: float = 0.08

var _extortion_director: BanditExtortionDirector = null
var _raid_director:      BanditRaidDirector      = null
var _stash:              BanditCampStashSystem   = null
var _territory_response: BanditTerritoryResponse = null
var _work_coordinator:   BanditWorkCoordinator   = null
var _group_brain:        BanditGroupBrain        = null
var _perception_system:  BanditPerceptionSystem  = null
var _intent_system:      BanditIntentSystem      = null
var _find_wall_cb:       Callable                = Callable()
var _find_wall_samples_cb: Callable              = Callable()
var _find_workbench_cb:  Callable                = Callable()
var _find_storage_cb:    Callable                = Callable()
var _find_placeable_cb:  Callable                = Callable()
var _world_node:         Node                    = null
var _world_spatial_index: WorldSpatialIndex      = null
var _pending_structure_dispatches: Array[Dictionary] = []
var _group_team_target_cache: Dictionary         = {}
var _group_target_pool_cache: Dictionary         = {}
var _structure_target_valid_cache: Dictionary    = {}
var _structure_cache_gc_at: float                = 0.0
var _dispatch_log_next_at: Dictionary            = {}
var _lod_debug_last_npc: Dictionary              = {}
var _lod_debug_npc_counts: Dictionary            = {"fast": 0, "medium": 0, "slow": 0}
var _cargo_return_block_reason_by_member: Dictionary = {}
var _lod_mode_perf: Dictionary = {}
var _drop_metrics_pulse_seq: int = 0
var _tick_scan_buffers: TickScanBuffers          = TickScanBuffers.new()
var _structure_work_buffers: StructureWorkBuffers = StructureWorkBuffers.new()
var _dispatch_work_buffers: DispatchWorkBuffers  = DispatchWorkBuffers.new()
var _method_caps: MethodCapabilityCache          = MethodCapabilityCacheScript.new()
var _worker_instrumentation_enabled: bool        = true
var _worker_loop_enabled: bool                   = true
var _missing_world_index_error_logged: bool      = false
var _perf_window_elapsed_s: float                = 0.0
var _perf_window_accum: Dictionary               = {}
var _perf_baseline_snapshots: Dictionary         = {}
var _group_perception_elapsed: Dictionary        = {}
var _group_scan_owner_cache: Dictionary          = {}
var _group_lod_profile_decisions: Dictionary     = {}
var _lod_profile_last_by_member: Dictionary      = {}
var _physics_tick_seq: int                       = 0
var _crowd_group_runtime: Dictionary             = {}
var _structure_target_attackers_assigned: Dictionary = {} # target_key -> count
var _structure_target_by_member: Dictionary      = {} # member_id -> target_key
var _structure_target_group_by_member: Dictionary = {} # member_id -> group_id
var _structure_reassign_cooldown_until_by_member: Dictionary = {} # member_id -> timestamp
var _structure_repaths_this_pulse: int = 0
var _structure_repaths_last_pulse: int = 0
var _debug_scavenger_non_econ_orders: int = 0
@export var structure_dispatch_allow_leader: bool = false


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

func set_worker_instrumentation_enabled(enabled: bool) -> void:
	_worker_instrumentation_enabled = enabled


func is_worker_instrumentation_enabled() -> bool:
	return _worker_instrumentation_enabled and Debug.is_enabled("bandit_pipeline")


func log_worker_event(event_name: String, payload: Dictionary = {}) -> void:
	var role: String = String(payload.get("role", ""))
	if role == "scavenger" and event_name.begins_with("tactical_"):
		_debug_scavenger_non_econ_orders += 1
	if not is_worker_instrumentation_enabled():
		return
	var normalized := payload.duplicate(true)
	normalized["npc_id"] = str(normalized.get("npc_id", "unknown"))
	normalized["group_id"] = str(normalized.get("group_id", normalized.get("camp_id", "unknown")))
	normalized["camp_id"] = str(normalized.get("camp_id", normalized["group_id"]))
	normalized["state"] = str(normalized.get("state", "unknown"))
	normalized["tick"] = int(normalized.get("tick", 0))
	normalized["target_id"] = str(normalized.get("target_id", ""))
	normalized["position_used"] = str(normalized.get("position_used", "0.00,0.00"))
	normalized["work_cycle_id"] = str(normalized.get("work_cycle_id", ""))
	var parts: Array[String] = []
	parts.append("event=%s" % event_name)
	for key in ["npc_id", "group_id", "camp_id", "state", "tick", "target_id", "position_used", "work_cycle_id"]:
		parts.append("%s=%s" % [key, str(normalized.get(key, ""))])
	var extra_keys: Array = normalized.keys()
	extra_keys.sort()
	for key_var in extra_keys:
		var key: String = str(key_var)
		if key in ["npc_id", "group_id", "camp_id", "state", "tick", "target_id", "position_used", "work_cycle_id"]:
			continue
		parts.append("%s=%s" % [key, str(normalized[key_var])])
	Debug.log("bandit_pipeline", "[BANDIT_WORKER_EVENT] %s" % " ".join(parts))




func _on_work_coordinator_group_event(event_name: String, payload: Dictionary = {}) -> void:
	if _group_brain == null:
		return
	_group_brain.ingest_work_event(event_name, payload)
	log_worker_event("causal_" + event_name, payload)

func setup(ctx: Dictionary) -> void:
	_cadence        = ctx.get("cadence") as WorldCadenceCoordinator
	_npc_simulator  = ctx.get("npc_simulator")
	_player         = ctx.get("player")
	_bubble_manager = ctx.get("speech_bubble_manager")
	_world_spatial_index = ctx.get("world_spatial_index") as WorldSpatialIndex
	_worker_loop_enabled = _world_spatial_index != null
	_reset_perf_window_metrics()
	assert(_worker_loop_enabled, "BanditBehaviorLayer.setup requires world_spatial_index before worker loop startup.")
	if not _worker_loop_enabled:
		_log_missing_world_spatial_index_once("setup")
	_world_node = ctx.get("world_node")
	# Temporal governance boundary:
	# world cadence drives cross-system directors so extortion/raid orchestration
	# shares the same world pulse grid as chunk/autosave maintenance. This layer
	# keeps only a tiny fallback timer for scenes/tests that do not inject cadence.

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
		"dispatch_group_to_target_cb": Callable(self, "dispatch_group_to_target"),
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
		"world_spatial_index": _world_spatial_index,
		"update_deposit_pos_cb": Callable(self, "_update_deposit_pos"),
		"log_worker_event_cb": Callable(self, "log_worker_event"),
		"is_worker_instrumentation_enabled_cb": Callable(self, "is_worker_instrumentation_enabled"),
		"worker_instrumentation_enabled": _worker_instrumentation_enabled,
		"emit_group_event_cb": Callable(self, "_on_work_coordinator_group_event"),
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
		"log_worker_event_cb": Callable(self, "log_worker_event"),
		"is_worker_instrumentation_enabled_cb": Callable(self, "is_worker_instrumentation_enabled"),
		"worker_instrumentation_enabled": _worker_instrumentation_enabled,
		"emit_group_event_cb": Callable(self, "_on_work_coordinator_group_event"),
	})
	_stash.set_work_context({
		"get_work_tick_cb": Callable(_work_coordinator, "get_work_tick_seq"),
		"get_work_cycle_id_cb": Callable(_work_coordinator, "get_work_cycle_id_for_member"),
	})
	_group_brain = BanditGroupBrainScript.new() as BanditGroupBrain
	_group_brain.setup({})
	if _perception_system == null:
		_perception_system = BanditPerceptionSystemScript.new() as BanditPerceptionSystem
	_perception_system.setup({
		"world_spatial_index": _world_spatial_index,
		"player": _player,
		"work_coordinator": _work_coordinator,
		"log_worker_event_cb": Callable(self, "log_worker_event"),
	})
	if _intent_system == null:
		_intent_system = BanditIntentSystemScript.new() as BanditIntentSystem
	_intent_system.setup({
		"group_memory": BanditGroupMemory,
		"now_provider": Callable(RunClock, "now"),
	})


## Called from world.gd after SettlementIntel is ready.
func setup_group_intel(ctx: Dictionary) -> void:
	_group_intel = BanditGroupIntelScript.new()
	_group_intel.setup({
		"npc_simulator":             _npc_simulator,
		"player":                    _player,
		"get_interest_markers_near": ctx.get("get_interest_markers_near", Callable()),
		"get_detected_bases_near":   ctx.get("get_detected_bases_near",   Callable()),
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
	if _perception_system != null:
		_perception_system.update_queries({
			"find_nearest_player_wall": _find_wall_cb,
			"find_nearest_player_workbench": _find_workbench_cb,
			"find_nearest_player_storage": _find_storage_cb,
			"find_nearest_player_placeable": _find_placeable_cb,
		})


# ---------------------------------------------------------------------------
# Physics frame Ã¢ï¿½,ï¿½ï¿½?ï¿½ apply velocity to sleeping, non-lite enemies
# ---------------------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	if _npc_simulator == null:
		return
	var physics_start_usec: int = Time.get_ticks_usec()
	var separation_start_usec: int = 0
	var separation_elapsed_ms: float = 0.0
	var separation_group_scans: int = 0
	var separation_npc_scans: int = 0
	var separation_neighbor_checks_total: int = 0
	var crowd_mode_active_groups: int = 0
	var crowd_mode_groups_total: int = 0
	_physics_tick_seq += 1

	# Pass 1: apply desired velocities + collect per-group node positions
	var group_nodes: Dictionary = {}
	for enemy_id in _behaviors:
		var behavior: BanditWorldBehavior = _behaviors[enemy_id]
		var node = _npc_simulator.get_enemy_node(enemy_id)
		if not _is_world_behavior_eligible(node):
			continue
		var vel: Vector2 = behavior.get_desired_velocity()
		if vel.length_squared() > 0.01:
			node.velocity = vel.normalized() * (vel.length() + BanditTuningScript.friction_compensation())
		if behavior.group_id != "":
			if not group_nodes.has(behavior.group_id):
				group_nodes[behavior.group_id] = GroupMemberBuffer.new()
			var member_buffer: GroupMemberBuffer = group_nodes[behavior.group_id] as GroupMemberBuffer
			member_buffer.nodes.append(node)
			member_buffer.positions.append(node.global_position)

	# Pass 2: ally separation (local-neighborhood only; no O(n²) all-vs-all).
	separation_start_usec = Time.get_ticks_usec()
	for gid in group_nodes:
		var member_buffer: GroupMemberBuffer = group_nodes[gid] as GroupMemberBuffer
		if member_buffer == null:
			continue
		var member_count: int = member_buffer.nodes.size()
		if member_count < 2:
			continue
		separation_group_scans += 1
		separation_npc_scans += member_count
		crowd_mode_groups_total += 1
		var crowd_profile: Dictionary = _resolve_group_crowd_separation_profile(String(gid), member_buffer)
		var crowd_active: bool = bool(crowd_profile.get("active", false))
		if crowd_active:
			crowd_mode_active_groups += 1
		var eval_this_tick: bool = bool(crowd_profile.get("evaluate_this_tick", true))
		var effective_neighbor_limit: int = int(crowd_profile.get("neighbor_limit", LOCAL_SEPARATION_NEIGHBOR_LIMIT))
		var repulsion_scale: float = float(crowd_profile.get("repulsion_scale", 1.0))
		var repulsion_max_magnitude: float = float(crowd_profile.get("repulsion_max_magnitude", INF))
		for i in member_count:
			if not eval_this_tick:
				continue
			var a_node = member_buffer.nodes[i]
			if a_node == null or not is_instance_valid(a_node):
				continue
			var a_pos: Vector2 = member_buffer.positions[i]
			var sep: Vector2 = Vector2.ZERO
			var chunk_opt: Variant = EnemyRegistry.world_to_chunk(a_pos)
			if chunk_opt == null:
				continue
			var nearby: Array[Node2D] = EnemyRegistry.get_bucket_neighborhood(chunk_opt as Vector2i)
			if nearby.is_empty():
				continue
			var checked: int = 0
			for other in nearby:
				if checked >= effective_neighbor_limit:
					break
				if other == a_node or other == null or not is_instance_valid(other):
					continue
				if String(other.get("group_id")) != String(gid):
					continue
				if other.has_method("is_sleeping") and other.is_sleeping():
					continue
				checked += 1
				separation_neighbor_checks_total += 1
				var diff: Vector2 = a_pos - other.global_position
				var d: float = diff.length()
				if d < BanditTuningScript.ally_sep_radius() and d > 0.5:
					sep += diff.normalized() * (BanditTuningScript.ally_sep_radius() - d) \
						/ BanditTuningScript.ally_sep_radius() * BanditTuningScript.ally_sep_force()
			if sep.length_squared() > 0.01:
				if repulsion_scale < 0.999:
					sep *= repulsion_scale
				if sep.length() > repulsion_max_magnitude:
					sep = sep.normalized() * repulsion_max_magnitude
				a_node.velocity += sep
	separation_elapsed_ms = float(Time.get_ticks_usec() - separation_start_usec) / 1000.0

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
			if not _is_world_behavior_eligible(snode):
				continue
			var to_p: Vector2 = ap - snode.global_position
			if to_p.length() > 1.0:
				snode.velocity = to_p.normalized() * (
					BanditTuningScript.alerted_scout_chase_speed(gid) + BanditTuningScript.friction_compensation()
				)
	var physics_elapsed_ms: float = float(Time.get_ticks_usec() - physics_start_usec) / 1000.0
	_accumulate_perf_window({
		"physics_process_calls": 1,
		"physics_process_total_ms": physics_elapsed_ms,
		"ally_separation_total_ms": separation_elapsed_ms,
		"separation_group_scans": separation_group_scans,
		"separation_npc_scans": separation_npc_scans,
		"separation_neighbor_checks_total": separation_neighbor_checks_total,
		"crowd_mode_active_groups": crowd_mode_active_groups,
		"crowd_mode_groups_total": crowd_mode_groups_total,
	})


func _resolve_group_crowd_separation_profile(group_id: String, member_buffer: GroupMemberBuffer) -> Dictionary:
	var member_count: int = member_buffer.nodes.size()
	var crowd_active: bool = false
	var assault_target: Vector2 = BanditGroupMemory.get_assault_target(group_id)
	if member_count >= CROWD_DENSITY_MIN_MEMBERS \
			and BanditGroupMemory.is_structure_assault_active(group_id) \
			and _is_valid_structure_target(assault_target) \
			and _is_group_locally_dense(member_buffer.positions) \
			and _compute_positions_centroid(member_buffer.positions).distance_squared_to(assault_target) <= CROWD_ASSAULT_TARGET_NEAR_DIST_SQ:
		crowd_active = true
	var runtime: Dictionary = _crowd_group_runtime.get(group_id, {
		"stall_ticks": 0,
		"last_centroid": Vector2.ZERO,
		"has_centroid": false,
	}) as Dictionary
	var centroid: Vector2 = _compute_positions_centroid(member_buffer.positions)
	if bool(runtime.get("has_centroid", false)):
		if centroid.distance_squared_to(runtime.get("last_centroid", Vector2.ZERO) as Vector2) <= CROWD_STALL_CENTROID_EPSILON_SQ:
			runtime["stall_ticks"] = int(runtime.get("stall_ticks", 0)) + 1
		else:
			runtime["stall_ticks"] = 0
	else:
		runtime["stall_ticks"] = 0
	runtime["last_centroid"] = centroid
	runtime["has_centroid"] = true
	_crowd_group_runtime[group_id] = runtime
	var guard_rail_stuck: bool = crowd_active and int(runtime.get("stall_ticks", 0)) >= CROWD_STALL_GUARD_TICKS
	if not crowd_active:
		return {
			"active": false,
			"evaluate_this_tick": true,
			"neighbor_limit": LOCAL_SEPARATION_NEIGHBOR_LIMIT,
			"repulsion_scale": 1.0,
			"repulsion_max_magnitude": INF,
		}
	if guard_rail_stuck:
		return {
			"active": true,
			"evaluate_this_tick": true,
			"neighbor_limit": maxi(CROWD_SEPARATION_GUARD_NEIGHBOR_LIMIT, CROWD_SEPARATION_NEIGHBOR_LIMIT),
			"repulsion_scale": CROWD_REPULSION_GUARD_SCALE,
			"repulsion_max_magnitude": CROWD_REPULSION_GUARD_MAX_MAGNITUDE,
		}
	return {
		"active": true,
		"evaluate_this_tick": (_physics_tick_seq % CROWD_SEPARATION_EVERY_N_TICKS) == 0,
		"neighbor_limit": CROWD_SEPARATION_NEIGHBOR_LIMIT,
		"repulsion_scale": CROWD_REPULSION_SCALE,
		"repulsion_max_magnitude": CROWD_REPULSION_MAX_MAGNITUDE,
	}


func _compute_positions_centroid(positions: Array[Vector2]) -> Vector2:
	if positions.is_empty():
		return Vector2.ZERO
	var acc: Vector2 = Vector2.ZERO
	for pos in positions:
		acc += pos
	return acc / float(maxi(positions.size(), 1))


func _is_group_locally_dense(positions: Array[Vector2]) -> bool:
	var count: int = positions.size()
	if count < CROWD_DENSITY_MIN_MEMBERS:
		return false
	var max_pairs: int = (count * (count - 1)) / 2
	if max_pairs <= 0:
		return false
	var close_pairs: int = 0
	var close_dist_sq: float = pow(BanditTuningScript.ally_sep_radius() * CROWD_DENSITY_PAIR_DISTANCE_SCALE, 2.0)
	for i in count:
		for j in range(i + 1, count):
			if positions[i].distance_squared_to(positions[j]) <= close_dist_sq:
				close_pairs += 1
	return float(close_pairs) / float(max_pairs) >= CROWD_DENSITY_PAIR_RATIO_THRESHOLD


# ---------------------------------------------------------------------------
# Process tick Ã¢ï¿½,ï¿½ï¿½?ï¿½ behavior maintenance
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _npc_simulator == null:
		return
	_structure_repaths_last_pulse = _structure_repaths_this_pulse
	_structure_repaths_this_pulse = 0
	_release_structure_slots_for_inactive_assaults()
	_perf_window_elapsed_s += delta
	if RunClock.now() >= _structure_cache_gc_at:
		_structure_cache_gc_at = RunClock.now() + 1.5
		_prune_structure_target_caches()
	if _group_intel != null:
		_group_intel.tick(delta)
	var director_pulses: int = _cadence.consume_lane(&"director_pulse") if _cadence != null else 0
	if _cadence == null:
		_director_fallback_timer += delta
		if _director_fallback_timer >= 0.12:
			_director_fallback_timer -= 0.12
			director_pulses = 1
	for _pulse in director_pulses:
		if _extortion_director != null:
			_extortion_director.process_extortion(0.12)
		if _raid_director != null:
			_raid_director.process_raid()
	_process_pending_structure_dispatches()
	if not _worker_loop_enabled:
		_flush_perf_window_if_needed()
		return
	var work_loop_pulses: int = 0
	if _cadence != null:
		work_loop_pulses = _cadence.consume_lane(&"bandit_work_loop")
	else:
		_work_loop_fallback_timer += delta
		if _work_loop_fallback_timer >= 0.25:
			_work_loop_fallback_timer -= 0.25
			work_loop_pulses = 1
	if work_loop_pulses <= 0:
		_flush_perf_window_if_needed()
		return

	for _work_pulse in work_loop_pulses:
		_ensure_behaviors_for_active_enemies()
		_stash.ensure_barrels()
		var mode_signals: Dictionary = _get_global_lod_mode_signals()
		var active_mode: StringName = SimulationLODPolicyScript.resolve_interval_mode({
			"mode_signals": mode_signals,
		})
		var behavior_start_usec: int = Time.get_ticks_usec()
		var work_units: int = _tick_behaviors()
		var behavior_elapsed_ms: float = float(Time.get_ticks_usec() - behavior_start_usec) / 1000.0
		_record_mode_frame_time(active_mode, behavior_elapsed_ms)
		if _cadence != null:
			var lane_budget: int = _cadence.lane_budget(&"bandit_work_loop", -1)
			_cadence.report_lane_work(&"bandit_work_loop", work_units, lane_budget)
		_prune_behaviors()
	_flush_perf_window_if_needed()


# ---------------------------------------------------------------------------
# Behavior tick
# ---------------------------------------------------------------------------

func _tick_behaviors() -> int:
	# Ownership boundary:
	# 1) behavior.tick() decides locomotion/state evolution from current intent.
	# 2) work_coordinator performs world side effects + guarded transition requests.
	# This ordering prevents "silent jump" transitions after hit/pickup because
	# all side effects run through one post-behavior gate.
	_prune_behavior_timers()
	_lod_debug_last_npc.clear()
	_lod_debug_npc_counts = {"fast": 0, "medium": 0, "slow": 0}
	_drop_metrics_pulse_seq += 1
	var drop_pressure_mode: String = "normal"
	if LootSystem != null and LootSystem.has_method("get_drop_pressure_snapshot"):
		var pressure_snapshot: Dictionary = LootSystem.get_drop_pressure_snapshot() as Dictionary
		drop_pressure_mode = String(pressure_snapshot.get("level", "normal"))
	if _stash != null:
		_stash.begin_drop_pulse(_drop_metrics_pulse_seq, drop_pressure_mode)
	var work_units: int = 0
	var pulse_drop_budget_ctx: Dictionary = {
		"processed": 0,
		"max": drops_global_per_pulse_max,
		"per_npc_max": drops_per_npc_per_tick_max,
		"drops_pulse_id": _drop_metrics_pulse_seq,
	}
	var res_nodes_snapshot: Array = _get_all_resource_nodes()
	var group_perception_payload: Dictionary = _build_group_perception_payload(res_nodes_snapshot)
	var leader_pos_by_group: Dictionary = {}
	var leader_forward_by_group: Dictionary = {}
	var group_intent_by_group: Dictionary = {}
	var members_by_group: Dictionary = {}
	var orders_by_member: Dictionary = {}
	var scans_by_group: Dictionary = {}
	var scans_by_npc: Dictionary = {}
	var worker_active_count: int = 0
	var followers_without_task: int = 0
	var collect_claims: Dictionary = {}
	var mine_claims: Dictionary = {}
	var tick_calls: int = 0
	var tick_total_ms: float = 0.0
	for enemy_id in _behaviors:
		var beh: BanditWorldBehavior = _behaviors[enemy_id]
		if beh.group_id == "":
			continue
		var node = _npc_simulator.get_enemy_node(enemy_id)
		if node == null:
			continue
		if not members_by_group.has(beh.group_id):
			members_by_group[beh.group_id] = []
		var members: Array = members_by_group[beh.group_id] as Array
		var _rs: Dictionary = _get_runtime_lod_signals(node)
		var state_name: String = ""
		if beh.state >= 0 and beh.state < NpcWorldBehavior.State.size():
			state_name = NpcWorldBehavior.State.keys()[beh.state]
		var current_assignment: Dictionary = BanditGroupMemory.bb_get_assignment(beh.group_id, beh.member_id)
		members.append({
			"member_id": beh.member_id,
			"role": beh.role,
			"pos": node.global_position,
			"cargo_count": beh.cargo_count,
			"cargo_capacity": beh.cargo_capacity,
			"deposit_lock_active": beh.deposit_lock_active,
			"delivery_lock_active": beh.delivery_lock_active,
			"current_state": state_name,
			"current_resource_id": beh._resource_node_id,
			"pending_mine_id": beh.pending_mine_id,
			"pending_collect_id": beh.pending_collect_id,
			"last_valid_resource_node_id": beh.last_valid_resource_node_id,
			"current_assignment": current_assignment,
			"has_active_task": is_worker_cycle_active(beh) \
					or beh.pending_collect_id != 0 \
					or beh.pending_mine_id != 0 \
					or beh.cargo_count > 0 \
					or beh.state == NpcWorldBehavior.State.RESOURCE_WATCH,
			"in_combat": bool(_rs.get("is_in_direct_combat", false)),
			"recently_engaged": bool(_rs.get("was_recently_engaged", false)),
		})
		members_by_group[beh.group_id] = members
		if beh.role == "leader":
			leader_pos_by_group[beh.group_id] = node.global_position
			var desired_vel: Vector2 = beh.get_desired_velocity()
			var leader_fwd: Vector2 = desired_vel.normalized() if desired_vel.length_squared() > 0.1 else node.velocity.normalized()
			if leader_fwd.length_squared() < 0.1:
				leader_fwd = Vector2.RIGHT
			leader_forward_by_group[beh.group_id] = leader_fwd
		if not group_intent_by_group.has(beh.group_id):
			var runtime_group: Dictionary = BanditGroupMemory.get_group(beh.group_id)
			group_intent_by_group[beh.group_id] = String(runtime_group.get("current_group_intent", "idle"))
	var guard_slots_by_member: Dictionary = _build_guard_slots_by_member(members_by_group, leader_pos_by_group, leader_forward_by_group)
	orders_by_member = _compute_group_orders(members_by_group, leader_pos_by_group)
	_group_lod_profile_decisions = _build_group_lod_profile_decisions(orders_by_member)

	for enemy_id in _behaviors:
		var beh: BanditWorldBehavior = _behaviors[enemy_id]
		var node = _npc_simulator.get_enemy_node(enemy_id)
		if is_worker_cycle_active(beh):
			worker_active_count += 1
		if beh.role != "leader" and not is_worker_cycle_active(beh) \
				and beh.pending_collect_id == 0 and beh.pending_mine_id == 0 \
				and beh.cargo_count <= 0:
			followers_without_task += 1
		if beh.pending_collect_id != 0:
			var collect_key: String = str(beh.pending_collect_id)
			collect_claims[collect_key] = int(collect_claims.get(collect_key, 0)) + 1
		if beh.pending_mine_id != 0:
			var mine_key: String = str(beh.pending_mine_id)
			mine_claims[mine_key] = int(mine_claims.get(mine_key, 0)) + 1
		if not _is_world_behavior_eligible(node):
			if _work_coordinator != null:
				_work_coordinator.process_post_behavior(beh, node, pulse_drop_budget_ctx)
			continue

		var node_pos: Vector2 = _effective_work_position(node)
		_enforce_cargo_return_priority(beh, node_pos, "pre_tick")
		var tick_interval: float = _get_behavior_tick_interval(beh, node, node_pos)
		var elapsed: float = float(_behavior_elapsed.get(enemy_id, 0.0)) + BanditTuningScript.behavior_tick_interval()
		_behavior_elapsed[enemy_id] = elapsed
		if elapsed < tick_interval:
			if _work_coordinator != null:
				_work_coordinator.process_post_behavior(beh, node, pulse_drop_budget_ctx)
			continue
		# Resetear a 0 en vez de acumular residual para evitar que elapsed crezca
		# indefinidamente cuando tick_interval es corto (ej. 0.25s con jugador cerca).
		# Un elapsed creciente pasado a beh.tick() como delta hace que _stuck_timer
		# supere STUCK_CHECK_INTERVAL en el primer tick de PATROL, antes de que el
		# NPC haya movido, disparando stuck detection de forma falsa.
		var reaction_latency: float = maxf(elapsed - tick_interval, 0.0)
		_behavior_elapsed[enemy_id] = 0.0

		var member_order: Dictionary = {}
		if beh.group_id != "":
			member_order = orders_by_member.get(beh.member_id, {})
		var sim_decision: Dictionary = _resolve_member_simulation_profile_decision(beh, node, node_pos, member_order)
		var sim_profile: StringName = StringName(String(sim_decision.get("profile", String(SIM_PROFILE_FULL))))
		_apply_member_simulation_profile(node, sim_profile)
		var has_group_blackboard_data: bool = false
		if sim_profile == SIM_PROFILE_FULL and BanditTuningScript.enable_group_perception_pulse():
			has_group_blackboard_data = _fill_from_group_blackboard(beh, node_pos, _tick_scan_buffers.drops, _tick_scan_buffers.resources)
		if sim_profile == SIM_PROFILE_FULL and BanditTuningScript.enable_individual_scan_fallback():
			if not has_group_blackboard_data:
				_fill_drops_info_buffer(node_pos, _tick_scan_buffers.drops)
			if _tick_scan_buffers.resources.is_empty():
				_fill_res_info_buffer(beh, node_pos, res_nodes_snapshot, _tick_scan_buffers.resources)
		if sim_profile != SIM_PROFILE_FULL:
			_tick_scan_buffers.drops.clear()
			_tick_scan_buffers.resources.clear()
		var runtime_signals_ctx: Dictionary = _get_runtime_lod_signals(node)
		var ctx: Dictionary = _tick_scan_buffers.ctx
		ctx.clear()
		ctx.merge(_build_behavior_perception_context({
			"node_pos": node_pos,
			"nearby_drops_info": _tick_scan_buffers.drops,
			"nearby_res_info": _tick_scan_buffers.resources,
			"in_combat": bool(runtime_signals_ctx.get("is_in_direct_combat", false)),
			"recently_engaged": bool(runtime_signals_ctx.get("was_recently_engaged", false)),
			"simulation_profile": String(sim_profile),
		}), true)
		if beh.group_id != "":
			ctx["leader_pos"] = leader_pos_by_group.get(beh.group_id, beh.home_pos)
			ctx["group_intent"] = String(group_intent_by_group.get(beh.group_id, "idle"))
			if guard_slots_by_member.has(beh.member_id):
				var slot_info: Dictionary = guard_slots_by_member[beh.member_id] as Dictionary
				ctx["follow_slot_pos"] = slot_info.get("slot_pos", beh.home_pos)
				ctx["follow_slot_radius"] = float(slot_info.get("radius", GUARD_SLOT_RADIUS_DEFAULT))
				ctx["follow_slot_name"] = String(slot_info.get("slot_name", ""))
			member_order = orders_by_member.get(beh.member_id, {})
			if not member_order.is_empty():
				_apply_member_order(beh, ctx, member_order)
		if sim_profile == SIM_PROFILE_FULL and beh.group_id != "":
			scans_by_group[beh.group_id] = int(scans_by_group.get(beh.group_id, 0)) + 1
			var owner_entry: Dictionary = group_perception_payload.get(beh.group_id, {})
			if not owner_entry.is_empty():
				ctx["group_scan_owner_id"] = String(owner_entry.get("owner_id", ""))
		if sim_profile == SIM_PROFILE_FULL:
			scans_by_npc[beh.member_id] = int(scans_by_npc.get(beh.member_id, 0)) + 1
		_record_profile_stability_metrics(beh.member_id, beh.group_id, sim_profile, sim_decision)

		# Pasar tick_interval como delta (tiempo real desde ï¿½fÂºltimo tick),
		# no elapsed que puede ser mayor que tick_interval.
		var tick_start_usec: int = Time.get_ticks_usec()
		beh.tick(tick_interval, ctx)
		tick_total_ms += float(Time.get_ticks_usec() - tick_start_usec) / 1000.0
		tick_calls += 1
		_enforce_cargo_return_priority(beh, node_pos, "post_tick")
		work_units += 1
		var lod_mode: StringName = StringName(String(_lod_debug_last_npc.get(beh.member_id, {}).get("mode", String(SimulationLODPolicyScript.MODE_CONTEXTUAL))))
		_record_mode_reaction_latency(lod_mode, reaction_latency)
		_maybe_show_recognition_bubble(beh, node, node_pos)
		_maybe_show_idle_chat(beh, node, node_pos)

		# Sync save-state: cargo y behavior para continuidad data-only
		var save_state_ref: Dictionary = _get_save_state_for(enemy_id)
		if not save_state_ref.is_empty():
			save_state_ref["cargo_count"]    = beh.cargo_count
			save_state_ref["world_behavior"] = beh.export_state()

		if _work_coordinator != null:
			_work_coordinator.process_post_behavior(beh, node, pulse_drop_budget_ctx)
	var assignment_conflicts: int = _count_assignment_conflicts(collect_claims) + _count_assignment_conflicts(mine_claims)
	var reservation_metrics: Dictionary = {}
	if _work_coordinator != null:
		reservation_metrics = _work_coordinator.consume_reservation_conflict_metrics()
	_accumulate_perf_window({
		"behavior_tick_calls": tick_calls,
		"behavior_tick_total_ms": tick_total_ms,
		"work_units": work_units,
		"worker_active_count_samples": worker_active_count,
		"worker_active_count_frames": 1,
		"followers_without_task_samples": followers_without_task,
		"followers_without_task_frames": 1,
		"assignment_conflicts_total": assignment_conflicts,
		"double_reservations_avoided": int(reservation_metrics.get("double_reservations_avoided", 0)),
		"expired_reservations": int(reservation_metrics.get("expired_reservations", 0)),
		"assignment_replans": int(reservation_metrics.get("assignment_replans", 0)),
		"assault_context_build_ms": float(reservation_metrics.get("assault_context_build_ms", 0.0)),
		"assault_context_hits": int(reservation_metrics.get("assault_context_hits", 0)),
		"assault_per_npc_before_total_ms": float((reservation_metrics.get("assault_per_npc_ms_before_after", {}) as Dictionary).get("before_total_ms", 0.0)),
		"assault_per_npc_before_calls": int((reservation_metrics.get("assault_per_npc_ms_before_after", {}) as Dictionary).get("before_calls", 0)),
		"assault_per_npc_after_total_ms": float((reservation_metrics.get("assault_per_npc_ms_before_after", {}) as Dictionary).get("after_total_ms", 0.0)),
		"assault_per_npc_after_calls": int((reservation_metrics.get("assault_per_npc_ms_before_after", {}) as Dictionary).get("after_calls", 0)),
		"scan_total": _dict_int_sum(scans_by_npc),
	})
	_merge_nested_counter("scan_by_group", scans_by_group)
	_merge_nested_counter("scan_by_npc", scans_by_npc)
	return work_units


func _build_guard_slots_by_member(
		members_by_group: Dictionary,
		leader_pos_by_group: Dictionary,
		leader_forward_by_group: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for group_id_var in members_by_group.keys():
		var group_id: String = str(group_id_var)
		if not leader_pos_by_group.has(group_id):
			continue
		var members: Array = members_by_group[group_id] as Array
		if members.is_empty():
			continue
		var bodyguards: Array = []
		var others: Array = []
		for item in members:
			var member: Dictionary = item as Dictionary
			if String(member.get("role", "")) == "leader":
				continue
			if String(member.get("role", "")) == "bodyguard":
				bodyguards.append(member)
			else:
				others.append(member)
		var candidates: Array = []
		candidates.append_array(bodyguards)
		candidates.append_array(others)
		if candidates.is_empty():
			continue
		var anchor_pos: Vector2 = leader_pos_by_group[group_id] as Vector2
		var forward: Vector2 = leader_forward_by_group.get(group_id, Vector2.RIGHT)
		if forward.length_squared() < 0.01:
			forward = Vector2.RIGHT
		forward = forward.normalized()
		var right: Vector2 = Vector2(-forward.y, forward.x)
		var available_slots: Array[String] = GUARD_SLOT_PRIORITY.duplicate()
		for member_data in candidates:
			if available_slots.is_empty():
				break
			var member: Dictionary = member_data as Dictionary
			var member_pos: Vector2 = member.get("pos", anchor_pos)
			var best_slot_idx: int = 0
			var best_slot_dist_sq: float = INF
			for idx in available_slots.size():
				var slot_name: String = available_slots[idx]
				var local: Vector2 = GUARD_SLOT_LOCAL_OFFSETS.get(slot_name, Vector2.ZERO)
				var slot_pos := anchor_pos + forward * local.x + right * local.y
				var dist_sq := member_pos.distance_squared_to(slot_pos)
				if dist_sq < best_slot_dist_sq:
					best_slot_dist_sq = dist_sq
					best_slot_idx = idx
			var chosen_slot_name: String = available_slots[best_slot_idx]
			available_slots.remove_at(best_slot_idx)
			var chosen_local: Vector2 = GUARD_SLOT_LOCAL_OFFSETS.get(chosen_slot_name, Vector2.ZERO)
			var chosen_pos := anchor_pos + forward * chosen_local.x + right * chosen_local.y
			var slot_radius := GUARD_SLOT_RADIUS_ESCORT if chosen_slot_name.begins_with("escort") else GUARD_SLOT_RADIUS_DEFAULT
			out[String(member.get("member_id", ""))] = {
				"slot_name": chosen_slot_name,
				"slot_pos": chosen_pos,
				"radius": slot_radius,
			}
	return out


func _compute_group_orders(members_by_group: Dictionary, leader_pos_by_group: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	if _group_brain == null:
		return out
	for group_id_var in members_by_group.keys():
		var group_id: String = str(group_id_var)
		var group: Dictionary = BanditGroupMemory.get_group(group_id)
		if group.is_empty():
			continue
		var members: Array = members_by_group[group_id] as Array
		var blackboard: Dictionary = BanditGroupMemory.bb_get(group_id)
		var status: Dictionary = blackboard.get("status", {}) as Dictionary
		var canonical_intent_entry: Dictionary = status.get("canonical_intent_record", {}) as Dictionary
		var canonical_intent: Dictionary = canonical_intent_entry.get("value", {}) as Dictionary
		var has_canonical_intent: bool = _has_canonical_pipeline_intent(canonical_intent)
		var perception: Dictionary = blackboard.get("perception", {})
		var prioritized_drops_entry: Dictionary = perception.get("prioritized_drops", {})
		var prioritized_resources_entry: Dictionary = perception.get("prioritized_resources", {})
		var any_scavenger_busy: bool = false
		var any_member_threatened: bool = false
		for _m in members:
			var _md: Dictionary = _m as Dictionary
			if bool(_md.get("in_combat", false)) or bool(_md.get("recently_engaged", false)):
				any_member_threatened = true
			if String(_md.get("role", "")) == "scavenger" and bool(_md.get("has_active_task", false)):
				any_scavenger_busy = true
		var group_ctx := {
			"group_id": group_id,
			"group_mode": String(group.get("current_group_intent", "idle")),
			"leader_pos": leader_pos_by_group.get(group_id, group.get("home_world_pos", Vector2.ZERO)),
			"home_pos": group.get("home_world_pos", Vector2.ZERO),
			"interest_pos": group.get("last_interest_pos", Vector2.ZERO),
			"group_blackboard": blackboard,
			"prioritized_drops": prioritized_drops_entry.get("value", []),
			"prioritized_resources": prioritized_resources_entry.get("value", []),
			"canonical_intent": canonical_intent,
			"any_scavenger_busy": any_scavenger_busy,
			"any_member_threatened": any_member_threatened,
			"structure_assault_active": BanditGroupMemory.is_structure_assault_active(group_id),
		}
		if bool(group_ctx.get("structure_assault_active", false)) and not has_canonical_intent and _perception_system != null and _intent_system != null:
			var perception_snapshot: Dictionary = _perception_system.build_group_intent_perception({
				"group_id": group_id,
				"members": members,
				"prioritized_drops": group_ctx.get("prioritized_drops", []),
				"prioritized_resources": group_ctx.get("prioritized_resources", []),
				"structure_assault_active": true,
				"has_assault_target": _group_has_live_structure_target(group_id),
			})
			var intent_record: Dictionary = _intent_system.decide_group_intent(
				perception_snapshot,
				{
					"current_group_intent": String(group.get("current_group_intent", "idle")),
					"has_placement_react_lock": BanditGroupMemory.has_placement_react_lock(group_id),
				},
				{
					"policy_next_intent": "raiding",
					"reason": "structure_assault_pipeline",
					"source": "BanditBehaviorLayer._compute_group_orders",
				}
			)
			_intent_system.apply_group_intent_record(group_id, intent_record, {
				"source": "structure_assault_pipeline_compatibility_bridge",
			})
			intent_record["pipeline_path"] = "Perception->Intent->Task->Execution"
			intent_record["compatibility_bridge"] = "structure_assault_missing_canonical_intent"
			canonical_intent = intent_record
			log_worker_event("pipeline_compatibility_bridge_applied", {
				"group_id": group_id,
				"bridge": "structure_assault_missing_canonical_intent",
				"intent_decision": String(intent_record.get("decision_type", "")),
				"group_mode": String(intent_record.get("group_mode", "")),
				"pipeline_path": "Perception->Intent->Task->Execution",
			})
		group_ctx["canonical_intent"] = canonical_intent
		log_worker_event("pipeline_group_decision", {
			"group_id": group_id,
			"group_mode": String(group_ctx.get("group_mode", "idle")),
			"intent_decision": String(canonical_intent.get("decision_type", "")),
			"has_canonical_intent": _has_canonical_pipeline_intent(canonical_intent),
			"structure_assault_active": bool(group_ctx.get("structure_assault_active", false)),
			"prioritized_drops": int((group_ctx.get("prioritized_drops", []) as Array).size()),
			"prioritized_resources": int((group_ctx.get("prioritized_resources", []) as Array).size()),
			"members_count": int(members.size()),
		})
		var member_orders: Dictionary = _group_brain.assign_group_orders(group_id, members, group_ctx)
		log_worker_event("pipeline_group_orders_planned", {
			"group_id": group_id,
			"orders_count": int(member_orders.size()),
			"has_canonical_intent": _has_canonical_pipeline_intent(canonical_intent),
		})
		for member_id in member_orders.keys():
			out[str(member_id)] = member_orders[member_id]
	return out


func _apply_member_order(beh: BanditWorldBehavior, ctx: Dictionary, order: Dictionary) -> void:
	var order_type: String = String(order.get("order", ""))
	if order_type == "":
		return
	var task_payload: Dictionary = order.get("task", {}) as Dictionary
	var task_kind: String = String(task_payload.get("kind", ""))
	if task_kind != "":
		log_worker_event("pipeline_execution_task_consumed", {
			"npc_id": beh.member_id,
			"group_id": beh.group_id,
			"role": beh.role,
			"order": order_type,
			"task_kind": task_kind,
			"intent_decision": String((task_payload.get("intent", {}) as Dictionary).get("decision_type", "")),
			"macro_state": String(task_payload.get("macro_state", "")),
		})
	if task_kind != "" and task_kind != order_type:
		log_worker_event("pipeline_duplicate_decision_path_blocked", {
			"npc_id": beh.member_id,
			"group_id": beh.group_id,
			"order": order_type,
			"task_kind": task_kind,
			"reason": "task_kind_mismatch",
		})
		return
	if String(task_payload.get("kind", "")) == "assault_structure_target":
		log_worker_event("structure_assault_pipeline_execution", {
			"npc_id": beh.member_id,
			"group_id": beh.group_id,
			"order": order_type,
			"task_kind": String(task_payload.get("kind", "")),
			"intent_decision": String((task_payload.get("intent", {}) as Dictionary).get("decision_type", "")),
			"pipeline_path": "Perception->Intent->Task->Execution",
		})
	ctx["execution_order_active"] = true
	ctx["execution_order_type"] = order_type
	var structure_assault_active: bool = BanditGroupMemory.is_structure_assault_active(beh.group_id)
	var structure_target_alive: bool = _group_has_live_structure_target(beh.group_id)
	var structure_assault_sticky_member: bool = beh.role == "bodyguard" or beh.role == "leader"
	var canonical_pipeline_active: bool = _group_has_canonical_pipeline_intent(beh.group_id)
	var is_generic_override: bool = order_type == "follow_slot" \
			or order_type == "move_to_target" \
			or order_type == "attack_target"
	if structure_assault_active and structure_assault_sticky_member and is_generic_override and structure_target_alive and not canonical_pipeline_active:
		log_worker_event("structure_assault_target_overwritten", {
			"npc_id": beh.member_id,
			"group_id": beh.group_id,
			"overwritten_by_order": order_type,
			"bridge": "legacy_structure_assault_order_block",
		})
		if order_type == "attack_target":
			log_worker_event("ignored_generic_attack_during_structure_assault", {
				"npc_id": beh.member_id,
				"group_id": beh.group_id,
				"order": order_type,
			})
			log_worker_event("enter_extort_approach_blocked_due_to_structure_assault", {
				"npc_id": beh.member_id,
				"group_id": beh.group_id,
			})
		return
	elif structure_assault_active and structure_assault_sticky_member and is_generic_override and not structure_target_alive and not canonical_pipeline_active:
		var recovered_target: bool = _try_member_structure_assault_retarget(
			beh,
			ctx,
			"generic_order_without_live_target:%s" % order_type
		)
		if recovered_target:
			return
		log_worker_event("structure_assault_no_live_target_waiting_for_raidflow", {
			"npc_id": beh.member_id,
			"group_id": beh.group_id,
			"order": order_type,
		})
		# Evita "sticky-no-target limbo":
		# - attack_target sigue bloqueado para impedir chase casual.
		# - follow/move pasan como locomoción temporal mientras RaidFlow redespacha.
		if order_type == "attack_target":
			return
	var delivery_lock_engaged: bool = beh.delivery_lock_active and beh.cargo_count > 0
	var combat_override: bool = bool(ctx.get("in_combat", false)) or bool(ctx.get("recently_engaged", false))
	if delivery_lock_engaged and order_type != "return_home":
		if order_type != "attack_target" or not combat_override:
			log_worker_event("ignored_order_due_to_delivery_lock", {
				"npc_id": beh.member_id,
				"group_id": beh.group_id,
				"order": order_type,
				"cargo": beh.cargo_count,
				"delivery_lock_active": true,
			})
			log_worker_event("tactical_order_ignored_deposit_lock", {
				"npc_id": beh.member_id,
				"group_id": beh.group_id,
				"order": order_type,
				"cargo": beh.cargo_count,
				"deposit_lock_active": true,
				"delivery_lock_active": true,
			})
			return
	match order_type:
		"follow_slot":
			ctx["follow_slot_name"] = String(order.get("slot_name", ctx.get("follow_slot_name", "")))
		"move_to_target":
			var _mv: Variant = order.get("target_pos", null)
			var move_pos: Vector2 = _mv if _mv is Vector2 else Vector2.ZERO
			if move_pos != Vector2.ZERO and beh.state != NpcWorldBehavior.State.EXTORT_APPROACH:
				beh.enter_extort_approach(move_pos)
		"mine_target":
			var _mp: Variant = order.get("target_pos", null)
			var mine_pos: Vector2 = _mp if _mp is Vector2 else Vector2.ZERO
			var mine_id: int = int(order.get("target_id", 0))
			# Don't restart watch if already mining this resource — resetting clears
			# _mine_tick_timer and pending_mine_id, preventing hits from ever landing.
			var already_watching: bool = beh.state == NpcWorldBehavior.State.RESOURCE_WATCH \
					and beh._resource_node_id == mine_id and mine_id != 0
			var same_pending: bool = beh.pending_mine_id != 0 and beh.pending_mine_id == mine_id
			var same_last_valid: bool = beh.last_valid_resource_node_id != 0 and beh.last_valid_resource_node_id == mine_id
			if mine_pos != Vector2.ZERO and not already_watching and not same_pending and not same_last_valid:
				log_worker_event("tactical_mine_target_changed", {
					"npc_id": beh.member_id,
					"group_id": beh.group_id,
					"from_resource_id": beh._resource_node_id,
					"to_resource_id": mine_id,
					"state_before": _state_name_from_enum(beh.state),
				})
				beh.enter_resource_watch(mine_pos, mine_id)
			elif mine_id != 0:
				log_worker_event("tactical_mine_target_preserved", {
					"npc_id": beh.member_id,
					"group_id": beh.group_id,
					"target_id": mine_id,
					"already_watching": already_watching,
					"same_pending": same_pending,
					"same_last_valid": same_last_valid,
				})
		"pickup_target":
			var target_id: int = int(order.get("target_id", 0))
			# Don't re-enter loot approach for a drop already being chased.
			var already_chasing: bool = beh.state == NpcWorldBehavior.State.LOOT_APPROACH \
					and beh._loot_target_id == target_id
			if target_id != 0 and not already_chasing:
				beh.enter_loot_approach(target_id)
		"relax_at_home":
			# Leader waits at home while workers finish — don't interrupt an
			# existing idle/patrol cycle, only redirect if actively going elsewhere.
			match beh.state:
				NpcWorldBehavior.State.IDLE_AT_HOME, \
				NpcWorldBehavior.State.PATROL, \
				NpcWorldBehavior.State.RETURN_HOME:
					pass  # already resting or heading home
				_:
					beh.force_return_home()
		"return_home":
			beh.force_return_home()
		"assault_structure_target":
			var assault_pos: Vector2 = order.get("target_pos", Vector2.ZERO)
			if assault_pos != Vector2.ZERO:
				ctx["attack_target_pos"] = assault_pos
				beh.enter_wall_assault(assault_pos)
				log_worker_event("enter_wall_assault_called", {
					"npc_id": beh.member_id,
					"group_id": beh.group_id,
					"target_pos": assault_pos,
				})
		"attack_target":
			var attack_pos: Vector2 = order.get("target_pos", Vector2.ZERO)
			if attack_pos != Vector2.ZERO:
				ctx["attack_target_pos"] = attack_pos
				beh.enter_extort_approach(attack_pos)


func _try_member_structure_assault_retarget(beh: BanditWorldBehavior, ctx: Dictionary, reason: String) -> bool:
	if beh == null:
		return false
	var group_id: String = String(beh.group_id)
	if group_id == "":
		return false
	var node_pos: Vector2 = ctx.get("node_pos", beh.home_pos) as Vector2
	var intent: Dictionary = BanditGroupMemory.get_assault_target_intent(group_id)
	var anchor_pos: Vector2 = INVALID_STRUCTURE_TARGET
	if not intent.is_empty():
		anchor_pos = intent.get("anchor", INVALID_STRUCTURE_TARGET) as Vector2
	if not _is_valid_structure_target(anchor_pos):
		var pending: Vector2 = BanditGroupMemory.get_assault_target(group_id)
		if _is_valid_structure_target(pending):
			anchor_pos = pending
	if not _is_valid_structure_target(anchor_pos):
		var g: Dictionary = BanditGroupMemory.get_group(group_id)
		if String(g.get("last_interest_kind", "")) == "structure_assault_target":
			anchor_pos = g.get("last_interest_pos", INVALID_STRUCTURE_TARGET) as Vector2
	if not _is_valid_structure_target(anchor_pos):
		anchor_pos = node_pos
	var candidate: Vector2 = _resolve_member_assault_target(node_pos, anchor_pos, [])
	if not _is_valid_structure_target(candidate):
		return false
	if not _is_structure_target_still_valid(candidate):
		var pool: Array[Vector2] = _build_structure_target_pool_cached(group_id, anchor_pos)
		candidate = _pick_member_target_from_pool(node_pos, anchor_pos, pool, [])
		if not _is_valid_structure_target(candidate) or not _is_structure_target_still_valid(candidate):
			return false
	beh.enter_wall_assault(candidate)
	BanditGroupMemory.refresh_assault_target_pos(
		group_id,
		anchor_pos,
		candidate,
		BanditTuning.structure_assault_active_ttl()
	)
	BanditGroupMemory.record_interest(group_id, candidate, "structure_assault_target")
	log_worker_event("structure_assault_live_retarget_from_layer", {
		"npc_id": beh.member_id,
		"group_id": group_id,
		"target_pos": candidate,
		"reason": reason,
	})
	return true


func _has_canonical_pipeline_intent(intent_record: Dictionary) -> bool:
	if intent_record.is_empty():
		return false
	if String(intent_record.get("kind", "")) != "group_intent_decision":
		return false
	return not String(intent_record.get("decision_type", "")).is_empty()


func _group_has_canonical_pipeline_intent(group_id: String) -> bool:
	if group_id == "":
		return false
	var blackboard: Dictionary = BanditGroupMemory.bb_get(group_id)
	var status: Dictionary = blackboard.get("status", {}) as Dictionary
	var canonical_intent_entry: Dictionary = status.get("canonical_intent_record", {}) as Dictionary
	var canonical_intent: Dictionary = canonical_intent_entry.get("value", {}) as Dictionary
	return _has_canonical_pipeline_intent(canonical_intent)


func _resolve_member_simulation_profile_decision(
		beh: BanditWorldBehavior,
		node: Node,
		node_pos: Vector2,
		member_order: Dictionary) -> Dictionary:
	if _group_lod_profile_decisions.has(beh.member_id):
		return _group_lod_profile_decisions[beh.member_id] as Dictionary
	if beh.role == "leader" or beh.role == "bodyguard":
		return {
			"profile": String(SIM_PROFILE_FULL),
			"reason": "forced_role",
			"event_triggered": false,
		}
	var player_dist_sq: float = INF
	if _player != null and is_instance_valid(_player):
		player_dist_sq = node_pos.distance_squared_to(_player.global_position)
	var runtime_signals: Dictionary = _get_runtime_lod_signals(node)
	var in_combat: bool = bool(runtime_signals.get("is_in_direct_combat", false))
	var recently_engaged: bool = bool(runtime_signals.get("was_recently_engaged", false))
	var has_active_task: bool = is_worker_cycle_active(beh) \
			or beh.pending_collect_id != 0 \
			or beh.pending_mine_id != 0 \
			or beh.cargo_count > 0
	var has_order: bool = not member_order.is_empty()
	var is_near_player: bool = player_dist_sq <= OBEDIENT_PLAYER_NEAR_DISTANCE_SQ
	var is_far_player: bool = player_dist_sq >= DECORATIVE_PLAYER_FAR_DISTANCE_SQ
	if in_combat or recently_engaged or is_near_player:
		return {
			"profile": String(SIM_PROFILE_FULL),
			"reason": "fallback_event",
			"event_triggered": true,
		}
	if has_active_task or has_order:
		return {
			"profile": String(SIM_PROFILE_OBEDIENT),
			"reason": "fallback_task_obedient",
			"event_triggered": false,
		}
	if is_far_player:
		return {
			"profile": String(SIM_PROFILE_DECORATIVE),
			"reason": "fallback_far_decorative",
			"event_triggered": false,
		}
	return {
		"profile": String(SIM_PROFILE_OBEDIENT),
		"reason": "fallback_obedient",
		"event_triggered": false,
	}


func _build_group_lod_profile_decisions(orders_by_member: Dictionary) -> Dictionary:
	var members_by_group: Dictionary = {}
	for enemy_id in _behaviors.keys():
		var beh: BanditWorldBehavior = _behaviors.get(enemy_id) as BanditWorldBehavior
		if beh == null or beh.group_id == "":
			continue
		var node: Node = _npc_simulator.get_enemy_node(enemy_id)
		if node == null:
			continue
		var node_pos: Vector2 = _effective_work_position(node)
		var player_dist_sq: float = INF
		if _player != null and is_instance_valid(_player):
			player_dist_sq = node_pos.distance_squared_to(_player.global_position)
		var runtime_signals: Dictionary = _get_runtime_lod_signals(node)
		var intent: String = String(BanditGroupMemory.get_group(beh.group_id).get("current_group_intent", "idle"))
		var threat_detected: bool = intent == "alerted" or intent == "hunting" or intent == "extorting" or intent == "raiding"
		if not members_by_group.has(beh.group_id):
			members_by_group[beh.group_id] = []
		(members_by_group[beh.group_id] as Array).append({
			"member_id": beh.member_id,
			"role": beh.role,
			"in_combat": bool(runtime_signals.get("is_in_direct_combat", false)),
			"recently_engaged": bool(runtime_signals.get("was_recently_engaged", false)),
			"threat_detected": threat_detected,
			"player_near": player_dist_sq <= OBEDIENT_PLAYER_NEAR_DISTANCE_SQ,
			"player_mid": player_dist_sq <= DECORATIVE_PLAYER_FAR_DISTANCE_SQ,
			"player_far": player_dist_sq >= DECORATIVE_PLAYER_FAR_DISTANCE_SQ,
			"has_order": orders_by_member.has(beh.member_id) and not (orders_by_member.get(beh.member_id, {}) as Dictionary).is_empty(),
			"has_active_task": is_worker_cycle_active(beh) or beh.pending_collect_id != 0 or beh.pending_mine_id != 0 or beh.cargo_count > 0,
			"is_worker_cycle_active": is_worker_cycle_active(beh),
			"is_visible": (node as CanvasItem).is_visible_in_tree() if node is CanvasItem else false,
			"has_cargo": beh.cargo_count > 0,
		})
	var decisions: Dictionary = {}
	for group_id in members_by_group.keys():
		var assignment: Dictionary = SimulationLODPolicyScript.assign_group_member_profiles({
			"members": members_by_group[group_id],
			"max_full_per_group": LOD_MAX_FULL_PER_GROUP,
		})
		var group_decisions: Dictionary = assignment.get("decisions", {})
		var full_budget: int = int(assignment.get("budget", LOD_MAX_FULL_PER_GROUP))
		var full_count: int = int(assignment.get("full_count", 0))
		for member_id in group_decisions.keys():
			var entry: Dictionary = group_decisions[member_id] as Dictionary
			entry["group_id"] = String(group_id)
			entry["full_budget"] = full_budget
			entry["full_count"] = full_count
			group_decisions[member_id] = entry
		decisions.merge(group_decisions, true)
	return decisions


func _record_profile_stability_metrics(member_id: String, _group_id: String, profile: StringName, decision: Dictionary) -> void:
	var previous_profile: String = String(_lod_profile_last_by_member.get(member_id, ""))
	var current_profile: String = String(profile)
	_lod_profile_last_by_member[member_id] = current_profile
	var budget_exceeded: bool = String(decision.get("reason", "")).begins_with("budget_exceeded")
	var reactivation_by_event: bool = previous_profile != String(SIM_PROFILE_FULL) \
			and current_profile == String(SIM_PROFILE_FULL) \
			and bool(decision.get("event_triggered", false))
	_accumulate_perf_window({
		"profile_full_count": 1 if current_profile == String(SIM_PROFILE_FULL) else 0,
		"profile_obedient_count": 1 if current_profile == String(SIM_PROFILE_OBEDIENT) else 0,
		"profile_decorative_count": 1 if current_profile == String(SIM_PROFILE_DECORATIVE) else 0,
		"profile_switches_total": 1 if previous_profile != "" and previous_profile != current_profile else 0,
		"profile_budget_downgrades": 1 if budget_exceeded else 0,
		"profile_event_reactivations": 1 if reactivation_by_event else 0,
	})


func _apply_member_simulation_profile(node: Node, profile: StringName) -> void:
	if node == null:
		return
	var ai_comp = node.get("ai_component")
	if ai_comp == null:
		return
	if ai_comp.has_method("set_simulation_profile"):
		ai_comp.call("set_simulation_profile", profile)


# ---------------------------------------------------------------------------
# Group perception pulse
# ---------------------------------------------------------------------------

func _build_group_perception_payload(res_nodes_snapshot: Array) -> Dictionary:
	var payload: Dictionary = {}
	if not BanditTuningScript.enable_group_perception_pulse():
		return payload
	var groups: Dictionary = {}
	for enemy_id in _behaviors.keys():
		var beh: BanditWorldBehavior = _behaviors.get(enemy_id) as BanditWorldBehavior
		if beh == null or beh.group_id == "":
			continue
		if not groups.has(beh.group_id):
			groups[beh.group_id] = []
		(groups[beh.group_id] as Array).append({
			"enemy_id": String(enemy_id),
			"member_id": beh.member_id,
			"role": beh.role,
			"behavior": beh,
		})
	for group_id in groups.keys():
		var entry: Dictionary = _run_group_perception_pulse(group_id, groups[group_id] as Array, res_nodes_snapshot)
		if not entry.is_empty():
			payload[group_id] = entry
	return payload


func _run_group_perception_pulse(group_id: String, members: Array, res_nodes_snapshot: Array) -> Dictionary:
	var elapsed: float = float(_group_perception_elapsed.get(group_id, 0.0)) + BanditTuningScript.behavior_tick_interval()
	var owner: Dictionary = _select_group_scan_owner(group_id, members)
	if owner.is_empty():
		_group_perception_elapsed[group_id] = elapsed
		return {}
	var owner_pos: Vector2 = owner.get("node_pos", Vector2.ZERO)
	var interval: float = _group_perception_interval_for(group_id, owner_pos)
	if elapsed < interval:
		_group_perception_elapsed[group_id] = elapsed
		return {
			"owner_id": String(owner.get("member_id", "")),
			"owner_role": String(owner.get("owner_role", "")),
			"scanned": false,
		}
	_group_perception_elapsed[group_id] = 0.0
	_group_scan_owner_cache[group_id] = {
		"member_id": String(owner.get("member_id", "")),
		"owner_role": String(owner.get("owner_role", "")),
	}
	var drops: Array[Dictionary] = []
	var resources: Array[Dictionary] = []
	_fill_drops_info_buffer(owner_pos, drops)
	_fill_res_info_buffer(owner.get("behavior"), owner_pos, res_nodes_snapshot, resources)
	var home_pos: Vector2 = Vector2(BanditGroupMemory.get_group(group_id).get("home_world_pos", owner_pos))
	var prioritized_drops: Array = _prioritize_group_drops(owner_pos, drops)
	var prioritized_resources: Array = _prioritize_group_resources(home_pos, resources)
	BanditGroupMemory.bb_set_status(group_id, "scan_responsible_id", String(owner.get("member_id", "")), BanditGroupMemory.BLACKBOARD_STATUS_TTL, "group_perception_pulse")
	BanditGroupMemory.bb_set_status(group_id, "scan_responsible_role", String(owner.get("owner_role", "")), BanditGroupMemory.BLACKBOARD_STATUS_TTL, "group_perception_pulse")
	BanditGroupMemory.bb_write_prioritized_drops(group_id, prioritized_drops, 20.0, "group_perception_pulse")
	BanditGroupMemory.bb_write_prioritized_resources(group_id, prioritized_resources, 45.0, "group_perception_pulse")
	return {
		"owner_id": String(owner.get("member_id", "")),
		"owner_role": String(owner.get("owner_role", "")),
		"scanned": true,
	}


func _select_group_scan_owner(group_id: String, members: Array) -> Dictionary:
	var best_subleader: Dictionary = {}
	var best_member: Dictionary = {}
	for raw in members:
		if not (raw is Dictionary):
			continue
		var member: Dictionary = raw as Dictionary
		var enemy_id: String = String(member.get("enemy_id", ""))
		var node = _npc_simulator.get_enemy_node(enemy_id)
		if not _is_world_behavior_eligible(node):
			continue
		var node2d := node as Node2D
		if node2d == null:
			continue
		var role: String = String(member.get("role", ""))
		if role == "leader":
			return {
				"member_id": String(member.get("member_id", "")),
				"owner_role": "leader",
				"node_pos": node2d.global_position,
				"behavior": member.get("behavior"),
			}
		if role == "bodyguard" and best_subleader.is_empty():
			best_subleader = {
				"member_id": String(member.get("member_id", "")),
				"owner_role": "subleader_functional",
				"node_pos": node2d.global_position,
				"behavior": member.get("behavior"),
			}
		if best_member.is_empty():
			best_member = {
				"member_id": String(member.get("member_id", "")),
				"owner_role": "member_fallback",
				"node_pos": node2d.global_position,
				"behavior": member.get("behavior"),
			}
	if not best_subleader.is_empty():
		return best_subleader
	var cached: Dictionary = _group_scan_owner_cache.get(group_id, {})
	if not cached.is_empty():
		for raw in members:
			if not (raw is Dictionary):
				continue
			var member: Dictionary = raw as Dictionary
			if String(member.get("member_id", "")) != String(cached.get("member_id", "")):
				continue
			var enemy_id_cached: String = String(member.get("enemy_id", ""))
			var node_cached = _npc_simulator.get_enemy_node(enemy_id_cached)
			var node2d_cached := node_cached as Node2D
			if node2d_cached != null and _is_world_behavior_eligible(node_cached):
				return {
					"member_id": String(member.get("member_id", "")),
					"owner_role": String(cached.get("owner_role", "member_fallback")),
					"node_pos": node2d_cached.global_position,
					"behavior": member.get("behavior"),
				}
	return best_member


func _group_perception_interval_for(group_id: String, anchor_pos: Vector2) -> float:
	var base: float = BanditTuningScript.group_scan_interval()
	var g: Dictionary = BanditGroupMemory.get_group(group_id)
	var intent: String = String(g.get("current_group_intent", "idle"))
	if intent == "extorting" or intent == "hunting":
		base *= 0.5
	elif intent == "alerted":
		base *= 0.75
	var distance_to_player: float = INF
	if _player != null and is_instance_valid(_player):
		distance_to_player = anchor_pos.distance_to(_player.global_position)
	if distance_to_player <= 260.0:
		base *= 0.5
	elif distance_to_player <= 560.0:
		base *= 0.7
	elif distance_to_player >= 1400.0:
		base *= 1.4
	return clampf(base, 1.25, BanditTuningScript.group_scan_interval() * 2.0)


func _prioritize_group_drops(anchor_pos: Vector2, drops: Array) -> Array:
	if _perception_system == null:
		return []
	return _perception_system.prioritize_group_drops(anchor_pos, drops)


func _prioritize_group_resources(anchor_pos: Vector2, resources: Array) -> Array:
	if _perception_system == null:
		return []
	return _perception_system.prioritize_group_resources(anchor_pos, resources)


func _fill_from_group_blackboard(beh: BanditWorldBehavior, node_pos: Vector2, drops_out: Array[Dictionary], resources_out: Array[Dictionary]) -> bool:
	if _perception_system == null or beh.group_id == "":
		return false
	return _perception_system.fill_from_group_blackboard(beh.group_id, node_pos, drops_out, resources_out)


# ---------------------------------------------------------------------------
# ctx builders
# ---------------------------------------------------------------------------

func _effective_work_position(enemy_node: Node) -> Vector2:
	# Source-of-truth for loot/resource work scans is always the active member
	# position. Never pivot local pickup queries to leader/group/camp anchors,
	# otherwise drops generated by the miner can fall outside its own scan list.
	var node2d := enemy_node as Node2D
	return node2d.global_position if node2d != null else Vector2.ZERO

func _build_behavior_perception_context(input: Dictionary) -> Dictionary:
	if _perception_system == null:
		return input.duplicate(true)
	return _perception_system.build_member_context(input)

func _fill_drops_info_buffer(node_pos: Vector2, out: Array[Dictionary]) -> void:
	if _perception_system == null:
		out.clear()
		return
	_perception_system.fill_drops_info_buffer(node_pos, out, DROP_SCAN_ENOUGH_THRESHOLD, DROP_SCAN_MAX_CANDIDATES_EVAL)


func _fill_res_info_buffer(beh: BanditWorldBehavior, node_pos: Vector2,
		all_resources: Array, out: Array[Dictionary]) -> void:
	if _perception_system == null:
		out.clear()
		return
	_perception_system.fill_res_info_buffer(beh, node_pos, all_resources, out)


func _get_all_resource_nodes() -> Array:
	if _world_spatial_index != null:
		return _world_spatial_index.get_all_runtime_nodes(WorldSpatialIndex.KIND_WORLD_RESOURCE)
	return get_tree().get_nodes_in_group("world_resource")


func _log_missing_world_spatial_index_once(stage: String) -> void:
	if _missing_world_index_error_logged:
		return
	_missing_world_index_error_logged = true
	push_error("BanditBehaviorLayer initialization error: world_spatial_index is null (stage=%s)." % stage)


# ---------------------------------------------------------------------------
# Lazy behavior creation
# ---------------------------------------------------------------------------

func _ensure_behavior_for_enemy(enemy_id_str: String, node: Node = null,
		allow_runtime_fallback: bool = false) -> BanditWorldBehavior:
	if _behaviors.has(enemy_id_str):
		return _behaviors.get(enemy_id_str, null) as BanditWorldBehavior
	if _npc_simulator == null:
		return null

	var enemy_node: Node = node if node != null else _npc_simulator.get_enemy_node(enemy_id_str)
	if enemy_node == null:
		return null

	var save_state: Dictionary = _get_save_state_for(enemy_id_str)
	var group_id: String = String(save_state.get("group_id", ""))
	if group_id == "" and allow_runtime_fallback and "group_id" in enemy_node:
		group_id = String(enemy_node.get("group_id"))
	if group_id == "":
		return null

	var role: String = String(save_state.get("role", ""))
	if role == "":
		role = "bodyguard" if allow_runtime_fallback else "scavenger"

	var faction_id: String = String(save_state.get("faction_id", ""))
	if faction_id == "":
		var g_fallback: Dictionary = BanditGroupMemory.get_group(group_id)
		faction_id = String(g_fallback.get("faction_id", "bandits"))

	var home_pos: Vector2 = _get_home_pos(save_state)
	if home_pos == Vector2.ZERO and allow_runtime_fallback:
		var g_home: Dictionary = BanditGroupMemory.get_group(group_id)
		if g_home.has("home_world_pos"):
			var hpos = g_home.get("home_world_pos", Vector2.ZERO)
			if hpos is Vector2:
				home_pos = hpos as Vector2
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
	Debug.log("bandit_ai", "[BanditBL] behavior created id=%s role=%s group=%s cargo_cap=%d home=%s fallback=%s" % [
		enemy_id_str, beh.role, beh.group_id, beh.cargo_capacity, str(beh.home_pos),
		str(allow_runtime_fallback)])
	return beh


func _ensure_behaviors_for_active_enemies() -> void:
	for enemy_id in _npc_simulator.active_enemies:
		var enemy_id_str: String = String(enemy_id)
		if _behaviors.has(enemy_id_str):
			continue
		var node = _npc_simulator.get_enemy_node(enemy_id_str)
		if not _is_world_behavior_eligible(node):
			continue
		var beh: BanditWorldBehavior = _ensure_behavior_for_enemy(enemy_id_str, node, false)
		if beh == null:
			continue
		# Si el grupo tiene un assault pendiente (colocaciï¿½fÂ³n de estructura mientras no estaban spawneados)
		var assault_target: Vector2 = BanditGroupMemory.get_assault_target(beh.group_id)
		if assault_target.x >= 0.0:
			beh.enter_wall_assault(assault_target)
			_apply_structure_assault_focus(node)
			Debug.log("placement_react", "[BBL] pending assault applied on spawn id=%s group=%s target=%s" % [
				enemy_id_str, beh.group_id, str(assault_target)])


# ---------------------------------------------------------------------------
# Pruning
# ---------------------------------------------------------------------------

func _prune_behaviors() -> void:
	var to_remove: Array[String] = _dispatch_work_buffers.prune_ids
	to_remove.clear()
	for enemy_id in _behaviors:
		if _npc_simulator.get_enemy_node(enemy_id) == null:
			to_remove.append(String(enemy_id))
	for enemy_id in to_remove:
		_release_structure_target_slot_for_member(enemy_id)
		_structure_reassign_cooldown_until_by_member.erase(enemy_id)
		_behaviors.erase(enemy_id)
		_behavior_elapsed.erase(enemy_id)
		if NpcPathService.is_ready():
			NpcPathService.clear_agent(enemy_id)
		Debug.log("bandit_ai", "[BanditBL] behavior pruned id=%s" % enemy_id)


func _is_world_behavior_eligible(node: Node) -> bool:
	if node == null:
		return false
	if not _method_caps.has_method_cached(node, &"is_world_behavior_eligible"):
		return false
	return node.is_world_behavior_eligible()


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
	var g: Dictionary = BanditGroupMemory.get_group(beh.group_id)
	if String(g.get("current_group_intent", "")) != "hunting":
		return
	# Cooldown por NPC
	if RunClock.now() < beh.recognition_bubble_until:
		return
	# Solo si el jugador estï¿½fÂ¡ cerca
	if _player.global_position.distance_squared_to(node_pos) > RECOGNITION_RANGE_SQ:
		return
	# Nivel de hostilidad suficiente
	var faction_id: String = String(g.get("faction_id", ""))
	if faction_id == "":
		return
	var h_level: int = FactionHostilityManager.get_hostility_level(faction_id)
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
	beh.recognition_bubble_until = RunClock.now() + RECOGNITION_COOLDOWN
	Debug.log("bandit_ai", "[BBL] recognition bubble npc=%s h_level=%d tier=%d" % [
		beh.member_id, h_level, phrase_tier])


# ---------------------------------------------------------------------------
# Idle chat Ã¢ï¿½,ï¿½ï¿½?ï¿½ diï¿½fÂ¡logo ambiental de mundo
# ---------------------------------------------------------------------------

## Dispara una frase ambiental ocasional cuando el NPC estï¿½fÂ¡ ocioso o patrullando,
## sin que el jugador estï¿½fÂ© cerca. Crea sensaciï¿½fÂ³n de mundo vivo.
func _maybe_show_idle_chat(beh: BanditWorldBehavior,
		node: Node, node_pos: Vector2) -> void:
	if beh.cargo_count > 0:
		return
	if _bubble_manager == null:
		return
	# Cooldown por NPC (escalonado desde setup para que no hablen todos a la vez)
	if RunClock.now() < beh.idle_chat_until:
		return
	# Solo en estados ociosos Ã¢ï¿½,ï¿½ï¿½?ï¿½ no mientras caza, extorsiona, carga material ni vuelve al camp
	var state_ok: bool = beh.state == NpcWorldBehavior.State.IDLE_AT_HOME \
		or beh.state == NpcWorldBehavior.State.PATROL
	if not state_ok:
		return
	# No chatear si el grupo estï¿½fÂ¡ en intenciï¿½fÂ³n activa
	if beh.group_id != "":
		var g: Dictionary = BanditGroupMemory.get_group(beh.group_id)
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
		beh.idle_chat_until = RunClock.now() + 2.0  # micro-cooldown para no re-tirar cada frame
		return
	var phrase: String = IDLE_CHAT_PHRASES[randi() % IDLE_CHAT_PHRASES.size()]
	_bubble_manager.show_actor_bubble(node as Node2D, phrase, 3.5)
	# Cooldown aleatorio para que cada NPC hable a su propio ritmo
	beh.idle_chat_until = RunClock.now() + randf_range(IDLE_CHAT_COOLDOWN_MIN, IDLE_CHAT_COOLDOWN_MAX)


func _enforce_cargo_return_priority(beh: BanditWorldBehavior, member_pos: Vector2, stage: String) -> void:
	if beh == null or beh.cargo_count <= 0:
		if beh != null:
			_cargo_return_block_reason_by_member.erase(beh.member_id)
		return
	if beh.delivery_lock_active and beh.state != NpcWorldBehavior.State.RETURN_HOME:
		log_worker_event("return_home_triggered", {
			"npc_id": beh.member_id,
			"group_id": beh.group_id,
			"camp_id": beh.group_id,
			"state": str(int(beh.state)),
			"target_id": "",
			"position_used": "%.2f,%.2f" % [member_pos.x, member_pos.y],
			"reason": "delivery_lock_active",
			"stage": stage,
		})
	if beh.state == NpcWorldBehavior.State.RETURN_HOME:
		_cargo_return_block_reason_by_member.erase(beh.member_id)
		return
	if beh.deposit_lock_active:
		log_worker_event("deposit_lock_retry", {
			"npc_id": beh.member_id,
			"group_id": beh.group_id,
			"cargo": beh.cargo_count,
			"state_before": str(int(beh.state)),
			"stage": stage,
		})
	var prev_state: int = int(beh.state)
	beh.force_return_home()
	log_worker_event("cargo_not_returning", {
		"npc_id": beh.member_id,
		"group_id": beh.group_id,
		"camp_id": beh.group_id,
		"state": str(int(beh.state)),
		"target_id": "",
		"position_used": "%.2f,%.2f" % [member_pos.x, member_pos.y],
		"reason": "cargo_return_preempted",
		"cause": "non_return_state_with_cargo",
		"from_state": str(prev_state),
		"stage": stage,
	})


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
	if _structure_repaths_this_pulse >= STRUCTURE_REPATHS_PER_PULSE_BUDGET:
		if _can_emit_dispatch_log(group_id, 0.4):
			Debug.log("placement_react", "[BBL] dispatch aborted group=%s reason=repath_budget pulse=%d/%d" % [
				group_id,
				_structure_repaths_this_pulse,
				STRUCTURE_REPATHS_PER_PULSE_BUDGET,
			])
		return 0
	var cap: int = squad_size if squad_size > 0 else 999999
	var member_ids: Array[String] = _collect_live_structure_dispatch_member_ids(group_id, target_pos, cap)
	if member_ids.is_empty():
		BanditGroupMemory.set_assault_target(group_id, target_pos)
		if _can_emit_dispatch_log(group_id, 0.8):
			Debug.log("placement_react", "[BBL] dispatch queued (no spawneados) group=%s target=%s" % [
				group_id, str(target_pos)])
		return 0

	var target_pool: Array[Vector2] = _build_structure_target_pool_cached(group_id, target_pos)
	var claimed_targets: Array[Vector2] = []
	var team_targets: Dictionary = _load_group_sticky_team_targets(group_id)
	var immediate_count: int = mini(STRUCTURE_DISPATCH_SYNC_BUDGET, member_ids.size())
	var immediate_result: Dictionary = _dispatch_structure_members_slice(
		group_id,
		member_ids,
		0,
		immediate_count,
		target_pos,
		target_pool,
		claimed_targets,
		team_targets
	)
	var immediate_redirected: int = int(immediate_result.get("redirected", 0))
	var immediate_processed: int = int(immediate_result.get("processed", 0))

	if immediate_processed < member_ids.size():
		_enqueue_pending_structure_dispatch(
			group_id,
			target_pos,
			member_ids,
			immediate_processed,
			target_pool,
			claimed_targets,
			team_targets
		)
		if _can_emit_dispatch_log(group_id, 0.8):
			Debug.log("placement_react", "[BBL] dispatch deferred group=%s anchor=%s now=%d later=%d budget=%d" % [
				group_id,
				str(target_pos),
				immediate_redirected,
				member_ids.size() - immediate_processed,
				STRUCTURE_DISPATCH_FRAME_BUDGET,
			])

	BanditGroupMemory.clear_assault_target(group_id)
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
	if _structure_repaths_this_pulse >= STRUCTURE_REPATHS_PER_PULSE_BUDGET:
		return
	var budget: int = STRUCTURE_DISPATCH_FRAME_BUDGET
	var idx: int = 0
	while idx < _pending_structure_dispatches.size() and budget > 0:
		var job: Dictionary = _pending_structure_dispatches[idx] as Dictionary
		var gid: String = String(job.get("group_id", ""))
		if gid == "" or BanditGroupMemory.get_group(gid).is_empty():
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
		var slice_result: Dictionary = _dispatch_structure_members_slice(
			gid,
			member_ids,
			next_idx,
			chunk,
			anchor,
			target_pool,
			claimed_targets,
			team_targets
		)
		var processed: int = int(slice_result.get("processed", 0))
		next_idx += processed
		budget -= processed
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
		if processed <= 0:
			break
		idx += 1


func _dispatch_structure_members_slice(group_id: String, member_ids: Array, start_idx: int,
		count: int, anchor_pos: Vector2, target_pool: Array,
		claimed_targets: Array, team_targets: Dictionary) -> Dictionary:
	if _npc_simulator == null:
		return {"redirected": 0, "processed": 0}
	if count <= 0:
		return {"redirected": 0, "processed": 0}
	var redirected: int = 0
	var processed: int = 0
	var end_idx: int = mini(start_idx + count, member_ids.size())
	var validated_team_keys: Dictionary = {}
	for idx in range(start_idx, end_idx):
		if _structure_repaths_this_pulse >= STRUCTURE_REPATHS_PER_PULSE_BUDGET:
			break
		var member_id: String = String(member_ids[idx])
		var node = _npc_simulator.get_enemy_node(member_id)
		if node == null:
			processed += 1
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
		if _is_valid_structure_target(member_target) \
				and not _is_structure_target_slot_available(member_target, member_id):
			member_target = _pick_member_target_with_available_slot(
				member_pos,
				anchor_pos,
				target_pool,
				claimed_targets,
				member_id
			)
			team_targets[team_key] = member_target
		if not _is_valid_structure_target(member_target):
			_release_structure_target_slot_for_member(member_id)
			processed += 1
			continue
		if not _assign_structure_target_slot(group_id, member_id, member_target):
			processed += 1
			continue
		claimed_targets.append(member_target)
		if _is_valid_structure_target(member_target):
			BanditGroupMemory.bb_set_assignment(group_id, member_id, {
				"order": "assault_structure_target",
				"target_pos": member_target,
			}, 8.0, "structure_dispatch")
			log_worker_event("structure_assault_target_assigned", {
				"group_id": group_id,
				"npc_id": member_id,
				"target_pos": member_target,
			})
		_apply_structure_assault_focus(node)
		if _is_member_already_assaulting_near_target(group_id, member_id, member_target):
			processed += 1
			continue
		var beh_force: BanditWorldBehavior = _ensure_behavior_for_enemy(member_id, node, true)
		if beh_force != null and beh_force.group_id == group_id:
			beh_force.enter_wall_assault(member_target)
			_note_structure_member_repath(member_id)
			redirected += 1
			processed += 1
			continue
		var wb = node.get_node_or_null("WorldBehavior")
		if wb != null and wb.has_method("enter_wall_assault"):
			wb.call("enter_wall_assault", member_target)
			_note_structure_member_repath(member_id)
			redirected += 1
		processed += 1
	return {"redirected": redirected, "processed": processed}


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


func _pick_member_target_with_available_slot(member_pos: Vector2, anchor_pos: Vector2,
		target_pool: Array, claimed_targets: Array, member_id: String) -> Vector2:
	var current_target_key: String = String(_structure_target_by_member.get(member_id, ""))
	var preferred: Vector2 = _pick_member_target_from_pool(member_pos, anchor_pos, target_pool, claimed_targets)
	if _is_valid_structure_target(preferred) and _is_structure_target_slot_available(preferred, member_id):
		return preferred
	var best: Vector2 = INVALID_STRUCTURE_TARGET
	var best_dsq: float = INF
	for candidate in target_pool:
		if not (candidate is Vector2):
			continue
		var target_candidate: Vector2 = candidate as Vector2
		if not _is_valid_structure_target(target_candidate):
			continue
		var candidate_key: String = _structure_target_key(target_candidate)
		if candidate_key == current_target_key:
			if _is_structure_target_slot_available(target_candidate, member_id):
				return target_candidate
			continue
		if not _is_structure_target_slot_available(target_candidate, member_id):
			continue
		var dsq: float = member_pos.distance_squared_to(target_candidate)
		if dsq < best_dsq:
			best_dsq = dsq
			best = target_candidate
	if _is_valid_structure_target(best):
		return best
	return INVALID_STRUCTURE_TARGET


func _build_structure_target_pool_cached(group_id: String, anchor_pos: Vector2) -> Array[Vector2]:
	if group_id == "":
		return _build_structure_target_pool(anchor_pos)
	var key: String = _get_target_pool_cache_key(anchor_pos)
	var now: float = RunClock.now()
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
	_fill_wall_samples_buffer(anchor_pos, _structure_work_buffers.wall_samples)
	_append_scored_wall_samples(pool, _structure_work_buffers.wall_samples, anchor_pos)
	_fill_structure_query_centers_buffer(anchor_pos, anchor_pos, _structure_work_buffers.member_query_centers)
	for center in _structure_work_buffers.member_query_centers:
		# Los walls ya vienen del sampler dedicado; aquí solo sumar
		# placeables/contenedores para evitar queries redundantes de pared.
		_append_structure_candidates_for_center(pool, center, STRUCTURE_MEMBER_QUERY_RADIUS, false)
		if pool.size() >= STRUCTURE_MEMBER_CANDIDATE_LIMIT:
			break
	if pool.is_empty():
		pool.append(anchor_pos)
	return pool


func _fill_wall_samples_buffer(anchor_pos: Vector2, out: Array[Vector2]) -> void:
	out.clear()
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
		return
	if not _find_wall_cb.is_valid():
		return
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


func _append_scored_wall_samples(pool: Array[Vector2], wall_samples: Array[Vector2], anchor_pos: Vector2) -> void:
	if wall_samples.is_empty():
		return
	var rows: Array[Dictionary] = _structure_work_buffers.wall_rows
	rows.clear()
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

	var clustered_rows: Array[Dictionary] = _structure_work_buffers.clustered_rows
	clustered_rows.clear()
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
	var rows: Array[Dictionary] = _structure_work_buffers.dispatch_rows
	rows.clear()
	var seen: Dictionary = {}
	for eid in _behaviors:
		var beh: BanditWorldBehavior = _behaviors[eid]
		if beh.group_id != group_id:
			continue
		if not _is_structure_dispatch_role_allowed(String(beh.role)):
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
		var g: Dictionary = BanditGroupMemory.get_group(group_id)
		for mid in g.get("member_ids", []):
			var mid_str: String = String(mid)
			if seen.has(mid_str):
				continue
			if not _is_structure_dispatch_role_allowed(_resolve_structure_dispatch_member_role(mid_str)):
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


func _is_structure_dispatch_role_allowed(role: String) -> bool:
	if role == "bodyguard":
		return true
	if role == "leader":
		return structure_dispatch_allow_leader
	return false


func _resolve_structure_dispatch_member_role(member_id: String) -> String:
	if _behaviors.has(member_id):
		var beh: BanditWorldBehavior = _behaviors[member_id]
		return String(beh.role)
	if NpcProfileSystem != null and NpcProfileSystem.has_method("get_profile"):
		var profile: Dictionary = NpcProfileSystem.get_profile(member_id) as Dictionary
		return String(profile.get("role", ""))
	return ""


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


func _structure_target_key(target_pos: Vector2) -> String:
	return _get_target_valid_cache_key(target_pos)


func _is_structure_target_slot_available(target_pos: Vector2, member_id: String) -> bool:
	if not _is_valid_structure_target(target_pos):
		return false
	var key: String = _structure_target_key(target_pos)
	var current_key: String = String(_structure_target_by_member.get(member_id, ""))
	if current_key == key:
		return true
	var assigned: int = int(_structure_target_attackers_assigned.get(key, 0))
	return assigned < BanditTuningScript.max_attackers_per_structure()


func _assign_structure_target_slot(group_id: String, member_id: String, target_pos: Vector2) -> bool:
	if member_id == "" or group_id == "" or not _is_valid_structure_target(target_pos):
		return false
	var target_key: String = _structure_target_key(target_pos)
	var previous_key: String = String(_structure_target_by_member.get(member_id, ""))
	if previous_key == target_key:
		_structure_target_group_by_member[member_id] = group_id
		return true
	if previous_key != "" and not _can_member_reassign_structure_target(member_id):
		_structure_target_group_by_member[member_id] = group_id
		return false
	var assigned: int = int(_structure_target_attackers_assigned.get(target_key, 0))
	if assigned >= BanditTuningScript.max_attackers_per_structure():
		return false
	_release_structure_target_slot_for_member(member_id)
	_structure_target_attackers_assigned[target_key] = assigned + 1
	_structure_target_by_member[member_id] = target_key
	_structure_target_group_by_member[member_id] = group_id
	return true


func _can_member_reassign_structure_target(member_id: String) -> bool:
	if member_id == "":
		return true
	return RunClock.now() >= float(_structure_reassign_cooldown_until_by_member.get(member_id, 0.0))


func _note_structure_member_repath(member_id: String) -> void:
	_structure_repaths_this_pulse += 1
	if member_id == "":
		return
	_structure_reassign_cooldown_until_by_member[member_id] = \
		RunClock.now() + STRUCTURE_MEMBER_REASSIGN_COOLDOWN_S


func get_structure_dispatch_debug_snapshot() -> Dictionary:
	return {
		"repaths_this_pulse": _structure_repaths_this_pulse,
		"repaths_last_pulse": _structure_repaths_last_pulse,
		"pending_dispatch_jobs": _pending_structure_dispatches.size(),
		"scavenger_non_econ_orders": _debug_scavenger_non_econ_orders,
	}


func reset_structure_dispatch_debug_metrics() -> void:
	_structure_repaths_last_pulse = 0
	_structure_repaths_this_pulse = 0
	_debug_scavenger_non_econ_orders = 0


func _is_member_already_assaulting_near_target(group_id: String, member_id: String, target_pos: Vector2) -> bool:
	if group_id == "" or member_id == "" or not _is_valid_structure_target(target_pos):
		return false
	var assigned_key: String = String(_structure_target_by_member.get(member_id, ""))
	if assigned_key == "":
		return false
	var assigned_pos: Vector2 = _decode_structure_target_key_to_pos(assigned_key)
	if not _is_valid_structure_target(assigned_pos):
		return false
	return assigned_pos.distance_squared_to(target_pos) <= STRUCTURE_REDISPATCH_NEAR_TARGET_SQ


func _decode_structure_target_key_to_pos(target_key: String) -> Vector2:
	if target_key == "":
		return INVALID_STRUCTURE_TARGET
	var parts: PackedStringArray = target_key.split(":")
	if parts.size() != 2:
		return INVALID_STRUCTURE_TARGET
	var q: float = maxf(1.0, STRUCTURE_TARGET_CACHE_POS_QUANTUM)
	return Vector2(float(parts[0].to_int()) * q, float(parts[1].to_int()) * q)


func _release_structure_target_slot_for_member(member_id: String) -> void:
	if member_id == "":
		return
	var target_key: String = String(_structure_target_by_member.get(member_id, ""))
	if target_key != "":
		var current: int = int(_structure_target_attackers_assigned.get(target_key, 0))
		current = maxi(0, current - 1)
		if current <= 0:
			_structure_target_attackers_assigned.erase(target_key)
		else:
			_structure_target_attackers_assigned[target_key] = current
	_structure_target_by_member.erase(member_id)
	_structure_target_group_by_member.erase(member_id)


func _release_structure_slots_for_inactive_assaults() -> void:
	if _structure_target_by_member.is_empty():
		return
	var to_release: Array[String] = []
	for member_id_var in _structure_target_by_member.keys():
		var member_id: String = String(member_id_var)
		var group_id: String = String(_structure_target_group_by_member.get(member_id, ""))
		if group_id == "" or not BanditGroupMemory.is_structure_assault_active(group_id):
			to_release.append(member_id)
	for member_id in to_release:
		_release_structure_target_slot_for_member(member_id)


func _prune_structure_target_caches() -> void:
	var now: float = RunClock.now()
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
	var now: float = RunClock.now()
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
	var now: float = RunClock.now()
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
		"until": RunClock.now() + STRUCTURE_STICKY_TEAM_TARGET_TTL,
	}


func _is_structure_target_still_valid(target_pos: Vector2) -> bool:
	if not _is_valid_structure_target(target_pos):
		return false
	var cache_key: String = _get_target_valid_cache_key(target_pos)
	var now: float = RunClock.now()
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
	var query_centers: Array[Vector2] = _structure_work_buffers.member_query_centers
	_fill_structure_query_centers_buffer(member_pos, anchor_pos, query_centers)
	var candidates: Array[Vector2] = _structure_work_buffers.member_candidates
	candidates.clear()
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
	var centers: Array[Vector2] = []
	_fill_structure_query_centers_buffer(member_pos, anchor_pos, centers)
	return centers


func _fill_structure_query_centers_buffer(member_pos: Vector2, anchor_pos: Vector2, out: Array[Vector2]) -> void:
	out.clear()
	out.append(member_pos)
	if member_pos.distance_squared_to(anchor_pos) > 1.0:
		out.append(anchor_pos)
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
		out.append(member_pos + dir * STRUCTURE_MEMBER_QUERY_RING_RADIUS)
		if member_pos.distance_squared_to(anchor_pos) > 1.0:
			out.append(anchor_pos + dir * STRUCTURE_MEMBER_QUERY_RING_RADIUS)


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


func _group_has_live_structure_target(group_id: String) -> bool:
	if group_id == "":
		return false
	var pending_target: Vector2 = BanditGroupMemory.get_assault_target(group_id)
	if _is_valid_structure_target(pending_target) and _is_structure_target_still_valid(pending_target):
		return true
	var g: Dictionary = BanditGroupMemory.get_group(group_id)
	if g.is_empty():
		return false
	if String(g.get("last_interest_kind", "")) != "structure_assault_target":
		return false
	var interest_target: Vector2 = g.get("last_interest_pos", INVALID_STRUCTURE_TARGET) as Vector2
	return _is_valid_structure_target(interest_target) and _is_structure_target_still_valid(interest_target)


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
		group_intent = String(BanditGroupMemory.get_group(beh.group_id).get("current_group_intent", "idle"))
	var ai_state_name: String = ""
	if beh.state >= 0 and beh.state < NpcWorldBehavior.State.size():
		ai_state_name = NpcWorldBehavior.State.keys()[beh.state]
	var worker_cycle_active: bool = is_worker_cycle_active(beh)
	var runtime_signals: Dictionary = _get_runtime_lod_signals(node)
	var threat_detected: bool = group_intent == "alerted" or group_intent == "hunting" \
			or group_intent == "extorting" or group_intent == "raiding"
	var player_proximity_event: bool = distance_to_player <= SimulationLODPolicyScript.ACTOR_NEAR_DISTANCE
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
		"threat_detected": threat_detected,
		"player_proximity_event": player_proximity_event,
		"mode_signals": _get_global_lod_mode_signals(),
		"is_worker_cycle_active": worker_cycle_active,
	})
	_record_npc_lod_debug(beh, node, lod_debug, runtime_signals)
	return float(lod_debug.get("interval", BanditTuningScript.behavior_tick_interval()))


func _state_name_from_enum(state_value: int) -> String:
	if state_value >= 0 and state_value < NpcWorldBehavior.State.size():
		return NpcWorldBehavior.State.keys()[state_value]
	return ""


func is_worker_cycle_active(npc: BanditWorldBehavior) -> bool:
	if npc == null:
		return false
	var state_name: String = _state_name_from_enum(npc.state)
	return state_name == "RESOURCE_WATCH" \
			or state_name == "RETURN_HOME" \
			or str(npc.pending_mine_id) != "" \
			or str(npc.pending_collect_id) != "" \
			or int(npc.cargo_count) > 0


func _get_runtime_lod_signals(node: Node) -> Dictionary:
	var ai_comp = node.get("ai_component") if node != null else null
	var current_state: int = int(ai_comp.get("current_state")) if ai_comp != null else -1
	var current_target = ai_comp.get_current_target() if ai_comp != null and ai_comp.has_method("get_current_target") else null
	var has_active_target: bool = current_target != null and is_instance_valid(current_target)
	var is_in_direct_combat: bool = current_state == AIComponentScript.AIState.CHASE \
			or current_state == AIComponentScript.AIState.ATTACK \
			or has_active_target
	var _let: Variant = node.get("last_engaged_time")
	var was_recently_engaged: bool = SimulationLODPolicyScript.was_recently_engaged(float(_let) if _let != null else 0.0)
	var is_runtime_busy_but_not_combat: bool = false
	if not is_in_direct_combat:
		is_runtime_busy_but_not_combat = current_state == AIComponentScript.AIState.HURT \
				or current_state == AIComponentScript.AIState.DISENGAGE \
				or current_state == AIComponentScript.AIState.HOLD_PERIMETER \
				or bool(node.has_method("is_world_behavior_eligible") and not node.is_world_behavior_eligible())
	return {
		"is_in_direct_combat": is_in_direct_combat,
		"was_recently_engaged": was_recently_engaged,
		"is_runtime_busy_but_not_combat": is_runtime_busy_but_not_combat,
	}


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
		"cadence_reason": String(lod_debug.get("dominant_reason", "baseline")),
		"mode": String(lod_debug.get("mode", String(SimulationLODPolicyScript.MODE_CONTEXTUAL))),
		"is_worker_cycle_active": bool(lod_debug.get("is_worker_cycle_active", false)),
		"is_in_direct_combat": bool(runtime_signals.get("is_in_direct_combat", false)),
		"was_recently_engaged": bool(runtime_signals.get("was_recently_engaged", false)),
		"is_runtime_busy_but_not_combat": bool(runtime_signals.get("is_runtime_busy_but_not_combat", false)),
		"is_world_behavior_eligible": bool(node.has_method("is_world_behavior_eligible") and node.is_world_behavior_eligible()),
	}
	if _is_lod_debug_logging_enabled():
		Debug.log("bandit_lod", "[BanditLOD][npc] id=%s group=%s interval=%.2f bucket=%s cadence_reason=%s worker_active=%s combat=%s engaged=%s busy=%s" % [
			beh.member_id,
			beh.group_id,
			float(lod_debug.get("interval", 0.0)),
			bucket,
			String(lod_debug.get("dominant_reason", "baseline")),
			str(bool(lod_debug.get("is_worker_cycle_active", false))),
			str(bool(runtime_signals.get("is_in_direct_combat", false))),
			str(bool(runtime_signals.get("was_recently_engaged", false))),
			str(bool(runtime_signals.get("is_runtime_busy_but_not_combat", false))),
		])


func get_lod_debug_snapshot() -> Dictionary:
	return {
		"npc_counts": _lod_debug_npc_counts.duplicate(true),
		"npc_intervals": _lod_debug_last_npc.duplicate(true),
		"group_profile_decisions": _group_lod_profile_decisions.duplicate(true),
		"mode_perf": _snapshot_mode_perf(),
		"drop_metrics": _stash.get_debug_snapshot() if _stash != null else {},
		"group_scan": _group_intel.get_lod_debug_snapshot() if _group_intel != null else {},
		"behavior_metrics_window": get_perf_window_snapshot(),
		"behavior_metrics_baselines": get_perf_baseline_snapshots(),
	}


func _is_lod_debug_logging_enabled() -> bool:
	return Debug.is_enabled("ai") and Debug.is_enabled("bandit_lod")


func _get_global_lod_mode_signals() -> Dictionary:
	if GameEvents == null or not GameEvents.has_method("get_simulation_lod_mode_signals"):
		return {}
	return GameEvents.get_simulation_lod_mode_signals()


func _ensure_mode_perf_entry(mode: StringName) -> Dictionary:
	var mode_key: String = String(mode)
	if not _lod_mode_perf.has(mode_key):
		_lod_mode_perf[mode_key] = {
			"frame_samples": 0,
			"frame_time_total_ms": 0.0,
			"frame_time_avg_ms": 0.0,
			"reaction_samples": 0,
			"reaction_latency_total_s": 0.0,
			"reaction_latency_avg_s": 0.0,
		}
	return _lod_mode_perf[mode_key]


func _record_mode_frame_time(mode: StringName, elapsed_ms: float) -> void:
	var entry: Dictionary = _ensure_mode_perf_entry(mode)
	entry["frame_samples"] = int(entry.get("frame_samples", 0)) + 1
	entry["frame_time_total_ms"] = float(entry.get("frame_time_total_ms", 0.0)) + maxf(elapsed_ms, 0.0)
	entry["frame_time_avg_ms"] = float(entry.get("frame_time_total_ms", 0.0)) / float(maxi(int(entry.get("frame_samples", 0)), 1))
	_lod_mode_perf[String(mode)] = entry


func _record_mode_reaction_latency(mode: StringName, latency_s: float) -> void:
	var entry: Dictionary = _ensure_mode_perf_entry(mode)
	entry["reaction_samples"] = int(entry.get("reaction_samples", 0)) + 1
	entry["reaction_latency_total_s"] = float(entry.get("reaction_latency_total_s", 0.0)) + maxf(latency_s, 0.0)
	entry["reaction_latency_avg_s"] = float(entry.get("reaction_latency_total_s", 0.0)) / float(maxi(int(entry.get("reaction_samples", 0)), 1))
	_lod_mode_perf[String(mode)] = entry


func _snapshot_mode_perf() -> Dictionary:
	return _lod_mode_perf.duplicate(true)


func _reset_perf_window_metrics() -> void:
	_perf_window_elapsed_s = 0.0
	_perf_window_accum = {
		"physics_process_calls": 0,
		"physics_process_total_ms": 0.0,
		"ally_separation_total_ms": 0.0,
		"behavior_tick_calls": 0,
		"behavior_tick_total_ms": 0.0,
		"work_units": 0,
		"scan_total": 0,
		"separation_group_scans": 0,
		"separation_npc_scans": 0,
		"separation_neighbor_checks_total": 0,
		"crowd_mode_active_groups": 0,
		"crowd_mode_groups_total": 0,
		"assignment_conflicts_total": 0,
		"double_reservations_avoided": 0,
		"expired_reservations": 0,
		"assignment_replans": 0,
		"assault_context_build_ms": 0.0,
		"assault_context_hits": 0,
		"assault_per_npc_before_total_ms": 0.0,
		"assault_per_npc_before_calls": 0,
		"assault_per_npc_after_total_ms": 0.0,
		"assault_per_npc_after_calls": 0,
		"worker_active_count_samples": 0,
		"worker_active_count_frames": 0,
		"followers_without_task_samples": 0,
		"followers_without_task_frames": 0,
		"profile_full_count": 0,
		"profile_obedient_count": 0,
		"profile_decorative_count": 0,
		"profile_switches_total": 0,
		"profile_budget_downgrades": 0,
		"profile_event_reactivations": 0,
		"scan_by_group": {},
		"scan_by_npc": {},
	}


func _accumulate_perf_window(delta: Dictionary) -> void:
	for key_var in delta.keys():
		var key: String = str(key_var)
		var value = delta[key_var]
		if value is int:
			_perf_window_accum[key] = int(_perf_window_accum.get(key, 0)) + int(value)
		elif value is float:
			_perf_window_accum[key] = float(_perf_window_accum.get(key, 0.0)) + float(value)
		else:
			_perf_window_accum[key] = value


func _merge_nested_counter(key: String, source: Dictionary) -> void:
	var target: Dictionary = _perf_window_accum.get(key, {})
	for item in source.keys():
		var name: String = str(item)
		target[name] = int(target.get(name, 0)) + int(source[item])
	_perf_window_accum[key] = target


func _flush_perf_window_if_needed() -> void:
	if _perf_window_elapsed_s < METRICS_WINDOW_SECONDS:
		return
	var snapshot: Dictionary = get_perf_window_snapshot()
	Debug.log("perf_telemetry", "[BanditBehaviorMetrics][window] %s" % JSON.stringify(snapshot))
	_reset_perf_window_metrics()


func _dict_int_sum(src: Dictionary) -> int:
	var total: int = 0
	for k in src.keys():
		total += int(src[k])
	return total


func _count_assignment_conflicts(claims: Dictionary) -> int:
	var conflicts: int = 0
	for k in claims.keys():
		var claim_count: int = int(claims[k])
		if claim_count > 1:
			conflicts += claim_count - 1
	return conflicts


func get_perf_window_snapshot() -> Dictionary:
	var elapsed: float = maxf(_perf_window_elapsed_s, 0.0001)
	var physics_calls: int = int(_perf_window_accum.get("physics_process_calls", 0))
	var behavior_calls: int = int(_perf_window_accum.get("behavior_tick_calls", 0))
	var workers_frames: int = maxi(int(_perf_window_accum.get("worker_active_count_frames", 0)), 1)
	var followers_frames: int = maxi(int(_perf_window_accum.get("followers_without_task_frames", 0)), 1)
	var profile_samples: int = maxi(
			int(_perf_window_accum.get("profile_full_count", 0))
			+ int(_perf_window_accum.get("profile_obedient_count", 0))
			+ int(_perf_window_accum.get("profile_decorative_count", 0)),
			1)
	var scan_by_group: Dictionary = _perf_window_accum.get("scan_by_group", {})
	var scan_by_npc: Dictionary = _perf_window_accum.get("scan_by_npc", {})
	var physics_avg: float = float(_perf_window_accum.get("physics_process_total_ms", 0.0)) / float(maxi(physics_calls, 1))
	var behavior_avg: float = float(_perf_window_accum.get("behavior_tick_total_ms", 0.0)) / float(maxi(behavior_calls, 1))
	var crowd_mode_groups_total: int = int(_perf_window_accum.get("crowd_mode_groups_total", 0))
	var crowd_mode_active_ratio: float = float(_perf_window_accum.get("crowd_mode_active_groups", 0)) / float(maxi(crowd_mode_groups_total, 1))
	var phase1_reduction: Dictionary = _build_phase1_physics_reduction_snapshot(physics_avg)
	return {
		"window_seconds": elapsed,
		"cost_ms": {
			"physics_process_total": float(_perf_window_accum.get("physics_process_total_ms", 0.0)),
			"ally_separation_total": float(_perf_window_accum.get("ally_separation_total_ms", 0.0)),
			"ally_separation_total_ms": float(_perf_window_accum.get("ally_separation_total_ms", 0.0)),
			"behavior_tick_total": float(_perf_window_accum.get("behavior_tick_total_ms", 0.0)),
		},
		"cost_ms_avg": {
			"physics_process_avg": physics_avg,
			"behavior_tick_avg": behavior_avg,
		},
		"counters": {
			"work_units": int(_perf_window_accum.get("work_units", 0)),
			"scan_total": int(_perf_window_accum.get("scan_total", 0)),
			"separation_group_scans": int(_perf_window_accum.get("separation_group_scans", 0)),
			"separation_npc_scans": int(_perf_window_accum.get("separation_npc_scans", 0)),
			"separation_neighbor_checks_total": int(_perf_window_accum.get("separation_neighbor_checks_total", 0)),
			"workers_active_avg": float(_perf_window_accum.get("worker_active_count_samples", 0)) / float(workers_frames),
			"followers_without_task_avg": float(_perf_window_accum.get("followers_without_task_samples", 0)) / float(followers_frames),
			"assignment_conflicts_total": int(_perf_window_accum.get("assignment_conflicts_total", 0)),
			"double_reservations_avoided": int(_perf_window_accum.get("double_reservations_avoided", 0)),
			"expired_reservations": int(_perf_window_accum.get("expired_reservations", 0)),
			"assignment_replans": int(_perf_window_accum.get("assignment_replans", 0)),
			"assault_context_build_ms": float(_perf_window_accum.get("assault_context_build_ms", 0.0)),
			"assault_context_hits": int(_perf_window_accum.get("assault_context_hits", 0)),
			"assault_per_npc_ms_before_after": {
				"before_total_ms": float(_perf_window_accum.get("assault_per_npc_before_total_ms", 0.0)),
				"before_calls": int(_perf_window_accum.get("assault_per_npc_before_calls", 0)),
				"before_avg_ms": float(_perf_window_accum.get("assault_per_npc_before_total_ms", 0.0)) / float(maxi(int(_perf_window_accum.get("assault_per_npc_before_calls", 0)), 1)),
				"after_total_ms": float(_perf_window_accum.get("assault_per_npc_after_total_ms", 0.0)),
				"after_calls": int(_perf_window_accum.get("assault_per_npc_after_calls", 0)),
				"after_avg_ms": float(_perf_window_accum.get("assault_per_npc_after_total_ms", 0.0)) / float(maxi(int(_perf_window_accum.get("assault_per_npc_after_calls", 0)), 1)),
			},
			"profile_full_ratio": float(_perf_window_accum.get("profile_full_count", 0)) / float(profile_samples),
			"profile_obedient_ratio": float(_perf_window_accum.get("profile_obedient_count", 0)) / float(profile_samples),
			"profile_decorative_ratio": float(_perf_window_accum.get("profile_decorative_count", 0)) / float(profile_samples),
			"profile_switches_total": int(_perf_window_accum.get("profile_switches_total", 0)),
			"profile_budget_downgrades": int(_perf_window_accum.get("profile_budget_downgrades", 0)),
			"profile_event_reactivations": int(_perf_window_accum.get("profile_event_reactivations", 0)),
		},
		"comparative_metrics": {
			"ally_separation_total_ms": float(_perf_window_accum.get("ally_separation_total_ms", 0.0)),
			"separation_neighbor_checks_total": int(_perf_window_accum.get("separation_neighbor_checks_total", 0)),
			"crowd_mode_active_ratio": crowd_mode_active_ratio,
		},
		"scan_by_group": scan_by_group.duplicate(true),
		"scan_by_npc": scan_by_npc.duplicate(true),
		"baseline_compare": {
			"phase1_physics_reduction": phase1_reduction,
		},
	}


func _build_phase1_physics_reduction_snapshot(current_physics_avg: float) -> Dictionary:
	var baseline_keys: Array[String] = ["phase_1", "phase1", "fase_1", "fase1", "small"]
	var selected_key: String = ""
	var selected: Dictionary = {}
	for key in baseline_keys:
		if _perf_baseline_snapshots.has(key):
			selected_key = key
			selected = _perf_baseline_snapshots[key] as Dictionary
			break
	if selected.is_empty():
		return {"available": false}
	var window: Dictionary = selected.get("window", {})
	var cost_avg: Dictionary = window.get("cost_ms_avg", {})
	var baseline_physics_avg: float = float(cost_avg.get("physics_process_avg", 0.0))
	if baseline_physics_avg <= 0.0001:
		return {
			"available": false,
			"baseline_label": selected_key,
		}
	var reduction_abs: float = baseline_physics_avg - current_physics_avg
	var reduction_pct: float = (reduction_abs / baseline_physics_avg) * 100.0
	return {
		"available": true,
		"baseline_label": selected_key,
		"baseline_physics_avg_ms": baseline_physics_avg,
		"current_physics_avg_ms": current_physics_avg,
		"reduction_ms": reduction_abs,
		"reduction_pct": reduction_pct,
	}


func save_perf_baseline_snapshot(label: String) -> Dictionary:
	var normalized_label: String = label.strip_edges().to_lower()
	if normalized_label == "":
		normalized_label = "custom"
	var snapshot: Dictionary = {
		"saved_at_unix": Time.get_unix_time_from_system(),
		"window": get_perf_window_snapshot(),
	}
	_perf_baseline_snapshots[normalized_label] = snapshot
	Debug.log("perf_telemetry", "[BanditBehaviorMetrics][baseline_saved] label=%s payload=%s" % [
		normalized_label,
		JSON.stringify(snapshot),
	])
	return snapshot


func get_perf_baseline_snapshots() -> Dictionary:
	return _perf_baseline_snapshots.duplicate(true)
