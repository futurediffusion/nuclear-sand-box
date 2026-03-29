class_name FactionBehaviorProfile
extends RefCounted
## Perfil de comportamiento derivado del nivel de hostilidad actual.
## Objeto de solo lectura: se construye con from_level() y no se muta.
##
## Los enemies leen estas flags en lugar de interpretar manualmente los niveles.
## Uso:
##   var profile := FactionHostilityManager.get_behavior_profile("bandit")
##   if profile.can_attack_punitively:
##       ...

# ── Metadatos del estado ──────────────────────────────────────────────────
var hostility_level:   int   = 0
var hostility_points:  float = 0.0
## 0.0 = sin calor reciente, 1.0 = calor máximo.
## Sirve para escalar intensidad de reacciones inmediatas.
var heat_modifier:     float = 0.0
var extortion_pressure: float = 0.0
var raid_pressure:      float = 0.0
var social_momentum:    float = 0.0

# ── Flags de comportamiento ───────────────────────────────────────────────
## Nivel 1+
var can_intimidate:          bool = false   # acercarse, rodear, amagar
var can_extort:              bool = false   # iniciar extorsión
## Nivel 1+  (desaparece al activarse can_damage_workbenches en lv 7+)
var can_probe_walls:         bool = false   # envía 1-2 bandidos a golpear una pared del jugador

## Nivel 2+
var can_block_path:          bool = false   # cortar la ruta del jugador

## Nivel 3+
var can_call_reinforcements: bool = false   # alertar aliados cercanos
var can_pursue_briefly:      bool = false   # persecución corta tras negativa

## Nivel 4+
var can_attack_punitively:   bool = false   # ataque correctivo (no necesariamente letal)

## Nivel 5+
var can_knockout:            bool = false   # objetivo: dejar KO al jugador

## Nivel 6+
var can_loot_player:         bool = false   # saquear al jugador derribado

## Nivel 7+
var can_damage_workbenches:  bool = false   # destruir mesas de trabajo

## Nivel 8+
var can_damage_storage:      bool = false   # destruir cofres y almacenamiento

## Nivel 9+
var can_damage_walls:        bool = false   # dañar muros y defensas
var can_hunt_player:         bool = false   # buscar al jugador activamente

## Nivel 10
var can_raid_base:           bool = false   # raid organizada al base del jugador
var attack_to_kill:          bool = false   # la facción intenta matar, no solo KO


# ---------------------------------------------------------------------------
# Constructor
# ---------------------------------------------------------------------------

static func from_level(level: int, points: float, heat: float, extortion_pressure: float = 0.0, raid_pressure: float = 0.0) -> FactionBehaviorProfile:
	var p := FactionBehaviorProfile.new()
	p.hostility_level  = level
	p.hostility_points = points
	p.heat_modifier       = clampf(heat, 0.0, 1.0)
	p.extortion_pressure = clampf(extortion_pressure, 0.0, 1.0)
	p.raid_pressure      = clampf(raid_pressure, 0.0, 1.0)
	p.social_momentum    = clampf(p.heat_modifier * 0.35 + p.extortion_pressure * 0.35 + p.raid_pressure * 0.30, 0.0, 1.0)

	p.can_intimidate          = level >= 1
	p.can_extort              = level >= 1
	p.can_probe_walls         = level >= 1
	p.can_block_path          = level >= 2
	p.can_call_reinforcements = level >= 3
	p.can_pursue_briefly      = level >= 3
	p.can_attack_punitively   = level >= 4
	p.can_knockout            = level >= 5
	p.can_loot_player         = level >= 6
	p.can_damage_workbenches  = level >= 7
	p.can_damage_storage      = level >= 8
	p.can_damage_walls        = level >= 9
	p.can_hunt_player         = level >= 9
	p.can_raid_base           = level >= 10
	p.attack_to_kill          = level >= 10
	return p


# ---------------------------------------------------------------------------
# Helpers de lectura
# ---------------------------------------------------------------------------

## Devuelve true si la facción puede atacar al jugador en cualquier forma.
func is_hostile() -> bool:
	return can_attack_punitively

## Devuelve true si la facción usa solo presión social (sin ataque físico).
func is_pressuring_only() -> bool:
	return (can_intimidate or can_extort or can_block_path) and not can_attack_punitively

## Intensidad efectiva de ataque: nivel base ajustado por calor reciente.
## Útil para escalar daño, velocidad de persecución, etc.
## Retorna un valor 0.0..10.0+ (puede superar el nivel nominal en momentos de heat alto).
func effective_intensity() -> float:
	return float(hostility_level) + heat_modifier * 2.0
