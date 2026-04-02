# KPI Plan — Event-driven invalidation + reusable hot-loop buffers (2026-04-02)

## Scope

- `scripts/world/WorldSpatialIndex.gd`
- `scripts/world/SettlementIntel.gd`
- `scripts/world/BanditBehaviorLayer.gd`
- `scripts/world/BanditGroupIntel.gd`

## Before/After KPIs

> Baseline (`before`) and validation (`after`) should be sampled on the same save, same zone, and same in-game activity window (bandit camp + settlement interaction), minimum 5 minutes each.

### 1) Spatial index invalidation cost

From `WorldSpatialIndex.get_debug_snapshot()`:

- `persistent_incremental_apply_calls`
- `persistent_incremental_apply_avg_usec`
- `persistent_full_rebuild_calls`
- `persistent_full_rebuild_avg_usec`
- `event_driven_invalidation_hits` (new)
- `revision_poll_invalidations` (new)
- `pending_changed_chunks` (new)

Goal: raise event-driven invalidations while reducing revision-poll invalidations and unnecessary full rebuilds.

### 2) Settlement scan locality

From `SettlementIntel.get_debug_snapshot()`:

- `chunk_invalidations.partial_workbench_rescans` (new)
- `chunk_invalidations.full_workbench_rescans` (new)
- `chunk_invalidations.partial_base_scan_jobs_enqueued` (new)
- `chunk_invalidations.global_scan_fallbacks` (new)
- `pending_base_scan_jobs` (new)

Goal: more partial rescans/jobs than full global rescans in normal gameplay.

### 3) Tick/frame allocation pressure (bandit AI)

Indirect signal from profiler/telemetry:

- Lower per-frame allocations in Bandit runtime loops.
- Stable behavior output (no change in raid/extortion/settlement decisions).

Code-level changes reducing temporary allocations:

- reusable prune buffer in `BanditBehaviorLayer._prune_behaviors()`
- reusable live-group dictionary in `BanditGroupIntel._prune_removed_groups()`

## Smoke validation checklist

1. Spawn/enter active bandit area and trigger normal patrol/engagement.
2. Place/remove workbench and door/wall near settlement.
3. Validate no functional regressions:
   - extortion still enqueues with same policy gates,
   - raids/light-raids/probes still trigger,
   - base detection remains active.
4. Compare before/after snapshots for KPI sections above.

## Rollback strategy

- Fast rollback by reverting these 4 files only.
- Functional rollback is low-risk because changes are isolated to:
  - cache invalidation timing,
  - chunk-scoped settlement recompute scheduling,
  - temporary buffer reuse.
