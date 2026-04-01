# PR Smell Blacklist (fuente de verdad obligatoria)

Fecha: 2026-04-01  
Estado: **vigente y obligatorio para revisión de PR**

## Objetivo

Esta blacklist define olores arquitectónicos prohibidos en cambios de runtime.  
Se usa como **fuente de verdad obligatoria** para aprobar o rechazar PR.

## Regla de severidad y gate de rechazo

- **bloqueante:** el PR se rechaza hasta corregir el olor o registrar excepción temporal aprobada con plan de retiro y fecha.
- **advertencia:** el PR puede continuar solo con plan de mitigación explícito y ticket de seguimiento.

### Criterio de rechazo del PR

Un PR queda en estado **No Ready / Rechazado** cuando ocurre cualquiera de estos casos:

1. Introduce al menos un olor marcado como **bloqueante**.
2. Introduce un olor de **advertencia** sin plan de mitigación y sin ticket.
3. Introduce cualquier fallback permanente sin plan de retiro (se trata como bloqueante).

---

## Olores prohibidos

## 1) Timers locales nuevos cuando ya existe cadence

- **Severidad:** `bloqueante`
- **Por qué es peligroso:** fragmenta el control temporal, duplica fuentes de verdad del scheduling y crea divergencias de frecuencia difíciles de depurar.
- **Señal de detección:** se agregan `Timer`, `create_timer`, `_process`/`_physics_process` con contadores locales para orquestar trabajo que ya pertenece a `WorldCadenceCoordinator` o equivalente.
- **Alternativa correcta:** registrar el trabajo en la capa de cadence existente y mantener la semántica de negocio fuera del scheduler.

## 2) Lógica global nueva escondida en autoload

- **Severidad:** `bloqueante`
- **Por qué es peligroso:** aumenta acoplamiento implícito, rompe fronteras de ownership y hace opaco el flujo de decisiones.
- **Señal de detección:** autoload nuevo o autoload existente que empieza a decidir reglas de negocio sin contrato explícito de capa.
- **Alternativa correcta:** mover decisión a capa dueña (behavior/coordinación/persistencia según corresponda) y usar puertos explícitos para acceso global mínimo.

## 3) Duplicación de heurísticas de combate/hostilidad

- **Severidad:** `bloqueante`
- **Por qué es peligroso:** genera decisiones inconsistentes entre sistemas, regresiones por drift de reglas y conflictos en outcomes de combate/social.
- **Señal de detección:** condiciones similares de hostilidad/targeting/copias de thresholds en múltiples archivos en lugar de reutilizar el policy owner.
- **Alternativa correcta:** centralizar heurística en un owner único (policy/service) y exponer API reusable para consumidores.

## 4) Consultas globales a nodos si ya existe índice espacial

- **Severidad:** `bloqueante`
- **Por qué es peligroso:** degrada performance, introduce dependencias de escena frágiles y esquiva contratos de consulta del runtime.
- **Señal de detección:** uso nuevo de `get_tree().get_nodes_in_group`, búsquedas globales de nodos o escaneos completos donde ya hay `WorldSpatialIndex` (o equivalente).
- **Alternativa correcta:** resolver proximidad/ocupación mediante el índice espacial y delegar validación semántica al owner de dominio.

## 5) Mezcla de debug con mutación real

- **Severidad:** `bloqueante`
- **Por qué es peligroso:** debug deja de ser observacional, altera gameplay en producción y enmascara bugs al depender de flags/instrumentación.
- **Señal de detección:** código de telemetría/debug que cambia estado canónico, decide intents o altera ejecución real fuera de un mecanismo formal de configuración gameplay.
- **Alternativa correcta:** separar estrictamente observación (logs, métricas, trazas) de mutaciones de runtime.

## 6) Fallbacks permanentes sin retiro planificado

- **Severidad:** `advertencia` (sube a **bloqueante** si no hay plan de retiro)
- **Por qué es peligroso:** consolida deuda técnica, perpetúa paths ambiguos y dificulta verificar cuál es el comportamiento canónico.
- **Señal de detección:** ramas `legacy`, `temporary`, `TODO` o `fallback` sin fecha objetivo, owner responsable ni criterio de eliminación.
- **Alternativa correcta:** permitir fallback solo temporal con ticket, fecha límite, owner y criterio de retiro verificable.

---

## Checklist de revisión (uso obligatorio)

- [ ] No se introducen olores **bloqueantes** de esta blacklist.
- [ ] Si hubo **advertencias**, existe plan de mitigación + ticket.
- [ ] Todo fallback nuevo incluye owner, fecha límite y criterio de retiro.

## Referencias normativas

- `docs/runtime-architecture-pact.md`
- `docs/runtime-layer-matrix.md`
- `.github/PULL_REQUEST_TEMPLATE.md`
