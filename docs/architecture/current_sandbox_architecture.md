# Current Sandbox Architecture (Source of Truth)

This document defines the **current** architecture of the sandbox runtime.
It is the canonical architecture reference for contributors and agents.

Historical phase/migration context is intentionally out of scope.

---

## 1) System boundary map (current)

The runtime is split into four ownership layers:

1. **World orchestration**: composition, lifecycle, tick cadence, subsystem wiring.
2. **Canonical domain state**: gameplay decisions and authoritative write paths.
3. **Derived projections/read-models**: rebuildable query/visual/collider views.
4. **Snapshot persistence**: canonical save/load schema, versioning, migrations.

Rule: architecture changes must preserve this separation. Cross-layer writes are only valid through explicit owner APIs.

---

## 2) `world.gd` current role

Primary file: `scripts/world/world.gd`.

`world.gd` is the **runtime composition and orchestration root**. It owns:

- subsystem bootstrap and dependency wiring,
- tick/lifecycle scheduling,
- delegation into command/domain/projection owners,
- orchestration telemetry and diagnostics snapshots.

`world.gd` does **not** own canonical gameplay truth for structures, AI policy, or persistence payload schemas.

---

## 3) Canonical structure/building ownership

Canonical building/structure ownership is in the building domain and repositories:

- `scripts/domain/building/BuildingCommands.gd`
- `scripts/domain/building/BuildingSystem.gd`
- `scripts/domain/building/BuildingState.gd`
- `scripts/domain/building/BuildingEvents.gd`
- `scripts/domain/building/BuildingRepository.gd`
- `scripts/persistence/save/WorldSaveBuildingRepository.gd`
- `scripts/domain/building/SandboxStructureContract.gd`
- `scripts/world/SandboxStructureRepository.gd`

Authority model:

- Domain systems/repositories own canonical writes.
- Runtime and projections consume domain outputs/events.
- `world.gd` and gameplay scripts outside the owner APIs must not directly mutate structural canonical dictionaries.

Canonical structure payload vocabulary is unified under `SandboxStructureContract` (for example: `structure_id`, `kind`, `owner`, `chunk_pos`, `tile_pos`, `hp`, `max_hp`, `metadata`, `persistence_bucket`).

---

## 4) Projection model and source-of-truth rules

Current explicit projections:

- `scripts/projections/tilemap/BuildingTilemapProjection.gd`
- `scripts/projections/collision/WallColliderProjection.gd`
- `scripts/projections/territory/TerritoryProjection.gd`

Projection rules:

- Projections are **derived and rebuildable** read-models.
- They may keep internal caches/dirty queues for performance.
- Projection inputs must come from canonical domain changes, snapshot reloads, or explicit invalidation/rebuild flows.
- Projections are never promoted to canonical persistence or policy authority when canonical data exists.

Canonical gameplay flow for structures remains:

**command -> domain write/event -> projection refresh -> snapshot persistence**

---

## 5) Bandit AI pipeline ownership

The bandit AI architecture is stage-owned and explicit:

1. **Perception** (`BanditPerceptionSystem` and perception memory owners)
2. **Intent** (`BanditIntentSystem` / policy outputs)
3. **Task planning** (`BanditTaskPlanner`, `BanditGroupBrain` assignment authority)
4. **Execution runtime** (`BanditBehaviorLayer`, `BanditWorldBehavior`, related directors)

Ownership constraints:

- Each stage writes only its own stage state.
- Downstream stages may read upstream outputs.
- Execution performs actuation/side effects; it does not own high-level intent policy thresholds.
- Hidden single-module logic that mixes Perception+Intent+Task+Execution is a boundary violation.

---

## 6) Snapshot persistence ownership, versioning, and migration

Canonical persistence components:

- `scripts/core/WorldSnapshot.gd`
- `scripts/core/ChunkSnapshot.gd`
- `scripts/persistence/save/WorldSnapshotSerializer.gd`
- `scripts/persistence/save/WorldSnapshotVersioning.gd`
- `scripts/persistence/save/WorldSaveAdapter.gd`
- `scripts/systems/SaveManager.gd`

Current rules:

- Save/load authority is snapshot-based (`WorldSnapshot` contract).
- Snapshots include explicit `snapshot_version`.
- Version transitions are deterministic and stepwise through `WorldSnapshotVersioning` migrations.
- Legacy formats may be ingested only through explicit one-way migration into canonical snapshot contracts.
- Runtime/projection caches are non-canonical and must not be persisted as authoritative game state.

---

## 7) Diagnostics and telemetry boundaries

Diagnostics/telemetry are runtime observability surfaces, not domain or persistence authority.

Allowed boundaries:

- Orchestration counters/snapshots may be written by world/bootstrap owners.
- Domain/pipeline/projection owners may emit lightweight stage diagnostics and transition warnings.
- Compatibility bridges must be instrumented (warnings/counters) while active.

Forbidden boundary crossings:

- Diagnostic payloads are not canonical gameplay state.
- Telemetry/debug snapshots must not become persistence truth.
- No gameplay policy should rely exclusively on debug counters when canonical state is available.

---

## 8) Explicit legacy/deprecated surfaces (current)

Known remaining compatibility surfaces include:

- `scripts/world/PlayerTerritoryMap.gd` (legacy wrapper over territory projection)
- `scripts/projections/collider/BuildingColliderRefreshProjection.gd` (legacy refresh wrapper)
- `scripts/world/contracts/*CallableAdapter.gd` (transition adapters)
- UI/placeable wrappers in `Chest*` over `Container*`

Policy for legacy surfaces:

- Do not add new bridges unless blocked.
- Mark every bridge as deprecated and instrumented.
- Prefer deleting bridges by migrating callers onto canonical owner APIs.

---

## 9) Reference usage

Use this document as the architecture source of truth.

- `AGENTS.MD` should describe working rules and point here for architecture authority.
- `CLAUDE.md` should remain a quickstart and point here for architecture authority.
