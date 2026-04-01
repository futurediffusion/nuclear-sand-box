# Phase 4 — Inventario de autoloads/singletons actuales

Fecha de corte: 2026-04-01.
Fuente base de autoloads: sección `[autoload]` de `project.godot`.

## Criterios usados

- **Propósito declarado:** lo que expresa el nombre del sistema, su uso dominante y/o documentación existente.
- **Quién lo usa:** consumidores principales (no exhaustivo por línea, sí por subsistema).
- **Estado expuesto:** variables globales/colecciones/contadores consultables o mutables desde otros nodos.
- **Side effects:** señales, mutaciones globales, encolado de trabajo, IO, spawn/despawn, etc.
- **Clasificación:**
  - `Infra global necesaria`
  - `Servicio compartido`
  - `Comodidad peligrosa`
- **Riesgo (1-10):** priorización de migración (10 = más urgente).
- **ALTO RIESGO:** cuando el autoload mezcla **lectura + decisión + ejecución** de gameplay en la misma pieza.

## Inventario

| Autoload | Propósito declarado | Quién lo usa (principal) | Estado expuesto | Side effects | Clasificación | Riesgo | ALTO RIESGO |
|---|---|---|---|---|---|---:|---|
| `CameraFX` | FX de cámara (shake/impact). | `player`, `enemy`, `VFXComponent`, `sentinel`. | Referencia de cámara activa. | Ejecuta shake/efectos visuales globales. | Servicio compartido | 4 | No |
| `AggroTrackerService` | Registro global de engagements/agro. | `CharacterBase`, `AIComponent`, `DownedEncounterCoordinator`. | Diccionario de engagements target/enemy. | Actualiza y limpia engagement global. | Servicio compartido | 6 | No |
| `DownedEncounterCoordinator` | Resolver encuentros con objetivos derribados. | `CharacterBase`, `AIComponent`, `ContainerPlaceable`. | Config de chances/temporizadores y estado de encounters. | Decide outcome y ordena acciones (finish/spare/ignore). | **Comodidad peligrosa** | **9** | **Sí** |
| `ShopService` | Compra/venta y validación económica básica. | `keeper_menu_ui`, `inventory_panel`. | Ratios de venta, flags de debug. | Mutación de inventario/oro y transacciones. | Servicio compartido | 7 | No |
| `Seed` | Semilla de corrida procedural. | `world`, `ChunkPipeline`, `NpcSimulator`, `SaveManager`, `GameManager`. | `run_seed`, debug seed. | Inicializa/mezcla seed de sesión. | Infra global necesaria | 5 | No |
| `SaveManager` | Orquestar guardar/cargar estado global. | `world`, `player`, tests de persistencia. | Estado pendiente de save/load y punteros de contexto. | Serializa/deserializa runtime world/player/sistemas. | Infra global necesaria | 8 | No |
| `GameManager` | Director de sesión (fase, métricas, threat). | `main`, `player`, `enemy`, `hud`. | Fase de sesión, contadores y threat level. | Emite señales globales y avanza threat por tiempo/kills. | Servicio compartido | 6 | No |
| `ItemDB` | Catálogo global de items. | Inventario, loot, placement, audio, comandos, UI. | Diccionario global `items`, lista de `ItemData`. | Carga índice de items y responde lookups globales. | Infra global necesaria | 5 | No |
| `CraftingDB` | Catálogo global de recetas. | `CraftingRecipe`, `workbench_menu_ui`. | Índice global de recetas por id. | Carga recetas al boot. | Infra global necesaria | 4 | No |
| `PlacementSystem` | Modo de colocación/construcción del player. | `world`, placeables, `SaveManager`, UI, tests. | Estado vivo de ghost, item activo, flags de colocación. | Captura input, decide validez y ejecuta placement/spawn/paint. | **Comodidad peligrosa** | **10** | **Sí** |
| `LootSystem` | Spawn y reglas de drops. | Recursos, `player`, `CampStash`, `WallFeedback`, downed. | Reglas de drop/override runtime. | Spawnea drops, dispersa, integra eventos/inventario. | **Comodidad peligrosa** | **9** | **Sí** |
| `GameEvents` | Event bus global de gameplay. | Recursos, loot, `enemy`, `SettlementIntel`, telemetría/debug. | Señales globales de dominio. | Broadcast de eventos cross-sistema. | Infra global necesaria | 7 | No |
| `AudioSystem` | Reproducción/lookup central de SFX. | combate, recursos, UI, world, enemigos, armas. | Referencias de sound panel, toggles debug. | Reproduce audio global y enruta buses. | Servicio compartido | 5 | No |
| `Debug` | Flags y utilidades de depuración runtime. | Uso masivo transversal (`world`, AI, player, systems). | Flags globales (cheats, ghost mode, toggles). | Puede alterar comportamiento real de gameplay. | **Comodidad peligrosa** | **8** | No |
| `EnemyRegistry` | Índice global de enemigos vivos por weakref/chunk. | `enemy`, `NpcSimulator`, downed systems. | Buckets de enemigos e índices auxiliares. | Registro/unregister y mantenimiento periódico. | Servicio compartido | 6 | No |
| `AwakeRampQueue` | Escalonar primer tick completo de IA. | `AIComponent`. | Cola de ids y frames programados. | Drena cola por frame y difiere activación. | Servicio compartido | 6 | No |
| `WorldSave` | Fuente de verdad de persistencia in-session. | `world`, placeables, resources, save/command/tests (muy transversal). | Diccionarios globales de chunks, entidades, walls, flags, revisiones. | Escritura/lectura masiva del estado persistido. | Infra global necesaria | 8 | No |
| `UiManager` | Estado global de UI modal/cursores/bloqueos. | `player`, `main`, `PlacementSystem`, combate/UI/armas. | Razones de apertura, locks de interacción/combat. | Bloquea/permite input e interacción global. | Servicio compartido | 6 | No |
| `ModalWorldUIController` | Coordinación de modales world-space. | `ExtortionUIAdapter`, tests E2E. | Modal activo, reason, depth de pausa. | Pausa/reanuda estado de UI modal centralizado. | Servicio compartido | 4 | No |
| `PartyControlManager` | Transferir control entre actores. | `main`. | Actor controlado actual. | Cambia ownership de input/cámara. | Servicio compartido | 5 | No |
| `FactionSystem` | Registro base de facciones y miembros/sitios. | `NpcProfileSystem`, `SiteSystem`, `SaveManager`, `world`. | Diccionario global de facciones. | Alta/baja/actualización de datos de facción. | Servicio compartido | 6 | No |
| `SiteSystem` | Registro de sitios/POI por facción. | `EntitySpawnCoordinator`, `FactionViabilitySystem`, `SaveManager`. | Diccionario global de sitios. | Mutación de metadatos de sitio y snapshots. | Servicio compartido | 6 | No |
| `NpcProfileSystem` | Perfiles globales de NPC (facción/grupo/rol). | `enemy`, simulación, group intel, save, viability. | Diccionario global de perfiles. | Registro/actualización de perfil NPC. | Servicio compartido | 7 | No |
| `BanditGroupMemory` | Memoria social/táctica por grupo bandido. | world bandit stack, command, viability, save. | Estado de intención, miembros, cooldowns, claims, locks. | Mutaciones frecuentes de intent/cooldowns/targets. | **Comodidad peligrosa** | **9** | **Sí** |
| `FactionViabilitySystem` | Evaluar viabilidad operativa de facciones/grupos. | `NpcSimulator`, `CampfireComponent`. | Rebuild pending + estado derivado de viabilidad. | Corre evaluación periódica y cambia estado de grupo. | **Comodidad peligrosa** | **8** | **Sí** |
| `ExtortionQueue` | Cola de intents de extorsión. | `BanditGroupIntel`, `ExtortionFlow`, `BanditExtortionDirector`, `SaveManager`. | Intents pendientes + timestamps por grupo. | Enqueue/consume con cooldown anti-spam. | Servicio compartido | 7 | No |
| `RaidQueue` | Cola de intents de incursión/raid. | `BanditGroupIntel`, `RaidFlow`, `world`. | Intents pending + timestamps de raid/probe. | Enqueue/consume de raids. | Servicio compartido | 7 | No |
| `RunClock` | Reloj monotónico de runtime para cooldowns. | Uso muy transversal (AI, extorsión, raids, save, world). | `time_seconds`. | Avanza tiempo global y emite tick temporal implícito. | Infra global necesaria | 7 | No |
| `WorldTime` | Calendario de mundo (día/progreso). | Hostilidad, incidentes civiles, save. | Día actual y elapsed acumulado. | `_process` + señal de cambio de día. | Infra global necesaria | 6 | No |
| `FactionHostilityManager` | Fuente de verdad de hostilidad inter-facción. | AI/enemy/projectiles, políticas territoriales, downed, save, world systems. | Puntos, nivel, heat y perfiles por facción. | Aplica hostilidad, dedup, decay, señales y perfiles. | **Comodidad peligrosa** | **9** | **Sí** |
| `NpcPathService` | Servicio global de pathfinding/query navegable. | `AIComponent`, `sentinel`, `NpcWorldBehavior`, `BanditBehaviorLayer`, `world`. | Cache/mapa navegable, callbacks de conversión, readiness. | Calcula rutas y limpia/agrega agentes. | Servicio compartido | 7 | No |

## Priorización de migración (top sugerido)

1. **`PlacementSystem` (10)** — concentra input, validación, decisión y ejecución de placement/gameplay.
2. **`LootSystem` (9)** — resuelve reglas y ejecuta spawn/entrega de drops en runtime.
3. **`DownedEncounterCoordinator` (9)** — decide outcomes de encounter y ejecuta consecuencias.
4. **`BanditGroupMemory` (9)** — estado social central mutado por múltiples sistemas de decisión.
5. **`FactionHostilityManager` (9)** — lectura+decisión+mutación cross-domain de hostilidad.
6. **`FactionViabilitySystem` (8)** — evaluación periódica que impacta comportamiento global.

## Notas de riesgo

- Los autoloads marcados **ALTO RIESGO** son candidatos a separar en patrón **Read Model + Decision Service + Command/Executor**.
- `Debug` no quedó marcado como ALTO RIESGO por criterio estricto de tríada, pero su superficie global y flags de gameplay lo vuelven candidato temprano de encapsulación.
