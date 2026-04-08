# Typed Event Contracts Audit — Phase 1

Date: 2026-04-08

## Scope completed in this pass

This pass introduces a practical typed contract layer for the highest-value cross-system event payloads still exposed as ad-hoc dictionaries.

### Event families now typed/centralized

1. **Building / structure events**
   - Contract: `BuildingEventDto`
   - Producers migrated:
     - `BuildingEvents` now delegates event payload creation to DTO constructors.
     - `world.gd` placement-completed bridge now emits DTO-built payload.
   - Consumers migrated:
     - `PlacementReactionSystem` now normalizes via `BuildingEventDto.normalize_for_threat_assessment`.

2. **Placement / threat event ingestion**
   - Contract: `BuildingEventDto.normalize_for_threat_assessment`
   - Ownership rule:
     - Placement/threat pipeline consumes normalized shape with stable keys:
       - `event_type`, `item_id`, `tile_pos`, `target_position`, `metadata`.

3. **Intent publication records (assault target intent)**
   - Contract: `IntentPublicationRecordDto`
   - Producers migrated:
     - `BanditGroupMemory.publish_assault_target_intent`
     - `BanditGroupMemory.refresh_assault_target_pos`
   - Compatibility:
     - DTO preserves legacy top-level keys (`created_at`, `expires_at`, `ttl`) while adding a structured `lifecycle` block.

4. **Task planning outputs**
   - Contract: `TaskPlanOutputDto`
   - Producer migrated:
     - `BanditTaskPlanner.plan_member_task`
   - Ownership rule:
     - Planner returns sanitized order + explicit `task` payload through a centralized builder.

5. **Projection update inputs**
   - Contract: `ProjectionUpdateInputDto`
   - Producers/consumers migrated:
     - `WorldSpatialIndex.notify_placeables_changed` now emits DTO-shaped projection input.
     - `SpatialIndexProjection.apply_inputs` now normalizes through DTO.

6. **Snapshot load/rebuild notification**
   - Contract: `SnapshotRebuildNotificationDto`
   - Producer migrated:
     - `world.gd.get_snapshot_rebuild_report` now returns a structured rebuild notification contract.

## Still legacy / next migration candidates

- Threat assessment output payload (`ThreatAssessmentSystem.assess_building_event`) remains dictionary-based.
- Candidate group entries exchanged between placement reaction and threat assessment remain dictionary records.
- Canonical intent record returned by `BanditIntentSystem.decide_group_intent` remains dictionary-based.
- Projection event batches for tilemap/collider (`apply_events` arrays) are still dictionary payloads, but now sourced from typed building event constructors.
- Misc debug snapshots remain intentionally dictionary-based (diagnostic/read-model data).

## Field naming and ownership notes

- **Event-type naming** is now anchored by `BuildingEventDto` constants for structure + placement-completed event families.
- **Placement/threat ownership boundary**:
  - Producers can publish bridge payloads,
  - but consumers rely on DTO normalization before domain evaluation.
- **Intent record lifecycle ownership**:
  - TTL and expiration are set in one place (`IntentPublicationRecordDto`), reducing drift.

## Compatibility strategy used

- DTOs are introduced as **central constructors/normalizers** while preserving existing dictionary transport at module boundaries.
- Legacy keys required by downstream runtime code are retained where needed.
- Migration intentionally avoids broad subsystem redesign and keeps world composition behavior unchanged.
