# Constitution: AI Pipeline

## Source of truth
- Perception memory/blackboard owners (`BanditGroupIntel`, `BanditGroupMemory`) for sensed facts.
- Intent authority: `BanditIntentPolicy` / intent system outputs.
- Task authority: `BanditGroupBrain` (+ role planners).
- Execution authority: behavior/director runtime systems (`BanditBehaviorLayer`, `BanditWorldBehavior`, directors/stash).

## Read models / projections
- Any staged snapshot DTOs (`PerceptionSnapshot`, `IntentSnapshot`, task assignment payloads) are pipeline handoff contracts, not canonical world persistence.

## Allowed writers
- Perception stage writes perception state only.
- Intent stage writes intent state only.
- Task stage writes assignment state only.
- Execution stage writes runtime actuation and world interactions only.

## Allowed readers
- Downstream stages can read upstream outputs.
- Orchestrator can read stage outputs for scheduling/telemetry.

## Allowed side effects
- Execution stage may apply movement, combat, loot transfer, raid/extortion dispatch.
- Upstream stages may emit telemetry and transition events.

## Forbidden writes / authority
- Execution must not own social policy thresholds/intent selection.
- Perception must not directly choose tactical assignments or execution actions.
- Any single module that mixes Perception→Intent→Task→Execution in one hidden branch is a boundary violation.
