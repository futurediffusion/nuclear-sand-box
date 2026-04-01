# Phase 7 — Cut 3: State Inventory (mundo)

## Objetivo
Inventariar entidades/estado clave del mundo y señalar conflictos de soberanía de datos para priorizar correcciones de consistencia de comportamiento y restauración.

## Convenciones
- **Categoría declarada**: `runtime`, `save`, `derivado`, `cache`.
- **DOUBLE_TRUTH**: mismo significado existe en dos sitios autoritativos.
- **CACHE_AS_TRUTH**: cache/índice está decidiendo semántica en vez de solo acelerar lecturas.
- **Prioridad**: `P0` (impacto crítico), `P1` (alto), `P2` (medio).

---

## 1) Inventario de estado por entidad clave

| Dominio | Campo | Ubicación actual | Categoría declarada | Writers actuales | Readers principales |
|---|---|---|---|---|---|
| Territorio bandido | Radio territorial efectivo por facción | `BanditTerritoryQuery.radius_for_faction` (usa `FactionHostilityManager.get_behavior_profile`) | derivado | `FactionHostilityManager` (indirecto, vía hostilidad) | `BanditTerritoryQuery.groups_at/is_in_territory`, `WorldTerritoryPolicy`, `TavernDefensePosture` |
| Hostilidad de facción | `hostility_points`, `recent_heat`, `times_raided`, etc. | `FactionHostilityManager._factions` (`FactionHostilityData`) | runtime (persistible por save manager) | `FactionHostilityManager.add_hostility/reduce_hostility/_on_day_passed` | `BanditGroupIntel`, `RaidFlow`, `DownedEncounterCoordinator`, `BanditTerritoryQuery` |
| Hostilidad (compat temporal) | lectura/relay legacy de score hostilidad | `FactionRelationService` (sin estado propio, read-through) | derivado (compat) | *(sin writers de dominio)* | `FactionRelationService.get_hostility_score/get_finish_modifier`, listeners legacy de evento |
| Raids en cola | intents de raid pendientes | `RaidQueue._intents` | runtime | `BanditGroupIntel` (`enqueue_*` vía puerto), otros emisores de raid | `RaidFlow._consume_raid_queue` |
| Historial de raid por grupo | `_last_raid_time_by_group`, `_last_wall_probe_time_by_group` | `RaidQueue` | runtime | `RaidQueue.enqueue_*` | `BanditGroupIntel` (gates/cooldowns), helpers de cooldown |
| Jobs activos de raid | `_active_jobs[group_id]` | `RaidFlow` | runtime | `RaidFlow._create_job/_tick_*` | `RaidFlow` interno, telemetría `raid_closed` |
| Walls del jugador | `player_walls_by_chunk` (`tile_key -> {hp}`) | `WorldSave` (+ adapter `WallPersistence`) | save | `PlayerWallSystem` vía `WallPersistence.save_wall/remove_wall` y llamadas de daño/colocación | `PlayerWallSystem`, `SettlementIntel` (detección de base), `world.gd` |
| Walls estructurales | HP por tile estructural (`_structural_wall_hp`) + tilemap | `PlayerWallSystem` | runtime | `PlayerWallSystem.damage_structural_wall_at_tile` | `PlayerWallSystem`, `RaidFlow` (query de target indirecta) |
| Placeables persistentes | `placed_entities_by_chunk`, `placed_entity_chunk_by_uid`, `placed_entity_data_by_uid`, `placed_entities_revision` | `WorldSave` | save | `PlacementSystem`, `ContainerPlaceable`, removals en runtime de mundo | `WorldSpatialIndex`, `SettlementIntel`, `NpcPathService`, `world.gd` |
| Índice de placeables por item | `_placeables_by_item_id_and_chunk` + `_placeables_cache_revision` | `WorldSpatialIndex` | cache/derivado | `WorldSpatialIndex._ensure_placeables_cache` (rebuild desde `WorldSave`) | `SettlementIntel` (workbench/door queries), queries de mundo por item_id |
| Loot runtime (nodos) | `ItemDrop` vivos en escena / grupo `item_drop` | árbol de escena + `WorldSpatialIndex._runtime_nodes_by_kind` | runtime + cache | `LootSystem.spawn_drop`, `BanditCampStashSystem`, destrucción/pickup | `BanditBehaviorLayer`, `BanditCampStashSystem`, player pickup |
| Cargo bandido | `cargo_count`, `cargo_capacity`, `carried_items_manifest` | `NpcWorldBehavior`/`BanditWorldBehavior` + `CarryComponent` | runtime | `BanditBehaviorLayer`, `BanditCampStashSystem`, `DownedEncounterCoordinator` | `BanditBehaviorLayer`, `BanditWorkCoordinator`, depósitos en stash/barrels |
| Memoria grupal bandida | `_groups[group_id]` (`current_group_intent`, `leader_id`, `last_interest_pos`, etc.) | `BanditGroupMemory` | runtime (parcialmente serializable) | `NpcSimulator` (registro miembros), `BanditGroupIntel` (intent/interés), `RaidFlow` (flags assault), cleanup por runtime | `BanditWorldBehavior`, `BanditBehaviorLayer`, `BanditGroupIntel`, `RaidFlow` |
| Intel de asentamiento (markers) | `_markers` (`workbench`, `copper_mined`, etc.) | `SettlementIntel` | runtime derivado | `SettlementIntel.record_interest_event`, `_scan_workbenches`, señales de placement/resource | `BanditGroupIntel` |
| Intel de asentamiento (bases detectadas) | `_bases` | `SettlementIntel` | derivado | `SettlementIntel` (scan por doors + walls) | `BanditGroupIntel`, consultas `has_detected_base_near` |

---

## 2) Conflictos detectados

### P0 — DOUBLE_TRUTH: hostilidad en dos servicios ✅ RESUELTO (Cut 3)
- **Marcado:** `DOUBLE_TRUTH`
- **Significado duplicado:** “score de hostilidad de facción”.
- **Sitios:**
  1. `FactionHostilityManager` (`_factions`, canónico actual para gameplay).
  2. `FactionRelationService` (`_faction_hostilities`, estado paralelo) **[retirado]**.
- **Impacto:** decisiones divergentes de combate/finish modifier según qué servicio lea cada sistema; alto riesgo de comportamiento inconsistente tras eventos de hostilidad.
- **Riesgo de restauración:** si solo se persiste/rehidrata una fuente, la otra arranca desalineada.
- **Resolución aplicada:**
  - `FactionRelationService` migra a wrapper read-only contra `FactionHostilityManager`.
  - Se elimina el campo espejo `_faction_hostilities`.
  - Cambios de hostilidad se exponen como evento relay (`hostility_score_changed`) conectado desde `FactionHostilityManager.hostility_changed`.
  - Compatibilidad temporal documentada con fecha de retiro del wrapper: **2026-06-30**.

### P1 — CACHE_AS_TRUTH: índice de placeables usado para detectar semántica social
- **Marcado:** `CACHE_AS_TRUTH`
- **Caso:** `SettlementIntel` usa `WorldSpatialIndex.get_all_placeables_by_item_id("workbench")` y `get_placeables_by_item_ids_near(..., ["doorwood"])` para marcar actividad y detectar bases.
- **Riesgo:** si el índice queda stale respecto a `WorldSave.placed_entities_by_chunk`, la facción puede omitir/crear señales de base o workbench erróneas (afecta escalada, extorsión y raid).
- **Impacto:** comportamiento social inconsistente (falsos positivos/negativos en hunting/extorting/raiding).

### P1 — CACHE_AS_TRUTH: índice runtime de loot guía decisiones tácticas
- **Marcado:** `CACHE_AS_TRUTH`
- **Caso:** `BanditBehaviorLayer` decide aproximación/colección de loot usando cachés de drops (`item_drop`) refrescadas por pulso e integración con `WorldSpatialIndex`.
- **Riesgo:** lecturas stale pueden producir jitter (NPC va a loot inexistente) o pérdida de oportunidades de pickup real.
- **Impacto:** inconsistencia táctica visible (IA parece “dudosa” o roba menos/más de lo esperado).

### P2 — Doble ruta de consulta territorial (lógica duplicada)
- **Marcado:** *(no DOUBLE_TRUTH de datos, sí duplicación de regla)*
- **Caso:** `BanditTerritoryQuery.groups_at` y `is_in_territory` recalculan pertenencia territorial por separado.
- **Riesgo:** deriva lógica futura (si se cambia una ruta y no la otra).
- **Impacto:** inconsistencia de detección puntual (intrusión sí/no) en features que usan distinta API.

---

## 3) Priorización por impacto (inconsistencia/restauración)

1. **P0 — Unificar hostilidad en una sola verdad canónica**
   - Mover consumidores de `FactionRelationService` hacia `FactionHostilityManager` o convertir `FactionRelationService` en adapter read-only sin estado.
2. **P1 — Blindar SettlementIntel contra stale cache**
   - En paths críticos (base/workbench), validar contra `WorldSave` cuando hay mismatch de revisión o en eventos estructurales.
3. **P1 — Reglas explícitas de frescura para loot indexado**
   - TTL/invalidation clara + fallback a verificación de nodo vivo antes de decidir estado táctico.
4. **P2 — Consolidar consulta territorial en una única función base**
   - `is_in_territory` debería delegar en `groups_at` (o viceversa) para evitar deriva.

---

## 4) Nota operativa de Cut 3
Este inventario separa **verdad de dominio** (`WorldSave`, managers soberanos) de **proyecciones/aceleradores** (`WorldSpatialIndex`, caches runtime) y marca dónde hoy hay mezcla peligrosa para corrección priorizada en los próximos cuts.
