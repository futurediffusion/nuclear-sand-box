# INC-TECH-002 — Excepciones temporales telemetry/debug vs gameplay

Fecha de apertura: 2026-04-01
Owner: Runtime Architecture
Estado: Abierta (seguimiento)

## EXC-001 — Canal de tooling apagado por defecto

- **Descripción**: comandos diagnósticos con side-effects se movieron a `/tool ...`, pero el runtime mantiene implementaciones para soporte de QA interno.
- **Control actual**: `Debug.tooling_channel_enabled=false` por defecto; sin flag explícito no ejecutan.
- **Riesgo**: bajo (bloqueado por default, canal explícito requerido).
- **Plan de retiro**:
  1. Migrar comandos más sensibles a harness externo de pruebas (smoke/dev scenes).
  2. Reducir surface del `CommandSystem` a comandos no-mutantes en runtime regular.
  3. Dejar `/tool` solo en builds de tooling.
- **Fecha objetivo de retiro**: 2026-06-30.
- **Criterio de cierre**: 0 comandos mutantes disponibles en runtime normal + 100% de comandos de diagnóstico cubiertos por tooling externo.

## EXC-002 — Emisión de observaciones debug en runtime

- **Descripción**: `BanditBehaviorLayer` emite evento `debug_observation_emitted` en runtime para inspección de casos `alerted`.
- **Control actual**: evento read-only; no altera flujo/estado.
- **Riesgo**: muy bajo.
- **Plan de retiro**:
  1. Consolidar evento en un bus de observabilidad común.
  2. Desacoplar completamente del layer de comportamiento en siguiente iteración de telemetry.
- **Fecha objetivo de retiro**: 2026-05-31.
- **Criterio de cierre**: observación trasladada a adaptador de telemetry dedicado.
