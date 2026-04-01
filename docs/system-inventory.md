# System Inventory (estado actual)

Este inventario describe **qué implementa cada dominio hoy**, sus entradas/salidas principales, dependencias cruzadas y duplicados funcionales detectados.

---

## 1) Tiempo del mundo

### Implementación actual (módulos / clases / servicios)
- `WorldTime` (`scripts/systems/WorldTime.gd`)
  - Lleva día y progreso intra-día.
  - Emite señal: `day_passed(new_day)`.
  - Persistencia: `get_save_data()` / `load_save_data()`.
- `RunClock` (`scripts/systems/RunClock.gd`)
  - Reloj monotónico de runtime (`now()`), usado para cooldowns/scheduling sistémico.
  - Persistencia: `get_save_data()` / `load_save_data()`.
- `WorldCadenceCoordinator` (`scripts/world/WorldCadenceCoordinator.gd`)
  - Scheduler por lanes (`short_pulse`, `medium_pulse`, `director_pulse`, `chunk_pulse`, `autosave`, etc.).
  - Consumido desde `world.gd` y `BanditBehaviorLayer.gd`.

### Entradas / salidas principales
- Entrada:
  - `_process(delta)` en `WorldTime` y `RunClock`.
  - `advance(delta)` en `WorldCadenceCoordinator` desde `world.gd::_process`.
- Salida:
  - `WorldTime.day_passed` (consumido por `FactionHostilityManager._on_day_passed`).
  - `RunClock.now()` (consumido por extortion/raid/territorio/pathing).
  - `WorldCadenceCoordinator.consume_lane(...)` (drives world maintenance/directors).

### Dependencias cruzadas (lecturas/escrituras/eventos/llamadas)
| Dependencia cruzada | Tipo | Riesgo |
|---|---|---|
| `FactionHostilityManager._ready()` conecta `WorldTime.day_passed` | Evento | Medio |
| `BanditGroupIntel`, `RaidFlow`, `ExtortionFlow`, `WorldTerritoryPolicy`, `NpcPathService` leen `RunClock.now()` | Lectura común | Alto |
| `world.gd` y `BanditBehaviorLayer.gd` consumen lanes de `WorldCadenceCoordinator` | Llamada directa | Medio |
| `SaveManager` serializa/deserializa `run_clock` y `world_time` | Persistencia compartida | Medio |

### Duplicados funcionales detectados
- **Dos relojes globales en paralelo**:
  - `scripts/systems/WorldTime.gd::_process`
  - `scripts/systems/RunClock.gd::_process`
- Ambos mantienen tiempo persistente, pero para propósitos distintos. Hay riesgo de deriva conceptual (qué reloj usar para cada regla).

---

## 2) Bandit AI

### Implementación actual
- `BanditBehaviorLayer` (`scripts/world/BanditBehaviorLayer.gd`)
  - Orquestador principal de behaviors activos.
  - Gestiona extortion director, raid director, stash/work coordinators.
- `BanditWorldBehavior` (`scripts/world/BanditWorldBehavior.gd`) + `NpcWorldBehavior` (`scripts/world/NpcWorldBehavior.gd`)
  - FSM data-oriented por NPC (patrol/home/follow/approach/etc.).
- `BanditGroupIntel` (`scripts/world/BanditGroupIntel.gd`)
  - Scanner de inteligencia por grupo: score de actividad, intents, enqueue extortion/raid.
- `NpcSimulator` (`scripts/world/NpcSimulator.gd`)
  - Registro/lookup de enemigos activos + estados lite/sleeping.
- `BanditWorkCoordinator`, `BanditCampStashSystem` (apoyo logístico).

### Entradas / salidas principales
- Entrada:
  - `BanditBehaviorLayer.setup(ctx)` desde `world.gd::_ready`.
  - `BanditBehaviorLayer._process(delta)` y `_physics_process(delta)`.
  - `setup_group_intel(ctx)` después de inicializar `SettlementIntel`.
- Salida:
  - `dispatch_group_to_target(...)` para raids/assaults.
  - Escrituras en `BanditGroupMemory` (`update_intent`, `record_interest`, etc.).
  - Encolado en `ExtortionQueue` y `RaidQueue`.

### Dependencias cruzadas
| Dependencia cruzada | Tipo | Riesgo |
|---|---|---|
| `BanditBehaviorLayer` consume `WorldCadenceCoordinator` lane `director_pulse` | Llamada directa | Medio |
| `BanditGroupIntel` consulta `SettlementIntel` vía callables inyectados desde `world.gd` | Llamada directa | Alto |
| `BanditGroupIntel` escribe en `ExtortionQueue` y `RaidQueue` | Escritura | Alto |
| `BanditBehaviorLayer` usa `NpcSimulator.get_enemy_node` para ejecutar movimiento | Lectura runtime | Medio |
| `BanditBehaviorLayer` y `BanditWorkCoordinator` consultan `WorldSpatialIndex`/drops/resources | Lectura | Medio |

### Duplicados funcionales detectados
- Lógica de “cuándo escalar agresión grupal” repartida entre:
  - `BanditGroupIntel._maybe_enqueue_extortion`
  - `BanditGroupIntel._maybe_enqueue_wall_probe`
  - `BanditGroupIntel._maybe_enqueue_light_raid`
  - `BanditGroupIntel._maybe_enqueue_raid`
- El gate por cooldown/pending/intent aparece repetido con variantes en cada método.

---

## 3) Territorialidad / hostilidad

### Implementación actual
- `WorldTerritoryPolicy` (`scripts/world/WorldTerritoryPolicy.gd`)
  - Reglas de validación de placement en zonas sensibles.
  - Traduce eventos de interés a hostilidad de facción.
- `PlayerTerritoryMap` (`scripts/world/PlayerTerritoryMap.gd`)
  - Reconstrucción de zonas del jugador (workbench + bases cerradas detectadas).
- `BanditTerritoryQuery` (`scripts/world/BanditTerritoryQuery.gd`)
  - Query estática de territorio bandido por radio dinámico.
- `FactionHostilityManager` (`scripts/systems/FactionHostilityManager.gd`)
  - Fuente de verdad de puntos/nivel/decay/perfil de comportamiento.
- `FactionRelationService` (`scripts/systems/FactionRelationService.gd`)
  - Lecturas derivadas de hostilidad.

### Entradas / salidas principales
- Entrada:
  - `world.gd::_validate_placement_restrictions` -> `WorldTerritoryPolicy.validate_placement`.
  - `world.gd::record_interest_event` -> `WorldTerritoryPolicy.record_interest_event`.
  - `FactionHostilityManager.add_hostility/reduce_hostility`.
- Salida:
  - `FactionHostilityManager.hostility_changed` / `level_changed`.
  - `WorldTerritoryPolicy` dispara callback `_on_bandit_territory_intrusion`.
  - `BanditTerritoryQuery.groups_at/is_in_territory` usado por reglas de intrusión.

### Dependencias cruzadas
| Dependencia cruzada | Tipo | Riesgo |
|---|---|---|
| `WorldTerritoryPolicy.record_interest_event` llama `FactionHostilityManager.add_hostility` | Escritura global | Alto |
| `WorldTerritoryPolicy.validate_placement` lee `BanditGroupMemory` + `FactionHostilityManager.get_behavior_profile` | Lectura cruzada | Alto |
| `BanditTerritoryQuery.radius_for_faction` depende de `FactionHostilityManager` | Lectura | Medio |
| `FactionHostilityManager` depende de `WorldTime.day_passed` para decay | Evento | Medio |
| `world.gd` orquesta policy + territory map + settlement intel | Acoplamiento orquestación | Medio |

### Duplicados funcionales detectados
- Cálculo de pertenencia territorial bandida en dos caminos:
  - `BanditTerritoryQuery.groups_at(world_pos)`
  - `BanditTerritoryQuery.is_in_territory(world_pos)`
- Ambos repiten iteración sobre `BanditGroupMemory` + cálculo de radio/distancia.

---

## 4) Raids / extortion

### Implementación actual
- Extortion:
  - `ExtortionQueue` (`scripts/systems/ExtortionQueue.gd`) — cola persistible.
  - `BanditExtortionDirector` (`scripts/world/BanditExtortionDirector.gd`) — coordinador.
  - `ExtortionFlow` (`scripts/world/ExtortionFlow.gd`) — lógica de encounter.
  - `ExtortionUIAdapter` (`scripts/world/ExtortionUIAdapter.gd`) — puente UI + signal `choice_resolved`.
- Raid:
  - `RaidQueue` (`scripts/systems/RaidQueue.gd`) — intents pendientes runtime.
  - `BanditRaidDirector` (`scripts/world/BanditRaidDirector.gd`) — wrapper de flujo.
  - `RaidFlow` (`scripts/world/RaidFlow.gd`) — ciclo de vida de raid jobs.

### Entradas / salidas principales
- Entrada:
  - `BanditGroupIntel` encola intents (`ExtortionQueue.enqueue`, `RaidQueue.enqueue_*`).
  - `BanditBehaviorLayer._process` ejecuta `process_extortion` y `process_raid` por pulso.
  - `ExtortionUIAdapter.choice_resolved` -> `ExtortionFlow.on_choice_resolved`.
- Salida:
  - Mutación de `BanditGroupMemory` (intents/cooldowns/flags).
  - Hostilidad en `FactionHostilityManager.add_hostility` por pago/rechazo/insulto.
  - Despacho de escuadras vía `dispatch_group_to_target`.

### Dependencias cruzadas
| Dependencia cruzada | Tipo | Riesgo |
|---|---|---|
| `BanditGroupIntel` escribe en `ExtortionQueue`/`RaidQueue` | Escritura | Alto |
| `ExtortionFlow` lee/escribe `BanditGroupMemory` y `FactionHostilityManager` | Lectura/escritura | Alto |
| `RaidFlow` depende de queries inyectadas desde `world.gd` (`find_nearest_player_*`) | Llamada directa | Alto |
| `BanditBehaviorLayer` aplica movimiento de extorsión desde `_physics_process` | Llamada directa | Medio |
| `SaveManager` persiste `ExtortionQueue`, pero no jobs activos de flows | Persistencia parcial | Medio |

### Duplicados funcionales detectados
- Patrón de cola “intent por grupo + consume_for_group + timestamp por grupo” duplicado entre:
  - `scripts/systems/ExtortionQueue.gd`
  - `scripts/systems/RaidQueue.gd`
- Estados de ciclo de vida (approaching/attacking/abort/finish) con estructura similar en:
  - `ExtortionFlow` vs `RaidFlow`.

---

## 5) Loot / drops / pickups

### Implementación actual
- `LootSystem` (`scripts/systems/LootSystem.gd`)
  - Fabrica drops y aplica física inicial/scatter.
- `ItemDrop` (`scripts/items/item_drop.gd`)
  - Entidad runtime pickupable (magnet, throw, scatter, pickup).
  - Registra runtime node en `WorldSpatialIndex`.
- `GameEvents` (`scripts/systems/GameEvents.gd`)
  - Bus de eventos `loot_spawned`, `item_picked`, `entity_died`, etc.
- `EventLogger` (`scripts/debug/EventLogger.gd`)
  - Listener de debug para eventos de loot/pickup.

### Entradas / salidas principales
- Entrada:
  - `LootSystem.spawn_drop(...)` desde sistemas de muerte/rotura.
  - `ItemDrop._process` + `_on_body_entered` + `_try_pickup`.
- Salida:
  - `GameEvents.emit_loot_spawned` y `emit_item_picked`.
  - Escritura a inventario del player (`InventoryComponent.add_item`).

### Dependencias cruzadas
| Dependencia cruzada | Tipo | Riesgo |
|---|---|---|
| `LootSystem` depende de `ItemDB` y `GameEvents` por path `/root/*` | Llamada directa global | Medio |
| `ItemDrop` escribe inventario del player y emite en `GameEvents` | Escritura/evento | Alto |
| `ItemDrop` se indexa en `WorldSpatialIndex` para uso de AI | Escritura de índice | Medio |
| `EventLogger` consume señales de `GameEvents` | Evento debug | Bajo |

### Duplicados funcionales detectados
- Resolución de `item_data`/`item_id` aparece en ambos:
  - `LootSystem.spawn_drop` (resuelve `ItemData` antes de instanciar)
  - `ItemDrop._resolve_item_data` (vuelve a resolver en `_ready`)

---

## 6) Placement / placeables / walls

### Implementación actual
- `PlacementSystem` (`scripts/systems/PlacementSystem.gd`)
  - Modo de colocación, ghost, validación física, spawn de placeables y drag-paint de walls.
- `PlacementCatalog` / `BuildableCatalog` (resolución metadata de placement).
- `PlayerWallSystem` (`scripts/world/PlayerWallSystem.gd`)
  - Colocación/daño/remoción de paredes del jugador.
- `WallPersistence` (`scripts/world/WallPersistence.gd`)
  - Adapter de paredes de jugador -> `WorldSave.player_walls_by_chunk`.
- `StructuralWallPersistence` (`scripts/world/StructuralWallPersistence.gd`)
  - Persistencia de paredes estructurales en `chunk_save[chunk].placed_tiles`.
- `WallRefreshQueue`, `ChunkWallColliderCache`, `WallTileResolver` (runtime de colisión y resolución de impacto).

### Entradas / salidas principales
- Entrada:
  - `PlacementSystem.begin_placement`, `_input`, `_do_place_at_tile`.
  - `world.gd` delega APIs de pared a `PlayerWallSystem`.
- Salida:
  - `PlacementSystem.placement_completed`.
  - `PlayerWallSystem.player_wall_hit`, `player_wall_drop`, `structural_wall_hit/drop`.
  - Escrituras persistentes en `WorldSave` / `chunk_save`.

### Dependencias cruzadas
| Dependencia cruzada | Tipo | Riesgo |
|---|---|---|
| `PlacementSystem` consulta/escribe `WorldSave` y runtime instances | Lectura/escritura | Alto |
| `PlacementSystem` llama validadores externos (ej. `world.gd::_validate_placement_restrictions`) | Callback cruzado | Medio |
| `PlayerWallSystem` usa `WallPersistence` + `StructuralWallPersistence` + callbacks de `world.gd` | Composición + callables | Alto |
| `world.gd` drena `WallRefreshQueue` y dispara `_ensure_chunk_wall_collision` | Llamada directa | Medio |
| `ChunkWallColliderCache` depende de `loaded_chunks` + builder + stage metrics | Lectura/escritura runtime | Medio |

### Duplicados funcionales detectados
- Persistencia de paredes separada en dos adapters con operaciones casi gemelas:
  - `WallPersistence.{save_wall,remove_wall,load_chunk_walls}`
  - `StructuralWallPersistence.{save_wall,remove_wall,load_chunk_walls}`
- Validación de bloqueo de tile para construcción/movimiento aparece en múltiples sitios:
  - `PlacementSystem.can_place_at`
  - `PlayerWallSystem.can_place_player_wall_at_tile`
  - `WorldSpatialIndex.placeable_blocks_movement`

---

## 7) Pathing

### Implementación actual
- `NpcPathService` (`scripts/world/NpcPathService.gd`)
  - Autoload A* por tile + LOS Bresenham + caché por agente.
  - Fuente de blockers: cliffs, walls tilemap, placeables (`WorldSave`/`WorldSpatialIndex`), puertas.
- Consumidores:
  - `AIComponent` (chase) y `NpcWorldBehavior`/`BanditWorldBehavior` (mundo).

### Entradas / salidas principales
- Entrada:
  - `NpcPathService.setup(ctx)` desde `world.gd`.
  - `get_next_waypoint(agent_id, current_pos, goal, opts)`.
  - `has_line_clear(start, goal)`.
- Salida:
  - Waypoint en world-space para steering del NPC.

### Dependencias cruzadas
| Dependencia cruzada | Tipo | Riesgo |
|---|---|---|
| `NpcPathService` lee tilemaps de mundo (`cliffs_tilemap`, `walls_tilemap`) | Lectura directa | Alto |
| `NpcPathService` consulta `WorldSpatialIndex` y `WorldSave` para blockers/placeables | Lectura cruzada | Alto |
| `NpcPathService` usa `RunClock.now()` para repath interval | Lectura común | Medio |

### Duplicados funcionales detectados
- Lógica de “qué placeable bloquea movimiento” duplicada entre:
  - `NpcPathService._placeable_blocks_movement`
  - `WorldSpatialIndex.placeable_blocks_movement`

---

## 8) World save / persistencia

### Implementación actual
- `WorldSave` (`scripts/systems/WorldSave.gd`)
  - Estado canónico en memoria de chunks, entidades, paredes de jugador, placeables y data por uid.
- `SaveManager` (`scripts/systems/SaveManager.gd`)
  - Serialización a disco (`user://savegame.json`) y rehidratación.
  - Persiste también sistemas globales (faction/site/npc_profile/bandit memory/queues/relojes/hostilidad).
- Adapters de dominio:
  - `WallPersistence`, `StructuralWallPersistence`, colas (`ExtortionQueue.serialize/deserialize`).

### Entradas / salidas principales
- Entrada:
  - `SaveManager.save_world()` (manual/autosave/close)
  - `SaveManager.load_world_save()` al boot de `world.gd`.
  - `WorldSave.add/remove/set_*` APIs usadas por sistemas de runtime.
- Salida:
  - Archivo JSON versionado con snapshot completo.
  - Estado pendiente de player (`_pending_player_pos`, inventario, oro).

### Dependencias cruzadas
| Dependencia cruzada | Tipo | Riesgo |
|---|---|---|
| `world.gd` llama `SaveManager.register_world/load_world_save` y `_perform_world_save` | Llamada directa | Alto |
| `SaveManager` serializa datos de múltiples autoloads (`WorldSave`, `BanditGroupMemory`, `FactionHostilityManager`, etc.) | Escritura agregada | Alto |
| `entity_coordinator.snapshot_entities_to_world_save()` se ejecuta previo a guardar | Llamada directa | Medio |
| `WorldSave.wall_tile_blocker_fn` se inyecta desde `world.gd` | Callback cruzado | Medio |

### Duplicados funcionales detectados
- Persistencia de estado por sistema distribuida (cada sistema serializa su propio formato), más snapshot global de `SaveManager`; no hay contrato unificado de versionado por subdominio.

---

## 9) Telemetry / debug

### Implementación actual
- `WorldSimTelemetry` (`scripts/world/WorldSimTelemetry.gd`)
  - Snapshot periódico de cadence, LOD bandits, settlement, spatial index y mantenimiento world.
- `Debug` (`scripts/systems/Debug.gd`) como logger categorizado (consumido transversalmente).
- `GameEvents` (`scripts/systems/GameEvents.gd`) + `EventLogger` (`scripts/debug/EventLogger.gd`).

### Entradas / salidas principales
- Entrada:
  - `world.gd::_process` llama `_world_sim_telemetry.tick(delta)`.
  - `EventLogger._ready` conecta señales de `GameEvents`.
- Salida:
  - `Debug.log(...)` consolidado.
  - Snapshots: `get_debug_snapshot`, `dump_debug_summary`, `build_overlay_lines`.
  - Prints de eventos de gameplay.

### Dependencias cruzadas
| Dependencia cruzada | Tipo | Riesgo |
|---|---|---|
| `WorldSimTelemetry` consume objetos internos (`BanditBehaviorLayer`, `SettlementIntel`, `WorldSpatialIndex`, `ChunkPerfMonitor`) | Lectura multi-sistema | Medio |
| `EventLogger` depende de señales de `GameEvents` | Evento | Bajo |
| Gran parte del código escribe directamente a `Debug.log` | Acoplamiento transversal | Medio |

### Duplicados funcionales detectados
- Instrumentación en dos canales paralelos:
  - Canal estructurado/snapshot: `WorldSimTelemetry`
  - Canal event-driven textual: `GameEvents` + `EventLogger`
- Además, múltiples `print(...)` directos en scripts de runtime (`ItemDrop`, etc.) fuera de ambos canales.

---

## Resumen de duplicados funcionales clave (prioridad sugerida)
1. **Relojes paralelos (`WorldTime` vs `RunClock`)** — aclarar contrato por dominio.
2. **Colas paralelas (`ExtortionQueue` vs `RaidQueue`)** — posible base común de queue semantics.
3. **Bloqueo de movimiento/colocación en 3+ sitios** (`NpcPathService`, `WorldSpatialIndex`, `PlacementSystem`/`PlayerWallSystem`).
4. **Persistencia de muros en adapters separados** (`WallPersistence` / `StructuralWallPersistence`) con operaciones espejo.
5. **Territorio bandido con doble implementación de consulta** (`groups_at` / `is_in_territory`).
