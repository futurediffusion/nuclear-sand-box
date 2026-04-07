# Phase 4 Closure — Explicit Projections

This closes the Phase 4 migration scope for explicit projections (spatial index, wall collider refresh, and territory read model) without starting Phase 5 AI normalization.

## Source of truth (now)

- **Placeables and persisted placement data** remain canonical in `WorldSave` (`placed_entities_by_chunk`, `placed_entity_chunk_by_uid`, revisions/change log).
- **Player wall ownership/state** remains canonical in building/domain + persistence (`BuildingState`/`PlayerWallSystem`/`WorldSave.player_walls_by_chunk`).
- **Territory-driving facts** remain canonical at input boundaries:
  - workbench presence from canonical placeables snapshots,
  - enclosed base detections from `SettlementIntel` snapshot outputs.

## What became an explicit projection / read model

- `SpatialIndexProjection` is the explicit read model for placeable lookups and chunk/item query acceleration.
- `WallColliderProjection` is the explicit physics refresh projection for collider dirty/rebuild scope orchestration.
- `TerritoryProjection` is the explicit read model for territory zone queries (`workbench` radius + enclosed-base derived zones).

## Compatibility that remains

- Existing compatibility entrypoints stay active (`apply_events`, `apply_change_set`, `apply_snapshot`, `rebuild_from_runtime`) while routing through explicit projection classes.
- Wall collider refresh keeps dual path wiring:
  - preferred `WorldProjectionRefreshContract` refresh,
  - fallback `WorldChunkDirtyNotifierContract` chunk dirty invalidation.
- Runtime-side bridge behavior (territory/base dirty marks from wall projection updates) remains to preserve current world orchestration behavior.

## Regression protection and observability added in this closure

- Added deterministic Phase 4 harness: `scripts/tests/phase4_explicit_projections_regression_runner.gd`.
  - Covers rebuild/sync flow for `SpatialIndexProjection` from canonical `WorldSave` data.
  - Covers `WallColliderProjection` refresh scope and fallback dirty-chunk invalidation.
  - Covers `TerritoryProjection` rebuild-from-sources contract.
  - Asserts projection outputs do **not** become canonical truth (projection invalidation/copies do not mutate canonical ownership).
- Added lightweight projection observability snapshots:
  - `WallColliderProjection.get_debug_snapshot()` for apply source/scope/fallback state.
  - `TerritoryProjection.get_debug_snapshot()` for rebuild counters and zone totals.

## Remaining migration work (later phases, out of Phase 4 scope)

- Remove remaining transitional compatibility wiring only after parity confidence in runtime environments.
- Continue cleanup of cross-projection coupling and feed channels where still legacy-bridged.
- Address broader AI/authority normalization and behavior-layer ownership in **later phases** (explicitly not part of this closure).
