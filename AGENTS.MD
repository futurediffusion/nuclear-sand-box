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

### ⏱️ AWAKE RAMP QUEUE (Autoload)

Ubicación:

- `scripts/systems/AwakeRampQueue.gd`

Rol:

- Escalona el primer full tick de IA cuando muchos enemigos despiertan al mismo tiempo.
- Aplica budget por frame para repartir el costo de AI/Nav/combate en varios frames.
- Evita starvation con un tope de delay máximo por enemigo.

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
