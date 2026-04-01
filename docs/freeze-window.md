# Freeze Window Operativo (fuente de verdad)

**Estado:** Activo  
**Inicio:** 2026-04-01  
**Fin:** 2026-04-15  
**Alcance:** Todo el repositorio `nuclear-sand-box`.

> Este documento es la **fuente de verdad** del equipo para el período de freeze.  
> Cualquier trabajo diario debe referenciar este archivo.

## Regla explícita del freeze

Durante el freeze **solo se permiten** cambios de:

1. Auditoría.
2. Limpieza.
3. Documentación de fronteras.
4. Deduplicación.
5. Renombrado semántico.

Cualquier cambio fuera de estas categorías se considera **rechazado** hasta cerrar el freeze.

## Criterios de aceptación diarios

Para que un cambio sea aceptado durante el freeze, cada entrega diaria debe dejar evidencia mínima en el mismo PR/commit:

- **Diff verificable:**
  - El diff debe ser acotado y trazable a una de las 5 categorías permitidas.
  - Debe evitar cambios funcionales de comportamiento.
- **Nota de frontera (boundary note):**
  - Explica qué frontera/documentación se aclara o respeta.
  - Incluye alcance (qué toca) y no alcance (qué no toca).
- **Riesgo mitigado:**
  - Declara el riesgo reducido (ej. deuda técnica, ambigüedad, duplicación, nombres confusos).
  - Describe cómo se validó que no se introducen features nuevas.

### Checklist diario (obligatorio)

- [ ] Cambio clasificado en una categoría permitida.
- [ ] Diff pequeño y auditable.
- [ ] Nota de frontera incluida.
- [ ] Riesgo mitigado declarado.
- [ ] Confirmación explícita: “sin feature nueva”.

## Exclusiones (cambios rechazados por considerarse feature nueva)

Ejemplos concretos que se rechazan durante el freeze:

- Agregar mecánicas nuevas de juego/simulación.
- Incorporar nuevas pantallas, menús o flujos de UX no existentes.
- Añadir endpoints, eventos o contratos de datos nuevos.
- Cambiar lógica de negocio para habilitar capacidades inéditas.
- Introducir assets funcionales para contenido nuevo (no limpieza).
- Cambiar balance/comportamiento para alterar experiencia de usuario final.
- Integrar librerías o dependencias para habilitar funcionalidades nuevas.

## Publicación y referencia en canal diario

Este documento queda publicado en `docs/freeze-window.md` como referencia oficial.

**Instrucción operativa para el canal de trabajo diario:**

- Al iniciar cada jornada, publicar un mensaje con enlace a este documento.
- Todo reporte diario debe incluir: categoría permitida, evidencia (diff + nota de frontera + riesgo mitigado), y estado del checklist.

Mensaje sugerido para el canal:

> Fuente de verdad del freeze: `docs/freeze-window.md`  
> Hoy solo ejecutamos cambios permitidos (auditoría, limpieza, fronteras, deduplicación o renombrado semántico) con evidencia completa.

## Criterios de salida y habilitación de features

La salida formal del freeze se rige por `docs/freeze-exit-criteria.md`.

Referencias publicadas y obligatorias:

- Gate de salida del freeze: `docs/freeze-exit-criteria.md`
- Mapa de soberanía: `docs/sovereignty-map.md`
- Glosario canónico: `docs/domain-glossary.md`
- Política de side effects: `docs/side-effects-policy.md`

Una vez cumplidos todos los criterios de salida, las features nuevas se habilitan solo con referencia explícita al owner afectado (dominio + owner canónico) en cada PR.
