# Phase 4 Closure — Explicit Projections (Historical Record)

> [!WARNING]
> **Historical phase closure artifact.**
> This document captures the projection migration boundary as of Phase 4 closure.
> It has been **superseded by later work** and must **not** be used as current architecture truth.

## Current status after later phases

For current projection and ownership boundaries, use:

- [`docs/architecture/ownership/projections.md`](docs/architecture/ownership/projections.md)
- [`docs/architecture/ownership/persistence.md`](docs/architecture/ownership/persistence.md)
- [`docs/architecture/ownership/territory-settlement.md`](docs/architecture/ownership/territory-settlement.md)
- [`docs/architecture/ownership/README.md`](docs/architecture/ownership/README.md)

Read this file as historical migration evidence only.

## Phase 4 scope that was closed (at that time)

This closure covered explicit projections (spatial index, wall collider refresh, territory read model) and explicitly did not include broader Phase 5 AI normalization.

## Recorded closure state at Phase 4

### Canonical owners recorded at closure (historical)
- Placeables/persisted placement data remained canonical in `WorldSave`.
- Player wall ownership/state remained canonical in building domain + persistence.
- Territory-driving facts were sourced from canonical placeables and `SettlementIntel` snapshots.

### Explicit projection/read-model boundaries (historical)
- `SpatialIndexProjection` for placeable lookup/query acceleration.
- `WallColliderProjection` for physics refresh orchestration.
- `TerritoryProjection` for territory-zone read queries.

### Transitional compatibility retained (historical)
- Compatibility entrypoints (`apply_events`, `apply_change_set`, `apply_snapshot`, `rebuild_from_runtime`) remained.
- Wall collider refresh kept preferred contract path plus fallback dirty-chunk invalidation path.
- Runtime bridge behavior for territory/base dirty marks remained for orchestration compatibility.

## Regression + observability added in Phase 4

- Runner: `scripts/tests/phase4_explicit_projections_regression_runner.gd`
- Added projection debug snapshots on wall collider and territory projections.

## Notes on superseded wording

Any “source of truth (now)” phrasing in Phase 4 materials should be interpreted as “now, **as of Phase 4 closure**,” not as present-day architecture policy.
