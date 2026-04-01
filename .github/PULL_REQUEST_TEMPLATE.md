## Gate obligatorio — Copy/Paste requerido
Completa **todas** las líneas (no dejar vacío). Este bloque es validado por CI.

- Respuesta timer local injustificado: No
- Evidencia timer local injustificado:
- Respuesta decisión duplicada (assault/combat/hostility): No
- Evidencia decisión duplicada (assault/combat/hostility):
- Respuesta debug mutando estado: No
- Evidencia debug mutando estado:
- Justificación explícita si NO se usa Cadence en gameplay:
- Registro de excepción temporal (si aplica):
- Fecha de retiro obligatoria (YYYY-MM-DD):
- Criterio de done (sin nueva deuda del mismo tipo): Sí

## Runtime Architecture Review (obligatorio)

- [ ] Revisé `docs/runtime-layer-matrix.md` y confirmé que el cambio respeta fronteras de capa.
- [ ] Revisé `docs/runtime-architecture-pact.md` y declaré la regla que este cambio respeta.
- [ ] Revisé [`docs/pr-smell-blacklist.md`](../docs/pr-smell-blacklist.md) y [`docs/phase-7-cut1-time-scheduling.md`](../docs/phase-7-cut1-time-scheduling.md).
- [ ] Declaro el **owner de cada decisión de arquitectura tocada** (dominio + owner canónico).
- [ ] Confirmo explícitamente si este PR añade timer local (`Timer`, `create_timer`, contadores en `_process`/`_physics_process`).
- [ ] Si añade timer local: adjunté justificación aprobada con categoría `LOCAL_TIMER_BY_DESIGN` y fecha de revisión (`YYYY-MM-DD`).
- [ ] Si el caso debía usar Cadence: existe excepción temporal aprobada y registrada en `docs/incidencias/registro-unico-deuda-tecnica.md`.
- [ ] Acepto el criterio de bloqueo: cualquier “Sí” sin excepción aprobada deja el PR en **No Ready**.


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
- [ ] Confirmo que ningún dato/campo nuevo queda con doble categoría semántica.
- [ ] Confirmo que índices/caches nuevos no son autoritativos de gameplay.
- [ ] Si hubo excepción temporal, quedó registrada con owner, fecha de retiro (`YYYY-MM-DD`) y criterio de cierre.

> **Regla de merge (bloqueante):** si un dato/campo nuevo no declara categoría de verdad y owner, el PR queda en **No Ready**.

## Declaración de timer local (bloqueante cuando aplica)

- [ ] Si hay timer local, declaré por qué **no aplica Cadence** en este caso.
- [ ] Si hay timer local, declaré owner responsable y plan de retiro/migración.
- [ ] Si hay timer local, registré excepción temporal aprobada con fecha de retiro obligatoria.

> **Regla de merge (bloqueante):** timer local sin justificación + owner + excepción aprobada => **No Ready**.

## Reglas de bloqueo (sin excepción aprobada)

- [ ] Sin excepción aprobada, cualquier violación bloqueante de esta plantilla deja el PR en **No Ready**.
- [ ] Confirmo que toda excepción temporal usada quedó registrada en `docs/incidencias/registro-unico-deuda-tecnica.md`.
- [ ] Confirmo que ninguna excepción temporal queda sin fecha de retiro comprometida (`YYYY-MM-DD`).

## Declaración de feature (obligatorio para features nuevas)

- **Capa responsable**: <!-- Behavior / Coordination / Persistence / Debug-Telemetry / Cadence / SpatialIndex -->
- **Regla del pacto respetada**: <!-- Ej: R-Co2, R-B1, R-P3, etc -->
- **Owner de decisión tocada**: <!-- dominio + owner canónico -->
- **Evidencia de validación**: <!-- archivo(s), test(s), checklist -->

> Si este PR agrega una nueva feature y no completa los campos anteriores, se considera **No Ready** para merge.
