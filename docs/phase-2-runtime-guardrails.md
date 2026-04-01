# Phase 2 — Runtime Guardrails

**Estado:** Aprobado  
**Fecha:** 2026-04-01  
**Responsable técnico:** GPT-5.3-Codex

## Artefactos canónicos

- `docs/runtime-architecture-pact.md`
- `docs/runtime-layer-matrix.md`
- `docs/runtime-red-list.md`

## Resumen ejecutivo

Se formalizan las reglas de capas runtime y se identifica lista roja de módulos con 2+ violaciones al pacto para asegurar plan de remediación.

## Reglas canónicas adoptadas

1. Behavior decide intención.
2. Coordinación ejecuta interacción (sin redefinir intención).
3. Persistencia no decide gameplay.
4. Debug/telemetry observa, no gobierna.
5. Cadence define cuándo corre algo, no su semántica.
6. Spatial index responde consultas, no define verdad semántica.

## Criterio de cierre

Todos los módulos de lista roja deben tener excepción temporal registrada y plan de retiro/ruta de corrección.
