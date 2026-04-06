# Building Vertical Slice – Phase 2 Closure

## Scope closed in this phase
This closure is only for the walls/building vertical slice. It does **not** migrate raids, AI, territory, or spatial index ownership.

## Source of truth (after Phase 2)
- **Runtime building domain truth** is the `BuildingSystem` + `BuildingState` owned through `PlayerWallSystem` orchestration for player-wall lifecycle commands (place/damage/remove).  
- **Player-wall persistence truth** remains `WorldSave.player_walls_by_chunk` through `WorldSaveBuildingRepository` / `WallPersistence` (`{"hp": int}` schema unchanged).
- **Structural wall persistence truth** remains structural placed-tile entries (`source = -1`) via `StructuralWallPersistence`.

## Still legacy (intentionally retained)
- `world.gd` still exposes public wall API wrappers and delegates into dispatcher/`PlayerWallSystem` for backward compatibility.
- Callable fallback adapters in `PlayerWallSystem.setup(...)` remain available for projection-refresh/chunk-dirty wiring.
- Legacy audio config keys in `PlayerWallSystem.configure_audio(...)` are still accepted.

## Public compatibility that remains guaranteed
- Existing wall command entrypoints exposed by `world.gd` continue to exist and preserve runtime behavior.
- Persistence schemas are unchanged (`player_walls_by_chunk` with `hp`, structural placed-tile format).
- Wall events/signals consumed by world integrations remain valid (`player_wall_hit`, drops, structural hit/drop feedback).

## What to migrate next (future phases)
1. Remove callable fallback adapters once all wiring uses typed ports only.
2. Narrow `world.gd` wrappers to façade-only command forwarding and remove residual legacy-only branches.
3. Promote explicit building-domain regression runners into CI invocation paths.
4. After those are stable, evaluate deletion of dead compatibility code paths.

## Regression protection added in this phase
- Deterministic script-level regression harness for building-domain command lifecycle:
  - place structure
  - damage structure (non-lethal + lethal)
  - remove structure
  - rebuild/apply projection from rebuilt state using `BuildingColliderRefreshProjection` scope checks
- Runner: `scripts/tests/building_vertical_slice_phase2_regression_runner.gd`
- Suggested run command:
  - `godot --path . --headless --script res://scripts/tests/building_vertical_slice_phase2_regression_runner.gd`
