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
