# Phase 6 Snapshot Persistence Contract

## Scope
Phase 6 establishes persistence boundaries for save/load using **canonical snapshots**.

This contract is implementation-oriented and constrained to the current repo architecture (`SaveManager`, `WorldSave`, chunk systems, projection systems). It does **not** redesign world streaming or gameplay systems.

---

## 1) Canonical saveable state
Canonical saveable state is the minimum state required to deterministically rebuild runtime world/session state after load.

For this repo, canonical state includes:

- **World/session root state**
  - save metadata/version/seed
  - player core state currently persisted by `SaveManager` (position, inventory slots, gold)
  - world clocks/timers already persisted (`RunClock`, `WorldTime`)
- **Canonical world persistence owners**
  - `WorldSave.chunks` (chunk entity states + chunk flags)
  - `WorldSave.enemy_state_by_chunk`
  - `WorldSave.enemy_spawns_by_chunk`
  - `WorldSave.global_flags`
  - `WorldSave.player_walls_by_chunk`
  - `WorldSave.placed_entities_by_chunk`
  - `WorldSave.placed_entity_data_by_uid`
- **Existing domain-system persistent payloads** already serialized via SaveManager (faction/site/profile/memory/hostility/extortion systems).

Rule: if a value is required as authoritative input for reconstruction, it belongs in the canonical snapshot.

---

## 2) Non-canonical (must not be treated as save truth)
The following are **runtime/projection artifacts** and must not be promoted to canonical save truth:

- Live scene tree nodes and transient node references.
- Chunk streaming runtime caches (loaded chunk sets, staged queues, spawn jobs, perf windows).
- Projection/read-model internals (spatial index runtime buckets, collider cache bodies/hashes, territory query maps).
- Debug/telemetry snapshots and counters.
- Any state that can be rebuilt from canonical snapshot + deterministic rebuild flow.

These may be serialized only as optional diagnostics in the future, never as authoritative gameplay persistence.

---

## 3) Role of `WorldSnapshot` and chunk-level snapshots
Phase 6 introduces a **canonical aggregate contract**:

- **`WorldSnapshot` (root canonical DTO/Dictionary contract)**
  - Single top-level canonical payload consumed by save/load entrypoints.
  - Holds global/world-level canonical sections and a chunk-snapshot collection.
- **Chunk-level snapshots**
  - Canonical per-chunk payloads derived from existing owners (`WorldSave.chunks`, walls/placeables/enemy chunk maps).
  - Must be self-contained for chunk-owned state and stable across runtime refactors.

Boundary intent:
- save/load code reads/writes one canonical `WorldSnapshot` contract,
- internal runtime structures remain adapters and rebuild targets.

---

## 4) Serializers vs adapters
- **Serializers**
  - Responsible only for encoding/decoding canonical snapshot contracts to/from storage format (currently JSON).
  - Must not pull data directly from scattered runtime nodes.
  - Must not perform gameplay decisions or projection rebuild logic.

- **Adapters**
  - Map between runtime/domain owners and canonical snapshot structures.
  - Examples in current architecture: extraction from `WorldSave` + system `serialize()/deserialize()` boundaries and re-application into those owners during load.

Rule: serializers are format I/O; adapters are boundary mapping.

---

## 5) Intended save flow
1. Trigger save from existing save entrypoint.
2. Flush runtime-owned canonical sources that require pre-save snapshotting (e.g., entity coordinator snapshot into `WorldSave`).
3. Build canonical `WorldSnapshot` through adapters from authoritative owners.
4. Serialize `WorldSnapshot` to disk.
5. Do not serialize projection/runtime caches as truth.

---

## 6) Intended load flow
1. Read and deserialize persisted payload into canonical `WorldSnapshot`.
2. Validate snapshot metadata/version.
3. Apply snapshot sections into canonical owners (`WorldSave`, player/session owners, domain systems).
4. Rebuild/rehydrate runtime world from canonical owners through existing world/chunk loading paths.
5. Reinitialize projections/caches from canonical state (not from previous runtime memory).

---

## 7) Projection rebuild after load
After canonical state is restored:

- Rebuild or invalidate and lazily rebuild projection layers (spatial index, wall collider refresh/caches, territory maps, other read models).
- Projection state must be derived from canonical owners and deterministic context (chunk size, tile↔chunk mapping, loaded-chunk window).
- Any projection mismatch is resolved by re-sync/rebuild; projection persistence is not required for correctness.

---

## 8) Out of scope for Phase 6
- Rewriting current save/load implementation in this task.
- Replacing chunk streaming/pipeline architecture.
- Changing gameplay/domain ownership boundaries beyond documenting the snapshot contract.
- Introducing cross-version migration framework beyond current version checks.
- Persisting debug telemetry, perf traces, or runtime-only orchestration queues as canonical data.

---

## Contract summary
Phase 6 persistence boundary is:

`Canonical owners -> WorldSnapshot adapters -> serializer -> disk -> serializer -> WorldSnapshot adapters -> canonical owners -> projection rebuild`

This keeps persistence deterministic, reduces coupling to runtime internals, and preserves current engine architecture.
