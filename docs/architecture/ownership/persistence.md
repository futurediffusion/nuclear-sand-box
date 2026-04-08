# Constitution: Persistence

## Source of truth
- Canonical save/load contract is snapshot-based (`WorldSnapshot`), adapted from authoritative owners (`WorldSave` + serialized domain systems).

## Read models / projections
- Runtime caches, loaded chunk sets, collider caches, spatial index, territory maps are non-canonical and rebuildable.

## Allowed writers
- `SaveManager` save/load entrypoints.
- Snapshot adapters/serializers (`WorldSaveAdapter`, `WorldSnapshotSerializer`).
- Canonical owners when applying load payload.

## Allowed readers
- Save pipeline reads canonical owners.
- Load pipeline reads persisted snapshot payload.

## Allowed side effects
- Pre-save flush of runtime entity state into canonical owners.
- Post-load projection invalidation/rebuild.

## Forbidden writes / authority
- Serializers must not gather truth directly from live scene nodes.
- Projection/runtime caches must not be persisted as authoritative game state.
- Gameplay systems must not bypass adapters to write disk payload format directly.
