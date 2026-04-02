# Phase 7 — Time Scheduling Inventory

Fecha de corte: 2026-04-01.

## Criterios de clasificación
- `MIGRAR_A_CADENCE`: scheduling de gameplay compartido o autoritativo que debería unificarse en `WorldCadenceCoordinator`.
- `MANTENER_LOCAL_BY_DESIGN`: timing estrictamente local (UX/animación/callback efímero) sin ownership global requerido.
- `DUDOSO_REVISAR`: mezcla de lógica de dominio + reloj local donde todavía no está claro el ownership final.

## Inventario de puntos de scheduling

| # | Archivo / método | Propósito | Frecuencia / trigger | Impacto gameplay | Clasificación | Prioridad |
|---|---|---|---|---|---|---|
| 1 | `scripts/world/world.gd::_ready` + `WorldCadenceCoordinator.configure_lane` | Define lanes globales (`short_pulse`, `medium_pulse`, `director_pulse`, `chunk_pulse`, `autosave`, scans de settlement). | 0.12s, 0.50s, `chunk_check_interval`, `autosave_interval`, 10s/30s por lane. | Orquestación central de mundo (chunks, raids/extorsión vía director, territorio, persistencia). | `MANTENER_LOCAL_BY_DESIGN` | **P0 (base)** |
| 2 | `scripts/world/world.gd::_process` (`consume_lane`) | Consume pulsos y ejecuta territorio, wall refresh, autosave y chunk update gating. | Por frame + pulsos due de Cadence. | Alto: afecta simulación de mundo + persistencia. | `MANTENER_LOCAL_BY_DESIGN` | **P0** |
| 3 | `scripts/world/BanditBehaviorLayer.gd::_process` (`director_pulse`) | Corre directors de extorsión/raid con lane única de Cadence (sin fallback local activo). | Cadence `director_pulse` (0.12s). | **Combate/hostilidad/raids** directos. | `MIGRADO_A_CADENCE` | **P0** |
| 4 | `scripts/world/BanditBehaviorLayer.gd::_process` (`bandit_behavior_tick`) + `BanditTuning.behavior_tick_interval` | Tick de behaviors de bandidos (scan drops/recursos, intents de ejecución, movement intents). | 0.5s base por lane, con sub-intervalos por NPC vía LOD interno. | **Combate/pathing/hostilidad** (NPC runtime principal). | `MIGRADO_A_CADENCE` | **P0** |
| 5 | `scripts/world/BanditGroupIntel.gd::tick` (`bandit_group_scan_slice` + `_scan_accumulator_by_group`) | Escaneo social por grupo y disparo de extorsión/raids/probes con cooldowns. | Lane `bandit_group_scan_slice` (8.0 / `GROUP_SCAN_SLICE_COUNT`), sin fallback local de scheduling; si falta inyección emite warning y no ejecuta scan. | **Hostilidad + raids** (decisión de intents). | `MIGRADO_A_CADENCE` | **P0** |
| 6 | `scripts/world/RaidFlow.gd::_tick_jobs` (`wall_assault_next_at`) | Ciclo de jobs de raid y dispatch periódico contra walls/placeables. | Ventanas 2.5s (wall probe) / 6.0s (wall assault) + jitter por grupo. | **Raids + combate estructural**. | `MIGRAR_A_CADENCE` | **P0** |
| 7 | `scripts/world/ExtortionFlow.gd::_tick_scheduled_callbacks` / `_schedule_callback` | Cola local de callbacks diferidos consumida por pulso Cadence del director (sin countdown local por `delta`). | Trigger por `director_pulse`; ejecución por `run_at` (`RunClock.now()`). | **Hostilidad + combate** (warning strike/retaliation). | `MANTENER_LOCAL_BY_DESIGN` | **P1** |
| 8 | `scripts/world/NpcPathService.gd::get_next_waypoint` | Repath interval cacheado por agente. | Default 1.5s, chase override 0.5s. | **Pathing** y respuesta de persecución. | `DUDOSO_REVISAR` | **P0** |
| 9 | `scripts/components/AIComponent.gd::physics_tick` (`_lod_timer`, `_warmup_tick_timer`) | Cadencia LOD de IA de combate y warmup ticks mínimos. | 0.2s (mid), 0.5–1.0s (far), warmup 0.10–0.20s. | **Combate + pathing local del NPC**. | `DUDOSO_REVISAR` | **P0** |
| 10 | `scripts/components/AIComponent.gd::_schedule_sleep_check` (`create_timer`) | Timer recurrente para sleep/wake hysteresis por actor. | `owner_entity.SLEEP_CHECK_INTERVAL` (mín 0.05s), reprogramado en callback. | **Combate/pathing** (activa o duerme IA). | `MIGRAR_A_CADENCE` | **P0** |
| 11 | `scripts/world/NpcSimulator.gd::_tick_lite_mode` / `_tick_data_only` | Loops de simulación por distancia (lite/data-only spawn/despawn). | `lite_check_interval` 0.25s, `sim_check_interval` 0.25s (default). | **Pathing + carga de NPCs + continuidad de combate**. | `DUDOSO_REVISAR` | **P0** |
| 12 | `scripts/world/SettlementIntel.gd::process` | Rescans de workbench/bases por dirty flag y pulsos dedicados de Cadence (sin fallback timer local). | 30s workbench, 10s base vía lanes dedicadas + eventos dirty. | Territorialidad y señales de interés (impacto indirecto en hostilidad/raids). | `MIGRADO_A_CADENCE` | P1 |
| 13 | `scripts/systems/WorldTime.gd::_process` + `day_passed` | Reloj calendárico (día/noche) y evento de día. | 1 día cada 900s reales. | **Hostilidad** (decay diario) y progresión sistémica. | `MANTENER_LOCAL_BY_DESIGN` | P1 |
| 14 | `scripts/systems/RunClock.gd::_process` | Reloj monotónico para cooldowns técnicos. | Incremento por frame. | Cooldowns de raids/extorsión/pathing/persistencia. | `MANTENER_LOCAL_BY_DESIGN` | P1 |
| 15 | `scripts/world/world.gd::autosave lane` + `SaveManager.save_world` | Persistencia periódica de estado global. | `autosave_interval` default 120s vía Cadence lane. | **Persistencia** (riesgo alto de pérdida de progreso). | `MANTENER_LOCAL_BY_DESIGN` | **P0** |
| 16 | `scripts/items/item_drop.gd` (`MagnetDelay` + `create_timer(120)`) | Delay de imán y autodespawn de drops. | Delay de magnet local + limpieza a 120s. | UX/limpieza de entidad pickup; bajo impacto sistémico. | `MANTENER_LOCAL_BY_DESIGN` | P2 |
| 17 | `scripts/components/VFXComponent.gd` (`create_timer`) | Delays visuales de slash y cleanup de partículas. | 0.06s y `lifetime + 0.1`. | Solo presentación visual. | `MANTENER_LOCAL_BY_DESIGN` | P3 |

## Timers prioritarios (combate, hostilidad, raids, pathing, persistencia)

### Prioridad P0 inmediata
1. `BanditGroupIntel` scan scheduler (intents de extorsión/raid/probe).
2. `RaidFlow` dispatch scheduling (`wall_assault_next_at`, jitter y ventanas).
3. `AIComponent` sleep-check recurrente por `create_timer`.
4. `NpcPathService` repath interval ownership.
5. `world.gd` autosave lane (verificar SLA de persistencia y catch-up).

### Prioridad P1
- `WorldTime`/`RunClock` hardening de contrato temporal (sin migración, pero con guardrails de drift/load).

### Prioridad P2+
- Timers locales de drops/VFX/UI, mantener con etiqueta explícita `LOCAL_TIMER_BY_DESIGN` cuando aplique.

## Backlog de migración ordenado por riesgo + impacto

1. **Pathing/AI wake scheduling (P0 crítico)**  
   - Definir ownership único para repath interval y sleep-check de IA.  
   - Riesgo actual: latencias inconsistentes por actor + reprogramación local recursiva.

2. **Settlement cadence hardening (P1 medio)**
   - Mantener escaneos de settlement gobernados por lanes dedicadas + señales dirty.
   - Riesgo actual: regressions de wiring en harness sin world completo.

3. **Hardening de persistencia temporal (P1 medio/alto)**  
   - Verificar política de autosave bajo frame drops/catch-up y coherencia con RunClock/WorldTime en load.  
   - Riesgo actual: pérdida de progreso o drift en cooldowns tras restore.

4. **Documentación y etiquetado de excepciones locales (P2/P3)**  
   - Añadir/normalizar `LOCAL_TIMER_BY_DESIGN` en timers visuales y limpieza efímera.  
   - Riesgo actual: deuda de governance, no de gameplay autoritativo.

## Migraciones ejecutadas (corte 2026-04-01)

### A) `BanditBehaviorLayer` directors (`director_pulse`)
- **Antes:** doble scheduling para directors (Cadence + fallback local de 0.12s dentro de `_process`).
- **Después:** consumo único desde `WorldCadenceCoordinator` (`director_pulse`); fallback local eliminado.
- **Motivo:** quitar dual-path temporal en flujo de extorsión/raid y evitar drift entre escenas.
- **Riesgos mitigados:** disparos duplicados/desfasados de directors, divergencia entre runtime de producción y harness de pruebas.

### B) `BanditGroupIntel` social scan slices
- **Antes:** timer local `_scan_timer` gobernaba el “cuándo” del scan por slices.
- **Después:** lane dedicada `bandit_group_scan_slice` en Cadence gobierna el pulso global del scanner.
- **Estado actual:** sin fallback local de scheduling; ante wiring incompleto se registra warning explícito.
- **Motivo:** centralizar ownership temporal del scanner social de alto impacto (intents de raid/extorsión).
- **Riesgos mitigados:** competencia de relojes paralelos, cadence inconsistente al pausar/reanudar mundo, variación difícil de testear.

### C) `ExtortionFlow` callbacks diferidos
- **Antes:** scheduler local por `delta` (`remaining`) dentro del flow.
- **Después:** callbacks diferidos se ejecutan por `run_at` usando `RunClock.now()` y se consumen solo cuando llega `director_pulse`.
- **Motivo:** eliminar timer local recurrente y consolidar el punto de scheduling en Cadence (director world-owned).
- **Riesgos mitigados:** drift por framerate, duplicación de ownership temporal entre flow y runtime world.
