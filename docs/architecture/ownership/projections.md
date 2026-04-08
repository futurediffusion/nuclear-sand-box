# Constitution: Projections

## Source of truth
- Never projections. Canonical truth remains in domain/persistence owners (`WorldSave`, wall/building owners, domain policy systems).

## Read models / projections
- `WorldSpatialIndex`
- `BuildingTilemapProjection`
- `WallColliderProjection` + `ChunkWallColliderCache` + `WallRefreshQueue`
- `TerritoryProjection`

## Allowed writers
- Projection owners may mutate only their own internal caches.
- Input updates must come from explicit domain events, snapshot reload, or invalidation/rebuild flows.

## Allowed readers
- Any subsystem may read projections for query/perf.

## Allowed side effects
- Dirty flags, queue scheduling, cache rebuild, lightweight diagnostics.

## Forbidden writes / authority
- No projection may write canonical persistence as primary responsibility.
- No gameplay policy decision may depend on a projection as sole authority if canonical data exists.
- No ad-hoc cross-system projection mutation (writes must go through owner API only).
