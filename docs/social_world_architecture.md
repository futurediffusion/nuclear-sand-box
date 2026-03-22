# Social world architecture

Documento corto de frontera para la siguiente etapa social.

## Fuente de verdad por dominio

- **Facción bandida** = hostilidad global persistente. Vive en `FactionHostilityManager` + `BanditGroupMemory` + política/intel bandido.
- **Taberna civil futura** = autoridad local contextual. Debe vivir aparte, con memoria local y sanciones locales, sin mezclarla con la hostilidad global bandida.
- **`world.gd`** = composición y cableado. Debe registrar servicios y conectar eventos, no decidir política social detallada.
- **Keepers / guards / NPCs** = actores ejecutores. Reaccionan a directivas; no son fuente de verdad del sistema social.

## Puntos de integración ya preparados

- `LocalSocialAuthorityPorts`: seam mínimo de composición para:
  - `TavernLocalMemory`
  - `TavernAuthorityPolicy`
  - `TavernResponseDirector`
- `WorldTerritoryPolicy` ya acepta esos puertos para observar eventos del mundo sin ensuciar `world.gd`.
- `BanditBehaviorLayer` queda fuera de la autoridad civil: consume runtime bandido, no política de taberna.

## Siguiente etapa esperada

1. Implementar `TavernLocalMemory` como fuente local de incidentes/contexto.
2. Implementar `TavernAuthorityPolicy` para decidir acceso, sospecha y escalado local.
3. Implementar `TavernResponseDirector` para traducir decisiones en respuestas de keeper/guards.
4. Conectar esas piezas a `LocalSocialAuthorityPorts` desde `world.gd`, sin volver a meter lógica social en actores o en el propio world.

## Nota de diseño: jobs diferidos de dominio

Para `ExtortionFlow` y futuros flows sociales, la siguiente pasada ideal sería
formalizar un criterio para jobs diferidos de dominio antes de crear un
servicio genérico.

### Mantener scheduling local al flow cuando

- El callback es **runtime-only** y puede perderse sin problema si el chunk o el
  mundo se reconstruyen.
- El owner natural del delay es **un único flow**.
- No hace falta persistencia, inspección global ni cancelación desde otros
  subsistemas.
- El volumen es pequeño y no justifica una capa extra de coordinación.

### Extraer un scheduler world-owned cuando

- Existan **dos o más flows** reutilizando el mismo patrón de callbacks
  diferidos.
- Haga falta **cancelación o visibilidad compartida** entre sistemas.
- El mundo necesite **auditar, pausar o budgetear** estos jobs desde un punto
  central.
- Algún callback deba **sobrevivir reload/rebuild** o integrarse con estado
  persistente.

### Decisión actual

Todavía **no hace falta**. En este momento, extraer un scheduler world-owned
sería más abstracción que claridad. El equilibrio actual favorece mantener los
callbacks diferidos pegados al flow que los entiende, y revisar la decisión
cuando aparezca un segundo consumidor real.
