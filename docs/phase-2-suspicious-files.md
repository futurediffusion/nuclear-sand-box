# Phase 2 — Suspicious Files Scoring

## Escala de scoring (0–3 por señal)
- **0 = limpio**: complejidad baja, señal prácticamente ausente.
- **1 = leve**: señal presente pero acotada.
- **2 = alto**: señal frecuente o con impacto claro en mantenibilidad.
- **3 = crítico**: señal dominante; archivo candidato prioritario para refactor.

## Señales evaluadas
1. **tamaño**
2. **métodos públicos**
3. **dependencias directas**
4. **acceso a singletons/autoloads**
5. **mezcla lectura+decisión+ejecución**
6. **duplicación de checks**
7. **flags/booleans de contexto**

## Ranking (mayor a menor score total)

| Archivo | tamaño | métodos públicos | dependencias directas | singletons/autoloads | mezcla R+D+E | duplicación checks | flags/booleans | **Total** |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| `world.gd` | 3 | 3 | 3 | 3 | 3 | 3 | 3 | **21** |
| `BanditBehaviorLayer.gd` | 3 | 1 | 3 | 1 | 3 | 3 | 3 | **17** |
| `ExtortionFlow.gd` | 2 | 1 | 2 | 0 | 3 | 2 | 2 | **12** |
| `BanditGroupIntel.gd` | 2 | 1 | 2 | 0 | 2 | 2 | 3 | **12** |
| `BanditWorkCoordinator.gd` | 2 | 0 | 1 | 0 | 2 | 2 | 2 | **9** |
| `SettlementIntel.gd` | 2 | 2 | 1 | 0 | 2 | 1 | 1 | **9** |
| `WorldSpatialIndex.gd` | 1 | 2 | 1 | 0 | 1 | 1 | 1 | **7** |
| `WorldTerritoryPolicy.gd` | 0 | 1 | 1 | 0 | 1 | 1 | 1 | **5** |
| `WorldCadenceCoordinator.gd` | 0 | 1 | 0 | 0 | 1 | 0 | 0 | **2** |

---

## Métricas de superficie API (líneas + públicos/exportados)

**Criterios usados en esta pasada**
- **Líneas totales**: conteo físico de líneas por archivo (`wc -l` / parse local).
- **Métodos públicos/exportados**: `func` no prefijadas con `_` (convención pública en GDScript).
- **Métodos mixtos (query + command)**: nombres que combinan señales de consulta y mutación en la misma API (ej. `mark_*_dirty*` sobre artefactos de consulta).
- **Umbral de alerta**: `líneas >= 500` **y** `métodos públicos >= 10`.

| Archivo | Líneas totales | Métodos públicos/exportados | Métodos públicos mixtos (query+command) | ¿Supera umbral? | Observación |
|---|---:|---:|---|---|---|
| `world.gd` | 2044 | 42 | `mark_interest_scan_dirty` | ✅ Sí | **surface area excesiva** |
| `BanditBehaviorLayer.gd` | 1604 | 5 | — | ❌ No | superficie API controlada |
| `ExtortionFlow.gd` | 669 | 4 | — | ❌ No | superficie API controlada |
| `BanditGroupIntel.gd` | 628 | 3 | — | ❌ No | superficie API controlada |
| `BanditWorkCoordinator.gd` | 570 | 2 | — | ❌ No | superficie API controlada |
| `SettlementIntel.gd` | 537 | 11 | `mark_interest_scan_dirty`, `mark_base_scan_dirty_near` | ✅ Sí | **surface area excesiva** |
| `WorldSpatialIndex.gd` | 377 | 16 | — | ❌ No (muchos públicos, tamaño medio) | superficie API controlada |
| `WorldTerritoryPolicy.gd` | 117 | 3 | — | ❌ No | superficie API controlada |
| `WorldCadenceCoordinator.gd` | 116 | 6 | — | ❌ No | superficie API controlada |

---

## `world.gd`
- **Total: 21 (crítico).**
- Macro-script (≈2k líneas), superficie pública muy amplia y acoplamiento alto con sistemas de mundo y utilidades.
- Mezcla de responsabilidades (consulta de estado, policy checks, side-effects, spawning/daño/gestión) en el mismo archivo.
- Múltiples checks condicionales similares y abundancia de flags/contexto (estado temporal, gating, dirty/pending).

## `BanditBehaviorLayer.gd`
- **Total: 17 (muy alto).**
- Tamaño alto y fuerte rol orquestador con varias dependencias de dominio (territorio, grupos, flujos, selección de objetivos).
- Aunque expone pocos métodos públicos, concentra mucha lógica de decisión y ejecución en cascada.
- Alta densidad de flags de contexto y ramas condicionales repetidas por tipo de situación/L0D/estado de grupo.

## `BanditWorkCoordinator.gd`
- **Total: 9 (alto moderado).**
- Tamaño medio-alto para un coordinador y acoplamiento operativo con el loop post-behavior.
- Menor API pública, pero mezcla lectura de contexto con scheduling/ejecución.
- Presencia apreciable de checks y banderas operativas.

## `BanditGroupIntel.gd`
- **Total: 12 (alto).**
- Archivo de tamaño medio-alto con densidad de estado contextual del grupo (memoria/intel/timers).
- API pública pequeña, pero interno con múltiples rutas condicionales y flags.
- Mezcla de lectura de señales, inferencia y actualización de estado utilizable por capas de comportamiento.

## `SettlementIntel.gd`
- **Total: 9 (alto moderado).**
- Tamaño medio-alto y API pública relativamente grande para utilidades de escaneo/interés.
- Dependencias directas contenidas y bajo acceso global, pero combina escaneo, registro de eventos y decisiones de marcación.
- Riesgo medio por duplicación de checks alrededor de “scan dirty”/“base near”.

## `WorldCadenceCoordinator.gd`
- **Total: 2 (bajo).**
- Archivo pequeño, API compacta y propósito acotado (cadencia/lanes).
- Baja señal de riesgo estructural: poca dependencia y casi sin flags o lógica duplicada.

## `WorldSpatialIndex.gd`
- **Total: 7 (medio).**
- Tamaño intermedio con API pública relativamente amplia (consultas y registro de nodos/placeables).
- Responsabilidad principalmente de indexación/consulta, con mezcla moderada de lectura y lógica de acceso.
- Riesgo más por superficie pública que por acoplamiento global.

## `ExtortionFlow.gd`
- **Total: 12 (alto).**
- Tamaño medio-alto y flujo multi-etapa (proceso, movimiento, resolución de elección).
- Mezcla fuerte de evaluación + decisión + ejecución durante el mismo pipeline.
- Densidad media-alta de checks y flags por etapa/contexto del flujo.

## `WorldTerritoryPolicy.gd`
- **Total: 5 (medio-bajo).**
- Archivo chico y focalizado, con pocas entradas públicas.
- Riesgo principal en policy checks que pueden duplicarse con otros validadores de colocación/interés.
- Carga de estado/contexto baja comparada con otros archivos del dominio.

---

## Fase 2.1 — Etiquetado R/D/E por métodos principales

Leyenda:
- **L (Lectura):** consulta/obtiene estado sin mutación esperada.
- **D (Decisión):** aplica reglas, scoring, branching de policy.
- **E (Ejecución):** muta estado, dispara side-effects, despacha acciones.

### `scripts/world/world.gd`
- `update_chunks(center)` → **L+D+E** (lee ventana/estado de chunk, decide carga/descarga, ejecuta generación/unload).
- `place_player_wall_at_tile(tile_pos)` → **D+E** (valida restricciones y persiste/instancia wall).
- `damage_player_wall_at_world_pos(world_pos)` → **L+D+E** (resuelve tile objetivo, decide impacto válido, aplica daño/feedback).
- `_mark_walls_dirty_and_refresh_for_tiles(tile_positions)` → **D+E** (marca dirty + dispara refresh inmediato).
- `_tick_player_territory()` → **L+D+E** (lee workbenches/bases, decide zonas, reconstruye mapa territorial).

### `scripts/world/BanditBehaviorLayer.gd`
- `_tick_behaviors()` → **L+D+E** (lee NPCs/LOD, decide intención por estado, aplica velocidades/objetivos).
- `dispatch_group_to_target(group_id, target_pos, squad_size)` → **D+E** (selección de miembros + dispatch efectivo).
- `_process_pending_structure_dispatches()` → **L+D+E** (lee cola, decide slice, ejecuta asignaciones).

### `scripts/world/ExtortionFlow.gd`
- `process_flow(delta)` → **L+D+E** (lee jobs/estado, decide transiciones, ejecuta cambios de etapa/aborts).
- `_resolve_extortion_warn(job)` → **D+E** (policy de warning + side-effects de presión/mensajería).
- `_tick_warning_strike(job, player_pos, friction_compensation)` → **L+D+E** (lee distancia/clock, decide strike, mueve/ordena NPC).

### `scripts/world/BanditGroupIntel.gd`
- `tick(delta)` → **L+D+E** (lee grupos/intervalos, decide qué grupos escanear, actualiza elapsed).
- `_scan_group(group_id, g)` → **L+D+E** (lee markers/bases, calcula score/intent, actualiza memoria y colas raid/extorsión).
- `_score_activity(markers, bases)` → **L+D** (query agregada + scoring de amenaza).

### `scripts/world/BanditWorkCoordinator.gd`
- `process_post_behavior(beh, enemy_node, drops_cache)` → **L+D+E** (lee contexto de NPC, decide tarea, ejecuta colección/minado/asalto).
- `_handle_structure_assault(beh, enemy_node)` → **L+D+E** (resuelve target estructural y ejecuta daño/loot).
- `_try_local_wall_strike(...)` → **L+D+E** (consulta target local, decide strike válido, ejecuta hit/damage).

### `scripts/world/SettlementIntel.gd`
- `process(delta)` → **L+D+E** (lee timers/lanes, decide scans, ejecuta expiración/rescan/pulsos base).
- `record_interest_event(kind, world_pos, meta)` → **L+D+E** (merge/canonicalización + inserción/actualización marker).
- `_process_pending_base_scan(door_budget)` → **L+D+E** (consume cola de puertas, decide base válida, muta `_bases`).

### `scripts/world/WorldSpatialIndex.gd`
- `get_placeables_by_item_ids_near(...)` → **L+D** (query + filtro por radio/item).
- `register_runtime_node(kind, node)` → **D+E** (normaliza entrada y muta índices runtime).
- `get_blocker_tiles_in_rect(...)` → **L+D** (consulta + filtro de bloqueo por tipo/placeable).

### `scripts/world/WorldTerritoryPolicy.gd`
- `validate_placement(tile_pos, tavern_chunk)` → **L+D** (consulta contexto + reglas territoriales).
- `record_interest_event(kind, world_pos)` → **D+E** (adapta evento a capa de intel).

### `scripts/world/WorldCadenceCoordinator.gd`
- `advance(delta)` → **D+E** (decide pulsos por lane y actualiza estado temporal interno).
- `consume_lane(name)` → **L+E** (query de pulsos + consumo/mutación de contador).

### Críticos adicionales (raids/persistencia/pathing)

#### `scripts/world/RaidFlow.gd`
- `process_flow()` → **L+D+E**.
- `_tick_jobs()` → **L+D+E**.
- `_resolve_structure_target(anchor_pos, allow_walls, prefer_storage)` → **L+D**.

#### `scripts/world/NpcPathService.gd`
- `get_next_waypoint(agent_id, current_pos, goal, opts)` → **L+D+E**.
- `_compute_path(agent_id, start, goal, c)` → **L+D+E**.
- `has_line_clear(start, goal)` → **L+D**.

#### `scripts/world/WallPersistence.gd`
- `save_wall(chunk_id, tile, wall_data)` → **D+E**.
- `load_chunk_walls(chunk_id)` → **L+D**.
- `serialize_wall_data(wall_data)` → **L+D**.

---

## Fase 2.2 — Casos sospechosos (mezcla 2–3 capas) y target-state

> Identificador: `archivo::método`

| Prioridad | ID | Capas mezcladas | Sistema crítico | Evidencia resumida | Target-state propuesto |
|---|---|---|---|---|---|
| **P0** | `scripts/world/world.gd::update_chunks` | L+D+E | **territorio + persistencia** | Decide ventana activa y ejecuta carga/descarga/generación en el mismo método. | Separar en `ChunkQuery.collect_window_diff(center)` (query pura), `ChunkPolicy.plan_chunk_transitions(diff)` (decisión), `ChunkExecutor.apply_plan(plan)` (ejecución). |
| **P0** | `scripts/world/RaidFlow.gd::_tick_jobs` | L+D+E | **raids** | Evalúa stage, decide transición y ejecuta asalto/retirada dentro del loop principal. | `RaidQuery.snapshot_jobs()`, `RaidDecision.resolve_next_stage(job)`, `RaidExecutor.run_stage(job, stage_decision)`. |
| **P0** | `scripts/world/BanditGroupIntel.gd::_scan_group` | L+D+E | **raids + territorio** | Lee markers/bases, scorea amenaza, actualiza memoria e inyecta intents (extorsión/raid). | `GroupIntelQuery.fetch_signals(group_id)`, `GroupIntelPolicy.derive_intent(signals)`, `GroupIntelExecutor.commit_intent(group_id, decision)`. |
| **P0** | `scripts/world/NpcPathService.gd::get_next_waypoint` | L+D+E | **pathing** | Mezcla cache lookup, decisión de repath y cómputo/mutación de waypoints. | `PathQuery.read_agent_cache(agent_id)`, `PathPolicy.should_repath(cache, goal, now)`, `PathExecutor.compute_or_advance(agent_id, decision)`. |
| **P1** | `scripts/world/SettlementIntel.gd::process` | L+D+E | **territorio** | Expira markers, decide scans de workbench/base y ejecuta job scheduling/pulsos en un bloque. | `SettlementQuery.collect_scan_inputs()`, `SettlementPolicy.plan_scans(inputs)`, `SettlementExecutor.apply_scan_plan(plan)`. |
| **P1** | `scripts/world/BanditWorkCoordinator.gd::process_post_behavior` | L+D+E | **raids** | Orquesta loot/mining/assault con selección de rama y side-effects directos. | `WorkQuery.build_npc_context()`, `WorkPolicy.pick_task(ctx)`, `WorkExecutor.execute_task(task, ctx)`. |
| **P1** | `scripts/world/world.gd::damage_player_wall_at_world_pos` | L+D+E | **persistencia** | Resuelve tile, valida objetivo y aplica daño/remoción/feedback inmediatamente. | `WallQuery.resolve_wall_hit(world_pos)`, `WallDamagePolicy.eval_hit(resolved, amount)`, `WallExecutor.apply_damage(result)`. |
| **P2** | `scripts/world/ExtortionFlow.gd::process_flow` | L+D+E | raids/social | Consume jobs, decide transiciones y ejecuta callbacks/movimiento en la misma pasada. | `ExtortionQuery.active_jobs()`, `ExtortionPolicy.next_transition(job)`, `ExtortionExecutor.apply_transition(job, decision)`. |
| **P2** | `scripts/world/world.gd::_tick_player_territory` | L+D+E | **territorio** | Lee anchors/bases detectadas y reconstruye mapa territorial en sitio. | `TerritoryQuery.collect_inputs()`, `TerritoryPolicy.build_zone_model(inputs)`, `TerritoryExecutor.publish_map(model)`. |
| **P2** | `scripts/world/SettlementIntel.gd::_process_pending_base_scan` | L+D+E | **territorio** | Consume puertas candidatas, decide base válida y escribe `_bases` en el mismo loop. | `BaseScanQuery.next_batch()`, `BaseScanPolicy.validate_base_candidate()`, `BaseScanExecutor.upsert_detected_base()`. |

---

## Fase 2.3 — Orden de ataque recomendado

1. **P0 primero:** `world::update_chunks`, `RaidFlow::_tick_jobs`, `BanditGroupIntel::_scan_group`, `NpcPathService::get_next_waypoint`.
2. **P1 segundo:** `SettlementIntel::process`, `BanditWorkCoordinator::process_post_behavior`, `world::damage_player_wall_at_world_pos`.
3. **P2 tercero:** extorsión y mantenimiento territorial incremental.

Criterio aplicado: priorizar mezcla R/D/E en rutas que impactan **territorio, raids, persistencia y pathing** antes de módulos auxiliares.

---

## Fase 2.4 — Checklist de cierre (completitud, evidencia, acciones)

### 1) Cobertura completa de los 9 archivos objetivo

Estado: **✅ Completo (9/9)**.

| Archivo | ¿Tiene scoring 7 señales? | ¿Tiene resumen técnico? | ¿Tiene recomendación concreta? |
|---|---|---|---|
| `world.gd` | ✅ | ✅ | ✅ |
| `BanditBehaviorLayer.gd` | ✅ | ✅ | ✅ |
| `ExtortionFlow.gd` | ✅ | ✅ | ✅ |
| `BanditGroupIntel.gd` | ✅ | ✅ | ✅ |
| `BanditWorkCoordinator.gd` | ✅ | ✅ | ✅ |
| `SettlementIntel.gd` | ✅ | ✅ | ✅ |
| `WorldSpatialIndex.gd` | ✅ | ✅ | ✅ |
| `WorldTerritoryPolicy.gd` | ✅ | ✅ | ✅ |
| `WorldCadenceCoordinator.gd` | ✅ | ✅ | ✅ |

### 2) Validación de señales de riesgo: puntuadas + justificadas

Estado: **✅ Cumplido**.

- Las **7 señales** (`tamaño`, `métodos públicos`, `dependencias directas`, `singletons/autoloads`, `mezcla R+D+E`, `duplicación checks`, `flags/booleans`) están puntuadas por archivo en el ranking.
- La justificación técnica breve se apoya en:
  - métricas objetivas de superficie API (líneas + métodos públicos),
  - etiquetas R/D/E por método principal,
  - y observaciones por archivo con foco en acoplamiento, branching y side-effects.

### 3) Recomendaciones concretas por archivo

Estado: **✅ Cumplido** (no solo observaciones).

| Archivo | Recomendación concreta |
|---|---|
| `world.gd` | Extraer pipeline `Query → Policy → Executor` para chunks, daño a muros y territorio; limitar API pública a fachada de coordinación. |
| `BanditBehaviorLayer.gd` | Separar selección de intención (`BehaviorPolicy`) de despacho efectivo (`BehaviorExecutor`) y encapsular flags de contexto en un `BehaviorContext`. |
| `ExtortionFlow.gd` | Partir el flujo por etapas explícitas (warn/approach/resolve) con transición pura y ejecutor de side-effects aislado. |
| `BanditGroupIntel.gd` | Dividir `_scan_group` en `fetch_signals`, `derive_intent`, `commit_intent`; persistir memoria de grupo vía puerto dedicado. |
| `BanditWorkCoordinator.gd` | Implementar `pick_task(ctx)` puro + `execute_task(task)`; reducir checks duplicados con catálogo de precondiciones reutilizable. |
| `SettlementIntel.gd` | Separar expiración de markers, planificación de scans y commit de resultados; consolidar `scan dirty/base near` en una sola policy. |
| `WorldSpatialIndex.gd` | Mantener módulo como servicio de query/indexing, pero reducir superficie pública agrupando operaciones de registro en una API de alto nivel. |
| `WorldTerritoryPolicy.gd` | Unificar validaciones de placement/interés para evitar duplicación entre policy y validadores adyacentes. |
| `WorldCadenceCoordinator.gd` | Conservar diseño actual; solo agregar tests de contrato para lanes y consumo de pulsos. |

### 4) Versión congelada del diagnóstico

- **Diagnóstico congelado:** `phase-2-suspicious-files`
- **Versión:** `v1.0`
- **Fecha de congelamiento (UTC):** `2026-04-01`
- **Responsable:** `GPT-5.3-Codex (OpenAI)`
- **Alcance congelado:** scoring + etiquetado R/D/E + casos sospechosos + orden de ataque.

### 5) Regla de entrada obligatoria para Fase 3 (refactor por soberanías)

Estado: **✅ Definido**.

Desde esta versión, toda planificación de Fase 3 debe:
1. usar este diagnóstico congelado como **input obligatorio**;
2. mapear cada iniciativa a una soberanía (`territorio`, `raids`, `persistencia`, `pathing`);
3. preservar prioridad `P0 → P1 → P2`;
4. declarar explícitamente qué método sospechoso (ID Fase 2.2) descompone y con qué target-state (`Query/Policy/Executor`).

> Si un plan de Fase 3 no referencia esta versión (`phase-2-suspicious-files v1.0, 2026-04-01`), se considera **incompleto**.
