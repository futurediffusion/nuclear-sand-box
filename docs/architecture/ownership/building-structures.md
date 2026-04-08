# Constitution: Building / Structures

## Source of truth
- Canonical structural state lives in `WorldSave` structure maps (`placed_entities_*`, wall chunk data) via repositories/adapters. (`scripts/systems/WorldSave.gd`, `scripts/persistence/save/WorldSaveBuildingRepository.gd`)
- Runtime wall/building domain writes are owned by `PlayerWallSystem` + `BuildingSystem`.

## Read models / projections
- Tilemap and collider representations are projections only (`BuildingTilemapProjection`, `WallColliderProjection`, `ChunkWallColliderCache`).

## Allowed writers
- `PlayerWallSystem` for player/structural wall mutations.
- `BuildingSystem` for placeable lifecycle domain writes.
- Persistence adapters/repositories when loading snapshot state.

## Allowed readers
- World query facades and gameplay systems through public APIs.
- Projection systems consuming domain events/change notifications.

## Allowed side effects
- Emit domain events/signals for projection refresh and VFX feedback.
- Mark chunk dirty / enqueue collider refresh / drop wall loot via explicit ports.

## Forbidden writes / authority
- `world.gd` must not mutate structural canonical dictionaries directly.
- Projections/colliders must never become canonical wall/building truth.
- Consumers must not write `WorldSave.placed_entities_by_chunk` or wall maps directly from gameplay scripts outside owners.
