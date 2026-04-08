# Migración: configuración de walls hacia `PlayerWallSystem`

## Objetivo
Evitar que `world.gd` vuelva a conocer detalles internos de audio/feedback/drops de walls del player.

## Estado actual
- `world.gd` sólo inyecta dependencias globales y parámetros funcionales base mediante `PlayerWallSystem.setup(...)`.
- `PlayerWallSystem` resuelve internamente:
  - defaults de audio (`DEFAULT_PLAYER_WALL_HIT_SOUNDS`, `DEFAULT_PLAYER_WALL_HIT_VOLUME_DB`),
  - overrides desde `SoundPanel` (vía `AudioSystem.get_sound_panel()`),
  - validación/sanitización de audio (`_to_valid_sound_pool`).

## Regla de mantenimiento
Si se agregan nuevos parámetros de **audio de walls**:
1. Implementar en `PlayerWallSystem.configure_audio(...)`.
2. Mantener `world.gd` sin claves de audio de walls en el `setup`.
3. No reintroducir variables runtime de audio de walls en `world.gd`.

## Compatibilidad temporal
`PlayerWallSystem.setup(...)` aún acepta claves legacy de audio (`player_wall_hit_sounds`, `player_wall_hit_volume_db`) para no romper integraciones existentes, pero su uso nuevo está desaconsejado.
