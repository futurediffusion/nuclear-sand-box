# Sandbox Migration History (Consolidated)

This document consolidates the high-level migration timeline that was previously split across many phase-specific markdown files.

For deep phase detail, see `docs/archive/migrations/`.

## Timeline

### Phase 1 — `world.gd` boundary freeze and extraction setup
- Established orchestration-only boundary for `world.gd`.
- Introduced command-dispatcher entry point and transition adapter strategy.
- Captured initial audits/metrics and phase closure evidence.

### Phase 2 — Building vertical slice
- Standardized building/wall ownership into dedicated domain systems.
- Reduced direct gameplay mutation paths from orchestration code.

### Phase 3 — Placement reaction boundary cleanup
- Separated placement/reaction decision logic from orchestration.
- Documented migration contract and closure checks.

### Phase 4 — Explicit projections
- Clarified projections as derived/read-model layers.
- Formalized projection invalidation/rebuild contracts.

### Phase 5 — Bandit AI pipeline extraction
- Isolated AI decision/pipeline responsibilities.
- Completed vertical-slice and pipeline handoff away from mixed ownership.

### Phase 6 — Snapshot persistence hardening
- Consolidated persistence ownership and snapshot boundaries.
- Closed migration loop for canonical save/load responsibility.

## How to use this history

- Use this file to understand **what changed and when**.
- Use `docs/architecture/current_sandbox_architecture.md` + `docs/architecture/ownership/*` for **current truth**.
- Use `docs/archive/migrations/` only when you need phase-level historical evidence.
