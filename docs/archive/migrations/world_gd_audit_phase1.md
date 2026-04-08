# world.gd — Auditoría de responsabilidades (Phase 1)

Objetivo: establecer línea base de responsabilidades del `world.gd` para medir reducción en fases posteriores.

**Criterio de lectura**
- **🟢 DOMINIO** en la columna “Función/método” indica lógica de negocio/casos de uso candidata a extracción.
- Tipo permitido: `bootstrap` | `wiring` | `tick` | `bridge Godot` | `dominio`.
- Riesgo de extracción evalúa acoplamiento actual con estado de `world.gd`, nodos Godot y side-effects.

| Función/método | Tipo | Dependencias que toca | Riesgo de extracción |
|---|---|---|---|
| `_ready` | bootstrap | SaveManager/WorldSave, TileMaps, ChunkPipeline, EntitySpawnCoordinator, NpcSimulator, CliffGenerator, PlayerWallSystem, SettlementIntel, BanditBehaviorLayer, NpcPathService, señales de GameEvents/PlacementSystem | alto |
| `_on_chunk_stage_completed` | wiring | señal `chunk_stage_completed`, `_player_wall_system`, `ensure_tavern_sentinels_spawned` | medio |
| `_on_spawn_job_completed` | wiring | jobs de spawn (`npc_keeper`), `_wire_keeper_incident_reporter` | medio |
| `_clear_chunk_wall_runtime_cache` | wiring | `_chunk_wall_collider_cache` | bajo |
| `_notification` | bridge Godot | `NOTIFICATION_WM_CLOSE_REQUEST`, `_perform_world_save`, `get_tree().quit()` | bajo |
| `_unhandled_input` | bridge Godot | InputMap (`ui_save_game/ui_load_game/ui_new_game`), SaveManager, reload scene | bajo |
| `_process_tile_erase_queue` | tick | `_pending_tile_erases`, `loaded_chunks`, `unload_chunk` | medio |
| `_process_wall_refresh_queue` | tick | `_wall_refresh_queue`, `_ensure_chunk_wall_collision`, `PlacementPerfTelemetry` | medio |
| `_register_drop_compaction_hotspot` | dominio | `_drop_compaction_hotspots`, Time | medio |
| `_prune_drop_compaction_hotspots` | dominio | `_drop_compaction_hotspots` | bajo |
| `_build_drop_compaction_anchor_list` | dominio | `_drop_compaction_hotspots`, `_world_spatial_index`, `_world_to_tile/_tile_to_chunk/_tile_to_world` | medio |
| `_get_drop_pressure_level_for_count` | dominio | thresholds de presión de drops | bajo |
| `_update_drop_pressure_snapshot` | tick | `_world_spatial_index`, `LootSystem.set_drop_pressure_snapshot` | medio |
| `_drop_pressure_scaled_int` | dominio | `_drop_pressure_snapshot` | bajo |
| `_drop_pressure_scaled_float` | dominio | `_drop_pressure_snapshot` | bajo |
| `_compact_item_drops_once` | dominio | `_world_spatial_index`, `ItemDrop`, hotspot API, queue_free | alto |
| `_process` | tick | `WorldCadenceCoordinator`, pipeline, simuladores, controladores visuales, autosave, chunk update | alto |
| `world_to_chunk` | bridge Godot | `_world_to_tile`, `_tile_to_chunk` | bajo |
| `_is_chunk_in_active_window` | dominio | `active_radius` | bajo |
| `update_chunks` | tick | pipeline/entity_coordinator/chunk_generator/vegetation, loaded_chunks, cola de erase | alto |
| `_record_chunk_stage_time` | wiring | `_perf_monitor.record` | bajo |
| `debug_print_chunk_stage_percentiles` | wiring | `_perf_monitor`, `_apply_calibrated_perf_budgets` | bajo |
| `_process_chunk_perf_debug` | tick | `_perf_monitor.tick` | bajo |
| `_apply_calibrated_perf_budgets` | wiring | `_perf_monitor`, propiedades de `pipeline` | medio |
| `unload_chunk` | wiring | `_tile_painter`, tilemaps, `_vegetation_root`, `cliff_generator` | medio |
| `get_spawn_biome` | dominio | `_ground_painter` | bajo |
| `get_walk_surface_at_world_pos` | bridge Godot | `_world_to_tile`, `get_walk_surface_at_tile` | bajo |
| `get_walk_surface_at_tile` | dominio | tile bounds, floor/placeables, `_ground_painter` | medio |
| `_resolve_floor_walk_surface` | dominio | `tilemap` floor layer, atlas map | bajo |
| `_is_valid_walk_surface_tile` | dominio | width/height | bajo |
| `_has_floorwood_placeable_at_tile` | dominio | `WorldSave.get_placed_entity_at_tile` | medio |
| `_debug_check_tile_alignment` | bridge Godot | tilemap local/map conversion, Debug | bajo |
| `_make_spawn_ctx` | wiring | contexto para spawner/simulación; World/Spawn config + callbacks | medio |
| `_on_ground_fallback_debug` | wiring | `_perf_monitor.record_fallback` | bajo |
| `_world_to_tile` | bridge Godot | `tilemap.to_local/local_to_map` | bajo |
| `_has_wall_tile_between` | dominio | `walls_tilemap`, `_tile_line_has_wall` | medio |
| `_tile_line_has_wall` | dominio | Bresenham + lectura de celdas de `walls_tilemap` | medio |
| `_tile_to_world` | bridge Godot | `tilemap.map_to_local/to_global` | bajo |
| `_tile_to_chunk` | dominio | `chunk_size` | bajo |
| `_get_sound_panel_for_walls` | wiring | `AudioSystem.get_sound_panel` | bajo |
| `_debug_check_player_chunk` | bridge Godot | conversiones tile/chunk + Debug | bajo |
| `unload_chunk_entities` | wiring | `pipeline`, `entity_coordinator`, `_chunk_wall_collider_cache` | medio |
| `_get_current_player_chunk` | wiring | `current_player_chunk` | bajo |
| `_chunk_key` | bridge Godot | `WorldSave.chunk_key_from_pos` | bajo |
| `_chunk_from_key` | bridge Godot | `WorldSave.chunk_pos_from_key` | bajo |
| `_get_extra_wall_support_lookup_for_chunk` | dominio | `WorldSave` + `BuildableCatalog` (doorwood) | medio |
| `can_place_player_wall_at_tile` | wiring | `_player_wall_system` | bajo |
| `place_player_wall_at_tile` | wiring | `_player_wall_system` | bajo |
| `damage_player_wall_from_contact` | wiring | `_player_wall_system` | bajo |
| `damage_player_wall_near_world_pos` | wiring | `_player_wall_system` | bajo |
| `damage_player_wall_at_world_pos` | wiring | `_player_wall_system` | bajo |
| `damage_player_wall_in_circle` | wiring | `_player_wall_system` | bajo |
| `find_nearest_player_wall_world_pos` | wiring | `_player_wall_system` | bajo |
| `find_nearest_player_wall_world_pos_global` | wiring | `_player_wall_system` | bajo |
| `find_player_wall_samples_world_pos` | wiring | `_player_wall_system` | bajo |
| `find_nearest_player_workbench_world_pos` | dominio | selector de item IDs de interés (workbench) | bajo |
| `find_nearest_player_storage_world_pos` | dominio | selector de item IDs de interés (chest/barrel) | bajo |
| `find_nearest_player_placeable_world_pos` | dominio | consulta por `_PLAYER_RAID_PLACEABLE_ITEM_IDS` | bajo |
| `_find_nearest_player_placeable_world_pos_by_items` | dominio | `_world_spatial_index.get_placeables...`, `_tile_to_world` | medio |
| `hit_wall_at_world_pos` | wiring | `_player_wall_system` | bajo |
| `damage_player_wall_at_tile` | wiring | `_player_wall_system` | bajo |
| `remove_player_wall_at_tile` | wiring | `_player_wall_system` | bajo |
| `refresh_wall_collision_for_tiles` | wiring | valida bounds + `_mark_walls_dirty_and_refresh_for_tiles` | bajo |
| `_mark_walls_dirty_and_refresh_for_tiles` | tick | cache/queue de colliders, settlement dirty flag, perf telemetry | medio |
| `mark_chunk_walls_dirty` | wiring | `_chunk_wall_collider_cache.mark_dirty` | bajo |
| `_ensure_chunk_wall_collision` | wiring | `_chunk_wall_collider_cache.ensure_for_chunk` | bajo |
| `_init_cliff_screen_size` | bridge Godot | viewport + shader param | bajo |
| `_update_cliff_occlusion` | bridge Godot | viewport/player/cliffs shader + lectura de tiles | medio |
| `get_spawn_world_pos` | bridge Godot | `_tile_to_world` | bajo |
| `teleport_to_spawn` | bridge Godot | `player`, `update_chunks`, Debug | medio |
| `get_tavern_center_tile` | dominio | geometría fija por chunk | bajo |
| `get_tavern_exit_world_pos` | dominio | keeper group lookup + fallback geométrico | medio |
| `get_tavern_inner_bounds_world` | dominio | keeper group lookup + fallback geométrico | medio |
| `🟢 ensure_tavern_sentinels_spawned` | dominio | sentinel_scene, entity_root, bounds/keeper/exit, spawn de 11 roles | alto |
| `🟢 _spawn_single_tavern_sentinel` | dominio | instantiate Sentinel, grupos, patrols, incident reporter | alto |
| `🟢 _get_interior_patrol_points` | dominio | geometría interior taberna | bajo |
| `🟢 _get_perimeter_patrol_points` | dominio | geometría lateral + randomización | bajo |
| `🟢 _tick_defense_posture` | dominio | TavernMemory + TavernDefensePosture.compute + reloj + transición de estado | medio |
| `🟢 _apply_defense_posture` | dominio | TavernPresenceMonitor, TavernAuthorityPolicy, patrullas | medio |
| `🟢 _adapt_perimeter_patrols` | dominio | nodos `tavern_sentinel`, cache de patrol points | medio |
| `🟢 _get_tavern_keeper_pos` | dominio | lookup `tavern_keeper` + fallback geométrico | bajo |
| `🟢 report_tavern_incident` | dominio | incident build, policy evaluate, memory record, director dispatch | alto |
| `🟢 _build_tavern_incident` | dominio | mapping incident_type → modelo `LocalCivilIncident` | medio |
| `_get_tavern_keeper_node` | wiring | lookup grupo `tavern_keeper` | bajo |
| `_wire_keeper_incident_reporter` | wiring | keeper wiring + service check + container registration | medio |
| `🟢 _register_tavern_containers` | dominio | scan de grupos chest/interactable en bounds + reporter | medio |
| `_find_nearest_player` | dominio | búsqueda nearest en grupo `player` | bajo |
| `🟢 _on_wall_hit_activity` | dominio | actividad de walls + clasificación interior/perímetro + incidentes civiles | alto |
| `_get_player_world_pos` | wiring | referencia a `player` | bajo |
| `_on_wall_drop_for_intel` | wiring | settlement intel, hotspot, territory dirty | bajo |
| `_on_placement_completed` | tick | throttle temporal + trigger placement react | medio |
| `🟢 _trigger_placement_react` | dominio | BanditGroupMemory, Faction hostility, scoring, locks, intents | alto |
| `_record_placement_react_debug_event` | wiring | contadores/debug ring buffer | bajo |
| `reset_placement_react_debug_metrics` | wiring | reset métricas de debug | bajo |
| `get_placement_react_debug_snapshot` | wiring | snapshot agregado de métricas | bajo |
| `🟢 _resolve_placement_react_squad_size` | dominio | reglas de tamaño de escuadra | bajo |
| `🟢 _score_placement_relevance` | dominio | fórmula de score (distancia/base/POI/bloqueo) | medio |
| `🟢 _score_placement_react_points_of_interest` | dominio | POIs desde world_spatial_index + hotspots | medio |
| `🟢 _score_placement_react_blocking` | dominio | `NpcPathService.has_line_clear` + budget checks | medio |
| `🟢 _get_placement_react_radius` | dominio | reglas por item + modo global wall assault | bajo |
| `🟢 _is_wall_assault_placement_item` | dominio | BuildableCatalog runtime id resolution | bajo |
| `🟢 _get_group_react_anchor` | dominio | npc_simulator (leader/centro), fallback home | medio |
| `🟢 _is_group_hostile_for_structure_assault` | dominio | FactionHostilityManager profile + baseline hostility | medio |
| `🟢 _is_faction_baseline_hostile_to_player` | dominio | FactionSystem lookup + heurística alias/fallback | medio |
| `🟢 _on_entity_died` | dominio | npc_simulator + incidente `murder_in_tavern` por bounds | medio |
| `_tick_player_territory` | tick | `_player_territory`, `_settlement_intel`, `_world_spatial_index` | medio |
| `is_in_player_territory` | dominio | `PlayerTerritoryMap` query | bajo |
| `get_player_territory_zones` | dominio | `PlayerTerritoryMap` query | bajo |
| `_validate_placement_restrictions` | dominio | delegación a `WorldTerritoryPolicy.validate_placement` | medio |
| `record_interest_event` | dominio | SettlementIntel + WorldTerritoryPolicy + hotspot/territory effects | medio |
| `_on_bandit_territory_intrusion` | dominio | notificación a `BanditBehaviorLayer` | medio |
| `get_interest_markers_near` | dominio | facade `SettlementIntel` | bajo |
| `rescan_workbench_markers` | dominio | `SettlementIntel` + territory dirty | bajo |
| `mark_interest_scan_dirty` | dominio | `SettlementIntel` | bajo |
| `get_detected_bases_near` | dominio | facade `SettlementIntel` | bajo |
| `has_detected_base_near` | dominio | facade `SettlementIntel` | bajo |
| `_paint_outer_ground_band` | bridge Godot | escritura de celdas en `ground_tilemap` | bajo |
| `get_debug_snapshot` | wiring | `_world_sim_telemetry`, `_day_night_controller` | bajo |
| `get_drop_pressure_snapshot` | wiring | copia de `_drop_pressure_snapshot` | bajo |
| `dump_debug_summary` | wiring | `_world_sim_telemetry` + day/night snapshot | bajo |
| `build_overlay_lines` | wiring | `_world_sim_telemetry` + day/night snapshot | bajo |
| `_perform_world_save` | wiring | `SaveManager.save_world`, métricas save | bajo |
| `_get_world_maintenance_debug_snapshot` | wiring | estado de pipeline/cadence/save/drop_compaction | bajo |

## Corte explícito de “dominio” (candidatas a extracción)

### Bloque A — Autoridad social de taberna (alta prioridad)
- `ensure_tavern_sentinels_spawned`, `_spawn_single_tavern_sentinel`, `_tick_defense_posture`, `_apply_defense_posture`, `_adapt_perimeter_patrols`, `report_tavern_incident`, `_build_tavern_incident`, `_on_wall_hit_activity`, `_register_tavern_containers`.
- Posible destino: `TavernAuthorityFacade` + `TavernSecurityOrchestrator`.

### Bloque B — Placement reaction / raid intent (alta prioridad)
- `_trigger_placement_react` y todo su subárbol de scoring (`_score_placement_relevance`, `_score_placement_react_points_of_interest`, `_score_placement_react_blocking`, `_resolve_placement_react_squad_size`, `_get_group_react_anchor`, `_is_group_hostile_for_structure_assault`, `_is_faction_baseline_hostile_to_player`, `_get_placement_react_radius`, `_is_wall_assault_placement_item`).
- Posible destino: `PlacementReactionService`.

### Bloque C — Economía de item drops (prioridad media)
- `_register_drop_compaction_hotspot`, `_build_drop_compaction_anchor_list`, `_update_drop_pressure_snapshot`, `_compact_item_drops_once`, escaladores de presión.
- Posible destino: `DropPressureAndCompactionService`.

### Bloque D — Territorio/interés del jugador (prioridad media)
- `_tick_player_territory`, `record_interest_event`, `_on_bandit_territory_intrusion`, facades de SettlementIntel.
- Posible destino: `WorldInterestAndTerritoryFacade`.

## Lectura de riesgo para fases siguientes
- **Alto**: funciones con mezcla de reglas de negocio + acceso directo a escena + side-effects de varios subsistemas.
- **Medio**: reglas relativamente puras pero con 1–2 puertos de infraestructura.
- **Bajo**: wrappers/facades o utilidades puras.
