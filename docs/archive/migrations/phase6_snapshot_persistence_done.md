# Phase 6 — Snapshot Persistence Closure (Historical Record)

Date recorded: 2026-04-08

> [!WARNING]
> **Historical phase closure artifact.**
> This document records the Phase 6 persistence migration closure state.
> It may be partially superseded by subsequent persistence and compatibility cleanup, and should **not** be treated as the current architecture source of truth by itself.

## Current status after later phases

For current persistence ownership/contracts, use:

- [`docs/architecture/ownership/persistence.md`](../../architecture/ownership/persistence.md)
- [`docs/phase6_snapshot_persistence_contract.md`](phase6_snapshot_persistence_contract.md)
- [`docs/architecture/ownership/README.md`](../../architecture/ownership/README.md)

Use this file as historical migration context.

## Phase 6 scope that was closed (at that time)

Phase 6 closure covered snapshot persistence migration boundary, regression harness coverage, and lightweight save/load observability.

## Recorded closure state at Phase 6

### Canonical saveable boundary at closure time (historical)
- Save/load truth was routed through `WorldSnapshot` and `ChunkSnapshot` payloads.
- Canonical world owners remained in `WorldSave` maps for chunk entities/flags, enemy state/spawns, player walls, placed entities, and global flags.
- Existing serialized domain/system sections persisted by `SaveManager` remained part of the save pipeline.

### Derived state rebuild rule (historical)
- Projections/read models, runtime chunk-streaming internals, and telemetry/debug snapshots were treated as derived and rebuilt/invalidated after load.
- These remained explicitly non-canonical for persistence.

### Compatibility retained at closure (historical)
- Compatibility with prior save payload sections remained.
- Restore precedence paths retained snapshot + compatibility-envelope + legacy fallback ordering.
- Legacy placed-entity migration fallback remained active.

### Legacy persistence paths intentionally retained at closure (historical)
- `chunk_save` and legacy `worldsave_*` sections remained for old save compatibility during stabilization.

## Regression + observability added in Phase 6

- Runner: `scripts/tests/phase6_snapshot_persistence_regression_runner.gd`
- Added `SaveManager` save/load pipeline snapshot accessors for path/counter observability.

## Notes on superseded wording

Any definitive language in this file should be interpreted as “definitive for Phase 6 closure,” not as a guarantee that no later persistence architecture changes occurred.
