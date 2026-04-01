## Runtime Architecture Review (obligatorio)

- [ ] Revisé `docs/runtime-layer-matrix.md` y confirmé que el cambio respeta fronteras de capa.
- [ ] Revisé `docs/runtime-architecture-pact.md` y declaré la regla que este cambio respeta.
- [ ] Revisé [`docs/pr-smell-blacklist.md`](../docs/pr-smell-blacklist.md) y [`docs/phase-7-cut1-time-scheduling.md`](../docs/phase-7-cut1-time-scheduling.md).
- [ ] Confirmo explícitamente si este PR añade timer local (`Timer`, `create_timer`, contadores en `_process`/`_physics_process`).
- [ ] Si añade timer local: adjunté justificación aprobada con categoría `LOCAL_TIMER_BY_DESIGN` y fecha de revisión (`YYYY-MM-DD`).
- [ ] Si el caso debía usar Cadence: existe excepción temporal aprobada y registrada en `docs/incidencias/registro-unico-deuda-tecnica.md`.
- [ ] Acepto el criterio de bloqueo: cualquier “Sí” sin excepción aprobada deja el PR en **No Ready**.


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

## Declaración de feature (obligatorio para features nuevas)

- **Capa responsable**: <!-- Behavior / Coordination / Persistence / Debug-Telemetry / Cadence / SpatialIndex -->
- **Regla del pacto respetada**: <!-- Ej: R-Co2, R-B1, R-P3, etc -->
- **Evidencia de validación**: <!-- archivo(s), test(s), checklist -->

> Si este PR agrega una nueva feature y no completa los campos anteriores, se considera **No Ready** para merge.
