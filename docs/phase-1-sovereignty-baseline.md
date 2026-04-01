# Phase 1 — Sovereignty Baseline

**Estado:** Aprobado  
**Fecha:** 2026-04-01  
**Responsable técnico:** GPT-5.3-Codex

## Artefacto canónico

- `docs/sovereignty-map.md`

## Resumen ejecutivo

Se establece owner único por dominio crítico y se documenta explícitamente:

- qué decide cada dominio,
- qué no puede decidir,
- qué side effects quedan prohibidos,
- cuáles son los contratos de lectura/emisión.

## Owners canónicos (baseline)

- `WorldTime` (tiempo del mundo)
- `BanditGroupMemory` (intención grupal bandida)
- `FactionHostilityManager` (territorialidad/hostilidad)
- `EncounterFlowCoordinator` (coerción activa: extorsión/incursión)
- `InventoryComponent` (estado final de inventario)
- `PlacementSystem` (commit estructural)
- `NpcPathService` (pathing)
- `SaveManager` + `WorldSave` (persistencia)
- `EventLogger` (observabilidad)

## Criterio de cierre

No quedan dominios críticos con owner ambiguo ni conflictos sin decisión registrada.
