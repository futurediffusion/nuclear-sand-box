class_name RuntimeResetCoordinator
extends RefCounted

## Contrato canónico de RuntimeResetCoordinator (new game bootstrap):
## - Objetivo: centralizar reset global de runtime para evitar side effects cruzados.
## - Orden de reset (estricto y estable):
##   1) PlacementSystem.clear_runtime_instances()
##      * Debe correr primero para invalidar punteros runtime a entidades/mundos previos.
##   2) FactionSystem.reset(), SiteSystem.reset(), NpcProfileSystem.reset()
##      * Registries de dominio deben quedar vacíos antes de rehidratar simulación social.
##   3) BanditGroupMemory.reset(), ExtortionQueue.reset(), RaidQueue.reset()
##      * Limpia memoria táctica e intents pendientes derivados de estado viejo.
##   3.1) EnemyRegistry.reset()
##      * Evita índices huérfanos de enemigos entre runs (weakrefs/chunk buckets).
##   4) RunClock.reset(), WorldTime.load_save_data({})
##      * Relojes globales vuelven a baseline determinístico del nuevo run.
##   5) FactionHostilityManager.reset()
##      * Ejecuta al final porque depende de reloj y registries ya reiniciados.
## - Dependencias mínimas:
##   * Los autoloads listados deben existir y exponer los métodos usados.
##   * No depende de nodos de escena concretos ni de world.gd internals.
## - Side effects permitidos:
##   * Mutar estado global runtime de sistemas de dominio/tiempo/hostilidad.
##   * No crear/destruir nodos de escena ni tocar serialización fuera de estos resets.
func reset_new_game() -> void:
	_reset_placement_runtime()
	_reset_domain_registries()
	_reset_tactical_memory_and_queues()
	_reset_run_time()
	_reset_hostility_runtime()


func _reset_placement_runtime() -> void:
	PlacementSystem.clear_runtime_instances()


func _reset_domain_registries() -> void:
	FactionSystem.reset()
	SiteSystem.reset()
	NpcProfileSystem.reset()


func _reset_tactical_memory_and_queues() -> void:
	BanditGroupMemory.reset()
	ExtortionQueue.reset()
	RaidQueue.reset()
	EnemyRegistry.reset()


func _reset_run_time() -> void:
	RunClock.reset()
	WorldTime.load_save_data({})


func _reset_hostility_runtime() -> void:
	FactionHostilityManager.reset()
