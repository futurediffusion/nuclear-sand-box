# Building Vertical Slice Contract (Walls)

## Scope
Phase 2 contract for the walls/building vertical slice. This document defines boundaries for implementation without changing runtime behavior yet.

---

## 1) Source of truth for walls/building state

### Canonical runtime owner
- `PlayerWallSystem` is the **domain owner** for wall placement, damage, removal, ownership reconciliation, and wall-related drops/feedback triggers.
- `world.gd` is **not** the owner of wall rules; it remains a façade/orchestrator.

### Canonical persistence
- **Player-built walls**: `WorldSave.player_walls_by_chunk` via `WallPersistence` (`hp` schema preserved).
- **Structural/non-player walls**: `chunk_save[chunk].placed_tiles` entries with `source = -1` via `StructuralWallPersistence`.

### Derived views (not source-of-truth)
- `StructureWallsMap` tile content is a projection of persisted wall state (plus terrain-connect visuals), and can be reconciled/cleaned from persistence.
- Chunk wall colliders are projection cache artifacts and are disposable/rebuildable.

---

## 2) Domain commands for the module

Commands are gameplay-facing intent APIs routed by `world.gd` through `GameplayCommandDispatcher` to `PlayerWallSystem`.

- `can_place_player_wall_at_tile(tile_pos)`
- `place_player_wall_at_tile(tile_pos, hp_override = -1)`
- `damage_player_wall_from_contact(hit_pos, hit_normal, amount = 1)`
- `damage_player_wall_near_world_pos(world_pos, amount = 1)`
- `damage_player_wall_at_world_pos(world_pos, amount = 1)`
- `damage_player_wall_in_circle(world_center, world_radius, amount = 1)`
- `hit_wall_at_world_pos(world_pos, amount = 1, radius = 20.0, allow_structural_feedback = true)`
- `damage_player_wall_at_tile(tile_pos, amount = 1)`
- `remove_player_wall_at_tile(tile_pos, drop_item = true)`

Contract rule:
- New wall/building write operations must be introduced as commands at this boundary (dispatcher route), not as ad-hoc mutations in `world.gd`.

---

## 3) Domain events for the module

Current event contract (signals emitted by `PlayerWallSystem`):
- `player_wall_hit(tile_pos)`
- `structural_wall_hit(tile_pos)`
- `player_wall_drop(tile_pos, item_id, amount)`
- `structural_wall_drop(tile_pos, item_id, amount)`

Usage in current slice:
- `world.gd` subscribes for world-level side effects (incident/intel/territory hooks).
- Feedback/audio/drop visuals are still executed from `PlayerWallSystem` + `WallFeedback`, while emitted events are the integration contract for other modules.

Event rule:
- Consumers react to events; they must not mutate wall persistence directly.

---

## 4) Projections derived from wall state

1. **Tilemap projection** (`StructureWallsMap`)
   - Applied/reconnected from wall state (`apply_saved_walls_for_chunk`, strict apply + orphan cleanup).
   - Visual terrain-connect output is treated as projection output, not canonical data.

2. **Collider projection** (chunk-level)
   - `mark_chunk_walls_dirty` marks chunk cache dirty.
   - `WallRefreshQueue` enqueues loaded chunks.
   - `ChunkWallColliderCache.ensure_for_chunk` rebuilds/serves collider cache on demand.

3. **Spatial/AI hooks (current minimal contract)**
   - Wall-nearest/sample queries exposed by `world.gd` façade (`find_nearest_player_wall_world_pos`, etc.) remain read-model hooks for AI systems.
   - No new persistent spatial index for walls is required in this phase.

Projection rule:
- If projections diverge, rebuild from persistence/state owner; do not promote projection artifacts to source-of-truth.

---

## 5) Temporary legacy compatibility plan with `PlayerWallSystem`

Compatibility to preserve during migration tasks:
- Keep existing public wall commands on `world.gd` unchanged (wrappers), delegating to dispatcher.
- Keep transition ports/adapters used by `PlayerWallSystem.setup(...)`:
  - coordinate transform port
  - chunk dirty notifier port
  - projection refresh port
- Keep legacy audio config compatibility accepted by `PlayerWallSystem.configure_audio(...)` while preferring SoundPanel-driven resolution.
- Keep persistence schemas unchanged (`{ "hp": int }` for player walls; structural placed-tile format for structural walls).

Exit condition for this compatibility layer (later phase):
- Callables-only fallback paths can be removed after all wall command/integration call sites use typed ports and dispatcher path.

---

## 6) `world.gd`: allowed vs must stop doing

### Allowed (in this slice)
- Dependency wiring and setup of wall-related services.
- Public façade methods that delegate wall commands to `GameplayCommandDispatcher`.
- Projection orchestration only:
  - dirty marking
  - queueing collider refresh
  - ensuring chunk collider projection
- Subscribing to wall domain events and forwarding to other systems (intel/territory/authority).

### Must stop (and remain stopped)
- Direct wall domain decisions in `world.gd` (placement validity, hp math, ownership reconciliation, drop rules, wall tile ownership arbitration).
- Direct writes to wall persistence stores outside `PlayerWallSystem`/persistence adapters.
- Adding new wall gameplay rules in `_process`, `_ready`, or miscellaneous world helpers.

---

## 7) Non-goals for Phase 2

- No full rewrite of world architecture.
- No replacement of chunk pipeline, spawn systems, or unrelated AI/social subsystems.
- No persistence schema migration.
- No runtime behavior changes in this documentation task.
- No cross-system refactor outside walls/building vertical slice boundaries.

---

## Migration sequence (next implementation tasks)

1. **Lock boundaries in code comments/checklists**
   - Keep `world.gd` as façade + orchestration only for wall commands.

2. **Command/event naming stabilization**
   - Ensure all new wall/building writes enter through dispatcher command path.
   - Keep event consumers on signals rather than persistence pokes.

3. **Projection hardening**
   - Standardize tilemap/collider rebuild trigger path around dirty-mark + queue + ensure.

4. **Legacy adapter reduction (incremental)**
   - Migrate remaining callable fallback call sites toward typed ports, one integration at a time.

5. **Only then evaluate behavior-preserving cleanup**
   - Remove dead compatibility branches once all callers are migrated and verified.
