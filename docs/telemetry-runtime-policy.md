# Telemetry / Debug Runtime Policy (Gameplay Sovereignty)

Fecha: 2026-04-01
Estado: Activa

## 1) Principio rector

Los pipelines de **telemetry/debug son solo observabilidad**. No pueden:

- mutar estado canónico de gameplay,
- escribir persistencia operativa,
- ni participar como condición necesaria para decisiones de gameplay.

## 2) Reglas obligatorias

1. **Read-only por contrato**: todo módulo de telemetry/debug solo consume snapshots, señales y métricas.
2. **Sin control de flujo gameplay**: decisiones de AI, combate, inventario, hostilidad, placement y spawn no deben depender de señales de telemetry/debug.
3. **Comandos diagnósticos por canal explícito**: cualquier comando con side-effects de diagnóstico se ejecuta solo por canal de tooling (`/tool ...`) y con `Debug.tooling_channel_enabled=true`.
4. **Sin mutaciones inline por debug**: queda prohibido escribir velocity/hp/inventory/etc. desde ramas etiquetadas como debug.
5. **Excepciones temporales registradas**: toda excepción debe quedar documentada con owner, riesgo, fecha objetivo de retiro y criterio de cierre.

## 3) Hallazgos aplicados en esta intervención

- Se eliminó mutación de `velocity` en una rama de debug en `BanditBehaviorLayer`.
- Se reemplazó por un evento de observación read-only (`debug_observation_emitted`).
- Se encapsularon comandos de diagnóstico detrás de `/tool` + flag explícito.

## 4) Criterio de revisión futura

En cada PR con cambios de telemetry/debug:

- Buscar escrituras (`=`/`set*`/mutaciones) bajo ramas debug.
- Verificar que las rutas de gameplay no tengan dependencia fuerte de snapshots/telemetry.
- Confirmar que los comandos con side-effects queden fuera del canal runtime normal.
