# Phase 3 — Placement Reaction Audit (current state)

## Scope and objective
Audit **all active code paths** tied to placement-triggered hostile reactions before refactor.

This report maps:
- where placement reaction starts,
- where relevance/priority is evaluated,
- where assault intent is mutated/published,
- where reactions are dispatched/enqueued,
- duplicate/competing paths,
- `world.gd` responsibilities that must move vs stay.

---

## 1) Entry points (where placement reaction starts today)

### A. Primary hostile path: `PlacementSystem.placement_completed -> world.gd`
1. `PlacementSystem` emits `placement_completed(item_id, tile_pos)` for wall and scene placements.
2. `world.gd` connects this signal in `_ready` and handles it in `_on_placement_completed`.
3. `_on_placement_completed` throttles by `_PLACEMENT_REACT_EVENT_MIN_INTERVAL` and calls `_trigger_placement_react(item_id, world_pos)`.

**Classification**
- `PlacementSystem` emit: **runtime wiring/event source**
- `world.gd._on_placement_completed`: **runtime wiring + light policy (throttle)**
- `world.gd._trigger_placement_react`: **domain logic (currently oversized)**

### B. Parallel placement listeners (non-hostile but same trigger)
The same `placement_completed` signal is also consumed by:
- `SettlementIntel._on_placement_completed` (interest markers + dirty scans)
- `WorldSpatialIndex._on_placement_completed` (placeable index invalidation)

These do **not** directly trigger assault but are adjacent pathways consuming the same source event.

**Classification**
- `SettlementIntel`: **projection/read-model + domain-adjacent intel write**
- `WorldSpatialIndex`: **projection/index maintenance**

### C. Wall-destruction event exists, not part of placement-react yet
- `PlayerWallSystem` emits `player_wall_drop` and `structural_wall_drop`.
- `world.gd` currently wires only `player_wall_drop -> _on_wall_drop_for_intel` (intel + territory dirty/hotspot), not hostile reaction trigger.

This is relevant because Phase 3 contract expects wall-drop assault signals to enter the reaction pipeline.

---

## 2) Relevance and priority evaluation

## Current owner: `world.gd`
`_trigger_placement_react` currently performs full selection policy:
- Candidate group enumeration from `BanditGroupMemory.get_all_group_ids()`
- Hostility gate: `_is_group_hostile_for_structure_assault` and `_is_faction_baseline_hostile_to_player`
- Anchor resolution: `_get_group_react_anchor` (leader/center/home fallback)
- Radius gate: `_get_placement_react_radius` (including global wall-assault mode)
- Relevance score: `_score_placement_relevance` composed of:
  - distance,
  - base proximity,
  - points-of-interest via `_score_placement_react_points_of_interest`,
  - path blocking via `_score_placement_react_blocking` with `NpcPathService` budget/cache context.
- Sorting and cap: score desc + distance tie-break, `placement_react_max_groups_per_event`
- Lock override policy:
  - `has_placement_react_lock`
  - `get_placement_react_attempt`
  - min deltas `placement_react_lock_min_relevance_delta` / `placement_react_lock_min_distance_delta_px`
- High-priority squad sizing: `_resolve_placement_react_squad_size`

**Classification**
- Entire block is **domain logic** (should not remain in `world.gd` long-term).

---

## 3) Assault intent mutation/publication

### A. Placement-react write path (today)
Inside `world.gd._trigger_placement_react`, for accepted groups:
- `BanditGroupMemory.record_interest(gid, target_pos, "structure_placed")`
- `BanditGroupMemory.set_placement_react_lock(...)`
- `BanditGroupMemory.set_placement_react_attempt(...)`
- `BanditGroupMemory.update_intent(gid, "raiding")`
- `BanditGroupMemory.publish_assault_target_intent(..., source=ASSAULT_INTENT_SOURCE_PLACEMENT_REACT)`

### B. Priority semantics live in `BanditGroupMemory`
`publish_assault_target_intent` applies source priority:
- `placement_react` > `raid_queue` > `opportunistic`

This means placement-react can overwrite/beat lower-priority assault intents.

**Classification**
- `world.gd` writes: **domain logic**
- `BanditGroupMemory` persistence/priority API: **domain state boundary**

---

## 4) Dispatch/enqueue paths (direct or indirect reaction execution)

### A. Indirect dispatch path used by placement-react
Placement-react itself does not directly move NPCs. It publishes intent. Execution chain:
1. `RaidFlow.process_flow` consumes memory assault intents (`_consume_memory_assault_intents`) and creates `structure_assault` jobs.
2. `RaidFlow._tick_structure_assault` resolves live targets, refreshes intent heartbeat, and calls `_dispatch_group`.
3. `_dispatch_group` delegates to `BanditBehaviorLayer.dispatch_group_to_target`.
4. `BanditBehaviorLayer` redirects active members or queues pending target for not-yet-spawned members.

### B. Direct enqueue competitor path
`BanditGroupIntel` independently enqueues raids/probes and sets `current_group_intent` to `raiding`:
- `_maybe_enqueue_raid`
- `_maybe_enqueue_light_raid`
- `_maybe_enqueue_wall_probe`

`RaidFlow._consume_raid_queue` may publish/refresh structure assault intent from queue entries.

### C. Opportunistic direct behavior competitor
`BanditWorldBehavior` can call `enter_wall_assault(...)` from local opportunistic behavior (`_try_opportunistic_wall_assault`, `_try_property_sabotage`) without going through placement event scoring.

**Classification**
- `RaidFlow`: **runtime orchestration + domain flow application**
- `BanditBehaviorLayer.dispatch_group_to_target`: **runtime execution/orchestration**
- `BanditGroupIntel` enqueue methods: **domain logic (parallel intent producer)**
- `BanditWorldBehavior` opportunistic assault: **runtime AI behavior (competing attack source)**

---

## 5) Duplicate / competing paths (important before refactor)

1. **Multiple producers for `raiding` / assault intent**
   - `world.gd` placement-react path
   - `BanditGroupIntel` scan-driven raid/probe enqueue path
   - `RaidFlow` queue-consume path that can publish assault intent
   - `BanditWorldBehavior` opportunistic local assault movement

2. **Multiple consumers of placement event**
   - `world.gd`, `SettlementIntel`, `WorldSpatialIndex` all subscribe to `PlacementSystem.placement_completed`.
   - No unified event normalization layer yet.

3. **Two target memory channels in use**
   - modern `assault_target_intent`
   - compat `set_assault_target/get_assault_target` wrappers (still used by `BanditBehaviorLayer` pending dispatch when no spawned members)

4. **Lock interplay between systems**
   - `world.gd` sets placement-react lock/attempt context
   - `BanditGroupIntel` explicitly avoids downgrading to `idle` while lock active
   - `RaidFlow` clears placement-react context at structure assault finish

5. **Wall-drop signal partially wired**
   - player wall drop is wired only to intel hotpaths;
   - structural wall drop not wired in world setup;
   - neither currently enters placement-react hostility trigger path.

---

## 6) `world.gd` responsibilities related to placement reaction

## Currently in `world.gd` (placement-react related)
- Signal wiring from `PlacementSystem.placement_completed`.
- Event throttle state and debug counters/snapshots.
- Full candidate selection/scoring/hostility policy.
- Intent mutation and assault-intent publication into `BanditGroupMemory`.
- Auxiliary helpers used by scoring:
  - anchor resolution,
  - hostility baseline checks,
  - POI extraction from `WorldSpatialIndex` + drop hotspots,
  - blocking checks through `NpcPathService` budget context,
  - radius/squad-size thresholds.

## Should move in Phase 3
Move out of `world.gd` into domain services/pipeline:
- `_trigger_placement_react` core decision loop.
- `_score_placement_relevance` + POI/blocking scoring helpers.
- group hostility decision helpers for structure assault relevance.
- lock override policy semantics (delta thresholds) as explicit intent policy.
- squad-size selection policy for high-priority events.

## Should stay for now
Remain in `world.gd` as façade/wiring until full migration parity:
- subscription to source events (`PlacementSystem` and bridge events).
- delegation call into Phase 3 pipeline.
- debug/telemetry wrappers (or temporary bridge metrics).
- compatibility facades used by legacy callers (`record_interest_event`, etc.).

---

## 7) Precise migration map (Phase 3)

| Current location | Current function(s) | Current role | Phase 3 target | Action |
|---|---|---|---|---|
| `scripts/world/world.gd` | `_on_placement_completed` | placement event bridge + throttle | world façade + event adapter | **Keep**, but delegate to new placement-reaction pipeline input. |
| `scripts/world/world.gd` | `_trigger_placement_react` | end-to-end domain decision + intent writes | `ThreatAssessmentSystem` + `GroupIntentSystem` | **Move** domain logic out; leave thin bridge only. |
| `scripts/world/world.gd` | `_score_placement_relevance`, `_score_placement_react_points_of_interest`, `_score_placement_react_blocking` | scoring formula and gates | `ThreatAssessmentSystem` | **Move** unchanged first (parity extraction). |
| `scripts/world/world.gd` | `_is_group_hostile_for_structure_assault`, `_is_faction_baseline_hostile_to_player`, `_get_group_react_anchor`, `_get_placement_react_radius`, `_resolve_placement_react_squad_size` | selection/policy helpers | threat + intent policy modules | **Move** to domain services. |
| `scripts/systems/BanditGroupMemory.gd` | `publish_assault_target_intent`, lock/attempt APIs | state boundary + priority semantics | unchanged boundary | **Stay** (may gain typed DTO usage later). |
| `scripts/world/RaidFlow.gd` | `_consume_memory_assault_intents`, `_tick_structure_assault`, dispatch loop | runtime orchestrator consuming intent | runtime orchestrator | **Stay** for now; consume new intent events/contracts transparently. |
| `scripts/world/BanditBehaviorLayer.gd` | `dispatch_group_to_target` | NPC dispatch runtime execution | runtime execution | **Stay** (not Phase 3 extraction target). |
| `scripts/world/BanditGroupIntel.gd` | `_maybe_enqueue_*raid*`, intent updates | independent raid/extortion producer | separate producer path | **Stay**, but document conflict precedence and avoid regressions. |
| `scripts/world/SettlementIntel.gd` / `scripts/world/WorldSpatialIndex.gd` | placement signal handlers | projection/index updates | projection layer | **Stay**; potential future event bus unification optional. |
| `scripts/world/PlayerWallSystem.gd` + `world.gd` wiring | wall-drop signals | currently intel-only bridge | placement-reaction input bridge | **Phase 3 add**: route wall-drop event into new reaction input (no heavy logic in `world.gd`). |

---

## 8) Refactor guardrails for next task
- Do **not** alter raid runtime behavior in this audit.
- Preserve source-priority semantics in `BanditGroupMemory`.
- Preserve lock lifecycle: set on placement react, clear on structure assault finish.
- Keep `world.gd` backward-compatible wrappers while extracting domain logic.
- Migrate in parity mode first (behavior-equivalent extraction), then simplify duplicates.
