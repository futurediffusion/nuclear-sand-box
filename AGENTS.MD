# AGENTS.MD — NUCLEAR SAND BOX (Godot 4.x)

## 1️⃣ VISIÓN DEL PROYECTO

**NUCLEAR SAND BOX** ya no es un prototipo simple de combate.

Ahora es un **sandbox procedural 2D top-down** con:

- Mundo generado por chunks.
- Biomas (arena, pasto, piedra).
- Recursos minables (cobre).
- Campamentos de bandidos.
- Economía básica (oro + inventario).
- Sistema de stamina + bloqueo direccional.
- Componentes reutilizables (Health, Stamina, Inventory).
- Persistencia de entidades por chunk.
- Arquitectura preparada para escalar a facciones y control territorial.

Objetivo de evolución:

- Recursos que generen conflicto.
- NPCs que disputen territorio.
- Mundo persistente y coherente.

---

## 2️⃣ ARQUITECTURA GENERAL

### Escena principal

`scenes/main.tscn`

Contiene:

- `Player`
- `World` (TileMap + chunk system)
- `UI` (HUD + GameOverPanel)
- Sistemas globales conectados a `GameManager`

---

## 3️⃣ SISTEMAS PRINCIPALES

### 🌍 WORLD SYSTEM (Chunk-Based)

Script orquestador: `scripts/world/world.gd`

`world.gd` **no ejecuta la pipeline directamente** — delega a subsistemas mediante inyección de dependencias (`setup(ctx: Dictionary)`).

#### Subsistemas

| Subsistema | Tipo | Archivo | Responsabilidad |
|---|---|---|---|
| `ChunkPipeline` | Node | `scripts/world/ChunkPipeline.gd` | `generate_chunk`, persistent tiles, terrain-paint scheduler, stage queues (tiles/colliders), prefetch completo, ground mapping |
| `EntitySpawnCoordinator` | Node | `scripts/world/EntitySpawnCoordinator.gd` | Spawn jobs via `SpawnBudgetQueue`, ciclo de vida de entidades por chunk |
| `NpcSimulator` | Node | `scripts/world/NpcSimulator.gd` | Tracking de enemigos activos, lite-mode (AI on/off por distancia), simulación data-only |
| `ChunkPerfMonitor` | RefCounted | `scripts/world/ChunkPerfMonitor.gd` | Timings por stage, percentiles, auto-calibración de budgets |
| `ChunkWallColliderCache` | RefCounted | `scripts/world/ChunkWallColliderCache.gd` | Caché de colliders de walls por chunk (dirty/hash/reuse/eviction) |
| `WallRefreshQueue` | RefCounted | `scripts/world/WallRefreshQueue.gd` | Cola deduplicada de chunks para refresh diferido de colliders de walls (budget en `_process`) |
| `ChunkGenerator` | RefCounted | `scripts/world/chunk_generator.gd` | Datos procedurales de tiles via `FastNoiseLite`; `apply_ground_terrain_ctx` |
| `GroundPainter` | RefCounted | — | Terreno de GroundTileMap (dirt/grass) |
| `CollisionBuilder` | RefCounted | — | `StaticBody2D` de muros por chunk, caché por hash |
| `PropSpawner` | RefCounted | — | Ores, props, campamentos |

#### Ciclo de vida de un chunk

```
update_chunks()
  → pipeline.generate_chunk()        # prop spawns + perf record
  → entity_coordinator.load_chunk()  # restaurar estado desde WorldSave
  → chunk_generator.apply_ground_terrain_ctx()  # GroundTileMap batch
  → pipeline.enqueue_terrain_paint() # WorldTileMap persistent tiles (progresivo)
  → [pipeline stage queues]:
      tiles → colliders → entity_coordinator.enqueue_entities()
```

Al descargar: `unload_chunk()` + `entity_coordinator.unload_entities()` + `pipeline.on_chunk_unloaded()`

#### Biomas

`get_spawn_biome(x, y)` en `world.gd` mapea terreno de `GroundPainter` a IDs de bioma (`BIOME_ID_GRASSLAND=1`, `BIOME_ID_DENSE_GRASS=2`) que usa `PropSpawner` para densidad de ores.

`world.gd` tambien expone `get_walk_surface_at_world_pos(world_pos)` para clasificar superficie jugable (`grass`, `dirt`, `wood`) sin acoplar deteccion de tiles al player.

⚠️ **Reglas importantes:**

- Un chunk no debe regenerar entidades si ya fue generado (`entities_spawned_chunks`).
- El estado se conserva en memoria durante la sesión via `WorldSave` (autoload).
- UIDs de entidades son deterministas: `UID.make_uid(prefix, site_id, tile_pos)`.

### ⛏️ RECURSOS (Cobre)

Escena:

- `scenes/copper_ore.tscn`

Script:

- `scripts/resources/copper_ore.gd`

Funcionalidad:

- Tiene cantidad restante.
- Puede reproducir sonido de minado.
- Se integra con `InventoryComponent` del player.
- Futuro: ownership/control territorial.

### 🏕️ CAMPAMENTOS DE BANDIDOS

Escena:

- `scenes/bandit_camp.tscn`

Script:

- `scripts/world/bandit_camp.gd`

Rol:

- Punto de spawn controlado.
- Puede generar múltiples enemigos.
- Algunos aparecen cerca de cobre (custodia).
- Otros aparecen aleatoriamente.

Futuro:

- Centro de control territorial.
- Radio de influencia.
- Producción de patrullas.

### 🧍 PLAYER

Script:

- `scripts/gameplay/player.gd`

Componentes usados:

- `HealthComponent`
- `StaminaComponent`
- `InventoryComponent`
- `FootstepAudioComponent`

Sistemas activos:

- Movimiento con aceleración/fricción.
- Ataque melee con Slash.
- Bloqueo direccional con cono frontal.
- Consumo de stamina.
- Knockback.
- Emisión de señales para HUD.
- Integración con `GameManager` para muerte.

### 🧠 COMPONENTES REUTILIZABLES

Ubicación:

- `scripts/components/`

`HealthComponent`

- `max_hp`
- `hp`
- `armor`
- señales: `damaged`, `died`

`StaminaComponent`

- `max_stamina`
- `regen`
- `attack_cost`
- señal `stamina_changed`

`InventoryComponent`

- `gold`
- `items` (`Dictionary`)
- `add_item / remove_item`
- `sell / buy`
- `debug_print()`

`FootstepAudioComponent`

- Loop de pasos por superficie (`grass`, `dirt`, `wood`).
- Inicia/detiene segun velocidad real del personaje.
- Resuelve SFX y volumen desde `SoundPanel` para escalar a nuevos materiales.
- Consume superficie via `World.get_walk_surface_at_world_pos()`.

⚠️ **Regla:**

- La lógica reusable va en componentes.
- No duplicar sistemas dentro de `Player` o `Enemy`.

### 📦 CONTAINER PLACEABLES (Chest/Barrel)

Ubicación:

- `scripts/placeables/ContainerPlaceable.gd`
- Compat legacy: `scripts/placeables/ChestComponent.gd` (`ChestWorld` wrapper)
- `scripts/ui/ContainerUi.gd`
- Compat legacy: `scripts/ui/chest_ui.gd` (`ChestUi` wrapper)

Rol:

- Capa neutral para contenedores placeables reutilizable por chest/barrel y futuros `crate/locker/freezer`.
- Mantiene persistencia actual por `placed_uid` en `WorldSave.placed_entity_data_by_uid`.
- Expone config por datos/export: `max_slots`, `max_stack`, `drop_item_id`, `container_group`.
- Incluye placeholders no invasivos para fase futura: `locked`, `loot_profile`, `break_behavior`.
- Conserva compatibilidad total con lookup legacy (`UI/ChestUi`, grupo `chest_ui`) y añade alias neutral (`UI/ContainerUi`, grupo `container_ui`).

### 🪑 STOOL PLACEABLE (Sit Toggle)

Ubicación:

- `scenes/placeables/stool_world.tscn`
- `scripts/placeables/StoolComponent.gd`
- `data/items/stool.tres`

Rol:

- Placeable interactuable con prompt `E`.
- Toggle de sentarse/pararse del player.
- Al sentarse, el player salta al punto de asiento del stool, usa sprite `playersit` y bloquea movimiento/combate.
- Al volver a interactuar, retorna a la posición previa y recupera `idle/walk`.
- Mantiene persistencia por `placed_uid` (daño/rotura) con drop del item `stool`.

### 🧩 PLACEMENT METADATA (ItemData-Driven)

Ubicación:

- `scripts/items/ItemData.gd`
- `scripts/items/ItemDB.gd`
- `scripts/systems/PlacementCatalog.gd`

Rol:

- Placement incremental basado en metadata de item con fallback legacy seguro.
- Campos nuevos en `ItemData`: `placement_mode`, `placement_scene_path`, `repeat_place`, `drag_paintable`, `can_share_tile_with`, `ignore_collision_groups_when_placing`.
- `PlacementCatalog` mantiene API legacy (`resolve_scene_path`, `resolve_placement_mode`, `is_repeat_scene_item`, `can_share_tile`) pero ahora resuelve primero perfil de item y cae a tablas legacy cuando no hay metadata explícita.
- `PlacementSystem` consume reglas de catálogo para drag paint y excepciones físicas sin hardcodear `floorwood`.

### 👥 ENEMY REGISTRY (Autoload)

Ubicación:

- `scripts/systems/EnemyRegistry.gd`

Rol:

- Registro central de enemigos vivos usando `WeakRef`.
- Evita referencias stale/freed en lógica de separación.
- API: `register_enemy`, `unregister_enemy`, `get_live_enemies`, `count`.

### 🧱 COLLISION LAYERS (Canónico)

Ubicación:

- `scripts/systems/CollisionLayers.gd`

Rol:

- Fuente única de capas/máscaras de colisión para muros/props runtime.
- Evita números mágicos duplicados entre `CharacterBase`, `Player` y `CollisionBuilder`.
- Permite que la política personaje-vs-mundo se aplique de forma consistente en todos los derivados.

### 🫨 TILE HIT FEEDBACK (Utility)

Ubicación:

- `scripts/systems/TileHitFeedback.gd`

Rol:

- Helper reutilizable para feedback de golpe en tiles (`shake` + `flash`) usando `Sprite2D` temporal.
- Consume `source_id`, `atlas_coords` y `alternative_tile` del tile golpeado para reflejar el look actual.
- Diseñado para uso en `world.gd` (pared `wallwood`) y para extenderse luego a otros tiles golpeables.

### 🔥 WARMUP MANAGER

Ubicación:

- `scripts/systems/WarmupManager.gd`

Rol:

- Precarga recursos/escenas críticas al boot.
- Instancia y libera una vez escenas clave fuera de pantalla para evitar hitch de “primera vez”.
- Mantiene un mínimo de ventana de warm-up para ocultar picos iniciales del renderer.

### 🧱 BUILDING TILEMAP PROJECTION

Ubicación:

- `scripts/projections/tilemap/BuildingTilemapProjection.gd`

Rol:

- Proyección dedicada para pintar visuales de walls/structures en `StructureWallsMap` a partir de eventos de dominio o snapshots de estado.
- Mantiene `terrain_connect` y limpieza de tiles huérfanos sin convertir el TileMap en fuente de verdad.
- Pensado para rebuild seguro desde estado persistido (`apply_snapshot`) y actualización incremental por eventos (`apply_events`).

### 🗺️ TERRITORY PROJECTION

Ubicación:

- `scripts/projections/territory/TerritoryProjection.gd`
- Compat legacy: `scripts/world/PlayerTerritoryMap.gd` (wrapper)

Rol:

- Proyección/read-model explícita para queries de territorio del jugador (workbench + bases cerradas detectadas).
- Deriva estado runtime desde inputs canónicos (`WorldSpatialIndex`/grupo `workbench` y snapshots de `SettlementIntel`), sin ser fuente de verdad.
- Rebuild seguro mediante `rebuild_from_sources(...)` para invalidación y recomposición determinista.

### 🧱 WALL COLLIDER PROJECTION

Ubicación:

- `scripts/projections/collision/WallColliderProjection.gd`
- Compat legacy: `scripts/projections/collider/BuildingColliderRefreshProjection.gd` (wrapper)

Rol:

- Proyección física explícita que deriva dirty/rebuild de colliders desde eventos/snapshots del estado de building, sin convertir colliders en fuente de verdad.
- Centraliza el scope de tiles de pared que deben gatillar refresh y permite rebuild desde estado (`apply_snapshot` / `rebuild_from_state`).
- Se integra con `WorldProjectionRefreshContract` y, como fallback, con `WorldChunkDirtyNotifierContract` + `WallRefreshQueue`.

### 🧱 WALL PERSISTENCE (Adapter)

Ubicación:

- `scripts/world/WallPersistence.gd`

Rol:

- Adaptador único entre `PlayerWallSystem` y `WorldSave` para walls del player.
- Expone API por caso de uso (`save_wall`, `remove_wall`, `load_chunk_walls`, `list_player_walls`).
- Centraliza serialización/deserialización de `wall_data` sin cambiar el schema actual (`{"hp": int}`).

### WALL REFRESH QUEUE (World Runtime)

Ubicacion:

- `scripts/world/WallRefreshQueue.gd`

Rol:

- Recibe chunks de walls marcados dirty desde `world.gd` sin rebuild inmediato.
- Deduplica por chunk y drena la cola desde `_process`.
- Budget fijo inicial: 1 rebuild de collider por frame para suavizar tirones de picos.

### 🔌 WORLD TRANSITION PORTS (Phase 1)

Ubicación:

- `scripts/world/contracts/WorldCoordinateTransformContract.gd`
- `scripts/world/contracts/WorldChunkDirtyNotifierContract.gd`
- `scripts/world/contracts/WorldProjectionRefreshContract.gd`
- Adaptadores legacy:
  - `WorldCoordinateTransformCallableAdapter.gd`
  - `WorldChunkDirtyNotifierCallableAdapter.gd`
  - `WorldProjectionRefreshCallableAdapter.gd`

Rol:

- Contratos tipados mínimos para desacoplar callbacks críticos que antes se inyectaban como `Callable` sueltos en `setup(ctx)`.
- Objetivo de fase 1: mantener compatibilidad con wiring actual mediante adaptadores de transición sin ejecutar todavía la migración completa de fase 2.
- Primer consumidor migrado: `PlayerWallSystem` (coordenadas, dirty chunks, refresh/projections).

### 🧭 THREAT ASSESSMENT (Building/Placement Domain Service)

Ubicación:

- `scripts/domain/factions/ThreatAssessmentSystem.gd`

Rol:

- Servicio de dominio dedicado para evaluar si un evento de construcción/placement es suficientemente amenazante para generar candidatos de reacción hostil.
- Recibe un evento de building/placement + contexto (candidatos de grupo, umbrales) y devuelve una evaluación estructurada (`is_relevant`, `priority`, `severity`, `target_position`, `source_event`, `candidate_group_scope`, `debug`).
- No despacha IA ni ejecuta comportamiento runtime; solo produce datos para que capas de orquestación (ej. `world.gd`) publiquen intents downstream.

### 👁️ BANDIT PERCEPTION SYSTEM (Faction Domain Service)

Ubicación:
- `scripts/domain/factions/BanditPerceptionSystem.gd`

Rol:
- Capa dedicada de percepción para bandidos: centraliza normalización de señales de entorno (drops/resources cercanos, presencia del player, señales de combate reciente y targets de asalto estructural).
- Produce salidas estructuradas consumibles por capas downstream (`BanditBehaviorLayer`, blackboard/group pulse) sin asignar tareas ni ejecutar movimiento/combate.
- Mantiene compatibilidad con el runtime actual exportando tanto payload estructurado (`perception`) como campos legacy de contexto usados por comportamientos existentes.

### 🗂️ BANDIT TASK PLANNER (Faction Domain Service)

Ubicación:
- `scripts/domain/factions/BanditTaskPlanner.gd`

Rol:
- Capa explícita de planificación entre intent canónico (`BanditIntentSystem`) y ejecución runtime (`BanditBehaviorLayer`/`BanditWorldBehavior`).
- Consume `canonical_intent_record` + contexto de miembro y transforma esa intención en salidas concretas de orden/tarea (`follow_slot`, `move_to_target`, `mine_target`, `pickup_target`, `return_home`, `assault_structure_target`, `attack_target`).
- Emite payload estructurado en `order.task` para que la capa ejecutora consuma datos declarativos sin mezclar decisión de intención ni side effects de movimiento/combate.

### ⏱️ AWAKE RAMP QUEUE (Autoload)

Ubicación:

- `scripts/systems/AwakeRampQueue.gd`

Rol:

- Escalona el primer full tick de IA cuando muchos enemigos despiertan al mismo tiempo.
- Aplica budget por frame para repartir el costo de AI/Nav/combate en varios frames.
- Evita starvation con un tope de delay máximo por enemigo.

### 🎮 GAMEPLAY COMMAND DISPATCHER

Ubicación:

- `scripts/runtime/world/GameplayCommandDispatcher.gd`

Rol:

- Punto intermedio para comandos de gameplay recibidos por `world.gd`.
- `world.gd` mantiene fachada pública pero delega sin decidir outcomes de dominio.
- Enruta comandos de paredes de player hacia `PlayerWallSystem`.
- Enruta comandos de interest/scan hacia `SettlementIntel` y `WorldTerritoryPolicy`.
- Enruta incidentes civiles de taberna hacia la cadena `policy -> memory -> sanction director`.

### SOUND PANEL (Main Node)

Ubicacion:

- `scripts/systems/SoundPanel.gd`
- `scenes/main.tscn` (`Main/SoundPanel`)

Rol:

- Panel central con `@export` de SFX para ajustar sonidos desde un solo lugar en Inspector.
- Incluye perillas de volumen (`*_volume_db`) por categoria/sonido para balancear audio sin editar scripts.
- `main.gd` registra el nodo en `AudioSystem` para acceso global durante la sesion.
- Consumido por `slash.gd`, `tree_wood.gd`, `stone_ore.gd`, `grass_tuft.gd`, `BowWeapon.gd`, `enemy.gd`, `world.gd` (paredes de player) y `FootstepAudioComponent` (loop de caminar por superficie).

### 💬 IN-GAME COMMAND BAR

Ubicación:

- `scripts/gameplay/main.gd`

Rol:

- Abre una barra de comandos con `T` en la parte inferior.
- Ejecuta comandos con prefijo `/`.
- Soporta `/summon enemy` para invocar un enemigo cerca del jugador.

### 🧾 GameManager (Autoload)

Ubicación:

- `scripts/systems/game_manager.gd`

Rol:

- Director del loop de sesión. Nunca spawnea — solo emite señales.
- Señales globales: `player_died`, `player_healed`, `zone_entered`, `phase_changed(SessionPhase)`, `threat_level_changed(int)`.
- `SessionPhase` enum: `EXPLORE`, `RETURNING`, `RESTING`, `GAME_OVER`. Estado actual en `session_phase`.
- Contadores de sesión: `enemies_killed`, `resources_gathered`, `chunks_explored`, `session_time_seconds`, `threat_level`.
- `threat_level` sube cada 60s de juego o cada 5 kills; emite `threat_level_changed`.
- API pública: `register_kill()`, `register_resource_gathered()`, `register_chunk_explored()`.
- Evitar acoplamiento directo entre escenas.

---

## 4️⃣ ECONOMÍA ACTUAL (MVP)

- Oro almacenado en `InventoryComponent`.
- Recursos tipo string (`"copper"`).
- Venta y compra funcional vía debug.
- No hay UI de tienda aún.
- No hay persistencia entre sesiones.

Futuro:

- Taberna como hub.
- NPC comerciantes.
- Precios dinámicos.

---

## 5️⃣ REGLAS DE DISEÑO IMPORTANTES

- El mundo es sistémico, no scriptado.
- Recursos generan conflicto.
- No regenerar entidades arbitrariamente.
- Persistencia por chunk es obligatoria.
- Componentes > lógica hardcodeada.
- `GameManager` para eventos globales.
- Evitar rutas absolutas a nodos.
- Usar grupos para localizar entidades dinámicas.
- Convención obligatoria de personajes: todo script que derive de `CharacterBase` y sobrescriba `_ready()` debe llamar `super._ready()` como primera línea.

---

## 6️⃣ ESTADO ACTUAL DEL PROYECTO

Implementado:

- ✅ Mundo procedural con biomas.
- ✅ Chunk streaming.
- ✅ Persistencia en sesión.
- ✅ Cobre minable.
- ✅ Campamentos bandido.
- ✅ Taberna procedural como POI integrado al mundo.
- ✅ Enemigos funcionales.
- ✅ Bloqueo direccional.
- ✅ Stamina.
- ✅ Inventario básico.
- ✅ Contenedores placeables formalizados (`ContainerPlaceable` + `ContainerUi`) con wrappers legacy `Chest*` para compatibilidad total.
- ✅ Barriles como contenedor placeable persistente y spawn inicial en taberna (sobre la capa neutral de contenedores).
- ✅ Mesa de taberna convertida a placeable persistente (`table`) con receta en `tinkering` y destrucción con drop de item.
- ✅ Stool placeable (`stool`) con interacción de sentarse/pararse (toggle `E`) y sprite de sentado en player.
- ✅ HUD funcional.
- ✅ Game Over desacoplado.
- ✅ Colisiones de paredes y ajuste visual de transparencia por oclusión.

Pendiente / futuro inmediato:

- Sistema de facciones.
- Control territorial.
- Sistema de caminos.
- Guardado en disco.
- Economía real (sin debug).

---

## 7️⃣ ESCALABILIDAD PREVISTA

Arquitectura preparada para:

- Facciones NPC.
- IA que mine recursos.
- Disputas por nodos.
- Patrullas.
- Eventos dinámicos.
- Guardado completo del mundo.

---

## 8️⃣ LO QUE ESTE PROYECTO YA NO ES

- ❌ No es solo un prototipo de combate.
- ❌ No es un arena brawler.
- ❌ No depende de spawner fijo simple.

Es un **sandbox procedural en evolución**.

---

## 9️⃣ DIRECTIVA PARA AGENTES / CODEX

Cuando modifiques código:

- No romper persistencia de chunks.
- No regenerar entidades si ya existen.
- No duplicar lógica de componentes.
- Mantener separación `World / Player / Systems`.
- Si se agrega un sistema nuevo → documentarlo aquí.

---

## 🔟 RECOMENDACIONES PRÁCTICAS PARA CONTRIBUIR

Para mantener el proyecto estable y escalable:

- Priorizar cambios pequeños y verificables por sistema (`world`, `gameplay`, `ui`, `components`).
- Si tocas `world.gd`, validar explícitamente:
  - generación inicial,
  - reentrada a chunks ya visitados,
  - no duplicación de recursos/camps.
- Si tocas componentes, exponer señales y API mínima para evitar acoplamiento.
- Al agregar contenido sistémico nuevo (ej. nuevo recurso o POI), definir:
  - reglas de spawn,
  - interacción con inventario/economía,
  - comportamiento al descargar/cargar chunk.

---

## 1️⃣1️⃣ SUBSISTEMAS DE INTELIGENCIA DE ASENTAMIENTO

### `SettlementIntel` (`scripts/world/SettlementIntel.gd`)
Registra actividad del jugador y detecta bases reales. Dos capas independientes:

#### Capa 1 — Interest Markers
Eventos de actividad efímera o persistente. No implican una base.

**Markers persistentes:** `workbench` — existe mientras el placeable esté en WorldSave.
**Markers temporales (TTL 150-180s):** `copper_mined`, `stone_mined`, `wood_chopped`, `structure_placed`.

Deduplicación: misma `kind` a < 96px → refresh en lugar de copia nueva.

**Fuentes:** `GameEvents.resource_harvested` (minería/tala), `PlacementSystem.placement_completed` (construcción), `WorldSave.placed_entities_by_chunk` (workbench scan periódico).

**Dirty scope:** el flag `_dirty` es **global** (no por zona). Cuando se marca dirty, el siguiente tick rescana todos los workbenches en WorldSave. No hay filtrado por proximidad todavía.

API markers (también expuesta como fachada en `world.gd`):
- `record_interest_event(kind, world_pos, metadata)` — registrar evento manualmente
- `get_interest_markers_near(world_pos, radius) -> Array[Dictionary]` — consultar
- `rescan_workbench_markers()` — forzar rescan de workbenches inmediato (nombre honesto: solo rescana workbenches)
- `mark_interest_scan_dirty()` — marcar dirty para rescan en próximo tick (scope global)

#### Capa 2 — Base Detection
Detecta cierres reales: walls del jugador + doorwood + espacio interior cerrado.

**Heurística (por cada doorwood en WorldSave cerca del jugador):**
1. Ventana 25×25 tiles alrededor de la puerta
2. Cargar walls del jugador (`WorldSave.player_walls_by_chunk`) dentro de la ventana
3. Validar ≥ 2 walls cardinalmente adyacentes a la puerta
4. BFS desde cada vecino libre; si el fill sale del borde → exterior (descartado)
5. Fill contenido con ≥ 4 tiles interiores y ≥ 4 walls en ventana → base detectada

**Datos de una base:**
`id`, `center_world_pos`, `center_tile`, `door_tile`, `interior_tile_count`, `bounds`, `wall_count`, `updated_at`

**Triggers de rescan de bases:**
- Colocar/romper wall → `_mark_walls_dirty_and_refresh_for_tiles` en world.gd → `mark_base_scan_dirty_near`
- Wall destruida → señal `player_wall_drop` → `mark_base_scan_dirty_near`
- Colocar doorwood/wallwood → `PlacementSystem.placement_completed` → `mark_base_scan_dirty_near`
- Periódico: cada 10s usando posición del jugador vía `player_pos_getter`

API bases (también expuesta como fachada en `world.gd`):
- `rescan_bases_near(world_pos, radius)` — forzar rescan inmediato
- `get_detected_bases_near(world_pos, radius) -> Array[Dictionary]`
- `has_detected_base_near(world_pos, radius) -> bool`
- `mark_base_scan_dirty_near(world_pos)` — marcar dirty (scope global actualmente, world_pos ignorado)

**Limitaciones MVP:**
- Eliminación de doorwood sin señal → stale base desaparece en ≤10s
- Rooms > 25×25 tiles no se detectan
- No persiste entre sesiones
- Múltiples puertas generan entradas de base independientes
- `mark_base_scan_dirty_near` ignora el world_pos (dirty es global)

---

## 1️⃣2️⃣ SUBSISTEMAS DE COMPORTAMIENTO MUNDIAL DE BANDIDOS

### `NpcWorldBehavior` (`scripts/world/NpcWorldBehavior.gd`)
RefCounted. Máquina de estados reutilizable para NPCs que están sleeping o en lite-mode.
No modifica nodos — devuelve `get_desired_velocity()` y un coordinador lo aplica.

**Estados:** `IDLE_AT_HOME`, `PATROL`, `HOLD_POSITION`, `RETURN_HOME`, `APPROACH_INTEREST`, `FOLLOW_LEADER`

**Reglas base:**
- IDLE_AT_HOME → PATROL cuando expira idle_timer (2–6s)
- PATROL → IDLE_AT_HOME al llegar al destino o tras 14s
- RETURN_HOME si se aleja > 192px de home_pos (safety net)
- FOLLOW_LEADER: se acerca mientras dist > 32px

**API:**
- `setup(cfg: Dictionary)` — cfg: `home_pos`, `role`, `group_id`, `member_id`
- `tick(delta, ctx)` — ctx: `"node_pos": Vector2`, `"leader_pos": Vector2` (opcional)
- `get_desired_velocity() -> Vector2`
- `_get_patrol_radius() -> float` — virtual, override en subclase
- `_get_speed() -> float` — virtual, override en subclase

### `BanditWorldBehavior` (`scripts/world/BanditWorldBehavior.gd`)
Extiende `NpcWorldBehavior`. Radios y velocidades por rol; reacciona a `BanditGroupMemory.current_group_intent`.

**Radios de patrulla:** leader=28px, bodyguard=48px, scavenger=96px
**Velocidades:** leader=44, bodyguard=54, scavenger=58 (antes de compensar fricción del enemigo)
**Bias de idle:** leader=3×, bodyguard=1.5×, scavenger=1×

**Reacción a group_intent:**
- `"hunting"`: leader → APPROACH_INTEREST (last_interest_pos del grupo); bodyguard → FOLLOW_LEADER; scavenger no cambia
- `"extorting"`: leader → APPROACH_INTEREST
- `"idle"/"alerted"`: APPROACH_INTEREST o FOLLOW_LEADER → RETURN_HOME

### `BanditBehaviorLayer` (`scripts/world/BanditBehaviorLayer.gd`)
Node hijo de World. Gestiona el pool de `BanditWorldBehavior` para todos los bandidos activos.

**Creación lazy:** se crea un behavior cuando el enemigo está sleeping y tiene `group_id` en su save_state.
**Tick:** cada `TICK_INTERVAL=0.5s` — ticks de estado + prune de behaviors inválidos.
**Aplicación de velocidad:** en `_physics_process`, cada frame para enemies sleeping y no lite-mode.

**Fricción:** enemy.gd aplica `velocity.move_toward(0, friction*delta)` cuando sleeping (friction=1500).
`BanditBehaviorLayer` añade `FRICTION_COMPENSATION=25` a la magnitud del velocity para compensar,
de modo que el movimiento efectivo ≈ velocidad objetivo del behavior.

**Cargo (carry system):**
- Cada NPC tiene `cargo_count` / `cargo_capacity` (solo enteros — sin items reales).
- Capacidad por rol: leader=1, bodyguard=2, scavenger=4.
- Al llegar a casa (RETURN_HOME arriba en ARRIVED_DIST), `cargo_count = 0` (descarga).
- **Preferencia de carry:** NPCs prefieren llevar drops a la base en lugar de consumirlos.
  `BanditBehaviorLayer._handle_collection()` hace el `queue_free()` del drop e incrementa cargo.

**Loot pickup:**
- Grupos "item_drop": `ItemDrop._ready()` hace `add_to_group("item_drop")`.
- `BanditBehaviorLayer._refresh_world_caches()` recoge todos los drops del árbol una vez por tick.
- Pasa `nearby_drops_info` = `[{id, pos, amount}]` filtrado por LOOT_SCAN_RADIUS=144px en el ctx.
- scavenger y bodyguard pueden entrar en LOOT_APPROACH; leader no.

**Resource watch:**
- Grupos "world_resource": copper_ore, stone_ore, tree_wood hacen `add_to_group("world_resource")`.
- Pasa `nearby_res_info` = `[{pos}]` filtrado por RESOURCE_SCAN_RADIUS=288px.
- Solo scavengers entran en RESOURCE_WATCH (patrol de radio ~28px alrededor del recurso).

**Limitaciones MVP:**
- Solo bandidos con `group_id` reciben behavior
- No hay evasión de obstáculos — pueden quedarse atascados en paredes
- HOLD_POSITION no tiene transición automática
- cargo_count no persiste entre sesiones (siempre empieza en 0)
- NPCs no realmente "minan" recursos — solo los vigilan en RESOURCE_WATCH
- Las velocidades no compensan cambios en `friction` del enemy exportado

### `BanditGroupBrain` (`scripts/world/BanditGroupBrain.gd`)
RefCounted. Capa táctica superior a ejecución individual. Lee intención grupal + `GroupBlackboard`
y asigna órdenes por miembro para mantener coherencia de escuadra sin mover nodos directamente.

**Estados macro soportados:** `idle`, `patrol`, `alerted`, `hunting`, `raiding`, `working`, `retreating`, `depositing`, `defending_camp`.

**Órdenes emitidas por miembro:** `follow_slot`, `move_to_target`, `mine_target`, `pickup_target`, `return_home`, `attack_target`.

### `BodyguardController` / `ScavengerController` (`scripts/world/*Controller.gd`)
Controladores tácticos por rol que consumen `GroupBlackboard` y devuelven órdenes declarativas.
No aplican side-effects ni movimiento directo.

---

## 1️⃣3️⃣ INTELIGENCIA GRUPAL DE BANDIDOS — DETECCIÓN Y EXTORSIÓN

### `BanditGroupIntel` (`scripts/world/BanditGroupIntel.gd`)
RefCounted. Scanner de inteligencia a nivel de grupo. Ticks cada `SCAN_INTERVAL=8s`.
Para cada grupo con leader vivo, consulta `SettlementIntel` y actualiza `BanditGroupMemory`.

### `GroupBlackboard` en `BanditGroupMemory` (`scripts/systems/BanditGroupMemory.gd`)
Memoria compartida por grupo con estructura fija por secciones:

- `perception`: conocimiento efímero compartido (`known_resources`, `known_drops`)
- `assignments`: espacio reservado para asignaciones compartidas de trabajo
- `status`: estado agregado (`threat_level`, `leader_id`, `group_mode`)
- `expirations`: metadatos de vencimiento por rama para trazabilidad

Cada entrada se almacena con contrato TTL explícito:
`{value, timestamp, expires_at, ttl_seconds, source}`.

**Invalidación:**
- prune por tiempo en lecturas/escrituras de blackboard.
- entradas expiradas se eliminan sin tocar lógica de combate/movimiento.

**Wiring pasivo actual (sin cambiar locomoción/combate):**
- `BanditGroupIntel` escribe `threat_level` y `group_mode` después del scan/policy.
- `BanditBehaviorLayer` escribe `known_drops` y `known_resources` desde buffers de sensores por tick.
- eventos de liderazgo (`register/promote/remove`) sincronizan `status.leader_id`.

**Logs de consistencia:**
- `BanditGroupMemory` emite `[BGM][BB] consistency ...` (rate-limited) para validar
  que perception/status se llenan con datos compartidos en runtime.

**Flujo:**
1. `BanditGroupIntel.tick(delta)` llamado desde `BanditBehaviorLayer._process()`
2. Para cada grupo en `BanditGroupMemory`, si hay leader vivo:
   - Llama `get_interest_markers_near(home_pos, 384px)` y `get_detected_bases_near(...)`
   - Calcula score (pesos: base=15, workbench=10, structure=6, mine=3, chop=2)
   - Determina intent: score≥3→"alerted", ≥8→"hunting", ≥12→"extorting"
   - Actualiza `BanditGroupMemory.update_intent()` y `record_interest()`
3. Si "alerted": elige 1 scout NPC (no-leader, preferencia sleeping) → `BanditGroupMemory.set_scout()`
4. Si score≥12: intenta encolar extorsión (con spam guards)

**Anti-spam (3 capas):**
1. Un solo scan por grupo cada 8s (timer en BanditGroupIntel)
2. `ExtortionQueue.has_pending_for_group(group_id)` → skip si ya hay intent pendiente
3. `EXTORT_COOLDOWN=90s` en `BanditGroupMemory.last_extortion_request_time`

**Extortion intent enqueued:**
```
{target_id:"player", faction_id, group_id, source_npc_id: leader_id,
 trigger_kind: "workbench"|"base_detected"|etc, world_pos, created_at, severity}
```

**Reacción coordinada por intención:**
| intent | leader | bodyguard | scavenger/scout |
|---|---|---|---|
| "alerted" | no cambia | no cambia | 1 scout designado → APPROACH_INTEREST |
| "hunting" | → APPROACH_INTEREST (last_interest_pos) | → FOLLOW_LEADER | no cambia |
| "extorting" | → APPROACH_INTEREST | — | — |
| "idle" | — | → RETURN_HOME si persiguiendo | — |

**Campo `scout_npc_id` en BanditGroupMemory:**
- Seteado por `BanditGroupIntel._pick_scout()` al detectar "alerted"
- Consumido por `BanditWorldBehavior._on_group_intent_changed("alerted")`
- Solo el NPC cuyo `member_id == scout_npc_id` mueve al punto de interés

**Wiring (world.gd):**
`_bandit_behavior_layer.setup_group_intel({get_interest_markers_near, get_detected_bases_near})`
— llamado DESPUÉS de `_settlement_intel.setup()` para que los callables ya estén listos.

**Limitaciones MVP:**
- Solo detecta actividad del player, no de otros bandidos
- Score no decae si el jugador para de actuar (solo expiran los TTL de markers en SettlementIntel)
- Un solo target hard-coded: `"player"` como `target_id` de extorsión
- Sin notificación al jugador todavía (solo lógica de datos)
