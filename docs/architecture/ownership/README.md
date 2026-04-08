# Sandbox Ownership Constitution

This folder defines **write authority boundaries** for the sandbox runtime.

Use these docs as PR guardrails: if a change introduces a new write path, it must fit the owning subsystem rules below or explicitly amend this constitution in the same PR.

## Subsystems

- [Building / Structures](./building-structures.md)
- [Projections](./projections.md)
- [AI Pipeline](./ai-pipeline.md)
- [Persistence](./persistence.md)
- [Territory / Settlement](./territory-settlement.md)
- [World Bootstrap / Orchestration](./world-bootstrap-orchestration.md)

## Enforcement checklist (for PR reviews)

1. What is the source of truth for the state being changed?
2. Is the writer authorized by the subsystem constitution file?
3. Is this a projection/cache update (rebuildable) instead of a canonical write?
4. Are side effects routed through the owner (signals/ports/dispatchers), not ad-hoc direct mutation?
5. Does `world.gd` remain orchestration-only?
