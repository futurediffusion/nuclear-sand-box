class_name FactionHostilityData
extends RefCounted
## Estado persistente de hostilidad del jugador contra una facción concreta.
## Creado y gestionado exclusivamente por FactionHostilityManager.
## Los enemies nunca deben escribir en esto directamente.

var faction_id:          String = ""

# ── Puntos y nivel ────────────────────────────────────────────────────────
var hostility_points:    float  = 0.0   # fuente de verdad; nivel se deriva de aquí

# ── Temporalidad ──────────────────────────────────────────────────────────
var last_incident_day:   int    = -1    # día del último incidente registrado
var last_decay_day:      int    = 0     # día en que se aplicó decay por última vez

# ── Capa de calor reciente (heat) ─────────────────────────────────────────
# Representa la agitación inmediata: decae mucho más rápido que hostility_points.
# Sirve para que la facción reaccione con más intensidad justo tras un incidente.
var recent_heat:         float  = 0.0

# ── Contadores históricos ─────────────────────────────────────────────────
# Nunca se decrementan; permiten balanceo futuro y diagnósticos.
var times_paid:           int = 0
var times_refused:        int = 0
var times_insulted:       int = 0
var times_attacked:       int = 0
var times_killed_members: int = 0
var times_sacked_barrels: int = 0
var times_trespassed:     int = 0
var times_looted:         int = 0   # veces que le robaron al jugador
var times_workbench_hit:  int = 0
var times_storage_hit:    int = 0
var times_wall_hit:       int = 0
var times_raided:         int = 0


# ---------------------------------------------------------------------------
# Serialización
# ---------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"faction_id":          faction_id,
		"hostility_points":    hostility_points,
		"last_incident_day":   last_incident_day,
		"last_decay_day":      last_decay_day,
		"recent_heat":         recent_heat,
		"times_paid":          times_paid,
		"times_refused":       times_refused,
		"times_insulted":      times_insulted,
		"times_attacked":      times_attacked,
		"times_killed_members":times_killed_members,
		"times_sacked_barrels":times_sacked_barrels,
		"times_trespassed":    times_trespassed,
		"times_looted":        times_looted,
		"times_workbench_hit": times_workbench_hit,
		"times_storage_hit":   times_storage_hit,
		"times_wall_hit":      times_wall_hit,
		"times_raided":        times_raided,
	}


func from_dict(d: Dictionary) -> void:
	faction_id           = String(d.get("faction_id",           ""))
	hostility_points     = float(d.get("hostility_points",      0.0))
	last_incident_day    = int(d.get("last_incident_day",       -1))
	last_decay_day       = int(d.get("last_decay_day",          0))
	recent_heat          = float(d.get("recent_heat",           0.0))
	times_paid           = int(d.get("times_paid",              0))
	times_refused        = int(d.get("times_refused",           0))
	times_insulted       = int(d.get("times_insulted",          0))
	times_attacked       = int(d.get("times_attacked",          0))
	times_killed_members = int(d.get("times_killed_members",    0))
	times_sacked_barrels = int(d.get("times_sacked_barrels",    0))
	times_trespassed     = int(d.get("times_trespassed",        0))
	times_looted         = int(d.get("times_looted",            0))
	times_workbench_hit  = int(d.get("times_workbench_hit",     0))
	times_storage_hit    = int(d.get("times_storage_hit",       0))
	times_wall_hit       = int(d.get("times_wall_hit",          0))
	times_raided         = int(d.get("times_raided",            0))
