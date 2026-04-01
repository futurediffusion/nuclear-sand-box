extends RefCounted
class_name BanditTerritoryResponse

const BanditDomainPortsScript := preload("res://scripts/world/BanditDomainPorts.gd")

# BanditTerritoryResponse owns short-lived territorial reactions from active
# bandit NPCs. It keeps bubble phrasing/cooldowns outside BanditBehaviorLayer so
# the layer stays focused on runtime orchestration instead of micro-social UX.

const TERRITORY_BUILD_PHRASES: Array[String] = [
	"¿Qué estás construyendo ahí?",
	"Ese taller no debería estar ahí.",
	"Esto es territorio nuestro. Literalmente.",
	"¿Crees que puedes instalar eso sin permiso?",
	"Interesante. Habrá que hablar de eso.",
	"Bonito taller. Sería una lástima que le pasara algo.",
	"Cada vez que colocas algo aquí, nos debes más.",
	"No me ha pedido permiso nadie.",
	"Aquí no se construye sin pagar.",
]
const TERRITORY_MINE_PHRASES: Array[String] = [
	"Esos recursos son nuestros.",
	"Mina en otro sitio.",
	"Estás sacando lo que no es tuyo.",
	"Eso también tiene precio.",
	"Ya estamos viendo lo que haces.",
	"Cada golpe de pico cuesta.",
	"Sigue así y verás lo que pasa.",
	"No te hacemos pagar el aire. Aún.",
	"Te estás llevando más de lo que te corresponde.",
]
const TERRITORY_REACT_RANGE_SQ: float = 1000.0 * 1000.0
const TERRITORY_REACT_COOLDOWN: float = 20.0

var _territory_react_cooldown: Dictionary = {}
var _npc_simulator: NpcSimulator = null
var _bubble_manager: WorldSpeechBubbleManager = null
var _domain_ports: BanditDomainPorts = null

func setup(ctx: Dictionary) -> void:
	_npc_simulator = ctx.get("npc_simulator")
	_bubble_manager = ctx.get("speech_bubble_manager")
	_domain_ports = ctx.get("domain_ports") as BanditDomainPorts
	if _domain_ports == null:
		_domain_ports = BanditDomainPortsScript.new() as BanditDomainPorts
		_domain_ports.setup()

func notify_reaction(group_id: String, intrusion_pos: Vector2, kind: String) -> void:
	if _bubble_manager == null or _npc_simulator == null:
		return
	var now: float = _domain_ports.now()
	if now - float(_territory_react_cooldown.get(group_id, 0.0)) < TERRITORY_REACT_COOLDOWN:
		return
	var g: Dictionary = _domain_ports.bandit_group_memory().get_group(group_id)
	var member_ids: Array = g.get("member_ids", [])
	var best_node: Node2D = null
	var best_id: String = ""
	var best_dsq: float = TERRITORY_REACT_RANGE_SQ
	for mid in member_ids:
		var node = _npc_simulator.get_enemy_node(String(mid))
		if node == null:
			continue
		var n2d: Node2D = node as Node2D
		if n2d == null:
			continue
		var dsq: float = n2d.global_position.distance_squared_to(intrusion_pos)
		if dsq < best_dsq:
			best_dsq = dsq
			best_node = n2d
			best_id = String(mid)
	if best_node == null:
		return
	_territory_react_cooldown[group_id] = now
	var is_mining: bool = kind in ["copper_mined", "stone_mined", "wood_chopped"]
	var pool: Array[String] = TERRITORY_MINE_PHRASES if is_mining else TERRITORY_BUILD_PHRASES
	var phrase: String = pool[randi() % pool.size()]
	_bubble_manager.show_actor_bubble(best_node, phrase, 4.0)
	_domain_ports.debug_log("territory", "[TERRITORY] reaction npc=%s group=%s kind=%s" % [best_id, group_id, kind])
