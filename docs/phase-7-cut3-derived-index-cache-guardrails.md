# Phase 7 — Cut 3: Guardrails de índices derivados y cachés activas

Objetivo: impedir que índices/cachés se conviertan en verdad semántica y reducir drift frente a la fuente canónica.

## 1) Inventario de índices/cachés por subsistema

| Subsistema | Índice/Cache | Tipo | Verdad canónica origen |
|---|---|---|---|
| Spatial queries (`WorldSpatialIndex`) | `_runtime_nodes_by_kind`, `_runtime_meta_by_id` | Índice runtime | Árbol de escena (nodos vivos) |
| Spatial queries (`WorldSpatialIndex`) | `_placeables_by_item_id_and_chunk` | Cache/índice derivado persistente | `WorldSave.placed_entities_by_chunk` |
| Persistencia (`WorldSave`) | `placed_entity_chunk_by_uid` | Lookup auxiliar | `placed_entities_by_chunk` |
| Walls runtime (`ChunkWallColliderCache`) | hash/dirty/reuse por chunk | Cache de colisión | Tiles/muros canónicos de mundo |
| Walls runtime (`WallRefreshQueue`) | cola deduplicada de chunks sucios | Cache operacional | eventos dirty desde `world.gd` |

## 2) Regla de actualización: siempre desde verdad canónica

- `WorldSpatialIndex` reconstruye `_placeables_by_item_id_and_chunk` **solo** leyendo `WorldSave` y `placed_entities_revision`.
- Cambios semánticos de placeables se realizan en `WorldSave` (`add/remove/move`) y luego el índice detecta revisión nueva.
- Se añade API explícita `rebuild_placeables_cache_from_truth(reason)` para rebuild manual controlado sin escritura directa.

## 3) Bloqueo de escrituras semánticas en índices/cachés

- Se añade `try_write_placeables_cache(...)` en `WorldSpatialIndex` que devuelve `ERR_UNAUTHORIZED` y emite warning.
- Política: cualquier intento de “upsert” semántico en cache derivada se considera violación arquitectónica.
- `ArchitectureContractValidator` ahora exige la presencia del API bloqueante y rechaza firmas sospechosas de escritura directa en cache.

## 4) Política de invalidación/rebuild anti-drift

- Invalidez explícita: `invalidate_placeables_cache(reason)` limpia cache y fuerza estado “stale”.
- Rebuild controlado: `rebuild_placeables_cache_from_truth(reason)` invalida + reconstruye desde `WorldSave`.
- Rebuild implícito: `_ensure_placeables_cache()` rehace la proyección cuando `placed_entities_revision` cambia.

## 5) Chequeos periódicos de consistencia

- `WorldSpatialIndex` corre chequeo periódico cada `PLACEABLE_CACHE_CONSISTENCY_INTERVAL_SEC` (10s).
- Verifica conteo total de entries de `WorldSave` versus cache derivada.
- Si detecta drift:
  1. registra warning con detalle (`truth`, `cache`, `revision`);
  2. ejecuta `rebuild_placeables_cache_from_truth("consistency_drift")`.
- `get_debug_snapshot()` publica métricas de salud:
  - `checks_total`
  - `checks_failed`
  - `last_issue`
  - `interval_sec`

