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
## - Validación sin side effects reales:
##   * En entorno de pruebas, `configure_validation_spies()` permite inyectar dobles/spies por operación.
##   * Si hay spy para una operación, no se ejecuta el autoload real.
var _validation_spies: Dictionary = {}

func configure_validation_spies(spies_by_operation: Dictionary) -> void:
	_validation_spies = spies_by_operation.duplicate()


func reset_new_game() -> void:
	_reset_placement_runtime()
	_reset_domain_registries()
	_reset_tactical_memory_and_queues()
	_reset_run_time()
	_reset_hostility_runtime()


func _reset_placement_runtime() -> void:
	_invoke_reset("placement.clear_runtime_instances", func() -> void:
		PlacementSystem.clear_runtime_instances()
	)


func _reset_domain_registries() -> void:
	_invoke_reset("registries.faction.reset", func() -> void:
		FactionSystem.reset()
	)
	_invoke_reset("registries.site.reset", func() -> void:
		SiteSystem.reset()
	)
	_invoke_reset("registries.npc_profile.reset", func() -> void:
		NpcProfileSystem.reset()
	)


func _reset_tactical_memory_and_queues() -> void:
	_invoke_reset("tactical.bandit_group_memory.reset", func() -> void:
		BanditGroupMemory.reset()
	)
	_invoke_reset("tactical.extortion_queue.reset", func() -> void:
		ExtortionQueue.reset()
	)
	_invoke_reset("tactical.raid_queue.reset", func() -> void:
		RaidQueue.reset()
	)
	_invoke_reset("tactical.enemy_registry.reset", func() -> void:
		EnemyRegistry.reset()
	)


func _reset_run_time() -> void:
	_invoke_reset("time.run_clock.reset", func() -> void:
		RunClock.reset()
	)
	_invoke_reset("time.world_time.load_save_data", func() -> void:
		WorldTime.load_save_data({})
	)


func _reset_hostility_runtime() -> void:
	_invoke_reset("hostility.faction_hostility_manager.reset", func() -> void:
		FactionHostilityManager.reset()
	)


func _invoke_reset(operation: String, default_call: Callable) -> void:
	if _validation_spies.has(operation):
		var spy := _validation_spies[operation] as Callable
		if spy.is_valid():
			spy.call()
			return
	default_call.call()
