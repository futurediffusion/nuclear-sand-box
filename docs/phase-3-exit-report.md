# Phase 3 — Exit report (unicidad de decisiones)

**Fecha:** 2026-04-01  
**Objetivo del gate:** habilitar fase siguiente solo si todas las decisiones críticas tienen owner único y sin conflictos abiertos.

## 1) Verificación de decisiones críticas del ledger (owner único + conflictos abiertos)

### Resultado general
- **Owner único declarado:** ✅ en todas las decisiones `DGL-001`..`DGL-007`.
- **Conflictos abiertos en ledger:** ❌ **sí existen** (cinco decisiones marcadas explícitamente como `CONFLICTO_DUPLICACION_CONCEPTUAL`: `DGL-001`..`DGL-005`).

### Evidencia
- `docs/decision-ledger.md` mantiene `CONFLICTO_DUPLICACION_CONCEPTUAL` en `DGL-001` a `DGL-005`.
- `DGL-006` y `DGL-007` están registradas sin marca de conflicto abierto.

## 2) Confirmación de decisiones equivalentes en paralelo entre sistemas

### Resultado
- Se confirma la existencia histórica de decisiones equivalentes en paralelo documentadas en `docs/phase-3-concept-duplication.md` (casos A–G).
- Las más críticas (P0) siguen registradas como duplicación conceptual en el ledger (`DGL-001`..`DGL-005`).

### Conclusión de auditoría
- **No se puede afirmar cierre total** de decisiones equivalentes en paralelo en todos los sistemas críticos.
- Hay resolución de soberanía por dominio en `docs/sovereignty-map.md` (9/9), pero el ledger de decisiones de gameplay todavía lista conflictos conceptuales abiertos.

## 3) Evidencia por decisión (owner, contrato, consumidores, rutas antiguas)

> Nota: el contrato funcional por decisión y consumidores se toma del ledger actual. La evidencia de “ruta antigua retirada” solo se marca como cerrada cuando la documentación declara explícitamente remoción/restricción.

| Decisión | Owner único | Contrato (qué decide) | Consumidores | Ruta antigua retirada |
|---|---|---|---|---|
| DGL-001 | `CombatComponent` | Inicio efectivo de ataque + ventana de hit | `player`, `PlayerWeaponController`, `slash`, `AIComponent` | **No retirada** (sigue conflicto abierto) |
| DGL-002 | `PlayerWallSystem` | Veredicto canónico de hit a wall | `slash`, `world`, `WallFeedback`, `FactionHostilityManager` | **No retirada** (sigue conflicto abierto) |
| DGL-003 | `LootSystem` | Spawn canónico de drop / transferencia cargo | `item_drop`, `InventoryComponent`, `BanditBehaviorLayer`, `NpcWorldBehavior`, `GameEvents` | **No retirada** (sigue conflicto abierto) |
| DGL-004 | `BanditIntentPolicy` | Gate canónico de cooldown social/raid/probe | `BanditGroupIntel`, `BanditBehaviorLayer`, `BanditTerritoryResponse`, directors | **No retirada** (sigue conflicto abierto) |
| DGL-005 | `BanditGroupIntel` | Intención AI grupal `next_intent` | `BanditBehaviorLayer`, directors y flows | **No retirada** (sigue conflicto abierto) |
| DGL-006 | `ExtortionFlow` | Lifecycle de job activo de extorsión/incursión | `BanditExtortionDirector`, `ExtortionUIAdapter`, `FactionHostilityManager` | Parcialmente retirada (documentado en mapa de soberanía para coerción) |
| DGL-007 | `PlacementSystem` | Validez + commit de cambio estructural | `PlayerWallSystem`, persistencias de wall, `world`, `NpcPathService` | Parcialmente retirada (documentado en mapa de soberanía para estructura) |

## 4) Conflictos resueltos y riesgos remanentes

### Conflictos resueltos (nivel dominio / soberanía)
- `docs/sovereignty-map.md` declara validación **9/9** y sin filas `CONFLICTO` pendientes en dominios críticos.
- Resoluciones explícitas documentadas para coerción (`SOV-004`), botín/inventario (`SOV-005`) y construcción (`SOV-006`).

### Riesgos remanentes (nivel decisión gameplay)
- El ledger de gameplay conserva conflictos conceptuales abiertos en `DGL-001`..`DGL-005`.
- `docs/phase-3-concept-duplication.md` mantiene casos P0/P1/P2 de duplicación de decisión en runtime.
- Riesgo de desincronía entre intención y ejecución en coerción, resolución de wall-hit y arbitraje de AI/loot.

## 5) Gate de habilitación de fase siguiente

## Veredicto
- **Criterio de unicidad de decisión en todos los dominios críticos:** ⚠️ **Parcial**.
  - Cumple a nivel de soberanía por dominio (9/9 en `docs/sovereignty-map.md`).
  - No cumple plenamente a nivel de decisiones críticas del ledger (`DGL-001`..`DGL-005` aún abiertas).

## Decisión operativa
- **Fase siguiente: NO habilitada aún.**
- Condición para habilitar:
  1. cerrar formalmente `DGL-001`..`DGL-005` (estado “resuelto” con ruta antigua retirada),
  2. actualizar `docs/decision-ledger.md` sin marcas `CONFLICTO_DUPLICACION_CONCEPTUAL`,
  3. publicar addendum de evidencia con pruebas de no-paralelismo por decisión crítica.
