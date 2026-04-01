## Runtime Architecture Review (obligatorio)

- [ ] Revisé `docs/runtime-layer-matrix.md` y confirmé que el cambio respeta fronteras de capa.
- [ ] Revisé `docs/runtime-architecture-pact.md` y declaré la regla que este cambio respeta.
- [ ] Revisé [`docs/pr-smell-blacklist.md`](../docs/pr-smell-blacklist.md) y [`docs/phase-7-cut1-time-scheduling.md`](../docs/phase-7-cut1-time-scheduling.md).
- [ ] Confirmo explícitamente si este PR añade timer local (`Timer`, `create_timer`, contadores en `_process`/`_physics_process`).
- [ ] Si añade timer local: adjunté justificación aprobada con categoría `LOCAL_TIMER_BY_DESIGN` y fecha de revisión (`YYYY-MM-DD`).
- [ ] Si el caso debía usar Cadence: existe excepción temporal aprobada y registrada en `docs/incidencias/registro-unico-deuda-tecnica.md`.
- [ ] Acepto el criterio de bloqueo: cualquier “Sí” sin excepción aprobada deja el PR en **No Ready**.

## Declaración de feature (obligatorio para features nuevas)

- **Capa responsable**: <!-- Behavior / Coordination / Persistence / Debug-Telemetry / Cadence / SpatialIndex -->
- **Regla del pacto respetada**: <!-- Ej: R-Co2, R-B1, R-P3, etc -->
- **Evidencia de validación**: <!-- archivo(s), test(s), checklist -->

> Si este PR agrega una nueva feature y no completa los campos anteriores, se considera **No Ready** para merge.
