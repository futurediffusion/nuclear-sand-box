# world.gd responsibility audit (phase 2)

Date: 2026-04-08

## Classification snapshot

### 1) Composition/bootstrap
- Subsystem construction and wiring in `_ready()` and `_setup_building_module()`.
- Runtime dependency assembly for wall, building, cadence, telemetry, social, and projection modules.

### 2) Lifecycle/tick orchestration
- Lane scheduling via `WorldCadenceCoordinator`.
- Frame orchestration (`_process`, pulse handlers, chunk transitions, autosave trigger).
- Load/save lifecycle glue (`_notification`, deferred projection rebuild after snapshot load).

### 3) Legacy wrapper surface
- World public wall APIs kept for compatibility (`can_place_player_wall_at_tile`, `place_player_wall_at_tile`, damage/hit/remove variants).
- Settlement intel passthrough APIs kept for compatibility (`record_interest_event`, `get_detected_bases_near`, etc.).
- These wrappers now carry explicit `Legacy façade-only API` markers in `world.gd`.

### 4) Domain/tuning/config ownership
- **Moved in this phase:** placement-reaction tuning is now owned by `PlacementReactionRuntimeConfig` resource.
- `world.gd` now exports a single `placement_reaction_config` handle and forwards the payload to `PlacementReactionSystem`.

### 5) Projection/integration glue
- Projection refresh/dirty plumbing remains in `world.gd` as orchestration glue:
  - wall collider refresh queue bridging,
  - settlement dirty markers,
  - territory rebuild request triggers.
- This remains intentional while multiple modules still coordinate through world-level cadence and chunk lifecycle.

## Incremental migration outcome
- Reduced direct tuning authority in `world.gd` for placement-reaction behavior.
- Preserved runtime behavior by keeping defaults in `PlacementReactionRuntimeConfig` aligned with previous world exports.
- Explicitly documented wrapper intent to avoid accidental re-expansion of world ownership.
