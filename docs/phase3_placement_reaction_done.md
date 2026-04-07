# Phase 3 Closure — Placement Reaction Refactor

This closes the **Phase 3 placement reaction migration** in parity mode with regression hooks.

## What now triggers placement reaction

Placement reaction is now event-driven via `PlacementReactionSystem.handle_building_event(...)`, fed by:

- `PlacementSystem.placement_completed` bridged in `world.gd::_on_placement_completed`.
- `PlayerWallSystem.building_events_emitted` bridged in `world.gd::_on_building_events_emitted` (covers structure placed/damaged/removed events).

## Where threat is assessed

- Threat relevance and severity are assessed in `ThreatAssessmentSystem.assess_building_event(...)`.
- The result is a behavior-neutral assessment payload (`is_relevant`, `priority`, `severity`, `candidate_group_scope`, `debug`).

## Where intent is published

- Canonical placement-reaction intent publication is owned by `GroupIntentSystem.publish_placement_reaction_intent(...)`.
- The canonical publication path remains `BanditGroupMemory.publish_assault_target_intent(...)` with source precedence kept intact.

## What `world.gd` no longer owns

`world.gd` no longer owns placement-reaction threat scoring or intent mutation logic. It now only:

- subscribes to runtime source signals,
- adapts those into building events,
- delegates to `PlacementReactionSystem`.

## What remains legacy

- `BanditGroupIntel` and other non-placement raid producers remain active.
- `RaidFlow` / `BanditBehaviorLayer` runtime dispatch paths remain unchanged.
- Existing compatibility wrappers and facades in `world.gd` remain in place.

## What was added for regression protection + observability

- New regression harness: `scripts/tests/placement_reaction_phase3_regression_runner.gd`.
  - Covers building event ingestion normalization.
  - Covers threat assessment candidate filtering/output generation.
  - Covers canonical intent publication contract.
  - Covers duplicate reaction path suppression (dedupe window).
- Placement reaction telemetry now includes:
  - `skipped_by_duplicate` in per-event debug records.
  - `skipped_duplicate_events_total` in debug snapshot aggregates.
  - Summary logs now report `skipped_by_duplicate`.

## What should migrate next (later phases)

1. Move remaining placement-react tuning ownership out of `world.gd` exports into a dedicated config boundary.
2. Introduce explicit typed event DTOs for building/placement events (reduce dictionary-shape drift).
3. Retire legacy duplicate producers once parity metrics stay stable (especially overlap with intel-driven raid enqueue).
4. After parity, remove any no-longer-used compatibility wrappers from `world.gd`.

## Scope guard

This closure is intentionally limited to **placement reaction only**.  
No full AI normalization, raid redesign, or unrelated telemetry redesign is included in this phase.
