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
- [ ] **¿Se evita agregar decisiones semánticas nuevas en `scripts/world/world.gd`?**
  - Respuesta:
  - Evidencia de cumplimiento (ruta de código o nota de arquitectura):
- [ ] **¿Se evita reintroducir resets semánticos directos en `scripts/world/world.gd`?**
  - Respuesta:
  - Evidencia de cumplimiento (ruta de código o nota de arquitectura):
- [ ] **¿`BanditWorkCoordinator` se mantiene sin nuevas responsabilidades de dominio?**
  - Respuesta:
  - Evidencia de cumplimiento (ruta de código o nota de arquitectura):
- [ ] **¿agrega comportamiento en autoload que debería vivir en un owner de dominio?**
  - Respuesta:
  - Evidencia de cumplimiento (ruta de código o nota de arquitectura):
- [ ] **¿duplica heurística ya existente?**
  - Respuesta:
  - Evidencia de cumplimiento (ruta de código o nota de arquitectura):
- [ ] **¿mezcla debug con mutación?**
  - Respuesta:
  - Evidencia de cumplimiento (ruta de código o nota de arquitectura):

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
- [ ] Confirmo que cualquier compat/fallback/wrapper nuevo sin fecha de retiro deja el PR en **No Ready**.
- [ ] Confirmo que decisión semántica nueva en `world.gd` deja el PR en **No Ready**.
- [ ] Confirmo que nuevas responsabilidades de dominio en `BanditWorkCoordinator` dejan el PR en **No Ready**.
- [ ] Confirmo que la checklist obligatoria se mantiene hasta completar 2 sprints sin recaídas.
- [ ] Confirmo que el cierre exige 2 sprints consecutivos sin violaciones de estas reglas.

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
