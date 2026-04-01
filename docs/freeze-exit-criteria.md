# Criterios de salida del freeze (medibles)

**Fecha de emisión:** 2026-04-01  
**Estado:** Vigente  
**Precondición:** Durante el freeze siguen prohibidas features nuevas (`docs/freeze-window.md`).

Este documento define el gate formal de salida del freeze. La apertura a features solo ocurre cuando **todos** los criterios estén en estado cumplido y verificable.

## Gate de salida (100% obligatorio)

| ID | Criterio medible | Evidencia requerida | Estado objetivo |
|---|---|---|---|
| EXIT-01 | Existe y está publicado este documento (`docs/freeze-exit-criteria.md`). | Archivo versionado + referencia cruzada desde `docs/freeze-window.md`. | Cumplido |
| EXIT-02 | Los 9 sistemas críticos tienen fila completa y validada en `docs/sovereignty-map.md`. | Sección "Validación de owner único por fila" en estado **9/9** con decisión por sistema (`SOV-001`..`SOV-009`). | Cumplido |
| EXIT-03 | No queda ninguna entrada marcada como **CONFLICTO** sin decisión registrada. | Declaración explícita en `docs/sovereignty-map.md` + trazabilidad a sección de resolución. | Cumplido |
| EXIT-04 | Glosario y política de side effects están publicados y enlazados. | Enlaces activos a `docs/domain-glossary.md` y `docs/side-effects-policy.md` desde este documento y desde `docs/freeze-window.md`. | Cumplido |
| EXIT-05 | Habilitación de features nuevas exige referencia explícita al owner afectado. | Regla operativa incluida en este documento y en `docs/freeze-window.md`; todo PR de feature debe declarar `owner` y dominio del `docs/sovereignty-map.md`. | Cumplido |

## Checklist operativa de cierre

- [x] EXIT-01 completado.
- [x] EXIT-02 completado.
- [x] EXIT-03 completado.
- [x] EXIT-04 completado.
- [x] EXIT-05 completado.

## Regla de habilitación de features (post-freeze)

A partir del cierre formal del freeze, se habilitan features nuevas **solo si** cada propuesta incluye:

1. **Owner explícito afectado** (nombre del dominio + owner canónico de `docs/sovereignty-map.md`).
2. **Contrato de frontera** (qué decide el owner, qué no decide, y side effects prohibidos relevantes).
3. **Ruta de integración** (comandos/eventos permitidos entre dominios).

Formato mínimo obligatorio en PR de feature:

- `Dominio/owner afectado:` `<dominio> / <owner canónico>`
- `Impacto de soberanía:` `<sin cambio | cambio acotado | requiere ADR>`
- `Side effects prohibidos revisados:` `<sí/no>`

## Referencias cruzadas obligatorias

- Ventana operativa del freeze: `docs/freeze-window.md`
- Mapa de soberanía y decisiones: `docs/sovereignty-map.md`
- Glosario canónico: `docs/domain-glossary.md`
- Política de side effects: `docs/side-effects-policy.md`
