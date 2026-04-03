# Rollout de optimizaciones con feature flags + informe comparativo de snapshots

Fecha: 2026-04-03.

## 1) Feature flags independientes (tareas 1–5)

Las optimizaciones se controlan por setting de `ProjectSettings` (si no existe setting, usa default en `BanditTuning.gd`).

| Tarea | Flag | Default | Objetivo operativo |
|---|---|---:|---|
| 1 | `bandit/rollout_opt_task_1_assault_group_cap` | `true` | Limitar looters concurrentes por grupo en assault para bajar query pressure. |
| 2 | `bandit/rollout_opt_task_2_assault_scavenger_only` | `true` | Restringir pickup de assault a rol scavenger para evitar consultas redundantes de roles de combate. |
| 3 | `bandit/rollout_opt_task_3_assault_rotation` | `true` | Rotar miembros autorizados de pickup en assault para repartir carga y reducir bursts por pulso. |
| 4 | `bandit/rollout_opt_task_4_assault_context_cache` | `true` | Reusar contexto de assault por grupo para recortar costo por NPC en resolución de target/container. |
| 5 | `bandit/rollout_opt_task_5_group_order_cache` | `true` | Cachear órdenes de grupo y reducir recomputes (`group_recompute_total`). |

> Diseño de rollout: cada flag se puede apagar de forma aislada para A/B incremental, rollback selectivo o diagnóstico de regresión.

## 2) Escenarios reproducibles de perfilado

Correr cada escenario con seed fija y misma duración de ventana (mínimo 5 min, ideal 10 min), usando snapshots por ventanas de 5s.

### Escenario A — Wall placement (assault trigger)

1. Iniciar en zona con al menos 1 camp hostil activo.
2. Colocar 8–12 `wallwood` en perímetro corto y mantener presencia en rango de reacción.
3. Esperar activación de assault/raid y sostener 3–5 minutos.
4. Capturar snapshots en:
   - baseline (`flags off` según fase),
   - variante parcial,
   - variante candidata final.

### Escenario B — Romper + lootear + volver

1. Preparar ruta repetible con 2–3 nodos rompibles y drops en área compacta.
2. Ejecutar loop manual: romper -> lootear -> volver al área inicial.
3. Repetir por bloques de 3 minutos (mínimo 2 bloques).
4. Capturar snapshots en el mismo tramo del loop para before/after.

### Escenario C — Alta densidad de NPC

1. Cargar zona con 40–80 NPC activos en simultáneo.
2. Forzar convivencia de trabajo + combate + drops durante al menos 5 min.
3. Registrar picos de loot pressure y eventos de budget.
4. Capturar snapshots de ventana completa + picos.

## 3) Métricas a comparar (existentes + nuevas)

Comparar siempre sobre el mismo escenario, seed, duración y configuración de flags.

- `pickup_queries_per_pulse`
- `average_drop_candidates_per_query`
- `drop_processing_budget_hits`
- `scan_total`
- `workers_active_avg`
- `ally_separation_total_ms`
- `profile_full_ratio`
- `group_cache_hit_ratio`
- `group_recompute_total` (control directo para tarea 5)

## 4) Formato recomendado de informe comparativo

Crear una tabla por escenario con 3 snapshots mínimos: `before`, `candidate`, `recommended`.

| Escenario | Snapshot | Flags (T1..T5) | pickup_queries_per_pulse | avg_drop_candidates | budget_hits | scan_total | workers_active_avg | ally_sep_ms | profile_full_ratio | group_cache_hit_ratio | group_recompute_total |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| A wall placement | before | `00000` |  |  |  |  |  |  |  |  |  |
| A wall placement | candidate | `11100` |  |  |  |  |  |  |  |  |  |
| A wall placement | recommended | `11111` |  |  |  |  |  |  |  |  |  |
| B romper+loot+volver | before | `00000` |  |  |  |  |  |  |  |  |  |
| C alta densidad NPC | before | `00000` |  |  |  |  |  |  |  |  |  |

Notas sugeridas por fila:
- variación % vs baseline,
- observaciones de frame-time en picos,
- side-effects funcionales (si existen).

## 5) Criterios de aceptación

El rollout se acepta cuando se verifica todo lo siguiente:

1. **Reducción significativa de `pickup_queries_per_pulse` en assault**
   - objetivo recomendado: mejora consistente en escenarios A y C (no solo en una ventana aislada).
2. **Caída de `group_recompute_total`**
   - con mejora o estabilidad de `group_cache_hit_ratio`.
3. **Mejora de frame-time estable en picos de loot**
   - caída de `drop_processing_budget_hits` y/o menor severidad de spikes durante escenarios B/C.

## 6) Secuencia de rollout sugerida

1. Activar T1 -> validar A/C.
2. Activar T2 -> validar A/C.
3. Activar T3 -> validar A/B/C (impacta fairness/cadencia de pickup).
4. Activar T4 -> validar A/C (costo assault por NPC).
5. Activar T5 -> validar C + caída de `group_recompute_total`.
6. Probar combinación final candidata (`T1..T5` ON) en corrida extendida (>=10 min).

## 7) Combinación final recomendada y retiro de flags

- Recomendación inicial (si cumple criterios): **`T1=ON, T2=ON, T3=ON, T4=ON, T5=ON`**.
- Si una tarea falla KPI o introduce regresión funcional, mantenerla OFF y documentar excepción en informe.
- Cuando la combinación quede definitiva en producción:
  1. congelar el informe comparativo final,
  2. eliminar flags temporales de esa(s) tarea(s),
  3. dejar comportamiento como default no-condicional,
  4. conservar solo métricas de observabilidad que sigan aportando diagnóstico.

