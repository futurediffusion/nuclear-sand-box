## Runtime Architecture Review (obligatorio)

- [ ] Revisé `docs/runtime-layer-matrix.md` y confirmé que el cambio respeta fronteras de capa.
- [ ] Revisé `docs/runtime-architecture-pact.md` y declaré la regla que este cambio respeta.
- [ ] Confirmo que este PR no introduce clases con 2+ reglas rotas sin excepción aprobada.
- [ ] Revisé [`docs/pr-smell-blacklist.md`](../docs/pr-smell-blacklist.md) y confirmé que no introduzco olores bloqueantes (o adjunté excepción temporal aprobada).
- [ ] Completé la **checklist anti-olores** con evidencia y acepto el **criterio de bloqueo**: cualquier “Sí” sin excepción aprobada deja el PR en **No Ready**.

## Declaración de feature (obligatorio para features nuevas)

- **Capa responsable**: <!-- Behavior / Coordination / Persistence / Debug-Telemetry / Cadence / SpatialIndex -->
- **Regla del pacto respetada**: <!-- Ej: R-Co2, R-B1, R-P3, etc -->
- **Evidencia de validación**: <!-- archivo(s), test(s), checklist -->

> Si este PR agrega una nueva feature y no completa los campos anteriores, se considera **No Ready** para merge.
