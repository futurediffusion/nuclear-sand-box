extends Node

# ── FactionSystem ──────────────────────────────────────────────────────────
# Autoload. Registra facciones con miembros y sitios asociados.
# No tiene gameplay: es el modelo de datos puro.

var _factions: Dictionary = {}  # faction_id -> data dict


func _ready() -> void:
	_seed_default_factions()


# Asegura que las 3 facciones base siempre existan.
func _seed_default_factions() -> void:
	ensure_faction("player",  "player",  0.0)
	ensure_faction("bandit",  "bandit",  1.0)
	ensure_faction("bandits", "bandit",  1.0) # alias usado por enemies/runtime
	ensure_faction("tavern",  "tavern",  0.0)


# Crea la facción si no existe. Idempotente.
func ensure_faction(faction_id: String, type: String, hostility_to_player: float) -> void:
	if _factions.has(faction_id):
		return
	_factions[faction_id] = {
		"faction_id":         faction_id,
		"type":               type,
		"hostility_to_player": hostility_to_player,
		"allied_factions":    [],
		"member_ids":         [],
		"site_ids":           [],
	}


func get_faction(faction_id: String) -> Dictionary:
	return _factions.get(faction_id, {})


func get_all_faction_ids() -> Array:
	return _factions.keys()


func add_member(faction_id: String, npc_id: String) -> void:
	if not _factions.has(faction_id):
		return
	var members: Array = _factions[faction_id]["member_ids"]
	if not members.has(npc_id):
		members.append(npc_id)


func add_site(faction_id: String, site_id: String) -> void:
	if not _factions.has(faction_id):
		return
	var sites: Array = _factions[faction_id]["site_ids"]
	if not sites.has(site_id):
		sites.append(site_id)


# ── Persistencia ────────────────────────────────────────────────────────────

func serialize() -> Dictionary:
	return _factions.duplicate(true)


func deserialize(data: Dictionary) -> void:
	_factions = data
	_seed_default_factions()  # garantiza que las bases siempre estén


func reset() -> void:
	_factions.clear()
	_seed_default_factions()


# ── Debug 1D ────────────────────────────────────────────────────────────────

func print_all() -> void:
	Debug.log("faction", "=== FactionSystem (%d facciones) ===" % _factions.size())
	for fid: String in _factions:
		var f: Dictionary = _factions[fid]
		Debug.log("faction", "  [%s] type=%s hostile=%.1f members=%d sites=%d" % [
			fid,
			String(f.get("type", "?")),
			float(f.get("hostility_to_player", 0.0)),
			(f.get("member_ids", []) as Array).size(),
			(f.get("site_ids", []) as Array).size(),
		])
