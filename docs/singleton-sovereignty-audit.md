# Auditoría de soberanía y accesos a singletons/autoloads (Phase 2 suspicious files)

Fecha: 2026-04-01

Fuente de archivos sospechosos: `docs/phase-2-suspicious-files.md`.

## Criterio de clasificación
- **solo lectura**: consulta estado sin escribir ni disparar acciones globales.
- **lectura + decisión**: consulta y usa el resultado para ramificar lógica.
- **escritura/side effect**: escribe estado global, encola trabajo, conecta señales globales o dispara efectos globales.

## Resultados por archivo

### 1) `scripts/world/world.gd`
- `WorldSave.chunk_size = ...`, `WorldSave.wall_tile_blocker_fn = ...` → **escritura/side effect**.
- `SaveManager.register_world/load_world_save` → **escritura/side effect**.
- `Seed.run_seed` → **solo lectura**.
- `GameEvents.connect`, `PlacementSystem.connect` → **escritura/side effect**.
- `RunClock.now` → **lectura + decisión**.
- `BanditGroupMemory.get_*` + `record_interest/set_lock/update_intent` → **lectura + decisión** + **escritura/side effect**.
- `RaidQueue.has_*/enqueue_*` → **lectura + decisión** + **escritura/side effect**.
- `FactionHostilityManager.get_behavior_profile`, `FactionSystem.get_faction` → **lectura + decisión**.

**Soberanía:** rompe soberanía al decidir y mutar intención social/raid de grupos desde el orquestador de mundo.

**Telemetry/debug:** `Debug.log` no muta por sí mismo, pero está embebido en rutas de control críticas.

**Objetivo de refactor:** pasar a eventos/contratos para intención/raid y encapsular writes a `WorldSave` detrás de adapters.

### 2) `scripts/world/BanditBehaviorLayer.gd`
- `BanditGroupMemory.get_*` → **lectura + decisión**.
- `BanditGroupMemory.set_assault_target/clear_assault_target` → **escritura/side effect**.
- `RunClock.now`, `FactionHostilityManager.get_hostility_level` → **lectura + decisión**.
- `WorldSave.enemy_state_by_chunk` → **solo lectura**.
- `NpcPathService.clear_agent` → **escritura/side effect**.

**Soberanía:** media-alta; mezcla locomoción con decisiones de estado grupal.

**Telemetry/debug:** rama `DEBUG_ALERTED_CHASE` muta velocidad de NPC (riesgo real de mutación por debug).

**Objetivo de refactor:** invertir dependencia con puertos (`GroupIntentPort`, `PathServicePort`) y concentrar mutaciones de grupo en coordinador dedicado.

### 3) `scripts/world/ExtortionFlow.gd`
- `FactionHostilityManager.add_hostility` → **escritura/side effect**.
- `BanditGroupMemory.get_*` → **lectura + decisión**.
- `BanditGroupMemory.push_social_cooldown/update_intent` → **escritura/side effect**.
- `ExtortionQueue.consume_for_group` → **escritura/side effect** (consumo destructivo de cola).

**Soberanía:** alta; combina decisión de diálogo, economía del jugador y mutación social/faccional en la misma pieza.

**Telemetry/debug:** logs informativos; riesgo bajo directo.

**Objetivo de refactor:** encapsular outcome de extorsión en un servicio transaccional de dominio.

### 4) `scripts/world/BanditGroupIntel.gd`
- `BanditGroupMemory.get_*` → **lectura + decisión**.
- `BanditGroupMemory.update_intent/set_scout/record_interest/push_social_cooldown` → **escritura/side effect**.
- `FactionHostilityManager.get_*` → **lectura + decisión**.
- `FactionHostilityManager.add_hostility` → **escritura/side effect**.
- `ExtortionQueue.has_*/get_last_*/enqueue` → **lectura + decisión** + **escritura/side effect**.
- `RaidQueue.has_*/get_last_*/enqueue_*` → **lectura + decisión** + **escritura/side effect**.
- `RunClock.now` → **lectura + decisión**.

**Soberanía:** alta; el scanner de inteligencia también actúa como command dispatcher.

**Telemetry/debug:** `Debug.is_enabled/log` de bajo riesgo directo.

**Objetivo de refactor:** separar en `assessment` (read-only) y `intent command service` (writes/enqueues).

### 5) `scripts/world/BanditWorkCoordinator.gd`
- `BanditGroupMemory.get_group/is_structure_assault_active/has_placement_react_lock/get_assault_target` → **lectura + decisión**.
- `RunClock.now` → **lectura + decisión**.
- `Debug.log` → observabilidad.

**Soberanía:** baja-media; predomina lectura contextual.

**Telemetry/debug:** bajo.

**Objetivo de refactor:** recibir snapshot inmutable del estado grupal por tick para reducir lecturas directas a autoload.

### 6) `scripts/world/SettlementIntel.gd`
- `PlacementSystem.placement_completed.connect`, `GameEvents.resource_harvested.connect` → **escritura/side effect**.
- `WorldSave.placed_entities_by_chunk`, `WorldSave.player_walls_by_chunk`, `WorldSave.chunk_size` → **solo lectura**.
- Flags `_dirty/_base_scan_dirty` → **lectura + decisión** local.

**Soberanía:** media; correcto como read-model sobre persistencia, pero puede crecer a policy actor.

**Telemetry/debug:** bajo (logs).

**Objetivo de refactor:** encapsular lecturas de persistencia vía interfaz read-model (`IPlacedEntityReadModel`).

### 7) `scripts/world/WorldSpatialIndex.gd`
- `WorldSave.get_placed_entities_in_chunk/chunk_key/get_placed_entity_data/placed_entities_revision/placed_entities_by_chunk` → **solo lectura**.

**Soberanía:** baja; buen boundary de consulta.

**Telemetry/debug:** nulo relevante.

**Objetivo de refactor:** mantenerlo como read model, exponer interfaz para reducir acoplamiento.

### 8) `scripts/world/WorldTerritoryPolicy.gd`
- `BanditGroupMemory.get_*`, `FactionHostilityManager.get_behavior_profile`, `RunClock.now` → **lectura + decisión**.
- `FactionHostilityManager.add_hostility` → **escritura/side effect**.

**Soberanía:** media; una policy que escribe hostilidad global directamente.

**Telemetry/debug:** bajo (logs).

**Objetivo de refactor:** policy retorna decisión/incident y un applicator ejecuta `add_hostility`.

### 9) `scripts/world/WorldCadenceCoordinator.gd`
- Sin accesos a autoloads.

**Soberanía:** no aplica.

**Telemetry/debug:** snapshot interno sin writes globales.

**Objetivo de refactor:** no prioritario.

## Riesgos concretos de mutación accidental por debug/telemetry
1. `Debug` incluye flags que alteran gameplay (`ghost_mode`, `disable_enemy_cache`, etc.), no sólo logging.
2. `BanditBehaviorLayer` contiene una rama de debug que escribe `velocity` de NPC directamente.
3. `Debug.log` en sí es observabilidad gateada; el riesgo fuerte está en flags de control, no en el logger.
