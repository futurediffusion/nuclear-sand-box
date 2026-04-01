# Mini “por si acaso” register

Este documento define una rutina mínima para registrar y controlar incidencias detectadas en PRs y código existente, evitando que la deuda técnica crezca silenciosamente.

## Objetivo

Registrar excepciones y hallazgos que se aceptan temporalmente “por si acaso”, con trazabilidad, owner y fecha de salida.

## Rutina periódica única

Frecuencia: **semanal o por sprint** (elegir una sola y mantenerla estable).

En cada ciclo se revisa explícitamente:

1. **Heurísticas duplicadas**
2. **Timers paralelos**
3. **Fallbacks permanentes sin fecha de retiro**
4. **Accesos globales innecesarios**

## Clasificación y ownership

Cada hallazgo debe agruparse por dominio (ejemplo: `world`, `ui`, `systems`, `gameplay`) y asignar un owner de remediación.

Plantilla sugerida por hallazgo:

| ID | Dominio | Hallazgo | Riesgo | Owner | Estado |
|---|---|---|---|---|---|
| INC-XXXX | world | Timer paralelo en refresh de walls | Medio | @owner | Abierto |

## Requisitos obligatorios para fallbacks temporales

Todo fallback permitido temporalmente debe incluir:

- **Motivo**
- **Condición de retiro**
- **Fecha límite**
- **Responsable**

Plantilla mínima:

| Fallback | Motivo | Condición de retiro | Fecha límite | Responsable |
|---|---|---|---|---|
| `fallback_x` | Bloqueo de release | Métrica/feature X estable | 2026-05-01 | @owner |

## Cierre de ciclo

Al final de cada revisión, publicar un resumen breve con formato:

> **Agregado vs retirado**: `+N / -M`

Ejemplo:

> **Agregado vs retirado**: `+3 / -5` (deuda neta: -2)

Esto permite visualizar reducción real de deuda y evitar crecimiento silencioso.
