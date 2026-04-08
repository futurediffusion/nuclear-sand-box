# Sandbox Tick Domain Audit (incremental)

Date: 2026-04-08

## Objective
Clarify tick ownership across runtime systems without rewriting the main loop. This pass keeps the current cadence/lane model but makes domain ownership explicit and visible in code/debug snapshots.

## Tick domains

- `simulation_tick`
  - Chunk streaming pulse (`chunk_pulse`) in `world.gd` for `update_chunks` and active window transitions.
  - Resource regrowth pulse (`resource_repop_pulse`) through `ResourceRepopulator.tick_from_cadence(...)`.
- `ai_decision_tick`
  - Bandit decisions/work-loop (`bandit_work_loop`) in `BanditBehaviorLayer._process`.
  - Director orchestration (`director_pulse`) used by extortion/raid directors.
  - Settlement intel scans (`settlement_base_scan`, `settlement_workbench_scan`) configured in world cadence.
- `execution_runtime_tick`
  - Occlusion material updates (`occlusion_pulse`) via `OcclusionController.tick_from_cadence(...)`.
- `projection_rebuild_tick`
  - Medium pulse (`medium_pulse`) for territory refresh and drop pressure snapshot work in `world.gd`.
  - Projection rebuild/refresh requests continue to route through building/collider projection services.
- `persistence_tick`
  - Autosave pulse (`autosave`) in `world.gd` calling `_perform_world_save("autosave")`.
- `maintenance_tick`
  - Short maintenance pulse (`short_pulse`) for wall refresh + tile erase queues.
  - Drop cleanup/compaction pulse (`drop_compact_pulse`).

## Concrete changes in this pass

1. `WorldCadenceCoordinator.configure_lane(...)` now accepts a `domain` tag and includes it in debug snapshots.
2. `world.gd` now registers lanes via `_configure_world_cadence_lanes()` with explicit domain constants.
3. World maintenance debug snapshot lane inventory now reports each lane's domain.
4. `BanditBehaviorLayer.gd` now uses named lane constants (`LANE_DIRECTOR_PULSE`, `LANE_BANDIT_WORK_LOOP`) and fallback interval constants to reduce hidden string coupling.

## Notes on behavior preservation

- No authority moved between systems.
- No scheduler rewrite: existing cadence intervals, budgets, and fallback behavior are preserved.
- Runtime behavior should remain equivalent; this is primarily an ownership-clarity pass.
