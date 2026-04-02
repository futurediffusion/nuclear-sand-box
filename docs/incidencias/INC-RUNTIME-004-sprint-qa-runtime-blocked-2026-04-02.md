# INC-RUNTIME-004 — Bloqueo de QA runtime para cierre de sprint (raids/loot/retreat/cadence/hostility/save-load)

## Prioridad
- **P0 (bloqueante de cierre de sprint)**

## Tipo
- Bloqueo de validación runtime en entorno

## Fecha
- 2026-04-02 (UTC)

## Alcance solicitado
1. Prueba en juego real de: raids, loot, retreat, cadence ticks, hostility, save/load + rebuild.
2. Verificar efectos secundarios tras sacar resets de `world.gd`.
3. Confirmar que no reaparezcan rutas paralelas en assault/cooldown.
4. Registrar solo bugs de comportamiento real.
5. Cerrar sprint solo con comportamiento estable en runtime.

## Evidencia de ejecución
### Intento A — runners headless específicos
- `test_wall_refresh_optimized.gd`:
  - Error de parse en runtime: `Identifier "WallRefreshQueue" not declared in the current scope`.
- `walls_colliders_checklist_runner.gd`:
  - Error de parse: warning tratado como error + `PlacementCatalog` no declarado.

### Intento B — boot de juego principal en headless
- El arranque de `scenes/main.tscn` falla con múltiples errores de parse/carga (autoloads y recursos importados), incluyendo:
  - tipos no resueltos (`ShopPort`, `FactionHostilityData`, `BalanceConfig`, `ItemData`, `CraftingRecipe`, `PlacementCatalog`, etc.),
  - recursos importados faltantes en `.godot/imported/*.ctex|*.oggvorbisstr`.

## Resultado operativo
- **No fue posible completar validación runtime real en este entorno**, porque el proyecto no llega a boot estable en el binario disponible de Godot headless.
- Con este bloqueo, **el sprint no puede cerrarse** bajo el criterio de estabilidad runtime.

## Verificación puntual pedida (sin inferir estabilidad)
### Efectos secundarios por mover resets fuera de `world.gd`
- `world.gd` delega reset runtime a `RuntimeResetCoordinator` vía `_trigger_runtime_reset_for_new_game()`.
- `SaveManager.clear_all_data()` usa el runtime port `reset_runtime_for_new_game`.
- Hallazgo: la ruta de reset existe y está centralizada, pero no se pudo validar su comportamiento in-game por el bloqueo de boot.

### Ruta paralela assault/cooldown
- `RaidFlow` normaliza `raid_type` entrante a `structure_assault` mediante `_to_mainline_structure_assault(...)`.
- `BanditGroupIntel` consume cadence lane `bandit_group_scan_slice` y mantiene cálculo de cooldown vía helper `_cooldown_remaining(...)`.
- Hallazgo: **a nivel código**, no se detectó reintroducción obvia de una ruta paralela principal para assault; pendiente validar en runtime cuando el boot sea estable.

## Decisión de gate
- **Sprint: ABIERTO / BLOQUEADO**.
- Motivo: ausencia de evidencia runtime ejecutable para los casos críticos solicitados.

## Siguientes acciones mínimas
1. Ejecutar la misma batería en entorno con versión de Godot y assets importados compatibles con el repo.
2. Repetir checklist obligatorio: raids/loot/retreat/cadence/hostility/save-load-rebuild.
3. Reabrir decisión de cierre solo con evidencia runtime verde.
