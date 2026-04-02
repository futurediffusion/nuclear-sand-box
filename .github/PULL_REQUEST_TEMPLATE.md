## Gate obligatorio — Copy/Paste requerido
Completa **todas** las líneas (no dejar vacío). Este bloque es validado por CI.

- Respuesta timer local injustificado: No
- Evidencia timer local injustificado:
- Respuesta lógica nueva en autoload: No
- Evidencia lógica nueva en autoload:
- Respuesta lógica global oculta: No
- Evidencia lógica global oculta:
- Respuesta duplicación de heurística crítica: No
- Evidencia duplicación de heurística crítica:
- Respuesta decisión duplicada (assault/combat/hostility): No
- Evidencia decisión duplicada (assault/combat/hostility):
- Respuesta debug mutando estado: No
- Evidencia debug mutando estado:
- Respuesta telemetry/debug fuera de canal controlado mutando estado: No
- Evidencia telemetry/debug fuera de canal controlado mutando estado:
- Respuesta nueva decisión semántica en world.gd: No
- Evidencia nueva decisión semántica en world.gd:
- Respuesta reset semántico directo reintroducido en world.gd: No
- Evidencia reset semántico directo reintroducido en world.gd:
- Respuesta ¿agregaste lógica de negocio en world.gd?: No
- Evidencia ¿agregaste lógica de negocio en world.gd?:
- Respuesta nuevas responsabilidades de dominio en BanditWorkCoordinator: No
- Evidencia nuevas responsabilidades de dominio en BanditWorkCoordinator:
- Respuesta cambio de estado nuevo en el PR: No
- Owner de decisión tocada (obligatorio):
- Categoría de verdad para datos/campos nuevos: no aplica
- Owner de escritura para cambio de estado nuevo: no aplica
- Categoría de verdad del cambio de estado nuevo: no aplica
- Justificación explícita si NO se usa Cadence en gameplay:
- Registro de excepción temporal (si aplica): sin excepción
- Fecha de retiro obligatoria (YYYY-MM-DD): 2099-12-31
- Respuesta temporal/fallback/compat/wrapper nuevo en este PR: No
- Owner de temporal nuevo (si aplica): no aplica
- Fecha límite temporal nuevo (YYYY-MM-DD, si aplica): 2099-12-31
- Condición de salida verificable de temporal nuevo (si aplica): no aplica
- Criterio de done Sprint 1 (patrones corregidos no reingresan): Sí
- Criterio de done anti-reversión (no volver al estado anterior por flujo normal de PR): Sí
- Criterio continuidad checklist obligatoria (hasta completar 2 sprints sin recaídas): Sí
- Cierre 2 sprints consecutivos sin violaciones de estas reglas: Sí

## Runtime Architecture Review (obligatorio)

- [ ] Revisé `docs/runtime-layer-matrix.md` y confirmé que el cambio respeta fronteras de capa.
- [ ] Revisé `docs/runtime-architecture-pact.md` y declaré la regla que este cambio respeta.
- [ ] Revisé [`docs/pr-smell-blacklist.md`](../docs/pr-smell-blacklist.md) y [`docs/phase-7-cut1-time-scheduling.md`](../docs/phase-7-cut1-time-scheduling.md).
- [ ] Declaro el **owner de cada decisión de arquitectura tocada** (dominio + owner canónico).
- [ ] Confirmo explícitamente si este PR añade timer local (`Timer`, `create_timer`, contadores en `_process`/`_physics_process`).
- [ ] Si añade timer local: adjunté justificación aprobada con categoría `LOCAL_TIMER_BY_DESIGN` y fecha de revisión (`YYYY-MM-DD`).
- [ ] Si el caso debía usar Cadence: existe excepción temporal aprobada y registrada en `docs/incidencias/registro-unico-deuda-tecnica.md`.
- [ ] Acepto el criterio de bloqueo: cualquier “Sí” sin excepción aprobada deja el PR en **No Ready**.
- [ ] Confirmo que no agregué decisiones semánticas nuevas en `scripts/world/world.gd`.
- [ ] Confirmo que no reintroduje resets semánticos directos en `scripts/world/world.gd`.
- [ ] Confirmo que `BanditWorkCoordinator` no crece en responsabilidades de dominio.
- [ ] Confirmo que la checklist obligatoria se mantiene hasta completar 2 sprints sin recaídas.
- [ ] Confirmo que el cierre exige 2 sprints consecutivos sin violaciones de estas reglas.


## Checklist anti-olores (bloqueante)

> Contestar cada punto con evidencia (ruta de código, nota de arquitectura o link a decisión).

- [ ] ¿El PR introduce mutación fuera del owner de dominio declarado?
  - Respuesta:
  - Owner de decisión tocada:
  - Evidencia:
- [ ] ¿El PR duplica una decisión/heurística ya definida en documentos canónicos?
  - Respuesta:
  - Decisión canónica referenciada:
  - Evidencia:
- [ ] ¿El PR mezcla debug/telemetry con mutación autoritativa de gameplay?
  - Respuesta:
  - Evidencia:
- [ ] ¿El PR introduce side-effects prohibidos por `docs/side-effects-policy.md`?
  - Respuesta:
  - Dominio afectado:
  - Evidencia:

## Checklist específica — `world.gd` (obligatoria cuando aplica)

> Completar esta sección si el PR toca `scripts/world/world.gd`, `docs/world-gd-boundary.md` o facades conectadas por `world.gd`.

- [ ] **¿`world.gd` se mantiene dentro del presupuesto vigente (líneas ≤ 1900, métodos públicos ≤ 45, dependencias directas `preload` ≤ 26)?**
  - Respuesta:
  - Evidencia (`scripts/ci_guard_world_boundary.py` / CI):
- [ ] **¿Todo cambio en `world.gd` es solo composición, lifecycle o dispatch?**
  - Respuesta:
  - Evidencia (ruta de código o nota de arquitectura):
- [ ] **Si apareció lógica no-orquestación, ¿fue movida a facades/ports/coordinators existentes antes de merge?**
  - Respuesta:
  - Destino del movimiento (facade/servicio):
  - Evidencia (ruta de código o nota de arquitectura):
- [ ] **¿Se revisó el diff acumulado semanal de `world.gd` para prevenir recaídas?**
  - Respuesta:
  - Evidencia (artifact `world-gd-weekly-review.md` o link al run):


## Checklist específica — Bandit Assault Pipeline (obligatoria cuando aplica)

> Completar esta sección si el PR toca cualquier etapa o transición de `docs/phase-7-cut2-bandit-assault.md`.

- [ ] **¿introduce ruta alternativa?**
  - Respuesta:
  - Etapa(s) afectada(s):
  - Owner(s) afectado(s):
  - Evidencia (ruta de código o nota de arquitectura):
- [ ] **¿duplica decisión ya definida?**
  - Respuesta:
  - Etapa(s) afectada(s):
  - Owner(s) afectado(s):
  - Evidencia (ruta de código o nota de arquitectura):
- [ ] **¿corrige intención a mitad de pipeline?**
  - Respuesta:
  - Etapa(s) afectada(s):
  - Owner(s) afectado(s):
  - Evidencia (ruta de código o nota de arquitectura):
- [ ] **Para cada cambio del pipeline, declaré etapa y owner afectados.**

> **Regla de merge (bloqueante):** se bloquea el merge si el cambio crea una bifurcación no documentada en el diagrama canónico de `docs/phase-7-cut2-bandit-assault.md`.
> Si existe excepción temporal aprobada, debe registrarse en `docs/incidencias/registro-unico-deuda-tecnica.md` con responsable y fecha de retiro (`YYYY-MM-DD`).


## Declaración de datos/campos nuevos (bloqueante)

> Completar esta sección si el PR agrega o modifica campos de estado/datos de dominio.

- [ ] Para **cada dato/campo nuevo**, declaré categoría única de verdad: `runtime` / `save` / `derived` / `cache`.
- [ ] Para **cada dato/campo nuevo**, declaré owner de escritura único (sistema/servicio/capa dueña).
- [ ] Para **cada cambio de estado nuevo**, declaré owner de escritura único + categoría de verdad única.
- [ ] Confirmo que ningún dato/campo nuevo queda con doble categoría semántica.
- [ ] Confirmo que índices/caches nuevos no son autoritativos de gameplay.
- [ ] Si hubo excepción temporal, quedó registrada con owner, fecha de retiro (`YYYY-MM-DD`) y criterio de cierre.

> **Regla de merge (bloqueante):** si un dato/campo nuevo no declara categoría de verdad y owner, el PR queda en **No Ready**.

## Declaración de timer local (bloqueante cuando aplica)

- [ ] Si hay timer local, declaré por qué **no aplica Cadence** en este caso.
- [ ] Si hay timer local, declaré owner responsable y plan de retiro/migración.
- [ ] Si hay timer local, registré excepción temporal aprobada con fecha de retiro obligatoria.

> **Regla de merge (bloqueante):** timer local sin justificación + owner + excepción aprobada => **No Ready**.

## Reglas de bloqueo por tipo de violación (sin excepción aprobada)

- [ ] **Timer local injustificado** (`Respuesta timer local injustificado: Sí`) => **No Ready**.
- [ ] **Lógica nueva en autoload** (`Respuesta lógica nueva en autoload: Sí`) => **No Ready**.
- [ ] **Duplicación de heurística crítica** (`Respuesta duplicación de heurística crítica: Sí`) => **No Ready**.
- [ ] **Segunda ruta de decisión assault/combat/hostility** (`Respuesta decisión duplicada (assault/combat/hostility): Sí`) => **No Ready**.
- [ ] **Debug mutando estado real** (`Respuesta debug mutando estado: Sí`) => **No Ready**.
- [ ] **Lógica global oculta** (`Respuesta lógica global oculta: Sí`) => **No Ready**.
- [ ] **Telemetry/debug fuera de canal controlado mutando estado** (`Respuesta telemetry/debug fuera de canal controlado mutando estado: Sí`) => **No Ready**.
- [ ] **Fallback/excepción temporal sin fecha de retiro** => **No Ready**.
- [ ] **Compat/fallback/wrapper nuevo sin fecha de retiro** => **No Ready**.
- [ ] **Temporal/fallback/wrapper nuevo sin owner + fecha límite + condición verificable** => **No Ready**.
- [ ] **Decisión semántica nueva en `world.gd`** => **No Ready**.
- [ ] **Reset semántico directo reintroducido en `world.gd`** => **No Ready**.
- [ ] **Nuevas responsabilidades de dominio en `BanditWorkCoordinator`** => **No Ready**.
- [ ] **Criterio de done Sprint 1 en No** => **No Ready**.
- [ ] **Criterio de done anti-reversión en No** => **No Ready**.
- [ ] **Criterio continuidad checklist obligatoria en No (hasta 2 sprints sin recaídas)** => **No Ready**.
- [ ] **Cierre 2 sprints consecutivos sin violaciones en No** => **No Ready**.

## Declaración de feature (obligatorio para features nuevas)

- **Capa responsable**: <!-- Behavior / Coordination / Persistence / Debug-Telemetry / Cadence / SpatialIndex -->
- **Regla del pacto respetada**: <!-- Ej: R-Co2, R-B1, R-P3, etc -->
- **Owner de decisión tocada**: <!-- dominio + owner canónico -->
- **Evidencia de validación**: <!-- archivo(s), test(s), checklist -->

> Si este PR agrega una nueva feature y no completa los campos anteriores, se considera **No Ready** para merge.
