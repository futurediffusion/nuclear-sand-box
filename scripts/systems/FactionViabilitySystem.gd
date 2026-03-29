extends Node

# ── FactionViabilitySystem ───────────────────────────────────────────────────
# Autoload. Evalúa viabilidad de grupos bandit y gestiona reconstrucción de campfire.
#
# Condición de erradicación (AND estricto):
#   - Todos los miembros muertos  (strength = 0)
#   - Campfire destruida          (destruction_ratio = 1.0)
#
# Si la campfire es destruida pero quedan miembros vivos:
#   → cooldown CAMPFIRE_REBUILD_COOLDOWN segundos → nueva campfire en el camp.
#
# API pública:
#   is_faction_viable(group_id)            → bool
#   get_faction_strength(group_id)         → float 0.0–1.0
#   get_base_integrity(site_id)            → float 0.0–1.0
#   is_eradicated(group_id)               → bool
#   check_eradication(group_id)           → void  (idempotente)
#   notify_campfire_destroyed(group_id, camp_node) → void
#
# group_id format: "camp:{chunk_key}:{camp_index:03d}"

const CAMPFIRE_REBUILD_COOLDOWN: float = 45.0
const CAMPFIRE_SCENE: PackedScene = preload("res://scenes/placeables/campfire_world.tscn")

# group_id → {timer: float, camp_node: Node}
var _rebuild_pending: Dictionary = {}


func _process(delta: float) -> void:
	for gid: String in _rebuild_pending.keys():
		_rebuild_pending[gid]["timer"] = float(_rebuild_pending[gid]["timer"]) - delta
		if float(_rebuild_pending[gid]["timer"]) <= 0.0:
			_try_rebuild_campfire(gid)
			_rebuild_pending.erase(gid)


# ── Query API ────────────────────────────────────────────────────────────────

## Viable si algún miembro vivo O campfire en pie. Erradicado solo cuando ambos caen.
func is_faction_viable(group_id: String) -> bool:
	var members_alive: bool = _count_live_members(group_id) > 0
	var campfire_standing: bool = get_base_integrity(group_id) > 0.0
	return members_alive or campfire_standing


## Ratio de miembros vivos respecto al total registrado. 0.0 = todos muertos.
func get_faction_strength(group_id: String) -> float:
	var g: Dictionary = BanditGroupMemory.get_group(group_id)
	if g.is_empty():
		return 0.0
	var total: int = (g.get("member_ids", []) as Array).size()
	if total == 0:
		return 0.0
	return float(_count_live_members(group_id)) / float(total)


## Integridad de la campfire. 1.0 = en pie, 0.0 = destruida.
func get_base_integrity(site_id: String) -> float:
	var site: Dictionary = SiteSystem.get_site(site_id)
	if site.is_empty():
		return 1.0
	return 1.0 - clampf(float(site.get("destruction_ratio", 0.0)), 0.0, 1.0)


## Retorna true si el grupo fue marcado como erradicado.
func is_eradicated(group_id: String) -> bool:
	return bool(BanditGroupMemory.get_group(group_id).get("eradicated", false))


# ── Trigger API ──────────────────────────────────────────────────────────────

## Llamar cuando un miembro muere. Evalúa erradicación si no queda nadie.
func check_eradication(group_id: String) -> void:
	if group_id == "" or is_eradicated(group_id):
		return
	if is_faction_viable(group_id):
		return
	_eradicate(group_id)


## Llamar cuando la campfire de un campamento es destruida.
## camp_node: el nodo padre BanditCamp (para poder reconstruir la campfire).
## - Si quedan miembros vivos → inicia cooldown de reconstrucción.
## - Si no queda nadie        → evalúa erradicación directamente.
func notify_campfire_destroyed(group_id: String, camp_node: Node = null) -> void:
	if group_id == "":
		return
	SiteSystem.set_destruction_ratio(group_id, 1.0)

	if _count_live_members(group_id) > 0 and camp_node != null and is_instance_valid(camp_node):
		_rebuild_pending[group_id] = {
			"timer": CAMPFIRE_REBUILD_COOLDOWN,
			"camp_node": camp_node,
		}
		Debug.log("faction_eradication", "[FVS] campfire destruida, rebuild en %.0fs grupo=%s" % [
			CAMPFIRE_REBUILD_COOLDOWN, group_id])
	else:
		check_eradication(group_id)


# ── Internal ─────────────────────────────────────────────────────────────────

func _count_live_members(group_id: String) -> int:
	var g: Dictionary = BanditGroupMemory.get_group(group_id)
	if g.is_empty():
		return 0
	var count: int = 0
	for mid in g.get("member_ids", []):
		var profile: Dictionary = NpcProfileSystem.get_profile(String(mid))
		if String(profile.get("status", "")) != "dead":
			count += 1
	return count


func _try_rebuild_campfire(group_id: String) -> void:
	var data: Dictionary = _rebuild_pending.get(group_id, {})
	var camp_node: Node = data.get("camp_node")

	# Si el camp ya no existe (chunk descargado) o no quedan miembros → check eradication
	if camp_node == null or not is_instance_valid(camp_node):
		check_eradication(group_id)
		return
	if _count_live_members(group_id) == 0:
		check_eradication(group_id)
		return

	var campfire: CampfireWorld = CAMPFIRE_SCENE.instantiate() as CampfireWorld
	campfire.name = "CampfireWorld"
	campfire.group_id = group_id
	camp_node.add_child(campfire)
	SiteSystem.set_destruction_ratio(group_id, 0.0)
	Debug.log("faction_eradication", "[FVS] campfire reconstruida grupo=%s" % group_id)
	# No emitir faction_eradicated — la reconstrucción es un éxito del grupo


func _eradicate(group_id: String) -> void:
	var g: Dictionary = BanditGroupMemory.get_group(group_id)
	if not g.is_empty():
		g["eradicated"] = true

	var chunk_key := _chunk_key_from_group_id(group_id)
	if chunk_key != "":
		WorldSave.clear_chunk_enemy_spawns(chunk_key)

	Debug.log("faction_eradication", "[FVS] erradicado id=%s chunk=%s strength=%.2f integrity=%.2f" % [
		group_id, chunk_key,
		get_faction_strength(group_id),
		get_base_integrity(group_id),
	])
	GameEvents.emit_faction_eradicated(group_id)


## Extrae chunk_key del group_id. Formato: "camp:{chunk_key}:{camp_index:03d}"
func _chunk_key_from_group_id(group_id: String) -> String:
	var parts := group_id.split(":")
	if parts.size() < 3:
		return ""
	return parts[1]
