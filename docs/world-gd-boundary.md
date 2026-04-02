# world.gd boundary contract

`world.gd` is a composition root. It can:

- Bootstrap runtime systems in `_ready`.
- Wire ports/callables between systems.
- Drive cadence loops and chunk/bootstrap lifecycle.
- Trigger **authorized** reset/snapshot operations (`new game`, `save/load`, chunk reload).

`world.gd` must **not** own gameplay decision semantics. In particular:

- No incident-to-offense mapping tables.
- No authority/sanction decision trees.
- No defense posture decision rules.
- No direct policy branching that selects sanctions/outcomes.
- No direct `*.reset()` calls to domain systems (only explicit orchestration ports).

## Decision logic moved out

- Tavern incident semantic mapping + sanction flow now live in `TavernAuthorityOrchestrator`.
- Tavern defense posture evaluation/propagation now lives in `TavernAuthorityOrchestrator`.

## PR review gate (mandatory)

Any PR touching `scripts/world/world.gd` must pass `World boundary guard` workflow.
The guard fails if `world.gd` reintroduces forbidden decision markers or direct `*.reset()` de dominio sin excepción aprobada.
