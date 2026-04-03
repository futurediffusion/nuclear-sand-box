# Baseline fijo de métricas de `BanditBehaviorLayer`

Este baseline define una referencia estable para comparar fases futuras del loop de bandidos.

## Ventana de muestreo

- Ventana temporal fija: **5s** (`METRICS_WINDOW_SECONDS`).
- Fuente: log `perf_telemetry` con prefijo `BanditBehaviorMetrics`.
- Snapshot runtime disponible también en `BanditBehaviorLayer.get_lod_debug_snapshot()` bajo:
  - `behavior_metrics_window`
  - `behavior_metrics_baselines`

## Métricas esperadas por ventana

- Costos separados:
  - `cost_ms.ally_separation_total`
  - `cost_ms.behavior_tick_total`
  - `cost_ms.physics_process_total`
- Contadores:
  - `scan_by_group`
  - `scan_by_npc`
  - `workers_active_avg`
  - `followers_without_task_avg`
  - `assignment_conflicts_total`

## Baselines de referencia (fijos)

> Registrar estos 3 snapshots en sesiones controladas y mantenerlos como referencia inmutable para regresiones.

| Escala | Label sugerido | Escenario | Estado |
|---|---|---|---|
| Pequeña | `small` | Campamento mínimo + 1 grupo activo | Pendiente de captura |
| Mediana | `medium` | Campamento + interacción regular con recursos | Pendiente de captura |
| Grande | `large` | Escena con múltiples grupos y drops simultáneos | Pendiente de captura |

## Procedimiento recomendado de captura

1. Correr escena objetivo y estabilizar simulación 20-30s.
2. Tomar al menos 3 ventanas de 5s por escala.
3. Guardar baseline con `save_perf_baseline_snapshot("small"|"medium"|"large")`.
4. Exportar el payload JSON de log `baseline_saved` a documento/versionado de perf.
5. Comparar futuras fases contra ese baseline fijo (misma escala, misma ventana).
