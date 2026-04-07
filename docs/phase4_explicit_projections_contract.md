# Phase 4 Explicit Projections Contract

## Scope
This contract defines Phase 4 boundaries so spatial index data, wall colliders, and player/settlement territory are treated as **explicit projections** (read models), not primary state owners.

This document is boundary-only:
- no runtime behavior redesign,
- no broad engine refactor,
- no unrelated system changes.

---

## 1) Source of truth in this phase

For Phase 4, source-of-truth remains in existing domain/persistence owners:

- **Placed entities / placeables**: `WorldSave` placed-entity data (`placed_entities_by_chunk`, change serial, chunk deltas), written through existing placement/building flows.
- **Walls (player + structural)**: wall domain + persistence owners (`PlayerWallSystem`, wall persistence adapters, `WorldSave` wall/chunk flags).
- **Domain events that describe writes**: existing gameplay command/event paths (`GameplayCommandDispatcher`, `PlacementSystem`, `PlayerWallSystem` signals).
- **Territory policy decisions**: `WorldTerritoryPolicy` (validation/reaction policy), not cache/query structures.

Rule: if state can be rebuilt from domain owners and persistence, it is not source-of-truth.

---

## 2) What is a projection/read model

A projection in this phase is any structure that:
- exists to accelerate queries or integration,
- is rebuildable/invalidatable,
- does not define canonical gameplay ownership.

In-scope Phase 4 projections:
- `WorldSpatialIndex` runtime buckets + derived placeable caches,
- wall collider projection artifacts (`ChunkWallColliderCache`, `WallRefreshQueue`, refresh wiring),
- player/settlement territory query models (`PlayerTerritoryMap`, SettlementIntel-derived base/workbench views used for territory queries).

---

## 3) Roles of key projection components

### `WorldSpatialIndex`
Role: query/read acceleration for nearby runtime nodes and derived placeable lookup.

- Maintains chunked runtime-node indexes (drops/resources/workbenches/storage).
- Maintains derived cache views over persistent placeables for query efficiency.
- Can subscribe to write-side signals for invalidation/sync.
- Must be treated as disposable/rebuildable cache, never canonical entity ownership.

### Wall collider cache / refresh systems
Role: physics projection maintenance.

- `ChunkWallColliderCache` materializes/reuses chunk collider bodies from wall tile state.
- `WallRefreshQueue` prioritizes and throttles refresh work.
- Refresh entrypoints (e.g. `refresh_wall_collision_for_tiles` / projection refresh adapter) coordinate dirty-mark + enqueue + ensure flow.
- Colliders and queue state are operational artifacts only; wall truth remains in wall domain/persistence.

### Player territory / settlement territory structures
Role: territory read model for queries and reactions.

- `PlayerTerritoryMap` is a rebuilt query map from current workbench anchors + detected enclosed bases.
- Settlement/base marker datasets used by territory checks are derived views (from settlement scans/events), not canonical ownership tables.
- Territory structures answer “is this in territory?” and expose zones; they do not own placement rights or persistence.

---

## 4) Allowed inputs for projections

Projections may consume only:

1. **Domain write events / command outcomes**
   - placement completed/removed,
   - wall changed/damaged/removed,
   - explicit interest/scan dirty signals.

2. **Canonical persisted state snapshots/deltas**
   - `WorldSave` placed-entity data,
   - wall chunk flags and persisted wall data.

3. **Deterministic transform/context dependencies**
   - world↔tile conversion,
   - chunk sizing,
   - loaded-chunk visibility for runtime-only refresh scheduling.

Not allowed as projection input: other projection outputs as implicit truth without invalidation/rebuild path.

---

## 5) What projections must never do

Projections must never:

- decide or enforce gameplay policy as canonical authority,
- perform direct domain writes to canonical persistence as their primary responsibility,
- require perfect continuity (must tolerate clear/rebuild),
- become hidden coupling points where unrelated systems mutate them ad hoc,
- be used as the only source to recover persistent game state.

---

## 6) What `world.gd` is still allowed to do in Phase 4

`world.gd` remains orchestration-only and may:

- wire projection dependencies and adapters,
- forward command/event traffic to owning systems,
- trigger projection invalidation/refresh orchestration (`dirty` marks, queue pulses, ensure calls),
- tick projection maintenance loops with budget/cadence,
- expose façade query methods that delegate to projection systems.

`world.gd` must not reintroduce domain ownership logic for spatial indexing, wall authority, or territory policy.

---

## 7) Migration sequence for upcoming Phase 4 tasks

1. **Boundary lock**
   - Confirm all three areas are documented/treated as projections (this contract).

2. **Explicit input paths**
   - Ensure each projection has explicit feed points from domain events or canonical state snapshots.
   - Remove/avoid ad-hoc implicit writes.

3. **Invalidation and rebuild clarity**
   - Standardize “mark dirty → schedule refresh → rebuild/ensure” behavior for colliders and territory/spatial caches.

4. **Call-site tightening in `world.gd`**
   - Keep `world.gd` as wiring/tick façade; move any remaining ownership-like decisions to existing owner systems.

5. **Parity checks (no behavior refactor)**
   - Validate that projection rebuilds match current runtime outcomes.
   - Keep gameplay behavior unchanged while boundaries become explicit.

6. **Follow-up cleanup**
   - After parity confidence, remove redundant legacy projection mutation paths (only those within Phase 4 scope).

---

## Boundary summary

Phase 4 target boundary:

`Domain writes + persistence owners` → `explicit projection feeds` → `projection caches/read models` → `query consumers`

Where:
- canonical truth stays with domain/persistence owners,
- projections stay rebuildable and policy-neutral,
- `world.gd` stays as composition/orchestration façade.
