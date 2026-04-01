## Resumen
- Describe brevemente el cambio y su impacto.

## Checklist obligatoria — olores prohibidos (bloqueante)
Marca cada ítem con `Sí` o `No` y agrega evidencia.

Fuentes de verdad:
- [`docs/pr-smell-blacklist.md`](../docs/pr-smell-blacklist.md)
- [`docs/phase-7-cut1-time-scheduling.md`](../docs/phase-7-cut1-time-scheduling.md)

> **Regla de merge:** cualquier respuesta **“Sí”** sin justificación aprobada y sin excepción registrada bloquea el merge.

- [ ] **¿Este PR añade timer local explícito (`Timer`, `create_timer`, contador temporal en `_process` / `_physics_process`)?**
  - Respuesta:
  - Evidencia (ruta de código o nota de arquitectura):
- [ ] **Si añade timer local: ¿la categoría permitida es `LOCAL_TIMER_BY_DESIGN` y la excepción incluye fecha de revisión (`YYYY-MM-DD`)?**
  - Respuesta:
  - Categoría / Fecha de revisión:
  - Evidencia (ruta de código o nota de arquitectura):
- [ ] **¿Este caso debería usar Cadence según `phase-7-cut1-time-scheduling.md`?**
  - Respuesta:
  - Evidencia (ruta de código o nota de arquitectura):
- [ ] **Si debería usar Cadence, ¿existe excepción temporal aprobada y registrada?**
  - Respuesta:
  - ID / enlace de aprobación:
  - Registro en deuda temporal (fila):
- [ ] **¿agrega comportamiento en autoload que debería vivir en un owner de dominio?**
  - Respuesta:
  - Evidencia de cumplimiento (ruta de código o nota de arquitectura):
- [ ] **¿duplica heurística ya existente?**
  - Respuesta:
  - Evidencia de cumplimiento (ruta de código o nota de arquitectura):
- [ ] **¿mezcla debug con mutación?**
  - Respuesta:
  - Evidencia de cumplimiento (ruta de código o nota de arquitectura):

## Evidencia global obligatoria
- [ ] Incluí evidencia para todos los puntos (ruta de código o nota de arquitectura).
- [ ] Si hubo excepciones, quedaron registradas en `docs/incidencias/registro-unico-deuda-tecnica.md` (registro único de deuda temporal) con fecha de retiro y fecha de revisión.
- [ ] Acepto criterio de bloqueo: si este caso debería usar Cadence y no hay excepción temporal aprobada, este PR queda en **No Ready**.

## Excepciones (solo si aplica)
Si marcaste algún **“Sí”**, completa:
- Justificación aprobada:
- Categoría permitida (obligatoria): `LOCAL_TIMER_BY_DESIGN`
- Fecha de revisión (YYYY-MM-DD):
- ID / enlace de aprobación:
- Registro en deuda temporal (fila o sección):
- Fecha de retiro comprometida (YYYY-MM-DD):
