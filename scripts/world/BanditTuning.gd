extends RefCounted
class_name BanditTuning

# Centralized runtime tuning for bandit world orchestration.
# Keep group/faction-specific lookups behind helpers so we can branch later
# without hunting hardcoded literals across behavior/director code.

const DEFAULT_FACTION: String = "default"

# ---------------------------------------------------------------------------
# World simulation
# ---------------------------------------------------------------------------
const BEHAVIOR_TICK_INTERVAL: float = 0.5      # segundos entre ticks de behavior

# Scan radii — distancias máximas para detectar drops/recursos por tick
const LOOT_SCAN_RADIUS:     float = 144.0
const RESOURCE_SCAN_RADIUS: float = 288.0

# Rango melee para que un NPC golpee un recurso mientras minea
const MINE_RANGE: float = 52.0

# ---------------------------------------------------------------------------
# Group social policy
# ---------------------------------------------------------------------------
const GROUP_SCAN_INTERVAL: float = 8.0
const GROUP_TERRITORY_RADIUS: float = 384.0
const GROUP_EXTORT_COOLDOWN: float = 90.0
const GROUP_RAID_COOLDOWN: float = 120.0
const GROUP_ALERTED_THRESHOLD: float = 3.0
const GROUP_HUNTING_THRESHOLD: float = 8.0
const GROUP_ALERTED_RELEASE_THRESHOLD: float = 2.0
const GROUP_HUNTING_RELEASE_THRESHOLD: float = 6.5
const GROUP_INTENT_HYSTERESIS_GRACE: float = 10.0

# ---------------------------------------------------------------------------
# Wall probe — banda pequeña enviada a destruir una pared del jugador (lv 1-6)
# Frecuencia y tamaño del squad escalan con el nivel de hostilidad.
# ---------------------------------------------------------------------------
const WALL_PROBE_ATTACK_DURATION: float = 22.0  # s — tiempo golpeando la pared
const WALL_PROBE_MAX_DURATION:    float = 55.0  # s — abort total del job
const WALL_PROBE_WALL_INTERVAL:   float = 2.5   # s — cada cuánto redirige al muro
const STRUCTURE_NO_TARGET_GRACE: float = 20.0
const STRUCTURE_ASSAULT_MAX_TOTAL_SAFETY: float = 1200.0
const STRUCTURE_ASSAULT_ACTIVE_TTL: float = 8.0
const ASSAULT_SUPPRESS_GENERIC_DROP_PICKUP: bool = true
const ENABLE_WORKER_RESOURCE_FALLBACK: bool = true

# ---------------------------------------------------------------------------
# Physics / separation
# ---------------------------------------------------------------------------
const FRICTION_COMPENSATION: float = 25.0
const ALERTED_SCOUT_CHASE_SPEED: float = 55.0

# Separación entre aliados en el mismo grupo (sleeping NPCs sin CharacterBody2D sep)
const ALLY_SEP_RADIUS: float = 44.0
const ALLY_SEP_FORCE:  float = 55.0

# ---------------------------------------------------------------------------
# Cargo pickup radii
# ---------------------------------------------------------------------------
# Radio de recogida durante órbita de minería (desde el centro del recurso)
const ORBIT_COLLECT_RADIUS:       float = 56.0
# Radio de recogida al llegar a un drop objetivo (barre todo lo cercano)
const LOOT_ARRIVE_COLLECT_RADIUS: float = 40.0

# ---------------------------------------------------------------------------
# Cargo deposit animation / audio
# ---------------------------------------------------------------------------
const CARGO_FALL_TIME:   float = 0.25   # duración de la caída visual de items al barril
const CARGO_SFX_STAGGER: float = 0.07   # delay entre sonidos al depositar varios items

const TAUNT_RANGE_SQ: float = 300.0 * 300.0
const COLLECT_RANGE_SQ: float = 160.0 * 160.0
const ABORT_PLAYER_DISTANCE_SQ: float = 6000.0 * 6000.0
const EXTORT_TAUNT_BUBBLE_DURATION: float = 3.5
const EXTORT_WARN_MELEE_LOCK_DURATION: float = 7.0
const EXTORT_AI_REENABLE_DELAY: float = 12.0
const EXTORT_WARN_APPROACH_SPEED: float = 75.0
const EXTORT_GROUP_APPROACH_SPEED: float = 55.0
const EXTORT_WARN_STRIKE_RANGE: float = 76.0
const EXTORT_WARN_STRIKE_RANGE_BONUS: float = 8.0

static func faction_for_group(_group_id: String) -> String:
	return DEFAULT_FACTION

# ---------------------------------------------------------------------------
# World simulation accessors
# ---------------------------------------------------------------------------

static func behavior_tick_interval() -> float:
	return BEHAVIOR_TICK_INTERVAL

static func loot_scan_radius() -> float:
	return LOOT_SCAN_RADIUS

static func loot_scan_radius_sq() -> float:
	return LOOT_SCAN_RADIUS * LOOT_SCAN_RADIUS

static func resource_scan_radius() -> float:
	return RESOURCE_SCAN_RADIUS

static func resource_scan_radius_sq() -> float:
	return RESOURCE_SCAN_RADIUS * RESOURCE_SCAN_RADIUS

static func mine_range_sq() -> float:
	return MINE_RANGE * MINE_RANGE

static func enable_worker_resource_fallback() -> bool:
	return ENABLE_WORKER_RESOURCE_FALLBACK

# ---------------------------------------------------------------------------
# Physics / separation accessors
# ---------------------------------------------------------------------------

static func friction_compensation() -> float:
	return FRICTION_COMPENSATION

static func alerted_scout_chase_speed(_group_id: String = "") -> float:
	return ALERTED_SCOUT_CHASE_SPEED

static func ally_sep_radius() -> float:
	return ALLY_SEP_RADIUS

static func ally_sep_force() -> float:
	return ALLY_SEP_FORCE

# ---------------------------------------------------------------------------
# Cargo pickup accessors
# ---------------------------------------------------------------------------

static func orbit_collect_radius_sq() -> float:
	return ORBIT_COLLECT_RADIUS * ORBIT_COLLECT_RADIUS

static func loot_arrive_collect_radius_sq() -> float:
	return LOOT_ARRIVE_COLLECT_RADIUS * LOOT_ARRIVE_COLLECT_RADIUS

# ---------------------------------------------------------------------------
# Cargo deposit accessors
# ---------------------------------------------------------------------------

static func cargo_fall_time() -> float:
	return CARGO_FALL_TIME

static func cargo_sfx_stagger() -> float:
	return CARGO_SFX_STAGGER

static func extort_taunt_range_sq(_group_id: String = "") -> float:
	return TAUNT_RANGE_SQ

static func extort_collect_range_sq(_group_id: String = "") -> float:
	return COLLECT_RANGE_SQ

static func extort_abort_distance_sq(_group_id: String = "") -> float:
	return ABORT_PLAYER_DISTANCE_SQ

static func extort_pay_amount(player_gold: int, _group_id: String = "") -> int:
	return maxi(1, int(player_gold * 0.2))

static func extort_taunt_bubble_duration(_group_id: String = "") -> float:
	return EXTORT_TAUNT_BUBBLE_DURATION

static func extort_warn_melee_lock_duration(_group_id: String = "") -> float:
	return EXTORT_WARN_MELEE_LOCK_DURATION

static func extort_ai_reenable_delay(_group_id: String = "") -> float:
	return EXTORT_AI_REENABLE_DELAY

static func extort_warn_approach_speed(_group_id: String = "") -> float:
	return EXTORT_WARN_APPROACH_SPEED

static func extort_group_approach_speed(_group_id: String = "") -> float:
	return EXTORT_GROUP_APPROACH_SPEED

static func extort_warn_strike_range(_group_id: String = "") -> float:
	return EXTORT_WARN_STRIKE_RANGE

static func extort_warn_strike_range_bonus(_group_id: String = "") -> float:
	return EXTORT_WARN_STRIKE_RANGE_BONUS

# ---------------------------------------------------------------------------
# Group social policy accessors
# ---------------------------------------------------------------------------

static func group_scan_interval() -> float:
	return GROUP_SCAN_INTERVAL

static func group_territory_radius() -> float:
	return GROUP_TERRITORY_RADIUS

static func extort_cooldown_base() -> float:
	return GROUP_EXTORT_COOLDOWN

static func raid_cooldown_base() -> float:
	return GROUP_RAID_COOLDOWN

static func alerted_threshold() -> float:
	return GROUP_ALERTED_THRESHOLD

static func hunting_threshold() -> float:
	return GROUP_HUNTING_THRESHOLD

static func alerted_release_threshold() -> float:
	return GROUP_ALERTED_RELEASE_THRESHOLD

static func hunting_release_threshold() -> float:
	return GROUP_HUNTING_RELEASE_THRESHOLD

static func intent_hysteresis_grace() -> float:
	return GROUP_INTENT_HYSTERESIS_GRACE

static func minimum_alerted_threshold() -> float:
	return 1.0

static func minimum_hunting_threshold() -> float:
	return 2.0


# ---------------------------------------------------------------------------
# Wall probe accessors
# ---------------------------------------------------------------------------

## Retorna {chance: float, cooldown: float, squad_size: int} para el nivel dado.
## chance    — probabilidad de dispararse en cada scan elegible (0.0-1.0)
## cooldown  — segundos mínimos entre probes del mismo grupo
## squad_size — cuántos bandidos son redirigidos a golpear la pared
static func wall_probe_config(level: int) -> Dictionary:
	match clampi(level, 1, 10):
		1: return {"chance": 0.10, "cooldown": 300.0, "squad_size": 1}
		2: return {"chance": 0.15, "cooldown": 250.0, "squad_size": 1}
		3: return {"chance": 0.22, "cooldown": 210.0, "squad_size": 1}
		4: return {"chance": 0.30, "cooldown": 175.0, "squad_size": 2}
		5: return {"chance": 0.40, "cooldown": 145.0, "squad_size": 2}
		6: return {"chance": 0.52, "cooldown": 115.0, "squad_size": 2}
		_: return {"chance": 0.52, "cooldown": 115.0, "squad_size": 2}

static func wall_probe_attack_duration() -> float:
	return WALL_PROBE_ATTACK_DURATION

static func wall_probe_max_duration() -> float:
	return WALL_PROBE_MAX_DURATION

static func wall_probe_wall_interval() -> float:
	return WALL_PROBE_WALL_INTERVAL

static func structure_no_target_grace() -> float:
	return STRUCTURE_NO_TARGET_GRACE

static func structure_assault_max_total_safety() -> float:
	return STRUCTURE_ASSAULT_MAX_TOTAL_SAFETY

static func structure_assault_active_ttl() -> float:
	return STRUCTURE_ASSAULT_ACTIVE_TTL

static func assault_suppress_generic_drop_pickup() -> bool:
	return ASSAULT_SUPPRESS_GENERIC_DROP_PICKUP
