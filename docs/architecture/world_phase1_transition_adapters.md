# world.gd — integraciones `setup(ctx: Dictionary)` y adaptadores de transición (Fase 1)

## Integraciones actuales detectadas (patrón `setup(ctx)`) 

`world.gd` hoy inyecta dependencias a múltiples subsistemas vía `setup(ctx: Dictionary)`. En esta fase nos enfocamos en los callbacks críticos usados por el circuito de paredes del player (`PlayerWallSystem`):

1. **Transformaciones de coordenadas**
   - Antes: callbacks ad hoc en el `ctx`:
     - `world_to_tile`
     - `tile_to_world`
     - `tile_to_chunk`
2. **Notificación de dirty chunks**
   - Antes: callback ad hoc en el `ctx`:
     - `mark_chunk_walls_dirty`
3. **Trigger de refresh/projections**
   - Antes: callback ad hoc en el `ctx`:
     - `mark_chunk_walls_dirty_and_refresh_for_tiles`

Estos callbacks estaban acoplados como `Callable` sueltos y crecían de forma orgánica dentro de `world.gd`.

## Objetivo de Fase 1 (sin migración completa de Fase 2)

Agregar una capa mínima de **contratos tipados + adaptadores de transición** para frenar la expansión de callbacks ad hoc.

### Contratos tipados mínimos

- `WorldCoordinateTransformContract`
- `WorldChunkDirtyNotifierContract`
- `WorldProjectionRefreshContract`

### Adaptadores de transición (compatibilidad)

- `WorldCoordinateTransformCallableAdapter`
- `WorldChunkDirtyNotifierCallableAdapter`
- `WorldProjectionRefreshCallableAdapter`

Los adaptadores siguen permitiendo backend por `Callable`, pero ahora detrás de interfaces tipadas.

## Resultado de esta fase

- `world.gd` deja de inyectar callbacks individuales a `PlayerWallSystem` para este circuito crítico.
- `PlayerWallSystem` consume puertos/contratos tipados (`*_port`) y mantiene fallback legacy para compatibilidad.
- Se prepara el terreno para Fase 2 (migrar más sistemas y eliminar definitivamente `Callable` legacy del wiring principal).
