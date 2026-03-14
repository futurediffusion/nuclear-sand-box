extends Node

# ── SiteSystem ─────────────────────────────────────────────────────────────
# Autoload. Registra sitios (campamentos, tabernas) con su facción y datos de lugar.
# No tiene gameplay: es el modelo de datos puro.

var _sites: Dictionary = {}  # site_id -> data dict


# Crea el sitio si no existe. Idempotente.
# core_tile: tile central del sitio (opcional, Vector2i(-1,-1) = desconocido)
func ensure_site(site_id: String, type: String, faction_id: String, core_tile: Vector2i = Vector2i(-1, -1)) -> void:
	if _sites.has(site_id):
		return
	_sites[site_id] = {
		"site_id":           site_id,
		"type":              type,
		"faction_id":        faction_id,
		"structural_tiles":  [],
		"stored_resources":  {},
		"core_tile":         core_tile,
		"destruction_ratio": 0.0,
	}
	FactionSystem.add_site(faction_id, site_id)


func get_site(site_id: String) -> Dictionary:
	return _sites.get(site_id, {})


func get_all_site_ids() -> Array:
	return _sites.keys()


# ── Persistencia ────────────────────────────────────────────────────────────
# Vector2i no es JSON-serializable directamente; lo guardamos como {x, y}.

func serialize() -> Dictionary:
	var out: Dictionary = {}
	for sid: String in _sites:
		var s: Dictionary = _sites[sid].duplicate()
		var ct: Vector2i = s.get("core_tile", Vector2i(-1, -1))
		s["core_tile"] = {"x": ct.x, "y": ct.y}
		out[sid] = s
	return out


func deserialize(data: Dictionary) -> void:
	_sites.clear()
	for sid: String in data:
		var s: Dictionary = (data[sid] as Dictionary).duplicate()
		var ct = s.get("core_tile", {"x": -1, "y": -1})
		if ct is Dictionary:
			s["core_tile"] = Vector2i(int(ct.get("x", -1)), int(ct.get("y", -1)))
		else:
			s["core_tile"] = Vector2i(-1, -1)
		_sites[sid] = s


func reset() -> void:
	_sites.clear()


# ── Debug 1D ────────────────────────────────────────────────────────────────

func print_all() -> void:
	Debug.log("site", "=== SiteSystem (%d sitios) ===" % _sites.size())
	for sid: String in _sites:
		var s: Dictionary = _sites[sid]
		Debug.log("site", "  [%s] type=%s faction=%s core=%s" % [
			sid,
			String(s.get("type", "?")),
			String(s.get("faction_id", "?")),
			str(s.get("core_tile", Vector2i(-1, -1))),
		])
