# Phase 5 Bandit AI Audit (Current Stack)

## Scope
This audit maps the current decision path across the bandit AI stack and highlights where **perception**, **intent**, **task assignment**, and **execution** are mixed or duplicated.

Primary references reviewed:
- `BanditBehaviorLayer`
- `BanditWorldBehavior`
- `BanditWorkCoordinator`
- `BanditGroupBrain`
- `BanditGroupIntel`
- `BanditIntentPolicy`
- `RaidFlow` / `BanditRaidDirector`
- `BanditGroupMemory`
- placement-reaction intent path (`GroupIntentSystem`, `PlacementReactionSystem`)

---

## 1) Files currently doing perception-like work

### Core perception producers
- **`scripts/world/BanditGroupIntel.gd`**
  - Group-level scanning of markers/bases, scoring activity, and converting scan inputs into policy inputs.  
  - Also emits presence hostility signals and triggers social escalations (extortion/raid/wall-probe enqueues).  
- **`scripts/world/BanditBehaviorLayer.gd`**
  - Per-member runtime context construction for behavior ticks (`nearby_drops_info`, `nearby_res_info`, leader/follow slots, combat/recent-engagement signals).  
  - Runs a separate **group perception pulse** and writes prioritized drops/resources to group blackboard.
- **`scripts/world/BanditWorkCoordinator.gd`**
  - Re-resolves local assault targets at runtime and builds per-group assault context caches with short TTLs.

### Secondary perception inputs
- **`scripts/systems/BanditGroupMemory.gd`** blackboard stores perception snapshots (`perception` section) used by other layers.
- **`scripts/domain/factions/ThreatAssessmentSystem.gd` + `PlacementReactionSystem.gd`** feed placement-threat perception into the bandit intent pipeline.

---

## 2) Files that decide or mutate intent-like state

### Intent mutation points
- **`scripts/world/BanditGroupIntel.gd`**
  - Evaluates policy and calls `BanditGroupMemory.update_intent(...)` during scan loops.
  - Explicitly upgrades to `"extorting"` / `"raiding"` when enqueue conditions pass.
- **`scripts/domain/factions/GroupIntentSystem.gd`**
  - Placement reaction path: records interest + lock + attempts, updates intent to `"raiding"`, publishes assault intent.
- **`scripts/world/RaidFlow.gd`**
  - Consumes queue/memory assault intents; on finish it resets group intent to `"idle"`.
- **`scripts/systems/BanditGroupMemory.gd`**
  - Canonical storage for `current_group_intent`, timestamps, assault context, and placement-react locks.

### Intent policy owner (pure policy)
- **`scripts/world/BanditIntentPolicy.gd`**
  - Good separation: computes thresholds/next intent eligibility from score + profile without mutating memory directly.

---

## 3) Files that assign task/order-like outputs

- **`scripts/world/BanditGroupBrain.gd`**
  - Computes per-member orders from group context (macro state + member state + blackboard).
  - Writes assignments into `BanditGroupMemory` blackboard.
- **`scripts/world/BanditBehaviorLayer.gd`**
  - Calls group brain to get orders, applies orders to behaviors (`_apply_member_order`), and also performs direct structure dispatch assignment (`bb_set_assignment(...assault_structure_target...)`).
  - Owns `dispatch_group_to_target(...)` callable used by RaidFlow and placement reaction.
- **`scripts/world/RaidFlow.gd`**
  - Job-level assignment/orchestration for raid stages and periodic dispatch target updates.
- **`scripts/world/BanditWorkCoordinator.gd`**
  - Performs guarded transition requests (`_request_return_home`, replan, post-hit continuity), effectively issuing low-level “next task” decisions during execution.

---

## 4) Files executing movement/combat/interaction

- **`scripts/world/NpcWorldBehavior.gd`**
  - Base movement/state-machine execution (patrol, follow, return home, loot/resource approach).
- **`scripts/world/BanditWorldBehavior.gd`**
  - Bandit-specific movement/combat state transitions, group-intent reaction, wall-assault entry, opportunistic sabotage, drop/work opportunism.
- **`scripts/world/BanditBehaviorLayer.gd`**
  - Applies desired velocity each physics frame, performs lifecycle orchestration, and invokes behavior ticks.
- **`scripts/world/BanditWorkCoordinator.gd`**
  - Executes world side effects: mining hits, loot/deposit handling, structure/wall damage, container looting, attack animation triggers.
- **`scripts/world/RaidFlow.gd`**
  - Executes raid-stage progression and dispatch calls (macro execution orchestrator).

---

## 5) Where layers compete to decide the same target/reaction

## A. Structure assault target selection is decided in multiple layers
- **RaidFlow** chooses/updates assault target from walls/placeables/intent fallback.
- **BanditBehaviorLayer** runs per-member structure target pool selection + slot assignment + direct `enter_wall_assault` dispatch.
- **BanditWorkCoordinator** re-resolves attack targets near assault anchors at execution time.
- **BanditWorldBehavior** may re-engage assault target from memory on intent changes or sticky checks.

**Net effect:** target authority is spread across macro job flow, group runtime dispatch, and per-NPC execution guard code.

## B. Intent transitions have multiple writers
- GroupIntel writes regular intent transitions from scans.
- GroupIntentSystem writes `raiding` for placement reaction.
- RaidFlow writes `idle` at raid finish.

**Net effect:** no single “intent arbiter” path; writers rely on ad-hoc precedence/locks.

## C. Assignment authority is split
- GroupBrain computes and caches member orders.
- BehaviorLayer can override/ignore generic orders during structure assault and write direct assignments itself.
- WorkCoordinator can force return/replan due to resource-cycle guards.

**Net effect:** tactical/micro assignment is robust but not single-owner; difficult to reason about why one order wins.

## D. Perception is duplicated by purpose and cadence
- GroupIntel scan loop (social perception).
- BehaviorLayer perception pulse and per-NPC local scans (work/runtime perception).
- WorkCoordinator builds short-lived assault context caches (combat-target perception).

**Net effect:** same practical question (“what should this group/NPC target now?”) is answered in multiple places.

---

## 6) Best candidates for first migration slice

### Recommended Slice 1: **Unify assault target authority**
Create a single read model for “active assault target contract” consumed by execution layers.

**Why first:**
- Highest overlap/duplication today (RaidFlow + BehaviorLayer + WorkCoordinator + WorldBehavior).
- Biggest source of sticky/override complexity and retarget race behavior.

**Minimal-scope migration steps:**
1. **Define canonical assault target contract** in one place (likely `BanditGroupMemory` blackboard/intent contract):
   - `anchor`, `target_pos`, `source`, `version`, `expires_at`, `reason`.
2. **Make RaidFlow the only writer** for active assault target changes during raid/structure-assault jobs.
3. **Demote BehaviorLayer target picking** to slotting/formation only (consume target, do not choose new world target except strict fallback telemetry).
4. **Demote WorkCoordinator target resolution** to validation/attack execution around the already-selected target (no independent retarget except fail-safe).
5. Keep WorldBehavior sticky re-engage logic, but only against canonical contract.

### Recommended Slice 2: **Intent write gate**
Introduce a lightweight intent arbiter API:
- `request_intent(group_id, next_intent, source, priority, ttl/lock)`
- Single conflict policy (placement_react > raid_queue > opportunistic > scan baseline).

This can initially wrap existing `BanditGroupMemory.update_intent` calls with minimal behavior change.

### Recommended Slice 3: **Perception channel separation**
Keep both loops but codify ownership:
- GroupIntel = social/perimeter perception.
- BehaviorLayer = tactical nearby work perception.
- WorkCoordinator = execution validation only.

Add explicit handoff fields in blackboard/contract to avoid recalculating equivalent targets in each layer.

---

## Migration map (concise)

| Layer | Current owners | Current overlap | First migration action |
|---|---|---|---|
| Perception | GroupIntel, BehaviorLayer, WorkCoordinator | Multiple scans choose/refresh targets | Keep 3 loops but standardize outputs and consumers |
| Intent | GroupIntel, GroupIntentSystem, RaidFlow | Multiple writers to `current_group_intent` | Add single request/gate API before storage |
| Task assignment | GroupBrain + BehaviorLayer + WorkCoordinator | Order generation and overrides compete | Keep GroupBrain as planner; centralize override reasons |
| Execution | NpcWorldBehavior, BanditWorldBehavior, WorkCoordinator | Execution + micro-decisions intertwined | Restrict execution layers to contract consumption + validation |
| Assault target authority | RaidFlow + BehaviorLayer + WorkCoordinator + WorldBehavior | Highest conflict area | Make RaidFlow/contract single source of truth |

---

## Notes
- The architecture already has good **named boundaries in comments**, but runtime authority still crosses those boundaries in structure-assault and intent transitions.
- This audit intentionally avoids refactor implementation; it identifies the first safe extraction seam to reduce decision contention with minimal gameplay risk.
