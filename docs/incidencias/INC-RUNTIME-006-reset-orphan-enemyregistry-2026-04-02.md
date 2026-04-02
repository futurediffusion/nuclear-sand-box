# INC-RUNTIME-006 — índices huérfanos de EnemyRegistry tras `new_game/reset` (2026-04-02)

## Resumen
Durante la revisión de cierre de sprint (gates de reset/cadence/hostilidad), se detectó que `RuntimeResetCoordinator` no invocaba un reset explícito del autoload `EnemyRegistry`.

Impacto potencial:
- buckets de chunk y mapas de índices (`_enemy_chunks`, `_enemy_bucket_indices`) podían sobrevivir entre runs;
- riesgo de estados huérfanos tras `new_game` (referencias débiles limpiadas tarde por tick, pero no en frontera de reset).

## Evidencia
- `RuntimeResetCoordinator._reset_tactical_memory_and_queues()` reseteaba memoria táctica (`BanditGroupMemory`, `ExtortionQueue`, `RaidQueue`) pero no `EnemyRegistry`.
- `EnemyRegistry` no exponía `reset()` para limpieza transaccional en borde de `new_game`.

## Corrección aplicada
1. Se agrega `EnemyRegistry.reset()` para limpiar estructuras runtime e invalidar cache de mundo.
2. Se integra `EnemyRegistry.reset()` en `RuntimeResetCoordinator._reset_tactical_memory_and_queues()`.

## Validación
- Guard de frontera de `world.gd` (`scripts/ci_guard_world_boundary.py`): **PASS**.
- Gobernanza PR no aplicable al runtime local sin plantilla de PR en variables de entorno (`PR_BODY/PR_TITLE`).

## Estado
- **Cerrada**: fix aplicado en runtime.
- Seguimiento recomendado: ejecutar checklist manual in-engine cuando haya binario Godot disponible (save/load + chunk unload/reload + raids + wall damage).
