extends RefCounted
class_name TavernLocalMemory

## Historial de incidentes civiles de la taberna para la sesión actual.
##
## Fase 2: almacenamiento en memoria RAM, sin persistencia entre sesiones.
## Fase 3: serializar a WorldSave para persistencia entre sesiones.
##
## USO:
##   _tavern_memory.record(incident)
##   var count := _tavern_memory.get_offender_count("Player")
##   var snap  := _tavern_memory.get_snapshot("tavern_main")

const MAX_ENTRIES: int = 128

## Registro cronológico de incidentes (como Dictionary via to_dict()).
var _entries: Array[Dictionary] = []

## Conteo acumulado de incidentes por actor_id.
## Clave: offender_actor_id (String). Valor: int.
var _offender_counts: Dictionary = {}


## Registra un incidente. Si se supera MAX_ENTRIES, descarta el más antiguo.
func record(incident: LocalCivilIncident) -> void:
	_entries.append(incident.to_dict())
	if _entries.size() > MAX_ENTRIES:
		_entries.pop_front()
	if not incident.offender_actor_id.is_empty():
		var prev: int = _offender_counts.get(incident.offender_actor_id, 0)
		_offender_counts[incident.offender_actor_id] = prev + 1


## Número de incidentes registrados para un actor_id concreto.
func get_offender_count(actor_id: String) -> int:
	return int(_offender_counts.get(actor_id, 0))


## Snapshot de estado para el port callable de LocalSocialAuthorityPorts.
## scope_id: el local_authority_id que se quiere consultar (p.ej. "tavern_main").
func get_snapshot(scope_id: String, _payload: Dictionary = {}) -> Dictionary:
	return {
		"scope_id":        scope_id,
		"entry_count":     _entries.size(),
		"offender_counts": _offender_counts.duplicate(),
	}
