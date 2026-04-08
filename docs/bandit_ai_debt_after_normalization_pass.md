# Bandit AI normalization debt (post-pass)

Date: 2026-04-08

Update: follow-up normalization pass applied (same date) to demote GroupBrain candidate orders into input hints and add blackboard read adapters.

## What was normalized in this pass

### Migrated flow: `continue_current_work` task ownership
- `BanditTaskPlanner` now resolves `continue_current_work` into canonical tasks directly (`return_home`, `mine_target`, `pickup_target`, `move_to_target`, `follow_slot`) instead of delegating final ownership to legacy `proposed_order` output.
- Legacy role-controller output (`proposed_order`) is now treated as **input hint only** (e.g. fallback slot/target hint), not final authority.
- Canonical planning now preserves scavenger resource continuity using member runtime memory fields (`existing_assignment`, `current_resource_id`, `pending_mine_id`, `last_valid_resource_node_id`) as **memory/history inputs**.

### Observability added
- `task.planning_trace` now includes:
  - `legacy_input_used: bool`
  - `legacy_input_source: String`
- Runtime telemetry (`BanditBehaviorLayer`) now emits these fields in:
  - `pipeline_execution_task_consumed`
  - `pipeline_task_authority`

This makes canonical-vs-legacy influence explicitly observable without returning tactical ownership to legacy systems.

### Follow-up migration completed
- `BanditGroupBrain._build_candidate_order_for_member` was replaced by an input-hint flow (`_build_input_hints_for_member` + `_extract_legacy_hints`) so role controllers no longer emit authoritative candidate orders into planning.
- Added transition read adapters:
  - `PerceptionReadModel` (perception facts)
  - `IntentStateReadModel` (canonical intent state)
- Added regression assertions in `phase5_bandit_ai_pipeline_regression_runner.gd` to enforce `planning_trace.authority == canonical_pipeline` and `legacy_input_used == false` for nominal loop cases (`idle/working/return/deposit`).

---

## Current architecture split (explicit)

### 1) Memory / history / input providers
- `BanditGroupMemory` blackboard (`perception`, `status`, assignments, TTL entries)
- Member runtime fields (`current_resource_id`, `pending_mine_id`, `last_valid_resource_node_id`, `has_active_task`, cargo flags)
- Legacy role controllers (`BodyguardController`, `ScavengerController`) now expected to be transitional input producers only

### 2) Canonical decision layers
- `BanditPerceptionSystem`: perception normalization
- `BanditIntentSystem`: intent decision records and canonical intent publication
- `BanditTaskPlanner`: canonical task mapping and task payload composition

### 3) Execution/runtime application
- `BanditBehaviorLayer`: executes tasks/orders, applies movement/runtime side effects
- `BanditWorldBehavior` + work/stash/raid/extortion coordinators: runtime behavior + transitions

---

## Remaining debt after this pass

1. **Role controller hints still exist as transitional source**
   - `BanditGroupBrain` now demotes role-controller output to minimal hints (`slot_name`, `target_pos`) only.
   - Remaining step is to replace controller-derived hints with fully canonical hint providers and retire role controllers.

2. **Blackboard payload shape still leaks tactical semantics**
   - Some entries under `status` and `perception` are consumed in forms that mirror tactical directives.
   - Next step: normalize read adapters so blackboard exposes “facts + memory” contracts only (not implied commands).

3. **Execution still carries compatibility guards for non-canonical edge cases**
   - `BanditBehaviorLayer` keeps safeguards for structure assault fallback and legacy mismatch handling.
   - These are useful guardrails today, but should shrink as canonical intent/task coverage increases.

4. **Scavenger nuanced economics still partly controller-derived in spirit**
   - Canonical planner now handles main economic loop, but parity with all controller edge heuristics should be validated and moved into explicit planner utilities.

5. **Metrics should be promoted to periodic summary counters**
   - We now log per-event canonical/legacy influence.
   - Follow-up: aggregate counters per group/per minute to support regression gates in automated tests.

---

## Safe next migration targets

1. Retire role controllers entirely by replacing legacy hint generation with canonical hint providers derived from perception/intent state.
2. Expand regression harness from planner-only assertions to runtime telemetry assertions over long-run simulations (`legacy_driven=false` on nominal loops).
3. Continue adapter rollout so remaining tactical codepaths stop reading raw blackboard branches directly.
4. Add aggregated counters/alerts (per-group, per-minute) for `legacy_input_used` to gate regressions automatically.
