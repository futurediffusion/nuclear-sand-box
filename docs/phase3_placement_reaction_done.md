# Phase 3 Closure — Placement Reaction Refactor (Historical Record)

> [!WARNING]
> **Historical phase closure artifact.**
> This document captures what was true at Phase 3 closure time.
> It is **superseded by later architecture changes** and is **not** the current source of truth.

## Current status after later phases

Use these docs for current architecture/ownership:

- [`docs/architecture/ownership/ai-pipeline.md`](docs/architecture/ownership/ai-pipeline.md)
- [`docs/architecture/ownership/world-bootstrap-orchestration.md`](docs/architecture/ownership/world-bootstrap-orchestration.md)
- [`docs/architecture/ownership/README.md`](docs/architecture/ownership/README.md)
- [`docs/phase3_placement_reaction_contract.md`](docs/phase3_placement_reaction_contract.md) (contract context)

Treat this page strictly as migration history.

## Phase 3 scope that was closed (at that time)

This closure was limited to placement-reaction migration in parity mode with regression hooks.

## Recorded closure state at Phase 3

### Placement reaction triggers (historical)
Placement reaction became event-driven through `PlacementReactionSystem.handle_building_event(...)`, fed by:
- `PlacementSystem.placement_completed` via `world.gd::_on_placement_completed`
- `PlayerWallSystem.building_events_emitted` via `world.gd::_on_building_events_emitted`

### Threat assessment + intent publication (historical)
- Threat relevance/severity were assessed in `ThreatAssessmentSystem.assess_building_event(...)`.
- Canonical placement-reaction intent publication was owned by `GroupIntentSystem.publish_placement_reaction_intent(...)`.

### `world.gd` responsibilities at closure time (historical)
`world.gd` no longer owned threat scoring or intent mutation for placement reaction; it subscribed to signals, adapted events, and delegated to `PlacementReactionSystem`.

### Legacy retained at closure (historical)
- `BanditGroupIntel` and other non-placement raid producers stayed active.
- `RaidFlow` / `BanditBehaviorLayer` runtime dispatch paths stayed unchanged.
- Compatibility wrappers/facades in `world.gd` remained.

## Regression + observability added in Phase 3

- Runner: `scripts/tests/placement_reaction_phase3_regression_runner.gd`
- Coverage included event normalization, threat filtering, canonical publication contract, and duplicate suppression.
- Added telemetry fields including `skipped_by_duplicate` and `skipped_duplicate_events_total`.

## Notes on superseded wording

Statements phrased as “now” or “canonical” in this file are **historical-to-Phase-3 statements**, not guarantees about today’s full AI architecture.
