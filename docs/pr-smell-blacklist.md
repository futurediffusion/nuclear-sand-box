# PR Smell Blacklist (fuente de verdad obligatoria)

Fecha: 2026-04-01  
Estado: **política permanente, vigente y obligatoria para revisión de PR**

## Objetivo

Esta blacklist define olores arquitectónicos prohibidos en cambios de runtime.  
Se usa como **fuente de verdad obligatoria** para aprobar o rechazar PR.

## Permanencia de la política

Esta política se declara **permanente**: no se limita a una fase puntual ni a un freeze temporal.

Racional de permanencia:

- Evitar el patrón de fragmentación de cambios conocido como **"40 mini por si acaso"**.
- Mantener un umbral estable de calidad arquitectónica en todos los PR nuevos.
- Forzar decisiones explícitas (mitigación o excepción temporal) cuando aparezcan riesgos reales.

## Reglas de bloqueo por tipo de violación

Cada violación se evalúa por tipo explícito y tiene salida binaria de gate (`No Ready` / `Ready`).

| Tipo de violación | Severidad | Resultado de gate sin excepción aprobada |
|---|---|---|
| Timer local injustificado | Bloqueante | `No Ready` |
| Lógica global nueva en autoload | Bloqueante | `No Ready` |
| Lógica global oculta (aunque no sea autoload nuevo) | Bloqueante | `No Ready` |
| Duplicación de heurística crítica | Bloqueante | `No Ready` |
| Segunda ruta de decisión assault/combat/hostility | Bloqueante | `No Ready` |
| Debug mutando estado real | Bloqueante | `No Ready` |
| Telemetry/debug mutando estado fuera de canal controlado | Bloqueante | `No Ready` |
| Fallback temporal sin fecha de retiro | Bloqueante | `No Ready` |
| Criterio de done Sprint 1 en `No` (reingreso de patrón corregido) | Bloqueante | `No Ready` |
| Criterio de done anti-reversión en `No` | Bloqueante | `No Ready` |

### Reglas transversales obligatorias

1. **Owner de decisión**: todo cambio nuevo debe declarar owner canónico de la decisión afectada.
2. **Cambio de estado nuevo**: todo cambio de estado nuevo debe declarar owner de escritura + categoría de verdad única (`runtime`, `save`, `derived`, `cache`).
3. **Fallback temporal**: toda excepción/fallback temporal exige fecha de retiro (`YYYY-MM-DD`) desde el primer PR y no puede declararse sin expiración explícita.
4. **No reingreso Sprint 1**: los patrones ya corregidos en Sprint 1 no pueden reingresar; si reaparecen, el PR se bloquea.
5. **Anti-reversión**: el done de cada PR debe garantizar que el flujo normal de PR no pueda volver al estado anterior.

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

## 6) Fallbacks/excepciones sin expiración obligatoria

- **Severidad:** `bloqueante`
- **Por qué es peligroso:** consolida deuda técnica, perpetúa paths ambiguos y dificulta verificar cuál es el comportamiento canónico.
- **Señal de detección:** ramas `legacy`, `temporary`, `TODO` o `fallback` sin fecha objetivo, owner responsable ni criterio de eliminación; o con fecha difusa/no verificable.
- **Alternativa correcta:** permitir fallback solo temporal con ticket, fecha límite, owner y criterio de retiro verificable.

---


## 7) Segunda ruta de decisión para assault/combat/hostility

- **Severidad:** `bloqueante`
- **Por qué es peligroso:** duplica autoridad de decisión, provoca drift entre policies y rompe la trazabilidad del owner canónico.
- **Señal de detección:** se introduce una ruta paralela de decisión (if/heurística/pipeline alterno) para assault/combat/hostility fuera del owner canónico.
- **Alternativa correcta:** extender el owner único existente (policy/service) y mantener consumidores en modo ejecución, no re-decisión.

## Checklist de revisión (uso obligatorio)

- [ ] No se introducen olores **bloqueantes** de esta blacklist.
- [ ] Si hubo excepción temporal, existe plan de mitigación + ticket + fecha de retiro.
- [ ] Todo fallback nuevo incluye owner, fecha límite y criterio de retiro.
- [ ] Todo cambio nuevo declara owner de decisión y categoría de verdad cuando aplica.
- [ ] Ningún patrón ya corregido en Sprint 1 reingresa en el PR.

## Referencias normativas

- `docs/runtime-architecture-pact.md`
- `docs/runtime-layer-matrix.md`
- `.github/PULL_REQUEST_TEMPLATE.md`
