# Phase 4 Projection Audit — false-ownership patterns

Date: 2026-04-07  
Scope audited: `WorldSpatialIndex`, wall collider projection path, territory/settlement projection path.

## Audit lens

This audit flags places where read models/projections are treated as if they own gameplay truth.

- **Valid projection use**: rebuildable cache/read model; fed from domain writes or canonical persistence; no policy ownership.
- **Architecture smell**: projection data decides canonical policy/writes, or other systems assume projection continuity as required truth.

---

## 1) `WorldSpatialIndex` treated as authoritative state

### A. Projection-valid uses (can remain)

| File | Function(s) | Why valid |
|---|---|---|
| `scripts/world/WorldSpatialIndex.gd` | `get_placeables_in_chunk`, `get_placeables_in_tile_rect`, `_ensure_placeables_cache`, `_rebuild_placeables_cache_full`, `_apply_placeables_cache_change` | Explicitly derives cache from `WorldSave` snapshots/deltas; no canonical ownership writes. |
| `scripts/world/WorldSpatialIndex.gd` | `register_runtime_node`, `update_runtime_node`, `get_runtime_nodes_near`, `get_all_runtime_nodes` | Runtime-node query index only; ephemeral and self-healing. |
| `scripts/resources/*`, `scripts/items/item_drop.gd`, `scripts/placeables/*` | Runtime registration calls (`register_runtime_node`, `update_runtime_node`, `unregister_runtime_node`) | Producer-side feed into projection index (expected). |
| `scripts/world/world.gd` | `_find_nearest_player_placeable_world_pos_by_items` | Query facade over projection, not write authority. |
| `scripts/world/SettlementIntel.gd` | `_scan_workbenches` | Uses index as acceleration while still treating WorldSave as canonical fallback/owner. |

### B. Architecture smells (must migrate)

| File | Function(s) | Smell |
|---|---|---|
| `scripts/world/SettlementIntel.gd` | `_on_placement_completed` -> `_world_spatial_index.notify_placeables_changed(...)` | Projection (`SettlementIntel`) pushes invalidation into another projection (`WorldSpatialIndex`). Event-driven feed is good, but coupling should move to explicit projection feed wiring. |
| `scripts/world/world.gd` | `_tick_player_territory` (`get_all_runtime_nodes(KIND_WORKBENCH)` fallback to tree group) | Territory rebuild input depends on runtime projection continuity rather than only canonical persistence snapshots. |

---

## 2) Wall collider systems treated as authoritative state

### A. Projection-valid uses (can remain)

| File | Function(s) | Why valid |
|---|---|---|
| `scripts/world/ChunkWallColliderCache.gd` | `mark_dirty`, `ensure_for_chunk`, `on_chunk_unloaded` | Canonical wall truth remains tile/persistence domain; collider bodies are rebuildable artifacts with dirty/hash reuse. |
| `scripts/world/WallRefreshQueue.gd` | enqueue/pop/revision helpers | Operational scheduler only; no wall ownership semantics. |
| `scripts/world/world.gd` | `_mark_walls_dirty_and_refresh_for_tiles`, `mark_chunk_walls_dirty`, `_ensure_chunk_wall_collision` | Orchestration path `dirty -> queue -> ensure`; compatible with projection model. |
| `scripts/world/PlayerWallSystem.gd` | `project_building_events`, use of `BuildingColliderRefreshProjection` | Domain events project into collider refresh adapter instead of treating colliders as canonical. |

### B. Architecture smells (must migrate)

| File | Function(s) | Smell |
|---|---|---|
| `scripts/world/ChunkWallColliderCache.gd` | `ensure_for_chunk` writes `WorldSave` flags (`walls_hash`, `walls_dirty`) | Projection cache maintenance writes persistence flags that can be mistaken as canonical wall state instead of projection bookkeeping. |
| `scripts/systems/CombatQuery.gd` | `find_first_wall_hit`, `shape_overlaps_wall`, `is_wall_collider` | Gameplay blockage checks trust collider presence as runtime truth fallback; colliders should not be sole authority where tile/domain truth exists. |
| `scripts/gameplay/slash.gd`, `scripts/weapons/arrow_projectile.gd` | direct branching on `CombatQuery.is_wall_collider(...)` | Damage/block behavior can depend on collider artifact identity instead of wall-domain query contracts. |

---

## 3) Territory / settlement intel structures treated as authoritative state

### A. Projection-valid uses (can remain)

| File | Function(s) | Why valid |
|---|---|---|
| `scripts/world/PlayerTerritoryMap.gd` | `rebuild`, `is_in_player_territory`, `get_zones` | Explicit query model rebuilt from workbench anchors + detected bases; does not persist ownership. |
| `scripts/world/SettlementIntel.gd` | marker/base scan APIs (`record_interest_event`, `get_detected_bases_near`, dirty scans) | Derived intel read model and event indexing; canonical placement/wall writes remain elsewhere. |
| `scripts/world/WorldTerritoryPolicy.gd` | `validate_placement`, `record_interest_event` | Policy owner consumes territory query outputs; does not hand ownership to projections. |
| `scripts/runtime/world/GameplayCommandDispatcher.gd` | `record_interest_event`, `rescan_workbench_markers` routing | Keeps command path explicit and avoids direct world-state ownership inside read models. |

### B. Architecture smells (must migrate)

| File | Function(s) | Smell |
|---|---|---|
| `scripts/world/world.gd` | `_tick_player_territory` with broad query `get_detected_bases_near(Vector2.ZERO, 999999.0)` | Rebuild contract is implicit/global and pull-based; projection lifecycle is owned by world tick heuristics instead of explicit bounded feed inputs. |
| `scripts/world/SettlementIntel.gd` | `_on_placement_completed` emits `record_interest_event("structure_placed", ...)` while also maintaining scan projection state | Mixed role (projection upkeep + behavior-significant event authoring) increases risk of treating intel map as authority. |
| `scripts/systems/local_authority/TavernPresenceMonitor.gd`, `scripts/systems/local_authority/TavernDefensePosture.gd` | direct `BanditTerritoryQuery.is_in_territory(...)` checks | Local authority pressure/posture may inherit implicit authority from territory query snapshots without explicit projection feed semantics. |

---

## 4) Migration map for Phase 4

### Must migrate in Phase 4

1. **Cross-projection coupling cleanup (SpatialIndex <-> SettlementIntel)**
   - Replace direct projection-to-projection invalidation calls with explicit projection feed adapter/event channel.
   - Target path: `SettlementIntel._on_placement_completed -> WorldSpatialIndex.notify_placeables_changed`.

2. **Collider authority tightening in combat/gameplay queries**
   - Ensure gameplay blocking/hit decisions resolve through wall-domain contract first, using collider queries as secondary operational fallback.
   - Target paths: `CombatQuery` wall-hit helpers + direct consumers (`slash`, `arrow_projectile`).

3. **Territory rebuild input explicitness**
   - Replace broad global pull rebuild (`Vector2.ZERO, 999999`) and runtime-node dependence with explicit projection feed/invalidation path.
   - Target path: `world.gd::_tick_player_territory` + corresponding dirty markers.

4. **Projection bookkeeping persistence boundary**
   - Clarify/segregate collider projection metadata (`walls_hash`, `walls_dirty`) from canonical wall truth semantics to avoid false ownership drift.
   - Target path: `ChunkWallColliderCache.ensure_for_chunk` + chunk-flag conventions.

### Can remain temporarily unchanged

1. `WorldSpatialIndex` cache internals and runtime-node indexing, including revision/delta rebuild logic.
2. `ChunkWallColliderCache`/`WallRefreshQueue` operational scheduling and budget behavior.
3. `PlayerTerritoryMap` shape/query implementation itself.
4. `WorldTerritoryPolicy` as policy owner and `GameplayCommandDispatcher` routing façade.
5. Existing `world.gd` façade methods that delegate to policy/intel/query modules (provided no new ownership logic is added).

---

## Recommended execution order (low-risk)

1. Introduce explicit projection feed interfaces (no behavior change).
2. Rewire `SettlementIntel`/`WorldSpatialIndex` and territory rebuild triggers to feed-based invalidation.
3. Tighten combat wall checks to domain-first, collider-second.
4. Rename/document chunk flags used by collider projection bookkeeping to prevent authority drift.
5. Keep parity tests/checklists for walls/colliders and settlement scans during migration.
