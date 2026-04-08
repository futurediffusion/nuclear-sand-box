# Constitution: World Bootstrap / Orchestration

## Source of truth
- `world.gd` owns composition state (wiring, lifecycle, tick cadence), not gameplay domain truth.

## Read models / projections
- `world.gd` can coordinate projection invalidation/rebuild and expose facade reads.

## Allowed writers
- Dependency wiring/setup, callback registration, orchestrator counters/telemetry.
- Delegation into command dispatcher, domain systems, and projection systems.

## Allowed readers
- Runtime node tree, subsystem handles, diagnostics snapshots.

## Allowed side effects
- Bootstrap scene/system setup.
- Tick scheduling and bounded refresh loops.
- Save/load orchestration hooks and projection rebuild orchestration.

## Forbidden writes / authority
- No new domain policy logic in `world.gd`.
- No canonical subsystem writes that bypass owning system APIs.
- Any new gameplay command entering `world.gd` must delegate first to dispatcher/owner instead of implementing local business rules.
