# INC-TECH-003 — Excepciones temporales runtime-layer (Fase 5)

Fecha de apertura: 2026-04-01  
Owner: Runtime Architecture  
Estado: Aprobada (temporal, con vencimiento)

## Alcance

Este registro cubre clases que hoy rompen 2+ reglas del pacto de arquitectura runtime y que **aún no completan el refactor**, pero cuentan con plan aprobado y fecha de salida.

## EXC-RUNTIME-001 — `scripts/systems/SaveManager.gd`

- **Reglas afectadas:** R-P3, R-C5, R-Co2.
- **Justificación de excepción:** detener la operación para un refactor integral de guardado/carga bloquearía validación de estabilidad de fase 5.
- **Control activo:** cambios en `SaveManager` requieren checklist de frontera Persistence en PR.
- **Plan comprometido:** mover resets y snapshots a adapters por agregado (ver Epic P1 en `docs/phase-5-exit-report.md`).
- **Fecha límite:** 2026-06-15.
- **Criterio de cierre:** 0 decisiones de gameplay en `SaveManager` + contrato temporal explícito por dominio.

## EXC-RUNTIME-002 — `scripts/world/world.gd`

- **Reglas afectadas:** R-B1, R-Co2.
- **Justificación de excepción:** `world.gd` es nodo de integración central; la extracción debe hacerse por etapas para no romper wiring de runtime.
- **Control activo:** decisiones de intención nuevas prohibidas en `world.gd`; solo wiring/coordinación técnica.
- **Plan comprometido:** extraer `StructureAssaultPolicyPort` y `WorldRuntimeOrchestrator` (ver Epic C1 en `docs/phase-5-exit-report.md`).
- **Fecha límite:** 2026-05-31.
- **Criterio de cierre:** intención social sale de `world.gd` y queda en owner Behavior/Policy.

## EXC-RUNTIME-003 — `scripts/world/BanditGroupIntel.gd`

- **Reglas afectadas:** R-B1/R-Co2, R-C5.
- **Justificación de excepción:** actualmente el módulo conserva decisión + parte operativa por historial de migración parcial.
- **Control activo:** cualquier enqueue nuevo requiere pasar por puerto coordinador dedicado.
- **Plan comprometido:** separar `BanditIntentPolicy` (decisión) de `BanditIntentDispatcher` (ejecución) y aislar reloj por contrato (ver Epic B1 en `docs/phase-5-exit-report.md`).
- **Fecha límite:** 2026-05-20.
- **Criterio de cierre:** `BanditGroupIntel` solo produce intents declarativos; no encola directamente.
