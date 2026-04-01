# Glosario de dominio canónico

Fecha: 2026-04-01.

Este glosario define nombres canónicos para conceptos de arquitectura social/mundo y registra sinónimos permitidos o no permitidos.
El objetivo es reducir ambigüedad antes de renombrados de mayor alcance en código.

## Reglas de uso

- En documentación de arquitectura, usar siempre el **nombre canónico**.
- Los **reemplazos permitidos** solo se aceptan en contexto informal o cuando se cita un nombre histórico.
- Los **reemplazos no permitidos** deben migrarse de forma incremental por dominio para evitar cambios masivos de alto riesgo.

## 1) Tiempo y cadencia

| Concepto | Nombre canónico | Reemplazos permitidos | Reemplazos no permitidos | Motivo de ambigüedad |
|---|---|---|---|---|
| Tiempo jugable persistente por día | Tiempo del mundo | reloj del mundo | tiempo global | Se confunde con reloj monotónico técnico |
| Tiempo técnico monotónico para cooldowns | Reloj de ejecución | run clock | tiempo global | Colisiona con semántica de día/noche |
| Scheduler por lanes del runtime | Cadencia del mundo | scheduler del mundo | tick manager | Nombre genérico poco preciso |

## 2) IA bandida

| Concepto | Nombre canónico | Reemplazos permitidos | Reemplazos no permitidos | Motivo de ambigüedad |
|---|---|---|---|---|
| Dominio de comportamiento de grupos y NPCs bandidos | IA bandida | comportamiento bandido | bandit ai (en títulos nuevos) | Mezcla idioma ES/EN y varía por documento |
| Estado/intención táctica por grupo | Intención de grupo bandido | group intent | mood de grupo | “Intent” solo no indica ámbito |
| Scanner de señales sociales para bandidos | Inteligencia de grupo bandido | intel bandida | detector bandido | Nombres vagos y poco trazables |

## 3) Territorialidad y hostilidad

| Concepto | Nombre canónico | Reemplazos permitidos | Reemplazos no permitidos | Motivo de ambigüedad |
|---|---|---|---|---|
| Reglas espaciales y fricción por facción | Territorialidad y hostilidad | hostilidad territorial | territorio | “Territorio” solo omite hostilidad |
| Estado cuantitativo de conflicto por facción | Hostilidad de facción | nivel de hostilidad | amenaza | “Amenaza” también se usa para sesión global |

## 4) Coerción bandida (extorsión e incursión)

| Concepto | Nombre canónico | Reemplazos permitidos | Reemplazos no permitidos | Motivo de ambigüedad |
|---|---|---|---|---|
| Dominio de encounters coercitivos | Coerción bandida (extorsión e incursión) | coerción bandida | raids / extortion | Mezcla idioma y separa un mismo macroflujo |
| Flujo coercitivo de demanda/amenaza | Flujo de extorsión | extorsión | extortion flow (en títulos nuevos) | Inconsistencia de estilo documental |
| Flujo coercitivo de ataque organizado | Flujo de incursión | incursión bandida | raid flow (en títulos nuevos) | “Raid” puede significar job, cola o evento |

## 5) Botín e inventario

| Concepto | Nombre canónico | Reemplazos permitidos | Reemplazos no permitidos | Motivo de ambigüedad |
|---|---|---|---|---|
| Estado runtime del item en mundo | Drop de botín | drop | loot node | Se confunde con sistema de generación de loot |
| Acción de absorber un drop | Recogida de botín | pickup | loot pickup | Mezcla de niveles (acción vs dominio) |
| Estado canónico de ítems del actor | Inventario | bolsa | storage | “Storage” sugiere contenedor world, no actor |

## 6) Construcción y estructuras

| Concepto | Nombre canónico | Reemplazos permitidos | Reemplazos no permitidos | Motivo de ambigüedad |
|---|---|---|---|---|
| Validación + commit de construcción | Sistema de construcción | placement system | placement (como dominio completo) | “Placement” solo cubre colocación inicial |
| Objetos construibles no muro | Estructuras colocables | placeables | props colocables | Se mezcla con props decorativos de generación |
| Estructura defensiva del jugador | Muro del jugador | pared del jugador | wall player | Orden/idioma inconsistente |

## Plan de renombrado incremental (bajo riesgo)

1. **Fase A (docs de soberanía e inventario):** normalizar títulos de dominio y términos de frontera en `docs/sovereignty-map.md` y `docs/system-inventory.md`.
2. **Fase B (docs de arquitectura social):** propagar canónicos a `docs/social_world_architecture.md` y documentación operativa asociada.
3. **Fase C (código y API pública):** solo cuando exista matriz de impacto y pruebas de regresión por dominio.

Estado actual: **Fase A iniciada en esta entrega**.
