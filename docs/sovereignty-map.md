# Mapa de soberanía de sistemas

Fuente base: `docs/system-inventory.md` (9 dominios críticos).

## Tabla de soberanía

| Sistema | Dueño real de la verdad | Qué puede decidir | Qué no puede decidir | De quién puede leer | A quién puede emitir eventos | Qué side effects le están prohibidos |
|---|---|---|---|---|---|---|
| Tiempo del mundo | `WorldTime` (`scripts/systems/WorldTime.gd`) | Día actual, avance intra-día y emisión de `day_passed` | Cooldowns de runtime monotónico (`RunClock`), scheduling de lanes (`WorldCadenceCoordinator`) | `RunClock` y `WorldCadenceCoordinator` (solo consulta para coordinación) | `FactionHostilityManager` (vía `day_passed`) | Mutar hostilidad de facciones, encolar raids/extorsión, escribir inventarios |
| Bandit AI | `BanditGroupMemory` (estado grupal canónico consumido por `BanditBehaviorLayer`) | Intent actual por grupo, prioridades tácticas, dispatch a objetivos, transición de estados de behavior | Nivel de hostilidad global de facción, reglas de placement territorial, persistencia global de mundo | `SettlementIntel`, `WorldSpatialIndex`, `NpcSimulator`, `RunClock`, colas (`ExtortionQueue`/`RaidQueue`) | `ExtortionQueue`, `RaidQueue`, `dispatch_group_to_target` | Escribir directamente `FactionHostilityManager` sin pasar por flujos/políticas, mutar `WorldSave` estructural |
| Territorialidad / hostilidad | `FactionHostilityManager` (`scripts/systems/FactionHostilityManager.gd`) | Puntos, nivel, decay y perfil de comportamiento de hostilidad por facción | Movimiento individual de NPCs, pathfinding, resolución de pickups/loot | `WorldTime` (day tick), `BanditTerritoryQuery`, `PlayerTerritoryMap`, `BanditGroupMemory` | Señales `hostility_changed` / `level_changed` a consumidores de mundo | Spawn/despawn de entidades, mutación de inventario/gold, escritura de colas de raids sin política |
| Coerción bandida (extorsión e incursión) | `ExtortionFlow` y `RaidFlow` (cada flujo es dueño de su job activo) | Ciclo de vida de encounter/job activo, resolución de choice, abort/finish y efectos derivados | Hostilidad canónica base (solo solicitar cambios), ownership territorial de placement, reloj global | `ExtortionQueue`, `RaidQueue`, `BanditGroupMemory`, `FactionHostilityManager`, `RunClock` | `BanditBehaviorLayer` (dispatch), `FactionHostilityManager` (solicitud de cambios), UI adapter (`choice_resolved`) | Alterar directamente sistema de placement, persistir estado fuera de sus colas/flows, editar reglas de pathing |
| Botín e inventario | `ItemDrop` (estado canónico del drop runtime) | Pickup, magnet, scatter/throw y momento de consumo del drop | Política económica global (precios), reglas de hostilidad territorial, estado canónico de inventario del player | `ItemDB`, `InventoryComponent` del player, `WorldSpatialIndex`, `GameEvents` | `GameEvents.emit_loot_spawned`, `GameEvents.emit_item_picked` | Escribir hostilidad de facción, encolar raids/extorsión, modificar estructuras de paredes |
| Construcción y estructuras | `PlacementSystem` (intención y validez de colocación) | Validez de placement, spawn de placeables, drag-paint de walls, completar acción de construcción | Política de hostilidad global, prioridades tácticas de bandits, reloj del mundo | `PlacementCatalog`, `BuildableCatalog`, `WorldSave`, validadores externos (`WorldTerritoryPolicy`) | `placement_completed`, callbacks a `PlayerWallSystem`/`world.gd` | Cambiar niveles de facción directamente, manipular colas de raids/extorsión, alterar path service global |
| Pathing | `NpcPathService` (grafo/caché y veredicto de ruta) | Cálculo de ruta A*, LOS y bloqueos navegables efectivos | Política de combate, intención de raid/extorsión, persistencia de hostilidad | `WorldSave`, `WorldSpatialIndex`, tile blockers (cliffs/walls/doors) | Consumidores de AI (`AIComponent`, `NpcWorldBehavior`, `BanditWorldBehavior`) | Escribir inventario/oro, modificar `FactionHostilityManager`, spawnear entidades |
| World save / persistencia | `SaveManager` + `WorldSave` (estado persistido canónico) | Serialización/deserialización de estado de sesión y mundo por dominios registrados | Reglas de gameplay en runtime, decisiones tácticas de AI, validación de placement en frame | Todos los dominios registrados (`run_clock`, `world_time`, colas, walls, entidades, etc.) | Capa de carga/arranque (`world.gd`, sistemas registrados) | Decidir outcomes de combate/AI, emitir hostilidad como regla de negocio, resolver pickups en vivo |
| Telemetry / debug | `EventLogger` (verdad canónica solo de observabilidad, no gameplay) | Qué se registra, formato de log y trazabilidad de eventos | Cualquier estado de gameplay canónico (inventario, hostilidad, placement, pathing) | `GameEvents` y señales de subsistemas | Consola/debug sinks | Mutar estado de juego, escribir persistencia, disparar decisiones de AI |

## Validación de owner único por fila

- Tiempo del mundo: owner único validado (`WorldTime`).
- Bandit AI: owner único validado (`BanditGroupMemory`).
- Territorialidad / hostilidad: owner único validado (`FactionHostilityManager`).
- Coerción bandida (extorsión e incursión): **CONFLICTO** — en la práctica hay dos owners paralelos de jobs activos (`ExtortionFlow` y `RaidFlow`), separados por dominio de flujo pero sin un agregador único de encounters.
- Botín e inventario: **CONFLICTO** — `ItemDrop` decide pickup runtime, pero el estado final de items vive en `InventoryComponent`; existe frontera de autoridad compartida en la transición pickup→inventario.
- Construcción y estructuras: **CONFLICTO** — `PlacementSystem` decide colocación, mientras `PlayerWallSystem`/`WallPersistence`/`StructuralWallPersistence` consolidan estado de paredes, generando autoridad fragmentada en walls.
- Pathing: owner único validado (`NpcPathService`).
- World save / persistencia: owner único validado (`SaveManager` + `WorldSave` como única autoridad persistente).
- Telemetry / debug: owner único validado (`EventLogger` para observabilidad).

## Priorización de conflictos (riesgo)

Escala usada: **Crítico** (impacta economía/combate y puede corromper progresión), **Alto** (puede desincronizar estado canónico entre subsistemas), **Medio** (deuda de autoridad con impacto acotado).

1. **Coerción bandida (extorsión e incursión) — CRÍTICO**  
   Dos dueños efectivos para encounters activos (`ExtortionFlow` y `RaidFlow`) pueden generar resolución duplicada, degradación de hostilidad incongruente y outcomes no deterministas bajo concurrencia de colas.
2. **Botín e inventario — ALTO**  
   La frontera `ItemDrop` (runtime) → `InventoryComponent` (estado final) permite escrituras cruzadas fuera de un contrato único, con riesgo de duplicación/perdida de ítems.
3. **Construcción y estructuras — ALTO**  
   `PlacementSystem` valida/crea, pero `PlayerWallSystem` + persistencias de walls consolidan parcialmente el estado; esto abre mutaciones estructurales laterales que pueden romper pathing y guardado.

## Decisiones de soberanía adoptadas

- **Fecha:** 2026-04-01.
- **Responsable técnico:** GPT-5.3-Codex (agente técnico).
- **Decisiones:**
  1. Se definió un owner canónico por cada uno de los 9 dominios del inventario.
  2. Se etiquetaron como **CONFLICTO** los dominios con autoridad fragmentada en runtime/persistencia.
  3. Se explicitó para cada dominio el perímetro de lectura, emisión de eventos y side effects prohibidos para evitar acoplamiento de autoridad.
  4. Se priorizaron conflictos por riesgo operacional y de corrupción de estado.

## Resolución de conflictos y flujo autorizado

### 1) Coerción bandida (extorsión e incursión) (riesgo CRÍTICO)

- **Estado afectado:** lifecycle de encounter activo (creación, transición, resolución y cierre), impacto derivado en hostilidad.
- **Writer antiguo eliminado:** escrituras laterales directas entre `ExtortionFlow` y `RaidFlow` sobre jobs/estados activos de encounter.
- **Owner único oficial:** `EncounterFlowCoordinator` (nuevo owner de job activo inter-flujo).
- **Nuevo flujo autorizado (contrato explícito):**
  - `BanditGroupMemory`/colas emiten **comandos** `enqueue_extortion` o `enqueue_raid`.
  - `EncounterFlowCoordinator` decide activación y delega ejecución a `ExtortionFlow` o `RaidFlow`.
  - Los flows devuelven **eventos** `encounter_step_changed` / `encounter_resolved`.
  - Solo `EncounterFlowCoordinator` emite comando oficial de ajuste a `FactionHostilityManager`.
- **Guardas defensivas:**
  - `ExtortionFlow` y `RaidFlow` rechazan (`assert`/early return + log) cualquier intento de mutar job activo fuera del `coordinator_token`.
  - `FactionHostilityManager` ignora solicitudes no firmadas como `source=EncounterFlowCoordinator`.

### 2) Botín e inventario (riesgo ALTO)

- **Estado afectado:** transición de ownership de item (drop en mundo → inventario persistente del jugador).
- **Writer antiguo eliminado:** inserción directa de ítems en `InventoryComponent` desde nodos `ItemDrop` sin comando de dominio.
- **Owner único oficial:** `InventoryComponent` (owner final de estado de inventario).
- **Nuevo flujo autorizado (contrato explícito):**
  - `ItemDrop` emite **evento** `pickup_requested(drop_id, item_id, qty, actor_id)`.
  - `InventoryPickupService` traduce el evento a **comando** `add_item_if_valid` dirigido a `InventoryComponent`.
  - `InventoryComponent` confirma con **evento** `item_pickup_committed` y recién entonces `ItemDrop` se consume/despawn.
- **Guardas defensivas:**
  - `ItemDrop` no puede ejecutar `inventory.add_*` directo (bloqueado por interfaz restringida).
  - `InventoryComponent` valida idempotencia por `drop_id` (si ya fue aplicado, rechaza segunda mutación).

### 3) Construcción y estructuras (riesgo ALTO)

- **Estado afectado:** estado estructural de walls/placeables y su persistencia consistente con pathing.
- **Writer antiguo eliminado:** mutaciones directas de walls desde `PlayerWallSystem`, `WallPersistence` o `StructuralWallPersistence` fuera del circuito de placement.
- **Owner único oficial:** `PlacementSystem` (owner de intención + commit estructural).
- **Nuevo flujo autorizado (contrato explícito):**
  - Actores (UI/herramientas/sistemas) emiten **comando** `request_structure_change`.
  - `PlacementSystem` valida reglas (`WorldTerritoryPolicy`, colisiones, path blockers) y ejecuta commit.
  - `PlacementSystem` emite **evento** `structure_changed` para que persistencias sincronicen snapshot.
  - Persistencia queda en modo subscriber-only: serializa lo emitido, no decide mutaciones.
- **Guardas defensivas:**
  - `PlayerWallSystem` y capas de persistencia marcan APIs de escritura como internas del `PlacementSystem`.
  - Rechazo explícito de cambios estructurales cuando `origin != PlacementSystem` (log de violación de soberanía).
