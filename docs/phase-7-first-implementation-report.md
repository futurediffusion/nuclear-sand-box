# Phase 7 — First Implementation Report

Fecha: 2026-04-01.
Alcance: Corte 1 + Corte 2 + Corte 3 en una sola iteración de implementación.

## 1) Entregables por corte

### Corte 1 — Migración crítica a Cadence + excepciones locales

Implementación aplicada:

- `RaidFlow` migró el scheduler de dispatch de asalto desde reloj local por timestamp (`wall_assault_next_at`) a cooldown por **pulsos de director** (cadence-driven), eliminando la dependencia de comparación temporal por `RunClock` para cada dispatch.
- Se mantiene jitter determinista por grupo, pero convertido a cantidad de pulsos (`wall_assault_pulses_until_dispatch`).

Excepciones locales documentadas (permanecen fuera de cadence por diseño en este corte):

1. `BanditBehaviorLayer._tick_timer`  
   - Categoría: `LOCAL_TIMER_BY_DESIGN` (temporal).  
   - Motivo: tick interno de integración LOD + costo por NPC; no decide handoff cross-system.  
   - Revisión: 2026-04-08.
2. `ExtortionFlow._scheduled_callbacks`  
   - Categoría: `LOCAL_TIMER_BY_DESIGN` (temporal).  
   - Motivo: callbacks efímeros cancelables de un único flow; pendiente migración a lanes si se comparte scheduler entre dominios.  
   - Revisión: 2026-04-08.
3. `SettlementIntel` fallback sin cadence inyectada  
   - **Retirada** en este corte de seguimiento: rescans periódicos ahora dependen solo de lanes Cadence + dirty flags.
   - Estado actual: sin excepción `LOCAL_TIMER_BY_DESIGN` activa para fallback timer.

### Corte 2 — Ruta principal única del bandit assault

Implementación aplicada:

- `RaidFlow` normaliza cualquier `raid_type` entrante no canónico hacia `structure_assault` vía `_to_mainline_structure_assault(...)`.
- La normalización deja trazabilidad explícita: `declared_branch`, `mainline_normalized`, `normalization_reason_code`.
- Resultado operativo: no hay bifurcación silenciosa por tipo de raid al crear job; todos los jobs entran a la misma ruta principal de ejecución.

### Corte 3 — Resolución de conflictos de verdad (>=2)

Implementación aplicada:

1. **WR-002 (alto impacto): señales sociales de SettlementIntel**  
   - Antes: workbench/door podían salir de `WorldSpatialIndex` (derivado/cache) como fuente principal.  
   - Después: `SettlementIntel` toma workbenches y doors solo desde `WorldSave` (verdad canónica persistente).
2. **WR-003 (alto impacto): decisiones tácticas de loot/resource en BanditBehaviorLayer**  
   - Antes: lookup runtime podía depender de `WorldSpatialIndex`.  
   - Después: decisiones se basan en grupos runtime del árbol (`item_drop`, `world_resource`), eliminando el cache como autoridad semántica.

## 2) KPI — impacto inmediato

## KPI A — Timers críticos fuera de cadence

- Antes (baseline): 6.
- Después inmediato: 4.
- Variación inmediata: **-33.3%**.

Detalle:
- Sale de la lista crítica el scheduler de dispatch de `RaidFlow` (ahora pulso cadence-driven).
- Sale también el fallback timer de `SettlementIntel` (solo lanes Cadence + dirty flags).

## KPI B — Rutas de asalto fuera de mainline

- Antes inmediato del ajuste: existían variantes por `raid_type` (`full`, `light`, `wall_probe`, `structure_assault`).
- Después: `RaidFlow` normaliza a `structure_assault` al crear job.
- Variación: **ruta principal única consolidada en creación de job** (0 bifurcaciones silenciosas por tipo de raid).

## KPI C — Conflictos de verdad de alto impacto en esta iteración

- Resueltos en código en este corte: **2** (`WR-002`, `WR-003`).
- Resultado: decisiones sociales y tácticas dejan de depender de proyecciones/caches como fuente principal.

## 3) Riesgo residual y seguimiento

1. `ExtortionFlow` mantiene scheduler local de callbacks (temporal, review 2026-04-08).
2. `BanditBehaviorLayer._tick_timer` sigue local para LOD interno (temporal, review 2026-04-08).
3. Debe completarse medición global consolidada en `docs/architecture-metrics-after.md` en próximo cierre para reflejar este delta incremental.

## 4) Estado de publicación

Reporte publicado: `docs/phase-7-first-implementation-report.md`.
Estado: **READY FOR REVIEW**.
