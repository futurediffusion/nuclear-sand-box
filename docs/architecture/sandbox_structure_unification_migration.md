# Sandbox Structure / Placeable Unification (Incremental Migration)

Date: 2026-04-08

## Objective

Unify the language for sandbox-owned structure-like world objects (player walls, structural walls, and placed buildables/placeables) without a large rewrite and without changing gameplay behavior.

---

## 1) Audit of current families and overlap

### A. Player walls
- **Ownership:** player-owned sandbox structures.
- **Persistence:** `WorldSave.player_walls_by_chunk` (`tile_key -> {"hp": int}`).
- **HP/removal semantics:** canonical wall HP + remove on zero, routed through `BuildingWallWorkflow`/`BuildingSystem` and persisted via `WorldSaveBuildingRepository`.
- **Projection requirements:** tilemap + wall collider projections from building events/snapshots.
- **Query API:** `BuildingState`, `BuildingWallWorkflow`, `PlayerWallSystem` and `WorldSave.list_player_walls_in_chunk`.

### B. Structural walls (non-player walls)
- **Ownership:** sandbox/environment-owned structure tiles.
- **Persistence:** `chunk_save[chunk_pos]["placed_tiles"]` entries with `layer/tile/source/atlas/hp` in `StructuralWallPersistence`.
- **HP/removal semantics:** ad-hoc in `PlayerWallSystem.damage_structural_wall_at_tile` + `StructuralWallPersistence`.
- **Projection requirements:** same wall tilemap/collider outcome path as player walls, but with separate persistence shape.
- **Query API:** `StructuralWallPersistence.get_wall/load_chunk_walls`.

### C. Placeables/buildables (entity placeables)
- **Ownership:** typically player-owned placed entities.
- **Persistence:** `WorldSave.placed_entities_by_chunk` + `WorldSave.placed_entity_data_by_uid`.
- **HP/removal semantics:** specialized per component (`ContainerPlaceable`, `WorkbenchComponent`, etc.).
- **Projection requirements:** spatial index projection/read model, plus runtime node lifecycle.
- **Query API:** `WorldSave.get_placed_entities_in_chunk`, `WorldSpatialIndex`, and per-system lookups.

### Overlap pain points
- Parallel persistence schemas for wall-like objects.
- Different record shapes for objects that all behave as chunk-owned structures.
- Fragmented query/read-model entry points.
- Duplicate HP/removal concepts expressed differently by family.

---

## 2) Canonical unified boundary introduced

### New canonical contract
- Added `SandboxStructureContract` as the shared structure-record language for structure-like objects.
- Canonical fields include:
  - `structure_id`, `kind`, `owner`, `chunk_pos`, `tile_pos`, `hp`, `max_hp`, `metadata`, `persistence_bucket`.
- Canonical kinds:
  - `player_wall`
  - `structural_wall`
  - `placeable`

This is a **unification layer**, not a persistence rewrite. Existing stores remain source-of-truth and are adapted into the canonical contract.

### New unification repository
- Added `SandboxStructureRepository` for chunk-scoped unified reads across:
  - player walls (`WorldSave.player_walls_by_chunk`),
  - structural walls (`StructuralWallPersistence`),
  - optional placeables (`WorldSave.placed_entities_by_chunk` + UID data).

---

## 3) What is now unified

1. **Common structural contract** for wall/placeable-like objects via `SandboxStructureContract`.
2. **Wall persistence shape bridging** improved:
   - `WorldSaveBuildingRepository` now normalizes through the shared contract for player-wall canonicalization.
   - `StructuralWallPersistence` exports canonical structure records via `load_chunk_structure_records`.
3. **Projection-facing payload convergence** for snapshot rebuild path:
   - world snapshot rebuild now collects loaded-chunk structural payloads through `SandboxStructureRepository` (player + structural walls in one structure language) before projection rebuild.
4. **Chunk ownership representation convergence** at the boundary:
   - all structure-like records are exposed chunk-scoped with common `chunk_pos`/`tile_pos` identity.

---

## 4) What remains intentionally specialized (for now)

1. **Underlying persistence stores remain split** for compatibility and migration safety:
   - player walls in `WorldSave.player_walls_by_chunk`;
   - structural walls in `chunk_save.placed_tiles` via `StructuralWallPersistence`;
   - placeables in `WorldSave.placed_entities_*`.
2. **Placeable runtime behavior remains specialized**:
   - component-specific damage/drop/inventory behavior is preserved.
3. **Building command/event pipeline remains wall-focused**:
   - no forced rewrite of placeable domain/event model in this step.

---

## 5) Compatibility and migration stance

- Save/load compatibility is preserved because canonical stores were not replaced.
- The unification layer is additive and explicit.
- Migration can proceed incrementally by moving call sites to canonical repository/contract APIs over time.

---

## 6) Next incremental steps (non-breaking)

1. Route additional structure queries (raid target selection, settlement scans) through `SandboxStructureRepository`.
2. Introduce optional shared HP adapter for breakable placeables using the same canonical structure record fields.
3. Expand snapshot adapters to include structural wall records directly where beneficial, still preserving legacy schemas.

