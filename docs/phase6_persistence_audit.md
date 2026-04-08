# Phase 6 Persistence Audit: Runtime-Scattered Dependencies

## Scope
This audit maps current save/load behavior and identifies where persistence depends on runtime-oriented structures (`Node` instances, live tilemaps, mutable caches, compatibility bridges) instead of canonical snapshot state.

Reviewed primary files:
- `scripts/systems/SaveManager.gd`
- `scripts/world/world.gd`
- `scripts/world/EntitySpawnCoordinator.gd`
- `scripts/world/PlayerWallSystem.gd`
- `scripts/world/StructuralWallPersistence.gd`
- `scripts/world/PropSpawner.gd`
- `scripts/projections/index/SpatialIndexProjection.gd`
- `scripts/projections/territory/TerritoryProjection.gd`
- `scripts/projections/tilemap/BuildingTilemapProjection.gd`
- `scripts/projections/collision/WallColliderProjection.gd`
- `scripts/systems/WorldSave.gd`

---

## 1) Current save logic: where it reads from runtime vs canonical owners

## Save entrypoint
- `SaveManager.save_world()` is the single save serializer and mixes:
  - direct canonical maps (`WorldSave.*` dictionaries),
  - world-owned runtime dictionary (`_world.chunk_save`),
  - runtime-to-canonical flush (`entity_coordinator.snapshot_entities_to_world_save()`),
  - subsystem serializers (`FactionSystem`, `SiteSystem`, `NpcProfileSystem`, etc.),
  - live player runtime state (`player.global_position`, inventory component slots/gold).

## Runtime-coupled pre-save flushes
- `SaveManager` explicitly depends on live `entity_coordinator` and `get_save_state()` on runtime nodes via `snapshot_entities_to_world_save()`.
- In `EntitySpawnCoordinator.snapshot_entities_to_world_save()` only currently tracked runtime nodes in `chunk_saveables` are snapshotted; non-loaded/non-tracked entities rely on already-persisted state.
- This creates a correctness dependency on runtime chunk residency and tracking coverage at save time.

## Direct serialized buckets
- Canonical-ish serialized now:
  - `WorldSave.chunks`, `enemy_state_by_chunk`, `enemy_spawns_by_chunk`, `global_flags`, `player_walls_by_chunk`, `placed_entities_by_chunk`, `placed_entity_data_by_uid`.
- Runtime-scattered serialized now:
  - `_world.chunk_save` (procedural/resource/placements/placed_tiles mix),
  - player runtime transform/inventory component fields,
  - subsystem state with heterogeneous contracts (good pragmatically, but not unified snapshot schema).

## Tilemap/cache/runtime artifacts not directly serialized
- Projection caches (`SpatialIndexProjection`, territory zones, collider/tilemap projection internals) are not serialized directly (good boundary).
- But some canonical data still depends on runtime-to-canonical reconciliation before save (notably entity saveables).

---

## 2) Current load logic: where reconstruction is runtime-oriented

## Save file decode and owner assignment
- `SaveManager.load_world_save()` restores dictionaries directly into global owners (`WorldSave.*`) and copies `chunk_save` into `world.chunk_save`.
- Placed entity load path includes legacy migration fallback from `placed_entities` array to chunk map.

## Runtime reconstruction after load
- `world.gd::_ready()` calls `SaveManager.load_world_save()` early, then runtime systems are created and fed with restored state references.
- `EntitySpawnCoordinator.enqueue_prefetched_jobs()` and chunk load paths rebuild runtime nodes by loading scenes from persisted paths and chunk data.
- Placeables are rebuilt from `WorldSave.get_placed_entities_in_chunk(...)`, then runtime instances are registered in `PlacementSystem`.
- Player walls are reconstructed by `PlayerWallSystem.apply_saved_walls_for_chunk(...)`, then tilemap/collider projections are refreshed.

## Runtime-source compatibility bridges (load/rebuild smell)
- `TerritoryProjection` keeps compatibility API `rebuild_from_runtime(...)` and resolves anchors from `Node2D` when present.
- `world.gd::_collect_player_workbench_projection_anchors()` has runtime group fallback (`get_nodes_in_group("workbench")`) when spatial index is unavailable.
- These are practical bridges but reintroduce runtime-dependency in reconstruction behavior.

---

## 3) Areas that already resemble canonical snapshot persistence

- `WorldSave` chunked maps for placeables and walls are already explicit canonical stores with helper APIs and change serials.
- `SpatialIndexProjection` is a clean derived projection fed from `WorldSave` revisions/change log and can fully rebuild from canonical state.
- Building projections (`BuildingTilemapProjection`, `WallColliderProjection`) are projection-only refresh layers and do not claim authority.
- `WorldSaveBuildingRepository` provides a clear domain persistence adapter for building structures (good boundary direction).
- Multiple subsystem serializers (`serialize()/deserialize()`) already function as bounded persistence contracts, even if not unified into one snapshot schema yet.

---

## 4) Architecture smells for sandbox persistence

1. **Dual authority between `chunk_save` and `WorldSave`**
   - `chunk_save` contains long-lived game state (resources, placements, placed_tiles) parallel to canonical maps in `WorldSave`.
   - This splits persistence authority and increases migration/consistency burden.

2. **Save correctness depends on runtime-loaded nodes**
   - Entity state requires pre-save runtime harvesting from live nodes.
   - Any untracked runtime entity or timing gap can skew saved state.

3. **Runtime compatibility fallbacks in projection inputs**
   - Territory/workbench logic can source from scene tree groups instead of canonical snapshots.
   - Useful for compatibility, but weakens deterministic replay from save alone.

4. **Heterogeneous persistence contract shape**
   - Save payload is an aggregate of ad-hoc sections (`chunk_save`, `WorldSave.*`, subsystem snapshots) without a single explicit `WorldSnapshot` contract envelope yet.

5. **Scene-path runtime reconstruction coupling**
   - Load paths instantiate placeables/props from stored scene paths and runtime registries.
   - Works today, but tightens persistence format to runtime asset/layout assumptions.

---

## 5) Highest-priority systems for snapshot migration

## Priority A (first)
1. **Unify canonical world payload around `WorldSave` + explicit world snapshot envelope**
   - Define snapshot sections that replace implicit mixed roots (`chunk_save` + `WorldSave.*`).
2. **Entity saveable flow (`EntitySpawnCoordinator` runtime harvest dependency)**
   - Move from “save-time runtime scrape” to explicit canonical entity state ownership/update flow.

## Priority B (next)
3. **`chunk_save` decomposition**
   - Split into canonical sections (resource/node states, structural placements) with explicit ownership.
4. **Territory/workbench projection input contract hardening**
   - Remove runtime node/group fallback from persistence-critical rebuild paths.

## Priority C (after core migration)
5. **Subsystem snapshot normalization**
   - Keep existing serializers but wrap under versioned, typed snapshot sections.
6. **Scene-path coupling reduction**
   - Introduce stable type IDs/catalog mapping where practical for placeables/props.

---

## 6) Parts that can remain temporarily compatible

These compatibility paths are acceptable during migration if explicitly marked transitional:
- Legacy placed entities array fallback migration in `SaveManager.load_world_save()`.
- Territory projection runtime fallback (`get_nodes_in_group("workbench")`) as non-authoritative backup.
- Existing `serialize()/deserialize()` subsystem contracts while wrapped into new snapshot envelope.
- Scene-path based spawn reconstruction for existing content, provided canonical identity/state is separated first.

---

## Migration map (concise)

1. Introduce `WorldSnapshot` top-level schema (versioned, explicit sections).
2. Map current `WorldSave.*` owners into snapshot sections (mostly direct lift).
3. Decompose `chunk_save` into named canonical sections; stop persisting raw mixed `chunk_save` blob.
4. Replace pre-save runtime scrape with canonical entity-state ownership updates (save becomes pure encode).
5. Harden load to: decode snapshot -> apply canonical owners -> rebuild projections/runtime deterministically.
6. Keep listed compatibility shims behind explicit “temporary bridge” markers until cutover.

