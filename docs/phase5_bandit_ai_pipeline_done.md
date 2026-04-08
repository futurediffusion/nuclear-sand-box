# Phase 5 Closure — Bandit AI Pipeline Normalization

This document closes the migrated **Phase 5 bandit AI slice** (`Perception → Intent → Task planning → Execution`) and records what now belongs to each layer.

## Ownership after Phase 5

### Perception now handles
- Runtime signal normalization for migrated group/member inputs (combat/threat, nearby loot/resources, assault-target availability).  
- Group-level perception snapshot generation via `BanditPerceptionSystem.build_group_intent_perception(...)` with canonical fields (`stage`, `threat_signals`, nearby counts, assault flags, trace metadata).
- Legacy blackboard proximity data is still consumed as input, but normalization/output shape is owned by Perception.

### Intent now handles
- Canonical group intent decision records from normalized perception (`kind=group_intent_decision`, `group_mode`, `decision_type`, trace fields).
- Policy-driven selection of decision type (`continue`, `react`, `pursue`, `return_home`, `structure_assault`, `loot_resource`).
- Publication of canonical intent record to group status (`status.canonical_intent_record`) for downstream task planning.

### Task planning now handles
- Transforming canonical intent + member context into canonical executable task orders (`BanditTaskPlanner.plan_member_task`).
- Order allowlist/sanitization and task payload construction (`order.task.kind`, intent summary, target payload).
- Migrated structure-assault routing for leader/bodyguard and economic fallbacks for loot/resource work.

### Execution now handles
- Consuming already-planned tasks and performing runtime side effects only (movement/combat/assault state transitions).
- Applying member orders and task payloads through `BanditBehaviorLayer._apply_member_order(...)`.
- Guarding against mismatched `order` vs `task.kind` at runtime to avoid duplicate decision paths.

### What remains legacy
- Compatibility bridge for structure assault when canonical intent is absent (`structure_assault_pipeline_compatibility_bridge`).
- Some tactical source inputs still originate in legacy blackboard/pulse wiring before normalization.
- Existing role controllers and historical behavior states remain in place where not yet migrated.

## Regression protection added in this closure

- New regression harness: `scripts/tests/phase5_bandit_ai_pipeline_regression_runner.gd`.
- Covered checks:
  - Perception output generation.
  - Canonical intent output generation.
  - Task planning output generation.
  - Execution consumption of migrated assault task.
  - Duplicate decision path prevention (mismatched order/task guard).

## Observability added in this closure

Lightweight `bandit_pipeline` instrumentation now logs:
- Group-level pipeline decision snapshots (`pipeline_group_decision`).
- Group-level planned-order summaries (`pipeline_group_orders_planned`).
- Explicit compatibility-bridge activations (`pipeline_compatibility_bridge_applied`).
- Execution-side task consumption (`pipeline_execution_task_consumed`).
- Runtime duplicate-path guard activations (`pipeline_duplicate_decision_path_blocked`).

## Out of scope (intentionally unchanged)

- Persistence snapshot migration was **not** started in this phase.
- Unrelated systems were not redesigned.

## Recommended next migration targets (Phase 6 / future AI work)

1. Remove compatibility bridge by enforcing canonical intent publication for all assault-capable groups.
2. Migrate remaining legacy tactical reads to consume only normalized perception/intent/task contracts.
3. Promote explicit typed/contracted runtime telemetry snapshots for pipeline stages (sampling + counters).
4. Expand regression harness to include full group-order generation from real blackboard snapshots.
5. Continue persistence-focused AI state migration in a dedicated phase (separate from this closure).
