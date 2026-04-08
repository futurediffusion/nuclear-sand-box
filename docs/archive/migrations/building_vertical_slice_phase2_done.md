# Building Vertical Slice — Phase 2 Closure (Historical Record)

> [!WARNING]
> **Historical phase closure artifact.**
> This document records the Phase 2 migration state at the time that phase closed.
> It is **superseded by later architecture work** and must **not** be treated as the current architecture source of truth.

## Current status after later phases

For current ownership and architecture expectations, use:

- [`docs/architecture/ownership/building-structures.md`](../../architecture/ownership/building-structures.md)
- [`docs/architecture/ownership/projections.md`](../../architecture/ownership/projections.md)
- [`docs/architecture/ownership/README.md`](../../architecture/ownership/README.md)

This file should be read as migration history only.

## Phase 2 scope that was closed (at that time)

This closure covered only the walls/building vertical slice. It did **not** migrate raids, AI, territory, or full spatial-index ownership.

## Recorded closure state at Phase 2

### Runtime + persistence boundaries (historical)
- Runtime building-domain behavior was routed through `BuildingSystem` + `BuildingState` via `PlayerWallSystem` orchestration for wall lifecycle commands.
- Player-wall persistence remained `WorldSave.player_walls_by_chunk` via `WorldSaveBuildingRepository` / `WallPersistence` (`{"hp": int}` schema unchanged at that time).
- Structural wall persistence remained structural placed-tile entries (`source = -1`) via `StructuralWallPersistence`.

### Transitional/legacy compatibility retained (historical)
- `world.gd` exposed wall API wrappers delegating into dispatcher/`PlayerWallSystem` for backward compatibility.
- Callable fallback adapters in `PlayerWallSystem.setup(...)` remained for projection-refresh/chunk-dirty wiring.
- Legacy audio config keys in `PlayerWallSystem.configure_audio(...)` remained accepted.

### Compatibility guarantees recorded at closure (historical)
- Wall command entrypoints in `world.gd` were preserved.
- Persistence schemas were unchanged (`player_walls_by_chunk` with `hp`, structural placed-tile format).
- Existing wall events/signals consumed by world integrations remained valid.

## Regression protection added in Phase 2

- Deterministic script-level regression harness for wall command lifecycle and projection rebuild checks.
- Runner: `scripts/tests/building_vertical_slice_phase2_regression_runner.gd`
- Suggested run command at closure time:
  - `godot --path . --headless --script res://scripts/tests/building_vertical_slice_phase2_regression_runner.gd`

## Notes on superseded wording

Any language in older references implying the above was the long-term final boundary should be interpreted as **phase-local closure language only**.
