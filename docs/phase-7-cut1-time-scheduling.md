# Phase 7 - Cut 1: Time Scheduling

## Objetivo del corte

Establecer una política única para el manejo del tiempo en tareas de gameplay recurrentes, definiendo de forma explícita quién es responsable del **"cuándo se ejecuta"** y en qué casos se permiten excepciones locales.

## Regla principal de ownership

Para tareas de gameplay recurrentes, **Cadence** es el dueño del **"cuándo se ejecuta"**.

Esto implica que:

- La decisión temporal de ejecución periódica (frecuencia, tick, ventana, reintentos, orden temporal) debe centralizarse en Cadence.
- Los sistemas de gameplay no deben introducir timers locales para controlar recurrencia si Cadence puede resolver el caso.
- Cualquier desviación debe tratarse como excepción explícita y documentada.

## Excepciones válidas para timer local

Se permite timer local únicamente en los siguientes escenarios:

1. **UI local**
   - Casos visuales o de interacción de interfaz que no afectan lógica de gameplay autoritativa.

2. **Animación local**
   - Efectos o secuencias visuales locales cuyo timing no modifica reglas de juego compartidas.

3. **Tooling temporal**
   - Herramientas auxiliares de desarrollo, debug o instrumentación de vida corta.

4. **Pruebas controladas**
   - Entornos de test aislados, con alcance y duración definidos, donde el objetivo sea validar comportamiento temporal.

## Requisito obligatorio para cualquier excepción

Cada uso de timer local en las excepciones anteriores debe incluir:

- **Justificación explícita** (qué problema resuelve y por qué Cadence no aplica en ese punto).
- **Categoría permitida obligatoria**: `LOCAL_TIMER_BY_DESIGN`.
- **Fecha de revisión obligatoria** en formato `YYYY-MM-DD`.

Sin estos elementos, el uso de timer local se considera incumplimiento de esta política.

## Gate obligatorio en checklist de PR

La plantilla de PR debe validar explícitamente estos puntos:

1. Si se añadió timer local.
2. Si existe categoría permitida `LOCAL_TIMER_BY_DESIGN` y fecha de revisión.
3. Si el caso realmente debía resolverse con Cadence.
4. Si existe excepción temporal aprobada y registrada.

**Criterio de bloqueo:** si el caso debía usar Cadence y no hay excepción temporal aprobada, el PR queda en estado **No Ready**.

Registro único para excepciones: `docs/incidencias/registro-unico-deuda-tecnica.md`.

## Tabla de decisión y revisión

| Caso | Cadence o Local | Motivo | Fecha de revisión |
|---|---|---|---|
| Gameplay recurrente (default) | Cadence | Ownership centralizado del "cuándo" para consistencia temporal | 2026-04-01 |
| UI local no autoritativa | Local | Render/UX local sin impacto en reglas compartidas | 2026-04-01 |
| Animación local | Local | Timing visual sin efecto en estado de gameplay autoritativo | 2026-04-01 |
| Tooling temporal | Local | Soporte de desarrollo transitorio con alcance acotado | 2026-04-01 |
| Pruebas controladas | Local | Validación aislada bajo condiciones de test explícitas | 2026-04-01 |
