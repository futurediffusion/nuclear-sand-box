# Phase 6 — Snapshot persistence closure

Date: 2026-04-08

This closes Phase 6 persistence migration with a canonical snapshot boundary, regression harness coverage, and lightweight save/load observability.

## Canonical saveable state (authoritative)

Canonical save/load truth now flows through `WorldSnapshot` and chunk-level `ChunkSnapshot` payloads:

- Save/session metadata: `snapshot_version`, `save_version`, `seed`, player position/inventory/gold, run/world time.
- Canonical world owners in `WorldSave`: chunk entities/flags, enemy state, enemy spawns, player walls (as normalized structures), placed entities, placed per-uid data, global flags.
- Existing domain/system serialized sections already persisted by `SaveManager` (factions/site/profile/group memory/extortion/hostility).

Primary code:
- `scripts/core/WorldSnapshot.gd`
- `scripts/core/ChunkSnapshot.gd`
- `scripts/persistence/save/WorldSaveAdapter.gd`
- `scripts/persistence/save/ChunkSnapshotSerializer.gd`

## Derived state rebuilt after load (non-canonical)

The following remain derived/read-model/runtime and are rebuilt or invalidated from canonical owners after load:

- Projections/read models (spatial index, territory, wall collider/tilemap projection layers).
- Runtime chunk-streaming internals (loaded chunk sets, stage queues, perf windows, spawn jobs).
- Telemetry/debug snapshots and counters.

Rule maintained: these structures **must not** act as save truth.

## Compatibility that remains

- `SaveManager` keeps compatibility with existing save payload sections while canonical snapshots are primary.
- Snapshot restore order remains:
  1) `snapshot_version` (`WorldSnapshot`) path
  2) `world_snapshot_state` compatibility envelope
  3) legacy `worldsave_*` payload fallback
- Legacy placed entity migration fallback (`placed_entities` array -> chunked map) remains active.

## Legacy persistence paths still present

Still present intentionally for compatibility:

- `chunk_save` section in save file (world runtime chunk payload section).
- `worldsave_chunks`, `worldsave_enemy_state`, `worldsave_enemy_spawns`, `worldsave_global_flags`, `worldsave_player_walls`.
- `world_snapshot_state` compatibility envelope.

These are kept to avoid breaking older save files while canonical snapshot contracts are stabilized.

## Regression protection added (Phase 6 harness)

New regression runner:
- `scripts/tests/phase6_snapshot_persistence_regression_runner.gd`

Covered assertions:
- snapshot construction from canonical `WorldSave` state.
- world snapshot serialization/deserialization roundtrip.
- load reconstruction into canonical owners (`WorldSave` maps).
- post-load projection rebuild (`SpatialIndexProjection.rebuild_from_source`).
- prevention of runtime/projection-derived mutations becoming save truth.

## Save/load observability added

`SaveManager` now records lightweight pipeline snapshots for debugging:

- `get_last_save_pipeline_snapshot()`
- `get_last_load_pipeline_snapshot()`

Each snapshot exposes compact counters (`chunk_count`, `structure_count`, `placed_entity_count`) plus source path (`save_world`, `world_snapshot`, `world_snapshot_state`, `legacy_worldsave_payload`) to make save/load path decisions visible without persisting runtime caches.

## Future persistence work still pending

Phase 6 is closed, but follow-up work may include:

- Gradual retirement plan for legacy payload sections once old save compatibility window is closed.
- Optional schema/version migration helpers for future snapshot version bumps.
- Additional deterministic load validation around high-scale chunk windows and long-running sessions.
