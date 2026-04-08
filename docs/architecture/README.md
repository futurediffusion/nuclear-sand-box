# Architecture Docs Map

Use this map to avoid triangulating architecture truth across multiple old phase docs.

## 1) Current architecture (authoritative)
- `current_sandbox_architecture.md` — canonical system boundary map.
- `ownership/README.md` + ownership docs — subsystem write/read ownership constitution.
- `sandbox_domain_language_migration.md` — active terminology standardization policy.
- `../social_world_architecture.md` — current social-system boundary direction.

## 2) Migration history (historical, non-authoritative)
- `migration_history.md` — consolidated phase timeline.
- `../archive/migrations/` — detailed archived phase docs and audits.

## 3) Contributor quickstart
- `../../CLAUDE.md` — onboarding and day-to-day contributor entrypoint.

## 4) Operational/how-to guides
- `sandbox-contract.md` — process guardrails during refactors.
- `../smoke_test.md` — smoke test runbook.
- `../walls_colliders_checklist.md` — walls/collider manual checklist.
- `../perf_kpi_event_invalidation_buffers.md` — KPI validation runbook.

## Documentation policy

When adding docs:
1. Prefer updating an existing authoritative doc over creating a new overlapping one.
2. If a doc is phase-specific, place it directly under `docs/archive/migrations/` once complete.
3. Mark historical docs clearly as non-authoritative.
