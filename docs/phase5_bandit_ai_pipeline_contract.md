# Phase 5 — Bandit AI Pipeline Contract (Perception → Intent → Task → Execution)

## Scope and constraints
- This contract is for **bandit world behavior in the current repo**, not a full AI rewrite.
- It defines **ownership boundaries** so Phase 5 can migrate incrementally.
- Runtime behavior should stay equivalent while responsibilities are moved.

---

## 1) Perception: what belongs here
Perception is **data acquisition + normalization only**.

Owns:
- Reading world signals (markers, bases, nearby drops/resources, nearby enemies/player).
- Sampling cadence/slicing/LOD for scans.
- TTL/expiration and freshness metadata for sensed facts.
- Producing canonical, serializable perception payloads (group-level and member-level).

Does **not** own:
- Threshold decisions for social escalation.
- Role assignment or order selection.
- Velocity, movement, attacks, or world side effects.

Current repo mapping (likely Perception owners):
- `scripts/world/BanditGroupIntel.gd` (group scanning, marker/base reads, scan cadence).
- `scripts/systems/BanditGroupMemory.gd` (shared blackboard perception/status TTL storage).
- `scripts/world/SettlementIntel.gd` (interest/base detection source consumed by bandits).

---

## 2) Intent: what belongs here
Intent is **policy translation** from perceived facts to group-level intent state.

Owns:
- Converting score/profile/context into intent (`idle`, `alerted`, `hunting`, `extorting`, etc.).
- Hysteresis/release gates and hostility-profile adjustments.
- Eligibility flags for social actions (extort/light raid/full raid/wall probe).

Does **not** own:
- Pulling raw world sensors directly each frame.
- Assigning per-member tactical jobs.
- Executing extortion/raid runtime steps directly.

Current repo mapping (likely Intent owners):
- `scripts/world/BanditIntentPolicy.gd` (intent evaluation and action eligibility policy).
- `scripts/world/BanditGroupIntel.gd` (currently mixes sensing + intent mutation; should call policy and emit normalized intent outputs).

---

## 3) Task planning: what belongs here
Task planning is **declarative assignment**, not movement.

Owns:
- Turning current intent + group context into per-member orders.
- Role-specific assignment (`pickup_target`, `mine_target`, `follow_slot`, `return_home`, etc.).
- Recompute/cache/invalidations for order plans.
- Work-cycle stage progression rules (guard conditions and transitions).

Does **not** own:
- Physics velocity application.
- Node mutation side effects like `queue_free()` directly inside pure planners.

Current repo mapping (likely Task owners):
- `scripts/world/BanditGroupBrain.gd` (macro-state resolution + group order assignment).
- `scripts/world/BodyguardController.gd`, `scripts/world/ScavengerController.gd` (role tactical planners).
- `scripts/world/BanditWorkCoordinator.gd` (resource-cycle transition coordination; should remain stage coordinator, not high-level intent policy).

---

## 4) Execution: what belongs here
Execution is **runtime actuation and side effects**.

Owns:
- Applying task/order outputs to behavior state machines and desired velocity.
- Applying desired velocity to live NPC nodes.
- Concrete world interactions (pickup/deposit/hit/spawn/consume) via runtime systems.
- Tick scheduling and coordinator wiring needed to run active NPCs.

Does **not** own:
- Choosing social intent policy thresholds.
- Re-scoring settlement threat policy itself.
- Becoming a long-term memory store.

Current repo mapping (likely Execution owners):
- `scripts/world/NpcWorldBehavior.gd` and `scripts/world/BanditWorldBehavior.gd` (state machine execution and movement intent).
- `scripts/world/BanditBehaviorLayer.gd` (orchestration loop, ctx build, physics application).
- `scripts/world/BanditCampStashSystem.gd` (deposit/pickup carry side effects).
- `scripts/world/BanditExtortionDirector.gd`, `scripts/world/BanditRaidDirector.gd`, `scripts/world/BanditTerritoryResponse.gd` (runtime social/raid execution flows).

---

## 5) What `BanditBehaviorLayer` is still allowed to own
`BanditBehaviorLayer` should remain the **runtime composition/orchestration node**:
- Behavior instance lifecycle (create/prune per active NPC).
- Tick cadence integration and per-NPC execution context assembly.
- Wiring among execution collaborators (work coordinator, stash, directors, simulator).
- Applying final desired velocity to eligible NPC nodes.
- Lightweight instrumentation and runtime counters for execution health.

---

## 6) What `BanditBehaviorLayer` must stop owning over time
`BanditBehaviorLayer` should progressively stop owning:
- Raw sensing/policy logic (scoring and intent threshold rules).
- Group-level planning decisions (who does what and why).
- Blackboard schema evolution and social memory semantics.
- Mixed “decide + execute” methods that bypass planner/policy boundaries.
- Feature-specific branching that belongs in policy/planner modules.

Target: `BanditBehaviorLayer` consumes **already-normalized** inputs:
- `PerceptionSnapshot`
- `IntentSnapshot`
- `TaskAssignments`
…and focuses on execution wiring only.

---

## 7) Existing file map to pipeline stages (practical)

| Stage | Primary files now | Notes for Phase 5 normalization |
|---|---|---|
| Perception | `scripts/world/BanditGroupIntel.gd`, `scripts/world/SettlementIntel.gd`, `scripts/systems/BanditGroupMemory.gd` | Separate scanner outputs from policy mutation side effects. |
| Intent | `scripts/world/BanditIntentPolicy.gd` (+ intent-mutation path in `BanditGroupIntel.gd`) | Centralize intent decision contract in policy output DTOs. |
| Task | `scripts/world/BanditGroupBrain.gd`, `scripts/world/BodyguardController.gd`, `scripts/world/ScavengerController.gd`, `scripts/world/BanditWorkCoordinator.gd` | Keep assignments declarative; isolate transition guards from execution side effects. |
| Execution | `scripts/world/BanditBehaviorLayer.gd`, `scripts/world/BanditWorldBehavior.gd`, `scripts/world/NpcWorldBehavior.gd`, `scripts/world/BanditCampStashSystem.gd`, `scripts/world/BanditExtortionDirector.gd`, `scripts/world/BanditRaidDirector.gd` | Preserve runtime behavior while replacing ad-hoc decision logic with staged inputs. |

---

## 8) Migration sequence for next Phase 5 tasks
1. **Freeze contract vocabulary**
   - Introduce lightweight dictionary contracts (or typed wrappers later): `PerceptionSnapshot`, `IntentSnapshot`, `TaskAssignments`, `ExecutionContext`.
   - No behavior changes yet; only adapters at boundaries.

2. **Extract Perception output boundary**
   - Make `BanditGroupIntel` emit normalized perception payloads before mutating memory/intent.
   - Keep existing writes for compatibility; add dual-path logging for parity.

3. **Route Intent through policy output DTO**
   - Standardize `BanditIntentPolicy.evaluate(...)` output consumption in one place.
   - Remove direct “intent branching” from execution-heavy methods where possible.

4. **Normalize Task assignment handoff**
   - Make `BanditGroupBrain` the authoritative per-member assignment producer.
   - `BanditWorkCoordinator` should consume assignments + emit transition events, not infer global intent.

5. **Constrain Execution to actuation**
   - `BanditBehaviorLayer` consumes snapshots/assignments and applies movement/side effects only.
   - Keep directors/stash as execution collaborators behind explicit calls.

6. **Delete duplicated decision paths**
   - Remove legacy in-layer fallbacks once parity metrics confirm stable behavior.
   - Keep debug toggles/telemetry but tied to stage outputs, not hidden local heuristics.

7. **Phase 5 exit criteria**
   - Every bandit decision path traceable as: `Perception -> Intent -> Task -> Execution`.
   - `BanditBehaviorLayer` contains orchestration/actuation only.
   - No runtime behavior rewrite required; only ownership normalization completed.
