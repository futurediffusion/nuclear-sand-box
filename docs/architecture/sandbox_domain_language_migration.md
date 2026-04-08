# Sandbox Domain Language Migration Guide

Date: 2026-04-08  
Status: Incremental standardization (non-breaking)

## Why this document exists

The sandbox has matured across multiple phases (building vertical slice, explicit projections, persistence snapshots, AI pipeline extraction). That progress also introduced layered vocabulary for the same concepts.

This guide defines one preferred language and a practical migration path so code, docs, telemetry, persistence, and AI surfaces speak the same conceptual dialect.

---

## 1) Vocabulary audit summary

### A) Structures, placeables, buildables

Observed overlap:
- `structure`
- `player_wall` / `structural_wall`
- `placeable`
- `buildable`
- ad-hoc counters like `structure_counts`

Current architecture direction already converges via:
- `SandboxStructureContract`
- `SandboxStructureRepository`

Preferred language:
- **structure_record**: canonical record shape for chunk-owned structures.
- **placeable_structure**: placeable entities represented under structure contract.
- **buildable_item**: catalog/item-level constructible definition (input to placement/building).

### B) AI intent/task pipeline

Observed overlap:
- `intent`, `current_group_intent`, `canonical_intent`, `canonical_intent_record`
- `task`, `order`, `task_planner`

Preferred language:
- **intent_record**: canonical decision payload between decision and execution layers.
- **task_plan**: planned execution payload (order + typed task data).
- Keep `order` as execution command field, but document it as part of task_plan output.

### C) Projections and snapshots

Observed overlap:
- `projection`, `read_model`, runtime cache naming
- `snapshot`, `world_snapshot_state`, `version` fallback

Preferred language:
- **derived_projection**: any rebuildable read model/cache layer.
- **canonical_snapshot**: persisted authority payload (`snapshot_version` contract).
- Legacy envelopes/keys remain compatibility-only and should be tagged as such.

### D) Runtime-only / legacy migration language

Observed overlap:
- `runtime-only`, `derived`, `cache`, `legacy`, `fallback`, `bridge`

Preferred language:
- **runtime_derived**: state that must never become persistence truth.
- **compat_legacy_hint**: transitional hints/fallbacks accepted during migration.
- **migration_steps**: deterministic migration trail previously referred to as migration path.

---

## 2) Canonical term map (preferred vs deprecated)

| Concept | Preferred term | Deprecated / legacy variants | Notes |
|---|---|---|---|
| Structure row/entry | `structure_record` | `structure`, `structure row` | Use for repository/DTO language. |
| Placeables under structure boundary | `placeable_structure` | `placeable` (ambiguous) | Keep `placeable` in gameplay UX, prefer `placeable_structure` in architecture docs/contracts. |
| Item-level constructible | `buildable_item` | `buildable` (noun) | Clarifies this is catalog/input, not world instance. |
| AI decision artifact | `intent_record` | `canonical_intent` | Keep field compatibility while migrating readers/writers. |
| AI execution plan | `task_plan` | `task`, `task_planner` (as payload name) | Planner class name may stay; payload should use task_plan language. |
| Query/cache layer | `derived_projection` | `projection` (unqualified), `runtime map` | Highlights rebuildable/non-authoritative role. |
| Persisted world envelope | `canonical_snapshot` | `world_snapshot_state`, generic `snapshot` | Keep old envelope support as compatibility only. |
| Non-persisted state | `runtime_derived` | `runtime-only`, `cache-only` | Prefer one label in diagnostics/docs. |
| Transitional fallback signal | `compat_legacy_hint` | `legacy hint`, `legacy fallback` | Use to explicitly isolate migration debt. |
| Migration trail | `migration_steps` | `migration_path` | Keep both keys during transition. |

---

## 3) What changed in this pass

1. Introduced a single code-level vocabulary snapshot (`SandboxDomainLanguage`) used by diagnostics and migrations.
2. Diagnostics now expose preferred terms while preserving legacy aliases:
   - `world_runtime.structure_record_counts` (preferred)
   - `world_runtime.structure_counts` (legacy alias)
   - `compatibility_bridges.bandit_task_plan` (preferred)
   - `compatibility_bridges.bandit_task_planner` (legacy alias)
3. Snapshot v1→v2 migration metadata now includes:
   - domain language snapshot
   - explicit runtime-derived sections
   - compatibility legacy hints
   - deterministic `migration_steps`

---

## 4) Migration policy (incremental, non-breaking)

1. **Add preferred term first**, keep legacy alias in telemetry/API during transition windows.
2. **Tag compatibility reads/writes** with `compat_legacy_hint` semantics in debug/diagnostics.
3. **Never persist runtime_derived state** as canonical snapshot truth.
4. **Prefer bounded renames** at architecture boundaries (DTOs/contracts/docs) over broad symbol churn.
5. Remove legacy aliases only when all known consumers have migrated.

---

## 5) Recommended next steps

1. Extend AI pipeline DTO names to include `intent_record` / `task_plan` aliases end-to-end.
2. Normalize docs under `docs/architecture/ownership/*` to use preferred terms consistently.
3. Add lightweight lint/check script to flag newly introduced deprecated terms in architecture-facing docs and telemetry keys.
