extends Node
## Fuente de verdad para la hostilidad del jugador contra cada facción.
##
## PRINCIPIOS:
##   • Los enemies NUNCA guardan la hostilidad como estado propio.
##   • Todo el estado persistente vive aquí, en FactionHostilityData por facción.
##   • La memoria local de un enemy es táctica/situacional, nunca la fuente de verdad.
##
## Uso desde cualquier sistema:
##   FactionHostilityManager.add_hostility("bandits", 0.0, "member_killed",
##       {"entity_id": uid, "position": pos})
##
## Uso desde enemies para decidir conducta:
##   var profile := FactionHostilityManager.get_behavior_profile("bandits")
##   if profile.can_attack_punitively: ...

# ---------------------------------------------------------------------------
# Señales
# ---------------------------------------------------------------------------

signal hostility_changed(faction_id: String, new_points: float, new_level: int)
signal level_changed(faction_id: String, old_level: int, new_level: int)

# ---------------------------------------------------------------------------
# Umbrales de nivel  (índice = nivel, 0 = neutral)
# ---------------------------------------------------------------------------
## Puntos mínimos para alcanzar cada nivel.
## Cambiar estos valores reescala toda la curva sin tocar lógica.
const LEVEL_THRESHOLDS: Array[float] = [
	0.0,     # 0  Neutral
	50.0,    # 1  Tensión ambigua
	150.0,   # 2  Acoso oportunista
	300.0,   # 3  Hostilidad condicional
	500.0,   # 4  Castigo correctivo
	750.0,   # 5  Derribo intencional
	1050.0,  # 6  KO + saqueo básico
	1400.0,  # 7  Sabotaje ligero
	1800.0,  # 8  Represalia estructural
	2250.0,  # 9  Cacería activa
	2750.0,  # 10 Guerra abierta
]

const LEVEL_NAMES: Array[String] = [
	"Neutral",
	"Tensión ambigua",
	"Acoso oportunista",
	"Hostilidad condicional",
	"Castigo correctivo",
	"Derribo intencional",
	"KO + saqueo básico",
	"Sabotaje ligero",
	"Represalia estructural",
	"Cacería activa",
	"Guerra abierta",
]

# ---------------------------------------------------------------------------
# Decay diario por tramo de hostilidad
# ---------------------------------------------------------------------------
## Días sin incidente antes de que empiecen a decaer los puntos.
## A mayor nivel, la facción necesita más calma sostenida antes de empezar a olvidar.
const DECAY_GRACE_DAYS_BY_LEVEL: Array[int] = [
	0,   # nivel 0  — neutral
	1,   # nivel 1  — baja
	1,   # nivel 2  — baja
	1,   # nivel 3  — baja
	2,   # nivel 4  — media
	2,   # nivel 5  — media
	2,   # nivel 6  — media
	3,   # nivel 7  — alta
	3,   # nivel 8  — alta
	4,   # nivel 9  — extrema
	4,   # nivel 10 — guerra
]

## % de hostility_points que se pierde por día una vez activo el decay.
## Porcentaje sobre los puntos actuales: escala con el nivel de forma natural.
## Ejemplo nivel 5 (750 pts): 750 * 0.06 = 45 pts/día → baja a nivel 3 en ~10 días.
## Ejemplo nivel 10 (2750 pts): 2750 * 0.015 = 41 pts/día → nivel 9 en ~12 días.
const DECAY_RATE_BY_LEVEL: Array[float] = [
	0.000,  # nivel 0  — neutral
	0.090,  # nivel 1  — baja   (9 %/día, hostilidad inicial se disipa rápido)
	0.080,  # nivel 2  — baja
	0.075,  # nivel 3  — baja
	0.060,  # nivel 4  — media
	0.060,  # nivel 5  — media
	0.050,  # nivel 6  — media
	0.035,  # nivel 7  — alta
	0.030,  # nivel 8  — alta
	0.018,  # nivel 9  — extrema
	0.015,  # nivel 10 — guerra (muy pegajoso)
]
## Mínimo absoluto de puntos perdidos por día aunque el % sea bajo.
const DECAY_MIN_PER_DAY: float = 2.0

## Si el heat cae por debajo de este umbral, el decay empieza aunque no haya
## transcurrido el grace period completo ("las aguas se han calmado físicamente").
const HEAT_COLD_THRESHOLD: float = 10.0

## El heat decae cada día sin grace period, pero más lento que antes.
## Con 40%/día: heat 400 tarda ~8 días en llegar a 10 → acción reciente persiste.
const HEAT_DECAY_RATE: float   = 0.40   # -40% por día (antes 50%)
const HEAT_MODIFIER_MAX: float = 250.0  # heat al que modifier = 1.0 (spread más largo)
const HEAT_CAP: float          = 400.0  # tope de acumulación

# ---------------------------------------------------------------------------
# Riqueza de banda (band_wealth)
# ---------------------------------------------------------------------------
## Cuánta riqueza suma cada tipo de incidente lucrativo.
const WEALTH_INCOME: Dictionary = {
	"extortion_paid":   0.0,   # usa el amount real del pago (metadata["amount"])
	"player_looted":   50.0,
	"barrel_sacked":   80.0,
	"storage_damaged": 120.0,
	"wall_damaged":    15.0,
}

## Umbrales de tier. Índice = tier (0-3).
const WEALTH_TIERS: Array[float] = [
	0.0,     # tier 0 — banda pobre (comportamiento base)
	300.0,   # tier 1 — operación establecida
	1000.0,  # tier 2 — banda rica
	2500.0,  # tier 3 — cartel
]

## Factor de reducción de cooldown de extorsión por tier.
## tier 3 → cooldown al 55 % del base.
const WEALTH_EXTORT_COOLDOWN_FACTOR: Array[float] = [1.0, 0.85, 0.70, 0.55]

## Factor de reducción de cooldown de raid por tier.
const WEALTH_RAID_COOLDOWN_FACTOR: Array[float]   = [1.0, 0.90, 0.75, 0.60]

## Días extra de grace para el decay de hostilidad por tier.
## Riqueza compra "memoria rencorosa" — la facción tarda más en olvidar.
const WEALTH_GRACE_BONUS: Array[int] = [0, 0, 1, 2]

## Reducción de T_ALERTED por tier (confianza territorial).
## tier 3 → el umbral efectivo baja 1.5 puntos; reaccionan a menos actividad.
const WEALTH_TERRITORIAL_BONUS: Array[float] = [0.0, 0.5, 1.0, 1.5]

## Decay diario de riqueza (2 %/día — acumula lento, pero no es eterno).
const WEALTH_DECAY_RATE: float = 0.02

# ---------------------------------------------------------------------------
# Pesos de incidentes — puntos de hostilidad persistente
# ---------------------------------------------------------------------------
## Usar amount = 0.0 en add_hostility() para aplicar el peso de la tabla.
## Pasar amount explícito para sobreescribir (conserva los contadores de reason).
##
## Gravedad: leve < media < grave < crítica
const INCIDENT_WEIGHTS: Dictionary = {
	# — Leves —
	"extortion_refused":    5.0,
	"extortion_insulted":   8.0,

	# — Medias —
	"member_attacked":     18.0,
	"player_trespassed":    6.0,

	# — Graves —
	"member_killed":       40.0,   # subido: matar es el acto más grave individual
	"barrel_sacked":       32.0,   # sabotaje económico + humillación territorial
	"player_looted":       20.0,

	# — Assets de facción —
	"workbench_damaged":   45.0,
	"storage_damaged":     50.0,
	"wall_damaged":        40.0,

	# — Reducciones —
	"extortion_paid":      -5.0,
	"ally_helped":        -15.0,
	"quest_completed":    -25.0,
}

# ---------------------------------------------------------------------------
# Pesos de heat — reacción inmediata (decae rápido)
# ---------------------------------------------------------------------------
## Los incidentes violentos generan mucho más heat que puntos persistentes.
## Esto hace que la facción reaccione con más intensidad justo después del suceso.
const HEAT_WEIGHTS: Dictionary = {
	"extortion_refused":   12.0,
	"extortion_insulted":  18.0,
	"member_attacked":     45.0,   # bajado: atacar sin matar no es tan caliente
	"player_trespassed":   10.0,
	"member_killed":      100.0,
	"barrel_sacked":       80.0,
	"player_looted":       35.0,
	"workbench_damaged":   90.0,
	"storage_damaged":    110.0,
	"wall_damaged":        75.0,
	"extortion_paid":       0.0,
	"ally_helped":          0.0,
	"quest_completed":      0.0,
}

# ---------------------------------------------------------------------------
# Spree / escalada por frecuencia
# ---------------------------------------------------------------------------
## Razones que pueden desencadenar un bonus de spree si el heat ya es alto.
const SPREE_ELIGIBLE_REASONS: Array[String] = [
	"member_killed",
	"member_attacked",
	"barrel_sacked",
	"workbench_damaged",
	"storage_damaged",
]

## [heat_threshold, bonus_pts, bonus_heat]
## Se aplica el primer tramo que supere el heat actual.
const SPREE_TIERS: Array = [
	[260.0, 40.0, 60.0],   # frío de guerra: +40 pts, +60 heat
	[160.0, 30.0, 45.0],   # escalada grave: +30 pts, +45 heat
	[ 80.0, 15.0, 25.0],   # calentamiento: +15 pts, +25 heat
]

# ---------------------------------------------------------------------------
# Deduplicación anti-doble-disparo
# ---------------------------------------------------------------------------
## Tiempo mínimo (ms) entre el mismo faction+reason+entity para contar.
## Evita que un bug de frame dispare el mismo evento dos veces seguidas.
const DEDUP_COOLDOWN_MS: int = 300

# ---------------------------------------------------------------------------
# Estado interno
# ---------------------------------------------------------------------------

var _factions: Dictionary       = {}   # faction_id -> FactionHostilityData
var _dedup_ts:  Dictionary       = {}   # "faction:reason:entity" -> Time ms


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	WorldTime.day_passed.connect(_on_day_passed)


# ---------------------------------------------------------------------------
# API pública — consulta
# ---------------------------------------------------------------------------

func get_faction_state(faction_id: String) -> FactionHostilityData:
	return _get_or_create(faction_id)


func get_hostility_points(faction_id: String) -> float:
	return _get_or_create(faction_id).hostility_points


func get_hostility_level(faction_id: String) -> int:
	return _points_to_level(_get_or_create(faction_id).hostility_points)


func get_level_name(faction_id: String) -> String:
	return LEVEL_NAMES[get_hostility_level(faction_id)]


## Devuelve el perfil de comportamiento que los enemies deben leer.
func get_behavior_profile(faction_id: String) -> FactionBehaviorProfile:
	var data: FactionHostilityData = _get_or_create(faction_id)
	var level: int                 = _points_to_level(data.hostility_points)
	var heat_mod: float            = clampf(data.recent_heat / HEAT_MODIFIER_MAX, 0.0, 1.0)
	return FactionBehaviorProfile.from_level(level, data.hostility_points, heat_mod)


func points_to_level(points: float) -> int:
	return _points_to_level(points)


## Devuelve el tier de riqueza de la facción (0-3).
## Usar para ajustar cooldowns, severidad y agresividad territorial.
func get_wealth_tier(faction_id: String) -> int:
	var wealth: float = _get_or_create(faction_id).band_wealth
	for t: int in range(WEALTH_TIERS.size() - 1, -1, -1):
		if wealth >= WEALTH_TIERS[t]:
			return t
	return 0


# ---------------------------------------------------------------------------
# API pública — escritura
# ---------------------------------------------------------------------------

## Registra un incidente que cambia la hostilidad de una facción.
##
## @param amount   Puntos explícitos. Si 0.0, se usa INCIDENT_WEIGHTS[reason].
## @param reason   Clave de INCIDENT_WEIGHTS. Actualiza contadores y log.
## @param metadata Contexto del incidente. Campos útiles:
##                   "entity_id"  — UID del NPC involucrado (para dedup)
##                   "position"   — Vector2 del incidente
##                   "asset_type" — tipo de asset dañado
##                   "amount"     — cantidad (oro, items)
func add_hostility(
		faction_id: String,
		amount:     float,
		reason:     String,
		metadata:   Dictionary = {}
) -> void:
	# ── Deduplicación ──────────────────────────────────────────────────────
	var entity_key: String = String(metadata.get("entity_id", ""))
	var dedup_key:  String = "%s:%s:%s" % [faction_id, reason, entity_key]
	var now_ms: int        = Time.get_ticks_msec()
	if _dedup_ts.has(dedup_key) and (now_ms - int(_dedup_ts[dedup_key])) < DEDUP_COOLDOWN_MS:
		Debug.log("faction_hostility", "[FHM] dedup skip %s" % dedup_key)
		return
	_dedup_ts[dedup_key] = now_ms

	# ── Resolver puntos ────────────────────────────────────────────────────
	var data:      FactionHostilityData = _get_or_create(faction_id)
	var old_level: int                  = _points_to_level(data.hostility_points)
	var pts:       float = amount if not is_zero_approx(amount) \
							else float(INCIDENT_WEIGHTS.get(reason, 0.0))

	# ── Resolver heat ──────────────────────────────────────────────────────
	var heat: float = float(HEAT_WEIGHTS.get(reason, 0.0))
	# Si el caller dio monto custom, escalar heat proporcionalmente
	if not is_zero_approx(amount) and INCIDENT_WEIGHTS.has(reason):
		var default_pts: float = absf(float(INCIDENT_WEIGHTS[reason]))
		if default_pts > 0.0:
			heat *= absf(pts) / default_pts

	# ── Spree bonus (solo en ofensas agresivas) ────────────────────────────
	var spree_pts:  float = 0.0
	var spree_heat: float = 0.0
	if pts > 0.0 and SPREE_ELIGIBLE_REASONS.has(reason):
		var result: Array = _compute_spree_bonus(data.recent_heat)
		spree_pts  = result[0]
		spree_heat = result[1]
		if spree_pts > 0.0:
			Debug.log("faction_hostility", "[FHM] spree bonus %s +%.0f pts (heat=%.0f)" % [
				faction_id, spree_pts, data.recent_heat])

	# ── Aplicar ────────────────────────────────────────────────────────────
	data.hostility_points = maxf(0.0, data.hostility_points + pts + spree_pts)
	if pts > 0.0 or heat > 0.0:
		data.recent_heat = minf(data.recent_heat + heat + spree_heat, HEAT_CAP)
	if pts > 0.0:
		data.last_incident_day = WorldTime.get_current_day()

	_increment_counter(data, reason)
	if reason == "extortion_paid":
		_record_payment(data, metadata)
	_accumulate_wealth(data, reason, metadata)

	# ── Señales ────────────────────────────────────────────────────────────
	var new_level: int = _points_to_level(data.hostility_points)
	hostility_changed.emit(faction_id, data.hostility_points, new_level)
	if new_level != old_level:
		level_changed.emit(faction_id, old_level, new_level)
		Debug.log("faction_hostility", "[FHM] %s NIVEL %d→%d [%s]" % [
			faction_id, old_level, new_level, LEVEL_NAMES[new_level]])

	Debug.log("faction_hostility",
		"[FHM] %s %+.0f pts (%s) → %.0f lv%d heat=%.0f" % [
		faction_id, pts + spree_pts, reason,
		data.hostility_points, new_level, data.recent_heat])


## Reduce hostilidad. Equivale a add_hostility con amount negativo.
func reduce_hostility(
		faction_id: String,
		amount:     float,
		reason:     String,
		metadata:   Dictionary = {}
) -> void:
	add_hostility(faction_id, -absf(amount), reason, metadata)


## Solo para debug/cheats. No actualiza contadores ni heat.
func set_hostility_points_debug(faction_id: String, points: float) -> void:
	var data:      FactionHostilityData = _get_or_create(faction_id)
	var old_level: int                  = _points_to_level(data.hostility_points)
	data.hostility_points               = maxf(0.0, points)
	var new_level: int                  = _points_to_level(data.hostility_points)
	hostility_changed.emit(faction_id, data.hostility_points, new_level)
	if new_level != old_level:
		level_changed.emit(faction_id, old_level, new_level)


# ---------------------------------------------------------------------------
# Decay diario
# ---------------------------------------------------------------------------

func _on_day_passed(new_day: int) -> void:
	for fid: String in _factions.keys():
		var data: FactionHostilityData = _factions[fid] as FactionHostilityData
		if data != null:
			_apply_daily_decay(data, new_day)


func _apply_daily_decay(data: FactionHostilityData, current_day: int) -> void:
	# ── Heat: siempre decae, sin grace period ─────────────────────────────
	if data.recent_heat > 0.0:
		data.recent_heat = maxf(0.0, data.recent_heat * (1.0 - HEAT_DECAY_RATE))
		if data.recent_heat < 1.0:
			data.recent_heat = 0.0

	# ── Compliance y wealth: siempre decaen, independiente de hostilidad ──
	_apply_compliance_decay(data, current_day)
	_apply_wealth_decay(data)

	# ── Hostility points: dos condiciones para empezar el decay ───────────
	if data.last_incident_day < 0 or data.hostility_points <= 0.0:
		return

	var level: int      = _points_to_level(data.hostility_points)
	var wealth_tier: int = _wealth_to_tier(data.band_wealth)
	# Banda rica recuerda sus rencores más tiempo — grace period extra.
	var grace: int      = DECAY_GRACE_DAYS_BY_LEVEL[level] + WEALTH_GRACE_BONUS[wealth_tier]
	var days_since: int = current_day - data.last_incident_day
	var heat_cold: bool = data.recent_heat < HEAT_COLD_THRESHOLD

	# Condición 1: pasaron suficientes días de calma para el nivel actual.
	# Condición 2: el heat ya se enfrió físicamente (aunque no haya pasado el grace).
	# Cualquiera de las dos basta para desbloquear el decay.
	if days_since <= grace and not heat_cold:
		return

	var rate: float  = DECAY_RATE_BY_LEVEL[level]
	if is_zero_approx(rate):
		return
	var decay: float = maxf(DECAY_MIN_PER_DAY, data.hostility_points * rate)

	var old_level: int    = level
	data.hostility_points = maxf(0.0, data.hostility_points - decay)
	data.last_decay_day   = current_day
	var new_level: int    = _points_to_level(data.hostility_points)

	hostility_changed.emit(data.faction_id, data.hostility_points, new_level)
	if new_level != old_level:
		level_changed.emit(data.faction_id, old_level, new_level)
		Debug.log("faction_hostility",
			"[FHM] decay %s lv%d→lv%d (day %d, -%.0f pts, heat=%.0f wealth=%.0f tier%d)" % [
			data.faction_id, old_level, new_level, current_day,
			decay, data.recent_heat, data.band_wealth, wealth_tier])


# ---------------------------------------------------------------------------
# Compliance decay y rebelión
# ---------------------------------------------------------------------------

## Decae el compliance_score si el jugador lleva días sin pagar.
## Si era pagador confiable y lleva +7 días sin pagar, escala hostilidad
## (la facción interpreta el silencio como rebelión deliberada).
func _apply_compliance_decay(data: FactionHostilityData, current_day: int) -> void:
	if data.compliance_score <= 0.0 or data.last_paid_day < 0:
		return
	var days_stopped: int = current_day - data.last_paid_day
	# Grace period de 5 días antes de que empiece el decay
	if days_stopped <= 5:
		return
	# Decae 0.04 por día (tarda ~15 días en ir de 1.0 a 0.4)
	data.compliance_score = maxf(0.0, data.compliance_score - 0.04)
	# Rebelión: si era pagador confiable (score >0.4 antes del decay) y lleva
	# exactamente 7 días sin pagar, la facción escala hostilidad.
	# Comprobamos en el rango 7-8 para que solo dispare una vez aunque el
	# game loop no procese cada día exacto.
	if data.compliance_score > 0.4 and days_stopped >= 7 and days_stopped <= 8:
		var rebellion_pts: float = data.compliance_score * 20.0
		data.hostility_points = minf(data.hostility_points + rebellion_pts, 3000.0)
		data.recent_heat = minf(data.recent_heat + rebellion_pts * 1.5, HEAT_CAP)
		var lvl: int = _points_to_level(data.hostility_points)
		hostility_changed.emit(data.faction_id, data.hostility_points, lvl)
		Debug.log("faction_hostility",
			"[FHM] REBELLION %s +%.0f pts (compliance=%.2f, days_stopped=%d)" % [
			data.faction_id, rebellion_pts, data.compliance_score, days_stopped])


# ---------------------------------------------------------------------------
# Band wealth
# ---------------------------------------------------------------------------

## Acumula riqueza de la banda cuando se registra un incidente lucrativo.
func _accumulate_wealth(data: FactionHostilityData, reason: String,
		metadata: Dictionary) -> void:
	var income: float
	if reason == "extortion_paid":
		# La extorsión cobrada trae el oro real del jugador a la banda
		income = float(metadata.get("amount", 0))
	elif WEALTH_INCOME.has(reason):
		income = float(WEALTH_INCOME[reason])
	else:
		return
	if is_zero_approx(income):
		return
	data.band_wealth += income
	Debug.log("faction_hostility",
		"[FHM] wealth +%.0f (%s) → %.0f tier%d [%s]" % [
		income, reason, data.band_wealth, _wealth_to_tier(data.band_wealth), data.faction_id])


## Decae la riqueza un 2 % por día.
func _apply_wealth_decay(data: FactionHostilityData) -> void:
	if data.band_wealth <= 0.0:
		return
	data.band_wealth = maxf(0.0, data.band_wealth * (1.0 - WEALTH_DECAY_RATE))
	if data.band_wealth < 5.0:
		data.band_wealth = 0.0


func _wealth_to_tier(wealth: float) -> int:
	for t: int in range(WEALTH_TIERS.size() - 1, -1, -1):
		if wealth >= WEALTH_TIERS[t]:
			return t
	return 0


# ---------------------------------------------------------------------------
# Spree helper
# ---------------------------------------------------------------------------

## Devuelve [bonus_pts, bonus_heat] según el heat actual.
## Solo se llama si la reason es spree-eligible.
func _compute_spree_bonus(current_heat: float) -> Array:
	for tier: Variant in SPREE_TIERS:
		var t: Array = tier as Array
		if current_heat >= float(t[0]):
			return [float(t[1]), float(t[2])]
	return [0.0, 0.0]


# ---------------------------------------------------------------------------
# Helpers internos
# ---------------------------------------------------------------------------

func _get_or_create(faction_id: String) -> FactionHostilityData:
	if not _factions.has(faction_id):
		var d := FactionHostilityData.new()
		d.faction_id = faction_id
		_factions[faction_id] = d
	return _factions[faction_id] as FactionHostilityData


func _points_to_level(points: float) -> int:
	for lvl: int in range(LEVEL_THRESHOLDS.size() - 1, -1, -1):
		if points >= LEVEL_THRESHOLDS[lvl]:
			return lvl
	return 0


## Registra los detalles de un pago de extorsión y actualiza el compliance_score.
## Llamado solo cuando reason == "extortion_paid".
func _record_payment(data: FactionHostilityData, metadata: Dictionary) -> void:
	var amount: int = int(metadata.get("amount", 0))
	data.last_paid_day    = WorldTime.get_current_day()
	data.last_paid_amount = amount
	data.total_paid_gold += amount
	# Cada pago sube el compliance_score. Cap en 1.0 (~5 pagos consecutivos).
	data.compliance_score = minf(1.0, data.compliance_score + 0.2)
	Debug.log("faction_hostility",
		"[FHM] payment recorded %s amount=%d compliance=%.2f total_gold=%d" % [
		data.faction_id, amount, data.compliance_score, data.total_paid_gold])


func _increment_counter(data: FactionHostilityData, reason: String) -> void:
	match reason:
		"member_killed":      data.times_killed_members += 1
		"member_attacked":    data.times_attacked        += 1
		"extortion_refused":  data.times_refused          += 1
		"extortion_insulted": data.times_insulted         += 1
		"extortion_paid":     data.times_paid             += 1
		"barrel_sacked":      data.times_sacked_barrels   += 1
		"player_trespassed":  data.times_trespassed       += 1
		"player_looted":      data.times_looted           += 1
		"workbench_damaged":  data.times_workbench_hit    += 1
		"storage_damaged":    data.times_storage_hit      += 1
		"wall_damaged":       data.times_wall_hit         += 1
		"can_raid_base":      data.times_raided           += 1


# ---------------------------------------------------------------------------
# Save / Load
# ---------------------------------------------------------------------------

func serialize() -> Dictionary:
	var out: Dictionary = {}
	for fid: String in _factions:
		var data: FactionHostilityData = _factions[fid] as FactionHostilityData
		if data != null:
			out[fid] = data.to_dict()
	return out


func deserialize(raw: Dictionary) -> void:
	_factions.clear()
	for fid: String in raw.keys():
		var d := FactionHostilityData.new()
		d.from_dict(raw[fid] as Dictionary)
		_factions[fid] = d


func reset() -> void:
	_factions.clear()
	_dedup_ts.clear()


# ---------------------------------------------------------------------------
# Debug
# ---------------------------------------------------------------------------

func print_all() -> void:
	Debug.log("faction_hostility",
		"=== FactionHostilityManager (%d facciones) ===" % _factions.size())
	for fid: String in _factions:
		var data: FactionHostilityData = _factions[fid] as FactionHostilityData
		var lvl:  int                  = _points_to_level(data.hostility_points)
		Debug.log("faction_hostility",
			"  [%s] lv%d (%s) pts=%.0f heat=%.0f incidents_day=%d kills=%d barrels=%d" % [
			fid, lvl, LEVEL_NAMES[lvl],
			data.hostility_points, data.recent_heat, data.last_incident_day,
			data.times_killed_members, data.times_sacked_barrels])
