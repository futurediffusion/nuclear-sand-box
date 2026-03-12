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

⚠️ **Regla:**

- La lógica reusable va en componentes.
- No duplicar sistemas dentro de `Player` o `Enemy`.

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

### 🔥 WARMUP MANAGER

Ubicación:

- `scripts/systems/WarmupManager.gd`

Rol:

- Precarga recursos/escenas críticas al boot.
- Instancia y libera una vez escenas clave fuera de pantalla para evitar hitch de “primera vez”.
- Mantiene un mínimo de ventana de warm-up para ocultar picos iniciales del renderer.

### ⏱️ AWAKE RAMP QUEUE (Autoload)

Ubicación:

- `scripts/systems/AwakeRampQueue.gd`

Rol:

- Escalona el primer full tick de IA cuando muchos enemigos despiertan al mismo tiempo.
- Aplica budget por frame para repartir el costo de AI/Nav/combate en varios frames.
- Evita starvation con un tope de delay máximo por enemigo.

### 🧾 GameManager (Autoload)

Ubicación:

- `scripts/systems/game_manager.gd`

Rol:

- Señales globales.
- `player_died`
- `zone_entered`
- Estado global temporal.
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
- Mantener este archivo actualizado cuando cambie la realidad jugable del proyecto.
