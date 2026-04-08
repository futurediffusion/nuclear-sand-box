# CLAUDE.md — Contributor Quickstart (current state)

This is the fast entrypoint for contributors. It is intentionally short.
For architecture authority, use `docs/architecture/current_sandbox_architecture.md` (source of truth).
Use `AGENTS.MD` as collaboration guardrails and `docs/architecture/ownership/*` as subsystem constitutions.

## 1) Run the project

- Open editor / run main scene:

```bash
godot --path .
```

- Run directly from CLI (main scene defined in `project.godot`):

```bash
godot --path . scenes/main.tscn
```

- Lightweight script parse check:

```bash
godot --path . --check-only --script scripts/world/world.gd
```

## 2) Architecture boundaries (today)

### Composition & lifecycle root
- `scripts/world/world.gd` is the runtime composition root and lifecycle orchestrator.
- It wires systems, ticks orchestration lanes, and delegates gameplay commands.
- It is **not** canonical truth for building rules, AI intent/tasking, or persistence payload design.

### Canonical building / structure flow
- Domain authority lives in `scripts/domain/building/*` (`BuildingCommands`, `BuildingSystem`, `BuildingState`, repository stack).
- Structure contract is unified around `SandboxStructureContract` + `SandboxStructureRepository`.
- Canonical path is: **command → domain change/event → projection refresh → snapshot persistence**.

### Explicit projections (read-models)
- Building visuals: `scripts/projections/tilemap/BuildingTilemapProjection.gd`
- Wall collision: `scripts/projections/collision/WallColliderProjection.gd`
- Territory queries: `scripts/projections/territory/TerritoryProjection.gd`
- Projections are rebuildable/derived; never promote projection/runtime cache data to canonical truth.

### Bandit AI pipeline
- Stage ownership is explicit: **Perception → Intent → Task Planning → Execution**.
- Core entrypoints:
  - `scripts/domain/factions/BanditPerceptionSystem.gd`
  - `scripts/domain/factions/BanditIntentSystem.gd`
  - `scripts/domain/factions/BanditTaskPlanner.gd`
  - Runtime execution layer in `scripts/world/BanditBehaviorLayer.gd` and related world behavior modules.

### Canonical snapshot persistence
- World save/load is snapshot-based (`WorldSnapshot`, `ChunkSnapshot`) with explicit versioning/migrations.
- Main entrypoints:
  - `scripts/persistence/save/WorldSnapshotSerializer.gd`
  - `scripts/persistence/save/WorldSnapshotVersioning.gd`
  - `scripts/persistence/save/WorldSaveAdapter.gd`
  - `scripts/systems/SaveManager.gd`
- Legacy compatibility flows should remain one-way into canonical snapshot contracts.

## 3) Primary files to read before modifying architecture

1. `scripts/world/world.gd` (orchestration boundary)
2. `scripts/runtime/world/GameplayCommandDispatcher.gd` (gameplay command routing)
3. `scripts/domain/building/*` (building authority)
4. `scripts/projections/**/*Projection.gd` (derived read-models)
5. `scripts/persistence/save/*Snapshot*.gd` + `WorldSaveAdapter.gd` (save contract)
6. `docs/architecture/ownership/README.md` + subsystem constitutions

## 4) What not to do

- Do **not** add new domain policy logic directly into `world.gd`.
- Do **not** bypass domain owners by mutating canonical building/persistence dictionaries from random gameplay scripts.
- Do **not** treat tilemaps, colliders, spatial indices, or other runtime caches as persistence truth.
- Do **not** collapse Bandit stages into hidden one-module logic that mixes perception/intent/task/execution authority.
- Do **not** introduce new legacy callable/setup bridges unless migration is blocked and deprecation is explicit.

## 5) Deeper docs (current)

- Current architecture source of truth: `docs/architecture/current_sandbox_architecture.md`
- Collaboration quick rules: `AGENTS.MD`
- Ownership boundaries: `docs/architecture/ownership/README.md`
- Historical migration context: `REGISTRO_CAMBIOS_DESDE_AGENTS.md`
