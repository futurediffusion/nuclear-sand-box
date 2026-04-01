# Phase 6 — Exit Report

Fecha de corte: 2026-04-01.  
Baseline de fase: fortalecimiento de gate de PR + blacklist de olores de arquitectura runtime.

## 1) Verificación de publicación y enlace normativo

- ✅ `docs/pr-smell-blacklist.md` existe y quedó ratificado como política **permanente**.
- ✅ La plantilla de PR en ambos nombres soportados por GitHub (`.github/PULL_REQUEST_TEMPLATE.md` y `.github/pull_request_template.md`) enlaza explícitamente la blacklist.
- ✅ Ambas plantillas declaran checklist anti-olores y criterio de bloqueo en estado **No Ready** para cualquier “Sí” sin excepción aprobada.

## 2) Confirmación de uso en PRs nuevos

A partir de esta fase, el gate se considera obligatorio para todo PR nuevo porque:

1. La checklist anti-olores está en la plantilla base.
2. El criterio de bloqueo quedó declarado en la misma plantilla.
3. La blacklist quedó definida como fuente de verdad permanente para revisión.

Resultado: cualquier PR nuevo que no complete esta evidencia queda fuera de condición de merge.

## 3) Validación de excepciones activas

Se auditó el registro y excepciones vigentes:

- Registro canónico: `docs/incidencias/registro-unico-deuda-tecnica.md` (exige responsable y fecha).
- Excepciones activas de runtime-layer: `INC-TECH-003`.
- Excepciones activas de telemetry/debug: `INC-TECH-002`.

### Estado de campos obligatorios (fecha de retiro + responsable)

| Excepción | Responsable declarado | Fecha de retiro declarada | Estado |
|---|---|---|---|
| EXC-001 (`INC-TECH-002`) | Sí (`Runtime Architecture`) | Sí (`2026-06-30`) | Cumple |
| EXC-002 (`INC-TECH-002`) | Sí (`Runtime Architecture`) | Sí (`2026-05-31`) | Cumple |
| EXC-RUNTIME-001 (`INC-TECH-003`) | Sí (`Runtime Architecture`) | Sí (`2026-06-15`) | Cumple |
| EXC-RUNTIME-002 (`INC-TECH-003`) | Sí (`Runtime Architecture`) | Sí (`2026-05-31`) | Cumple |
| EXC-RUNTIME-003 (`INC-TECH-003`) | Sí (`Runtime Architecture`) | Sí (`2026-05-20`) | Cumple |

Conclusión: las excepciones activas auditadas cuentan con responsable y fecha de retiro.

## 4) Métricas iniciales de fase 6

> Métrica inicial = snapshot al 2026-04-01 para iniciar seguimiento continuo.

| Métrica | Valor inicial |
|---|---:|
| Olores bloqueantes detectados en baseline de gate de PR | 0 |
| Bloqueos efectivos por checklist anti-olores (inicio de fase) | 0 |
| Correcciones directas aplicadas al marco de control | 5 |

Detalle de correcciones directas aplicadas en esta publicación:

1. Ratificación explícita de permanencia de política en blacklist.
2. Link normativo a blacklist en plantilla PR mayúscula.
3. Regla explícita de checklist anti-olores + criterio de bloqueo en plantilla PR mayúscula.
4. Link normativo a blacklist en plantilla PR minúscula.
5. Criterio de bloqueo explícito en plantilla PR minúscula.

## 5) Declaración de política permanente

Se declara formalmente esta política como **permanente** para evitar la deriva de calidad y el patrón de “40 mini por si acaso”.

Implicación operativa permanente:

- No se acepta fragmentar riesgos arquitectónicos en micro-PR para “pasar” el gate.
- Todo cambio nuevo debe demostrar ausencia de olores bloqueantes o excepción temporal aprobada.
- Toda excepción debe nacer con owner y fecha de retiro verificable.
