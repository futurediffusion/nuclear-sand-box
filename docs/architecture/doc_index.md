# Documentation Taxonomy Index

Last reviewed: 2026-04-08  
Scope: major architecture + contributor-guidance markdown docs in this repository.

## How to use this index

- Start with **Current reference** docs for architecture truth.
- Use **Operational guide** docs for runbooks/checklists/process.
- Read **Historical migration artifact** docs only for change history/context.
- Treat **Obsolete / archive** docs as non-authoritative; delete or move to an `archive/` folder.

---

## Current reference (safe as current truth)

| Document | Purpose | Safe to rely on? | Supersedes / Notes |
|---|---|---|---|
| `docs/architecture/current_sandbox_architecture.md` | Canonical, current architecture boundary map and ownership model. | **Yes** | Primary architecture source of truth. |
| `docs/architecture/ownership/README.md` | Ownership constitution entrypoint for all subsystem boundaries. | **Yes** | Use with all constitution files below. |
| `docs/architecture/ownership/building-structures.md` | Write authority for structures/building domain. | **Yes** | Replaces older phase-specific wall/building ownership assumptions. |
| `docs/architecture/ownership/projections.md` | Projection/read-model boundary rules. | **Yes** | Supersedes phase-local projection ownership notes. |
| `docs/architecture/ownership/ai-pipeline.md` | AI pipeline ownership and separation rules. | **Yes** | Supersedes phase-local AI ownership guidance. |
| `docs/architecture/ownership/persistence.md` | Persistence ownership and canonical snapshot boundaries. | **Yes** | Supersedes phase-local persistence ownership notes. |
| `docs/architecture/ownership/territory-settlement.md` | Territory/settlement authority boundaries. | **Yes** | Current constitution for territory/settlement truth. |
| `docs/architecture/ownership/world-bootstrap-orchestration.md` | `world.gd` orchestration/bootstrap authority limits. | **Yes** | Current authority for orchestration boundaries. |
| `docs/architecture/sandbox_domain_language_migration.md` | Preferred cross-module vocabulary and migration policy. | **Yes (for terminology policy)** | Active standardization guide; complements ownership docs. |
| `docs/social_world_architecture.md` | Current social-system boundary direction and integration seams. | **Yes (directional)** | Use as social architecture boundary note until folded into ownership constitution. |

---

## Operational guide (process/runbook/checklist docs)

| Document | Purpose | Safe to rely on? | Supersedes / Notes |
|---|---|---|---|
| `CLAUDE.md` | Contributor quickstart and repo entrypoint; points to canonical architecture doc. | **Yes (onboarding)** | Operational entrypoint, not the architecture authority itself. |
| `docs/architecture/sandbox-contract.md` | Enforces `world.gd` freeze/guardrails during refactor workflow. | **Yes (process guardrail)** | Contractual process doc; architecture details still come from current architecture + ownership docs. |
| `docs/ai_squad_refactor_board.md` | PR triage and phase-gate checklist for active AI refactor work. | **Yes (if refactor is active)** | Operational board; not architecture source of truth. |
| `docs/smoke_test.md` | Deterministic smoke-test procedure. | **Yes (testing runbook)** | Testing guide only. |
| `docs/walls_colliders_checklist.md` | Manual gate checklist for walls/colliders flows. | **Partially** | Keep only if still used in CI/release gate; otherwise archive. |
| `docs/perf_kpi_event_invalidation_buffers.md` | KPI measurement/validation plan for perf-sensitive invalidation work. | **Partially** | Useful as runbook if KPI gate still active; otherwise archive. |

---

## Historical migration artifact (use for context/history only)

| Document | Purpose | Safe to rely on? | Superseded by |
|---|---|---|---|
| `docs/architecture/sandbox-migration-log.md` | Phase closure timeline/checkpoints. | **No** | `current_sandbox_architecture.md` + ownership constitution set. |
| `docs/architecture/world_gd_audit_phase1.md` | Phase 1 baseline responsibility audit. | **No** | `ownership/world-bootstrap-orchestration.md`. |
| `docs/architecture/world_gd_responsibility_audit_phase2.md` | Phase 2 responsibility snapshot. | **No** | `ownership/world-bootstrap-orchestration.md` + current architecture doc. |
| `docs/architecture/world_gd_metrics.md` | Phase-era metrics baseline for world extraction. | **No (historical baseline)** | Keep for trend history only. |
| `docs/architecture/world_phase1_transition_adapters.md` | Transition adapter notes for phase 1 migration. | **No** | Ownership constitution + current orchestration rules. |
| `docs/architecture/sandbox_structure_unification_migration.md` | Incremental migration plan for structure/placeable unification. | **No (unless actively executing this migration)** | `ownership/building-structures.md` + language migration guide. |
| `docs/architecture/sandbox_tick_domain_audit.md` | Tick-domain audit snapshot used during migration. | **No** | Current architecture and orchestration constitution. |
| `docs/architecture/typed_event_contracts_audit_phase1.md` | Typed-event migration pass report. | **No** | Current DTO/contracts in code + ownership constitutions. |
| `docs/building_vertical_slice_contract.md` | Phase 2 contract for building vertical slice. | **No** | Ownership constitutions + current architecture doc. |
| `docs/building_vertical_slice_phase2_done.md` | Phase 2 closure record. | **No** | Same as above. |
| `docs/phase3_placement_reaction_audit.md` | Phase 3 pre-refactor audit snapshot. | **No** | AI/world ownership constitutions + current architecture. |
| `docs/phase3_placement_reaction_contract.md` | Phase 3 migration contract. | **No** | Ownership constitutions + current architecture. |
| `docs/phase3_placement_reaction_done.md` | Phase 3 closure record. | **No** | Same as above. |
| `docs/phase4_projection_audit.md` | Phase 4 projection audit snapshot. | **No** | `ownership/projections.md`. |
| `docs/phase4_explicit_projections_contract.md` | Phase 4 migration contract. | **No** | `ownership/projections.md` + current architecture. |
| `docs/phase4_explicit_projections_done.md` | Phase 4 closure record. | **No** | Same as above. |
| `docs/phase5_bandit_ai_audit.md` | Phase 5 AI-stack audit snapshot. | **No** | `ownership/ai-pipeline.md` + current architecture. |
| `docs/phase5_bandit_ai_pipeline_contract.md` | Phase 5 pipeline migration contract. | **No** | `ownership/ai-pipeline.md` + current architecture. |
| `docs/phase5_bandit_ai_pipeline_done.md` | Phase 5 closure record. | **No** | Same as above. |
| `docs/phase5_structure_assault_vertical_slice.md` | Phase 5 vertical-slice plan/context. | **No** | `ownership/ai-pipeline.md` + current architecture. |
| `docs/phase6_persistence_audit.md` | Phase 6 persistence audit snapshot. | **No** | `ownership/persistence.md` + current architecture. |
| `docs/phase6_snapshot_persistence_contract.md` | Phase 6 migration contract. | **No** | `ownership/persistence.md` + current architecture. |
| `docs/phase6_snapshot_persistence_done.md` | Phase 6 closure record. | **No** | Same as above. |
| `docs/player_wall_system_migration.md` | Legacy migration notes for wall config ownership shift. | **No** | `ownership/building-structures.md` + current architecture. |

---

## Obsolete / should be deleted or archived

| Document | Why obsolete | Action |
|---|---|---|
| `REGISTRO_CAMBIOS_DESDE_AGENTS.md` | Point-in-time change log tied to a specific AGENTS update/commit range; high drift risk and not architecture authority. | **Archive or delete** (prefer git history for this). |
| `docs/bandit-worker-fix-plan.md` | Tactical incident/work-item planning doc; not reusable architecture guidance. | **Archive** under incident history. |
| `docs/bandit-worker-fix-execution.md` | Execution log for a specific fix cycle. | **Archive**. |
| `docs/bandit-worker-regression-analysis.md` | Commit-specific regression analysis snapshot. | **Archive**. |
| `docs/bandit_ai_debt_after_normalization_pass.md` | Post-pass debt snapshot likely stale as code evolves. | **Archive** (or convert active items into issue tracker). |
| `docs/bandit_behavior_baseline_snapshots.md` | Snapshot baseline report likely stale unless continuously refreshed. | **Archive** unless actively maintained with date cadence. |
| `docs/bandit_rollout_flags_snapshot_report.md` | Rollout snapshot report; historical by nature. | **Archive**. |
| `docs/incidencias/INC-TECH-001-bloqueo-runtime-godot-checklist-walls.md` | Incident-specific checklist; not general architecture/contributor truth. | **Archive** in incident folder with clear historical label. |

---

## Suggested cleanup policy

1. Keep **Current reference** docs lean and linked from contributor entrypoints (`CLAUDE.md`, future `AGENTS.md`).
2. Move all **Historical migration artifact** docs into `docs/archive/migrations/` (preserve history, reduce confusion).
3. Move **Obsolete** tactical/incident docs into `docs/archive/incidents/` or delete if duplicated by issue tracker/git history.
4. Add a short “Read this first” pointer in `CLAUDE.md` to this index so contributors and agents start from one taxonomy page.
