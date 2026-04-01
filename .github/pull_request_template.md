## Gate obligatorio — Copy/Paste requerido
Completa **todas** las líneas (no dejar vacío). Este bloque es validado por CI.

- Respuesta timer local injustificado: No
- Evidencia timer local injustificado:
- Respuesta lógica nueva en autoload: No
- Evidencia lógica nueva en autoload:
- Respuesta lógica global oculta: No
- Evidencia lógica global oculta:
- Respuesta decisión duplicada (assault/combat/hostility): No
- Evidencia decisión duplicada (assault/combat/hostility):
- Respuesta debug mutando estado: No
- Evidencia debug mutando estado:
- Respuesta telemetry/debug fuera de canal controlado mutando estado: No
- Evidencia telemetry/debug fuera de canal controlado mutando estado:
- Respuesta cambio de estado nuevo en el PR: No
- Owner de decisión tocada (obligatorio):
- Categoría de verdad para datos/campos nuevos: no aplica
- Owner de escritura para cambio de estado nuevo: no aplica
- Categoría de verdad del cambio de estado nuevo: no aplica
- Justificación explícita si NO se usa Cadence en gameplay:
- Registro de excepción temporal (si aplica): sin excepción
- Fecha de retiro obligatoria (YYYY-MM-DD): 2099-12-31
- Criterio de done Sprint 1 (patrones corregidos no reingresan): Sí
- Criterio de done anti-reversión (no volver al estado anterior por flujo normal de PR): Sí

## Resumen
- Describe brevemente el cambio y su impacto.

## Checklist obligatoria — anti-olores + arquitectura (bloqueante)
Marca cada ítem con `Sí` o `No` y agrega evidencia.

Fuentes de verdad:
- [`docs/pr-smell-blacklist.md`](../docs/pr-smell-blacklist.md)
- [`docs/phase-7-cut1-time-scheduling.md`](../docs/phase-7-cut1-time-scheduling.md)
- [`docs/runtime-layer-matrix.md`](../docs/runtime-layer-matrix.md)

> **Regla de merge:** cualquier respuesta **“Sí”** sin justificación aprobada y sin excepción registrada bloquea el merge.
> **Regla adicional (Bandit Assault Pipeline):** se bloquea merge si el cambio crea bifurcación no documentada en el diagrama canónico de `docs/phase-7-cut2-bandit-assault.md`.

- [ ] **¿Declaraste owner de cada decisión de arquitectura tocada (dominio + owner canónico)?**
  - Respuesta:
  - Owner(es):
  - Evidencia:
- [ ] **¿Este PR añade timer local explícito (`Timer`, `create_timer`, contador temporal en `_process` / `_physics_process`)?**
  - Respuesta:
  - Evidencia (ruta de código o nota de arquitectura):
- [ ] **Si añade timer local: ¿incluye justificación de por qué no aplica Cadence + owner responsable + categoría `LOCAL_TIMER_BY_DESIGN`?**
  - Respuesta:
  - Justificación / Owner / Categoría:
  - Evidencia (ruta de código o nota de arquitectura):
- [ ] **¿Este caso debería usar Cadence según `phase-7-cut1-time-scheduling.md`?**
  - Respuesta:
  - Evidencia (ruta de código o nota de arquitectura):
- [ ] **Si debería usar Cadence, ¿existe excepción temporal aprobada y registrada con fecha de retiro obligatoria (`YYYY-MM-DD`)?**
  - Respuesta:
  - ID / enlace de aprobación:
  - Registro en deuda temporal (fila):
- [ ] **¿Para cada dato/campo nuevo declaraste categoría única de verdad (`runtime` / `save` / `derived` / `cache`) y owner de escritura?**
  - Respuesta:
  - Dato/campo → categoría + owner:
  - Evidencia (ruta de código o nota de arquitectura):
- [ ] **¿agrega comportamiento en autoload que debería vivir en un owner de dominio?**
  - Respuesta:
  - Evidencia de cumplimiento (ruta de código o nota de arquitectura):
- [ ] **¿duplica heurística ya existente?**
  - Respuesta:
  - Evidencia de cumplimiento (ruta de código o nota de arquitectura):
- [ ] **¿mezcla debug con mutación?**
  - Respuesta:
  - Evidencia de cumplimiento (ruta de código o nota de arquitectura):

- [ ] **¿introduce ruta alternativa en Bandit Assault Pipeline?**
  - Respuesta:
  - Etapa(s) afectada(s):
  - Owner(s) afectado(s):
  - Evidencia de cumplimiento (ruta de código o nota de arquitectura):
- [ ] **¿duplica decisión ya definida en Bandit Assault Pipeline?**
  - Respuesta:
  - Etapa(s) afectada(s):
  - Owner(s) afectado(s):
  - Evidencia de cumplimiento (ruta de código o nota de arquitectura):
- [ ] **¿corrige intención a mitad de pipeline en Bandit Assault Pipeline?**
  - Respuesta:
  - Etapa(s) afectada(s):
  - Owner(s) afectado(s):
  - Evidencia de cumplimiento (ruta de código o nota de arquitectura):
- [ ] **¿declara explícitamente etapa y owner afectados en cada cambio de pipeline?**
  - Respuesta:
  - Evidencia de cumplimiento (ruta de código o nota de arquitectura):

## Reglas de bloqueo (sin excepción aprobada)
- [ ] Acepto que toda violación bloqueante sin excepción aprobada deja este PR en **No Ready**.
- [ ] Si hubo excepción temporal, quedó registrada en `docs/incidencias/registro-unico-deuda-tecnica.md`.
- [ ] Confirmo que cada excepción temporal usada tiene fecha de retiro comprometida (`YYYY-MM-DD`).

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
- Responsable de retiro:
- Fecha de retiro comprometida (YYYY-MM-DD):
