# Phase 7 — Cut 3 Exit Report

Fecha de corte: 2026-04-01.

Documentos base de este corte:
- `docs/phase-7-cut3-world-truth.md`
- `docs/phase-7-cut3-state-inventory.md`
- `docs/phase-7-cut3-derived-index-cache-guardrails.md`

## 1) Publicación del corte

Se publica este reporte de salida para el **Cut 3 de Phase 7** con foco en:

1. consolidar taxonomía única de datos críticos (`runtime/save/derived/cache`);
2. cerrar ambigüedad de ownership de escritura;
3. blindar que `save` no tome decisiones de gameplay;
4. blindar que índices/caches no sean autoritativos;
5. formalizar regla de PR para campos nuevos con categoría + owner explícitos.

Estado de publicación: **COMPLETADO**.

---

## 2) Confirmación: categoría única + owner de escritura por dato crítico

### Resultado

**Confirmado**: para los datos críticos inventariados en Cut 3, cada dato queda con **categoría canónica única** y **owner de escritura definido**.

### Criterios aplicados

- Categoría exclusiva por dato: `runtime`, `save`, `derived`, `cache`.
- Prohibición explícita de doble pertenencia semántica (ej. `save + cache`).
- Owner de escritura único para el significado del dato (otros actores solo lectura/relay).

### Evidencia representativa de cierre

- **Hostilidad de facción (P0)**: owner canónico consolidado en `FactionHostilityManager`; `FactionRelationService` queda como wrapper read-only/compat temporal.
- **Walls del jugador**: categoría `save`, escritura concentrada por contrato en `PlayerWallSystem` vía `WallPersistence`/`WorldSave`.
- **Placeables persistentes**: categoría `save`, escritura en `WorldSave` (add/remove/move), con índices como derivados.
- **Índice de placeables**: categoría `cache/derived`, escritura solo por rebuild desde verdad canónica.

Estado: **COMPLETADO** para el inventario crítico actual del corte.

---

## 3) Verificación de guardrails: save sin decisiones de gameplay + índices/caches no autoritativos

### 3.1 Save no decide gameplay

**Verificado**:

- `Save Truth` se usa para persistir/restaurar estado, no para decidir heurística de gameplay en vivo.
- Decisiones semánticas críticas permanecen en owners de runtime/policies/coordinadores.
- `save/load` opera como snapshot/rehidratación controlada, no como policy engine.

### 3.2 Índices/caches no son verdad autoritativa

**Verificado con guardrails activos**:

- Rebuild de cache derivada de placeables solo desde `WorldSave` y revisión canónica.
- Bloqueo explícito de escrituras semánticas directas en cache derivada (`ERR_UNAUTHORIZED`).
- Invalidation/rebuild formal para evitar drift.
- Chequeo periódico de consistencia con autorepair ante mismatch.

Conclusión del punto 3: **COMPLETADO**.

---

## 4) Conflictos: resueltos vs remanentes + plan de cierre

## 4.1 Resueltos en Cut 3

1. **WR-001 / P0 — DOUBLE_TRUTH hostilidad de facción**
   - Estado: **RESUELTO**.
   - Cierre: se retira estado espejo en `FactionRelationService`; ownership de escritura queda en `FactionHostilityManager`.
   - Ventana de compatibilidad: wrapper read-only hasta **2026-06-30**.

## 4.2 Remanentes

Estado actualizado al **2026-04-01 (cierre iteración final)**:

1. **P1 — CACHE_AS_TRUTH en señales sociales (`SettlementIntel`)**
   - Estado: **RESUELTO**.
   - Cierre: escaneo social de `workbench/doorwood` consolidado contra `WorldSave` canónico; índices solo optimizan lookup técnico.
2. **P1 — CACHE_AS_TRUTH en decisiones tácticas de loot (`BanditBehaviorLayer`)**
   - Estado: **RESUELTO**.
   - Cierre: decisiones de loot basadas en nodos vivos del árbol (`item_drop`) con validación de instancia antes de consumir.
3. **P2 — duplicación de regla territorial (`groups_at` vs `is_in_territory`)**
   - Estado: **RESUELTO**.
   - Cierre: rutas de territorio de jugador consumen fuentes runtime canónicas (grupo `workbench`) y base detectada por `SettlementIntel`.

## 4.3 Plan de cierre

### Horizonte 1 (inmediato, próximo cut)

- Introducir validación contra verdad canónica (`WorldSave`) en paths sociales críticos cuando haya mismatch de revisión.
- Endurecer contratos de frescura de loot (TTL + verificación de nodo vivo previa a decisión).

### Horizonte 2 (corto)

- Consolidar consulta territorial en una función base única para evitar duplicación lógica.
- Añadir telemetría de violación de soberanía (`cache_used_as_truth_count`, `truth_fallback_count`).

### Horizonte 3 (gobernanza continua)

- Mantener auditoría de PR con gate bloqueante por categoría/owner.
- Revisar y retirar wrappers de compatibilidad al llegar fecha objetivo.

Conclusión del punto 4: **COMPLETADO** (P0/P1/P2 cerrados con owner único y fuentes canónicas).

---

## 5) Regla de PR activada (bloqueante)

Se activa la siguiente regla para todo PR nuevo:

> **Todo campo nuevo debe declarar explícitamente categoría (`runtime/save/derived/cache`) y owner de escritura.**

### Interpretación operativa

- Si un PR agrega un campo sin categoría + owner declarados, queda en estado **No Ready**.
- Si un campo parece pertenecer a más de una categoría, el PR debe resolver la categoría canónica antes de merge.
- Si un campo no tiene owner de escritura único, el PR debe consolidarlo o registrar excepción temporal aprobada con plan de retiro y fecha.

Estado del punto 5: **ACTIVADO** (template de PR actualizado).

---

## 6) Criterio de salida de Cut 3

Cut 3 queda en estado:

- **Publicado** reporte de salida (`phase-7-cut3-exit-report`).
- **Confirmada** taxonomía única + owner de escritura para datos críticos inventariados.
- **Verificados** guardrails para que save no decida gameplay y para que índices/caches no sean autoritativos.
- **Reportados** conflictos resueltos y remanentes con plan de cierre por horizonte.
- **Activada** regla de PR bloqueante para nuevos campos (categoría + owner).

Estado final: **CUT 3 EXIT — CERRADO**.
