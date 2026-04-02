class_name RuntimeResetCoordinator
extends RefCounted

## Contrato de RuntimeResetCoordinator (new game bootstrap):
## - Orden de reset (estricto):
##   1) PlacementSystem: limpia referencias runtime para evitar punteros colgantes.
##   2) Faction/Site/Npc profile registries: limpia estado de dominio persistido en memoria.
##   3) BanditGroupMemory/ExtortionQueue: vacía colas y memoria táctica derivada.
##   4) RunClock/WorldTime: reinicia tiempo de run a estado base.
##   5) FactionHostilityManager: limpia estado de hostilidad, dependiente de reloj limpio.
## - Dependencias mínimas:
##   * Los autoloads listados deben existir y exponer los métodos usados.
##   * No depende de nodos de escena concretos ni de world.gd internals.
## - Side effects permitidos:
##   * Mutar estado global runtime de sistemas de dominio/tiempo/hostilidad.
##   * No crear/destruir nodos de escena ni tocar serialización fuera de estos resets.
func reset_new_game() -> void:
	PlacementSystem.clear_runtime_instances()
	FactionSystem.reset()
	SiteSystem.reset()
	NpcProfileSystem.reset()
	BanditGroupMemory.reset()
	ExtortionQueue.reset()
	RunClock.reset()
	WorldTime.load_save_data({})
	FactionHostilityManager.reset()
