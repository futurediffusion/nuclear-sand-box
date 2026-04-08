# Phase 3 Placement Reaction Contract

## Scope
Phase 3 contract for migrating placement reaction from `world.gd` heuristics to a domain-first pipeline.

This document defines boundaries before implementation. It does **not** change runtime behavior by itself.

---

## 1) Input domain events that can trigger placement reaction

Placement reaction must be fed by **domain events**, not by direct polling inside `world.gd`.

Primary trigger events (from current runtime signals/facades):
- `placement_completed(item_id, tile_pos)` from `PlacementSystem`.
- `player_wall_drop(tile_pos, item_id, amount)` from `PlayerWallSystem` (structure loss/assault signal).
- `record_interest_event(kind, world_pos, metadata)` already routed through `SettlementIntel` for contextual enrichment.

Event normalization contract (new pipeline input):
- Convert each input into a `PlacementReactionEvent` with at least:
  - `kind` (`structure_placed`, `wall_damaged`, `wall_removed`, etc.)
  - `item_id`
  - `world_pos`
  - `timestamp`
  - `source` (`placement_system`, `player_wall_system`, `legacy_world_bridge`)
  - optional `metadata`

Rule:
- Triggering is event-driven and append-only; consumers decide relevance.

---

## 2) Role of `ThreatAssessmentSystem`

`ThreatAssessmentSystem` is the **scoring and risk gate** for placement reaction.

Responsibilities:
- Evaluate candidate groups/factions near the event.
- Compute threat/relevance score using existing data sources (distance, hostility/profile, known interest/base context, optional blocking/path hints).
- Return a behavior-neutral assessment object, e.g.:
  - `eligible_groups`
  - `score_by_group`
  - `recommended_severity`
  - `rejection_reasons` (for debug/telemetry)

Non-responsibilities:
- No movement orders.
- No extortion UI/flow execution.
- No direct mutation of `BanditGroupMemory` intent states.

---

## 3) Role of `GroupIntentSystem`

`GroupIntentSystem` is the **intent application layer** after threat assessment.

Responsibilities:
- Consume `ThreatAssessmentSystem` output.
- Decide and publish group-level intent transitions (`idle`/`alerted`/`hunting`/`extorting`) with cooldown/lock checks.
- Write intent changes via existing group-memory boundary (`BanditGroupMemory`), preserving current anti-spam semantics.
- Emit explicit domain events for downstream directors (extortion/raid orchestrators), instead of embedding orchestration in `world.gd`.

Non-responsibilities:
- No low-level per-frame movement.
- No direct pathfinding queries in hot loops.
- No rewriting raid/extortion directors in this phase.

---

## 4) What `world.gd` must stop doing

During migration, `world.gd` must stop accumulating placement-reaction domain logic.

Must stop (target boundary):
- Owning placement reaction scoring formulas.
- Selecting reactive squads/intents directly.
- Applying hostility/anchor/POI heuristics inline in `_trigger_placement_react`.
- Being the long-term owner of placement reaction throttling/lock policy.

`world.gd` remains allowed to:
- Subscribe to runtime signals.
- Build minimal bridge payloads.
- Delegate to domain systems (`ThreatAssessmentSystem` -> `GroupIntentSystem`).
- Keep temporary wrappers for backward compatibility.

---

## 5) What current legacy behavior remains temporarily

Until Phase 3 migration is complete, keep these behaviors:
- Existing `_on_placement_completed -> _trigger_placement_react(...)` path in `world.gd` remains active as fallback.
- Existing `BanditGroupIntel` scan-driven intent updates remain active.
- Existing `ExtortionQueue` / extortion director flow remains unchanged.
- Existing settlement/base marker production in `SettlementIntel` remains unchanged.

Temporary coexistence rule:
- New domain pipeline must be introduced behind feature-gated delegation, with legacy path preserved until parity checks pass.

---

## 6) What does **NOT** belong in this phase

Out of scope for this contract/migration slice:
- Full AI architecture rewrite.
- Full raid system redesign.
- New faction diplomacy/economy model.
- Save schema migrations.
- Runtime balancing pass for all hostility/intent thresholds.
- Refactor of unrelated world subsystems (chunk generation, tavern authority, drop compaction, etc.).

---

## 7) Migration sequence for next Phase 3 tasks

1. **Contract-first types + adapters**
   - Define `PlacementReactionEvent` and assessment/intention DTOs.
   - Add thin adapters from existing signals (`PlacementSystem`, `PlayerWallSystem`, `SettlementIntel` facade).

2. **Extract threat scoring**
   - Move scoring/relevance logic from `world.gd` placement-react helpers into `ThreatAssessmentSystem` with no behavior change.

3. **Extract intent application**
   - Introduce `GroupIntentSystem` that applies assessed outcomes to `BanditGroupMemory` and emits intent-domain events.

4. **Bridge `world.gd` to new pipeline**
   - Replace direct `_trigger_placement_react` decisions with delegation calls.
   - Keep legacy fallback path behind a flag until parity is validated.

5. **Parity verification + telemetry**
   - Compare legacy vs new decisions (activation count, selected groups, intent outcomes, cooldown behavior).

6. **Retire legacy placement-react internals**
   - After parity, remove duplicated scoring/selection logic from `world.gd` and keep façade-only orchestration.

---

## Boundary summary

Desired steady state for placement reaction pipeline:

`Runtime signals/events -> PlacementReactionEvent adapter -> ThreatAssessmentSystem -> GroupIntentSystem -> existing directors/memory`

`world.gd` = wiring + delegation, not domain owner.
