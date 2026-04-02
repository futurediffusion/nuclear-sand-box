# world.gd — auditoría de `get_tree().get_nodes_in_group(...)`

## Resumen

Se auditó cada uso de `get_nodes_in_group` en `scripts/world/world.gd` y se clasificó en:

- **Migrado** a índice/puerto runtime (`WorldSpatialIndex` o `npc_simulator.active_enemies`).
- **Mantener live-tree** por diseño (roles institucionales dinámicos o consultas esporádicas heterogéneas).

## Clasificación por uso

| Grupo | Zona/función | Frecuencia | Clasificación | Decisión |
|---|---|---:|---|---|
| `workbench` | `_tick_player_territory()` | **Caliente** (lane `medium_pulse`, ~0.5 s) | Migrable a índice | **Migrado** a `WorldSpatialIndex.KIND_WORKBENCH` (con fallback a group scan). |
| `enemy` | candidatos presencia taberna (`TavernPresenceMonitor`) | **Caliente** (`tick` cada 0.4 s) | Migrable a puerto runtime | **Migrado** a `npc_simulator.active_enemies` mediante `_get_live_enemy_nodes()`. |
| `enemy` | búsqueda cerca (`TavernPerimeterBrawl`) | Media/baja (38–85 s) | Migrable a puerto runtime | **Migrado** a `_get_enemies_near_runtime()` (fuente: `npc_simulator.active_enemies`). |
| `player` | candidatos presencia / nearest player | Caliente-media | Puerto específico disponible (`world.player`) | **Migrado** a `_get_live_player_nodes()` (usa `player` directo, fallback group scan). |
| `tavern_sentinel` | wiring monitores y doble-spawn guard | Baja / control de autoridad local | **Live-tree válido** | **Se mantiene**: set dinámico de sentinels por site y estado de spawn en runtime. |
| `tavern_keeper` | bounds/posición/wiring de keeper | Baja (event-driven) | **Live-tree válido** | **Se mantiene**: lookup canónico del keeper activo en escena (con fallback geométrico). |
| `npc` | candidatos presencia taberna | Caliente-media | Potencial puerto dedicado futuro | **Se mantiene por ahora**: no existe aún índice/registro runtime unificado de civiles/NPC no-hostiles. |
| `chest` / `interactable` | `_register_tavern_containers()` | Eventual (post-spawn / wiring) | Live-tree razonable | **Se mantiene**: consulta esporádica, heterogénea y acotada por bounds de taberna. |

## Migraciones aplicadas

1. `_tick_player_territory()` ahora consulta workbenches por índice runtime (`WorldSpatialIndex`) y evita escaneo global por grupo en el camino caliente.
2. `TavernPresenceMonitor.get_candidates` dejó de escanear globalmente `player` y `enemy`; ahora usa puertos runtime (`player` directo + `npc_simulator.active_enemies`).
3. `TavernPerimeterBrawl.get_nearby_enemies` usa consulta runtime local (`_get_enemies_near_runtime`) en lugar de `get_nodes_in_group("enemy")`.

## Verificación de reducción de scans globales (rutas calientes)

- Antes (rutas calientes principales):
  - `medium_pulse` (~0.5 s): 1 scan global de `workbench`.
  - `presence tick` (0.4 s): 3 scans globales (`player`, `enemy`, `npc`).
- Después:
  - `medium_pulse`: 0 scans globales en escenario normal (índice runtime; fallback sólo si índice ausente).
  - `presence tick`: 1 scan global (`npc`) + 2 puertos runtime (`player`, `enemy`).

**Resultado:** reducción neta en rutas calientes de **4 scans globales por ciclo combinado** a **1 scan global** (normal runtime), manteniendo fallback seguro.

## Casos que deben permanecer live-tree por diseño

- `tavern_sentinel`: estructura de autoridad local y verificación de guarnición dependen del set vivo en árbol.
- `tavern_keeper`: entidad única institucional con fallback geométrico; lookup en árbol es simple y robusto.
- `chest`/`interactable`: wiring eventual y heterogéneo; costo no caliente, beneficio de migración bajo hoy.
- `npc` (por ahora): falta índice runtime dedicado para civiles/NPC no-hostiles.
