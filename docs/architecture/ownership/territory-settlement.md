# Constitution: Territory / Settlement

## Source of truth
- Settlement signal intake and marker/base detection owned by `SettlementIntel`.
- Territory policy decisions owned by `WorldTerritoryPolicy`.
- Player territory query map (`TerritoryProjection` / player territory map) is derived, not canonical ownership.

## Read models / projections
- Workbench/base marker query sets.
- Player territory map and zone query outputs.

## Allowed writers
- `GameplayCommandDispatcher` routes settlement write commands (`record_interest_event`, `rescan_workbench_markers`, `mark_interest_scan_dirty`) into owners.
- `SettlementIntel` writes settlement interest/memory structures.
- `WorldTerritoryPolicy` writes policy-side reaction state.

## Allowed readers
- Placement reaction, bandit intent, authority/response systems, and orchestration code through public APIs.

## Allowed side effects
- Trigger dirty marks for territory rebuild.
- Register operational hotspots used by runtime compaction/reaction loops.
- Emit policy/reaction events.

## Forbidden writes / authority
- `world.gd` must not implement direct settlement/territory policy rules.
- Territory query maps must not decide placement rights as canonical law.
- Other systems must not mutate settlement internals directly; go through dispatcher/owner APIs.
