# Phase 5 — Structure Assault Vertical Slice (Perception → Intent → Task → Execution)

## Scope
- Migrated **one** representative flow only: `structure_assault`.
- No worker-loop redesign and no unrelated AI system rewrites.

## New explicit flow path
1. **Perception** (`BanditPerceptionSystem.build_group_intent_perception`)
   - Builds a normalized group perception snapshot for assault planning:
     - combat/recently-engaged member counts
     - nearby loot/resource counts
     - `structure_assault_active`
     - `has_assault_target`
2. **Intent** (`BanditIntentSystem.decide_group_intent`)
   - For active structure assault groups, resolves canonical intent record with:
     - `policy_next_intent = "raiding"`
     - decision expected to stay on `structure_assault_focus` while target is valid.
3. **Task** (`BanditTaskPlanner.plan_member_task`, called by `BanditGroupBrain.assign_group_orders`)
   - Consumes canonical intent and emits concrete orders (`assault_structure_target` for leader/bodyguards).
4. **Execution** (`BanditBehaviorLayer._apply_member_order`)
   - Applies the task order to runtime behavior.
   - Emits trace event `structure_assault_pipeline_execution` with intent/task metadata.

## Temporary compatibility bridges
- **Bridge A: non-assault fallback keeps legacy canonical intent path**
  - New Perception→Intent override is applied only when `structure_assault_active == true`.
  - All non-assault groups continue using the prior blackboard canonical intent (`status.canonical_intent_record`) to keep behavior stable while migration remains incremental.
- **Bridge B: perception source fallback remains blackboard-first elsewhere**
  - Existing blackboard perception (`prioritized_drops`, `prioritized_resources`) is still used by group planning.
  - The new normalized group perception snapshot is currently injected for structure assault routing only.

## Review notes
- The migrated path is now explicit in code and traceable by:
  - intent record metadata: `pipeline_path = "Perception->Intent->Task->Execution"`
  - execution event: `structure_assault_pipeline_execution`.
