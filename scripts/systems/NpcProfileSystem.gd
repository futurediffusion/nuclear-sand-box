extends Node

# ── NpcProfileSystem ───────────────────────────────────────────────────────
# Autoload. Registra perfiles de NPCs con facción, rol y estado de vida.
# No tiene gameplay: es el modelo de datos puro.

var _profiles: Dictionary = {}  # npc_id -> data dict


# Crea el perfil si no existe. Idempotente.
# El npc_id debe ser el entity_uid existente del nodo.
func ensure_profile(npc_id: String, faction_id: String, role: String, home_site_id: String = "") -> void:
	if npc_id == "":
		return
	if _profiles.has(npc_id):
		return
	_profiles[npc_id] = {
		"npc_id":       npc_id,
		"faction_id":   faction_id,
		"role":         role,
		"status":       "alive",
		"stats":        {},
		"traits":       [],
		"home_site_id": home_site_id,
	}
	FactionSystem.add_member(faction_id, npc_id)


func get_profile(npc_id: String) -> Dictionary:
	return _profiles.get(npc_id, {})


func get_all_npc_ids() -> Array:
	return _profiles.keys()


# Actualiza el status (alive, downed, dead, free).
func set_status(npc_id: String, status: String) -> void:
	if not _profiles.has(npc_id):
		return
	_profiles[npc_id]["status"] = status


# Devuelve todos los IDs de NPCs de una facción.
func get_members_of_faction(faction_id: String) -> Array:
	var result: Array = []
	for nid: String in _profiles:
		if String(_profiles[nid].get("faction_id", "")) == faction_id:
			result.append(nid)
	return result


# ── Persistencia ────────────────────────────────────────────────────────────

func serialize() -> Dictionary:
	return _profiles.duplicate(true)


func deserialize(data: Dictionary) -> void:
	_profiles = data


func reset() -> void:
	_profiles.clear()


# ── Debug 1D ────────────────────────────────────────────────────────────────

func print_all() -> void:
	Debug.log("npc", "=== NpcProfileSystem (%d perfiles) ===" % _profiles.size())
	for nid: String in _profiles:
		var p: Dictionary = _profiles[nid]
		Debug.log("npc", "  [%s] faction=%s role=%s status=%s site=%s" % [
			nid,
			String(p.get("faction_id", "?")),
			String(p.get("role", "?")),
			String(p.get("status", "?")),
			String(p.get("home_site_id", "")),
		])


# Imprime la relación NPC -> facción -> sitio para los primeros N perfiles.
func print_relation_tree(limit: int = 20) -> void:
	var count: int = 0
	Debug.log("npc", "=== NPC -> Facción -> Sitio ===")
	for nid: String in _profiles:
		if count >= limit:
			Debug.log("npc", "  ... (más de %d, usar print_all)" % limit)
			break
		var p: Dictionary = _profiles[nid]
		var fid: String = String(p.get("faction_id", "?"))
		var sid: String = String(p.get("home_site_id", "(sin sitio)"))
		var faction: Dictionary = FactionSystem.get_faction(fid)
		var ftype: String = String(faction.get("type", "?"))
		Debug.log("npc", "  %s -> [%s/%s] -> site:%s" % [nid, fid, ftype, sid])
		count += 1
