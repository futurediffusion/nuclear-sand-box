# Registro único de deuda temporal

> Fuente oficial para registrar excepciones temporales aprobadas que bloquean olores prohibidos en PR.
> Toda excepción debe incluir justificación aprobada, fecha de revisión, fecha de retiro y responsable.

## Reglas
- Registrar aquí cualquier excepción temporal aprobada vinculada a un PR.
- No se acepta excepción sin categoría permitida `LOCAL_TIMER_BY_DESIGN` cuando aplique a timer local.
- No se acepta excepción sin fecha de revisión (`YYYY-MM-DD`).
- No se acepta excepción sin fecha de retiro obligatoria (`YYYY-MM-DD`).
- No se acepta excepción sin owner/responsable explícito de retiro.
- El merge queda bloqueado para cualquier “Sí” sin justificación aprobada y sin fila en este registro.
- Criterio de done obligatorio: no entra nueva deuda del tipo corregido en el PR; si entra, el PR queda en **No Ready**.

## Excepciones activas
| ID | Fecha registro | PR | Olor prohibido | Categoría | Justificación aprobada | Responsable | Fecha de revisión | Fecha de retiro | Estado |
|---|---|---|---|---|---|---|---|---|---|
| _Sin excepciones activas_ |  |  |  |  |  |  |  |  |  |

## Excepciones retiradas
| ID | Fecha registro | PR | Olor prohibido | Categoría | Justificación aprobada | Responsable | Fecha de revisión | Fecha de retiro | Fecha retiro efectiva |
|---|---|---|---|---|---|---|---|---|---|
| EXC-TIME-EXTORT-001 | 2026-04-01 | N/A (registro histórico) | Timer local recurrente en `ExtortionFlow` | `LOCAL_TIMER_BY_DESIGN` | Scheduler `remaining += delta` reemplazado por `run_at` sobre `RunClock` y consumo exclusivo desde `director_pulse` en Cadence. | Runtime World | 2026-04-01 | 2026-04-01 | 2026-04-01 |


## Revisión semanal obligatoria de excepciones

- Cadencia: semanal (mínimo 1 vez por semana).
- Objetivo: confirmar retiro en fecha comprometida y evitar permanencia silenciosa.
- Responsable: owner registrado en cada excepción activa.
- Resultado esperado por revisión: `seguir`, `retirar ahora` o `escalar` (si la fecha de retiro fue superada).
- Regla: una excepción activa sin revisión semanal actualizada se considera incumplimiento del gate de PR.

### Log de revisiones semanales

| Fecha revisión | Excepción (ID) | Decisión (`seguir`/`retirar ahora`/`escalar`) | Acciones | Próxima revisión | Responsable |
|---|---|---|---|---|---|
| _Pendiente_ |  |  |  |  |  |
