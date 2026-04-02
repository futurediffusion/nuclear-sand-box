# Bandit Worker Fix Plan (fases + gates)

## Objetivo general
Restaurar el ciclo worker bandido sin **big rewrite**, con ejecución incremental por fases, gates claros y rollback local por fase.

## Principios de ejecución
- Cambios pequeños y verificables (1 fase por PR/commit lógico).
- No tocar raids/assault fuera de los puntos mínimos necesarios para transición worker (`cargo -> return_home -> deposit`).
- Cada fase cierra con evidencia medible en logs/telemetría.
- Si una fase falla su gate, se revierte **solo esa fase** y no el plan completo.

## Evidencia mínima transversal (todas las fases)
- Log estructurado por worker y etapa (`worker_id`, `group_id`, `phase`, `event`, `reason`, `tick`).
- Escena/escenario de prueba repetible con múltiples NPCs (mínimo 5 workers simultáneos).
- KPI de ciclo completo por worker: `acquire -> drop -> pickup -> cargo -> return_home -> deposit -> resume`.

---

## Fase 1 — Resource index visible correcto

**Objetivo**
- Garantizar que nodos de recurso y/o drops sean visibles en el índice consultado por workers en la misma ventana temporal esperada.

**Archivos (scope esperado)**
- `scripts/world/*` (registro/indexado espacial de recursos/drops).
- `scripts/components/AIComponent.gd` (lectura de índice para acquire/targeting).
- `docs/smoke_test.md` (pasos de verificación manual si aplica).

**Cambio esperado**
- El alta/baja de recursos en índice ocurre en orden determinista (spawn/register/unregister).
- Se elimina ventana donde el worker busca y el recurso existe en mundo pero no en índice.

**Gate / Criterio de done**
- En 3 corridas consecutivas con múltiples NPCs, `acquire_resource` encuentra candidato válido dentro del SLA definido (por ejemplo <= N ticks) en >= 95% de intentos.
- Sin aumento de errores de target inválido por ID.

**Métrica**
- `resource_index_visibility_latency_ms` (p50/p95).
- `acquire_success_rate` por worker y agregado.

**Rollback (solo fase 1)**
- Feature flag o revert del bloque de registro/indexado introducido en fase 1.
- Mantener instrumentación agregada (si no rompe comportamiento) para diagnóstico posterior.

---

## Fase 2 — Drop query por miembro

**Objetivo**
- Asegurar que la búsqueda de drop se haga con contexto del miembro worker correcto (posición real y ownership lógico), no con proxy ambiguo.

**Archivos (scope esperado)**
- `scripts/components/AIComponent.gd` (query de drops/pickup intent).
- `scripts/world/*` (servicio de query espacial si aplica).
- `scripts/tests/*` (test de regresión para query por miembro).

**Cambio esperado**
- Query de drop parametrizada por `worker_id/member_id` + `global_position` real.
- Motivos de descarte explícitos (`out_of_range`, `reserved_by_other`, `invalid_node`, etc.).

**Gate / Criterio de done**
- Ratio `hit_resource -> drop_candidate` estable y reproducible (sin oscilaciones anómalas) en escenario de múltiples NPCs.
- Reducción de colisiones de dos workers persiguiendo el mismo drop fuera de política.

**Métrica**
- `drop_query_hit_rate`.
- `drop_contention_rate` (conflictos por drop).
- `drop_query_reject_reason_count`.

**Rollback (solo fase 2)**
- Revert de la función de query por miembro a comportamiento previo.
- Conservación de logs de razones de descarte para comparar before/after.

---

## Fase 3 — Pickup → cargo

**Objetivo**
- Confirmar transición atómica de pickup exitoso a estado de cargo cargado.

**Archivos (scope esperado)**
- `scripts/components/CarryComponent.gd`.
- `scripts/items/item_drop.gd`.
- `scripts/components/AIComponent.gd` (estado worker tras pickup).

**Cambio esperado**
- Si pickup exitoso: `cargo_count > 0` y estado worker pasa a rama de retorno sin quedar en limbo.
- Si pickup falla: razón tipificada y reintento controlado (sin loop roto).

**Gate / Criterio de done**
- En múltiples NPCs, >= 95% de pickups exitosos terminan en `cargo_loaded` dentro de <= N ticks.
- Casos fallidos quedan clasificados con reason codes, sin pérdida silenciosa.

**Métrica**
- `pickup_to_cargo_success_rate`.
- `pickup_to_cargo_latency_ticks`.
- `pickup_fail_reason_count`.

**Rollback (solo fase 3)**
- Revert de transición pickup→cargo y restaurar flujo previo de pickup.
- Mantener contadores de reason codes para soporte de fase 4.

---

## Fase 4 — Cargo → return_home

**Objetivo**
- Priorizar consistentemente retorno a base cuando existe cargo, minimizando interferencia de intents no-worker.

**Archivos (scope esperado)**
- `scripts/components/AIComponent.gd` (árbitro de prioridades de estado).
- `scripts/world/BanditGroupIntel.gd` (solo hooks mínimos si afecta transición worker).

**Cambio esperado**
- Con cargo presente, el worker toma/retiene `return_home` con prioridad suficiente hasta llegar a zona de depósito.
- Se evita oscilación entre estados incompatibles con cargo.

**Gate / Criterio de done**
- En prueba con múltiples NPCs y carga activa, >= 95% alcanzan home/deposit sin desviarse a loops de combate/patrulla no permitidos por policy.

**Métrica**
- `cargo_return_home_start_rate`.
- `cargo_return_home_arrival_rate`.
- `state_oscillation_with_cargo_count`.

**Rollback (solo fase 4)**
- Revert de reglas de prioridad para `return_home` añadidas en esta fase.
- Preservar trazas de oscilación para fase 5.

---

## Fase 5 — Deposit → cargo=0

**Objetivo**
- Asegurar vaciado efectivo de cargo al depositar y cierre limpio del ciclo logístico.

**Archivos (scope esperado)**
- `scripts/components/CarryComponent.gd` (release/deposit).
- `scripts/components/AIComponent.gd` (confirmación de transición post-deposit).
- `scripts/placeables/ContainerPlaceable.gd` (si hay contrato de depósito).

**Cambio esperado**
- `deposit` exitoso limpia manifiesto/counter (`cargo_count == 0`) y emite evento verificable.
- Si no hay contenedor válido, fallback seguro y reason code explícito.

**Gate / Criterio de done**
- En múltiples NPCs, >= 95% de llegadas a deposit concluyen con `cargo=0` y sin cargo fantasma.

**Métrica**
- `deposit_success_rate`.
- `deposit_to_cargo_zero_latency_ticks`.
- `stuck_cargo_after_deposit_count`.

**Rollback (solo fase 5)**
- Revert de cambios de rutina de deposit y restablecer estrategia previa.
- Mantener watchdog/telemetría de cargo estancado si es no invasivo.

---

## Fase 6 — Resume work

**Objetivo**
- Reanudar el loop productivo tras depositar, cerrando ciclo completo repetible.

**Archivos (scope esperado)**
- `scripts/components/AIComponent.gd` (transición post-deposit a acquire/work).
- `scripts/world/*` (si hay scheduler/cadence específico de workers).
- `scripts/tests/*` (escenario e2e multi-NPC).

**Cambio esperado**
- Tras `cargo=0`, el worker vuelve a `acquire_resource`/work state sin quedar idle permanente.
- El ciclo completo se repite múltiples veces por NPC.

**Gate / Criterio de done**
- Evidencia de ciclos completos repetibles en corrida sostenida (ej. 10+ minutos) con múltiples NPCs.
- Sin degradación significativa de throughput entre ciclo 1 y ciclos posteriores.

**Métrica**
- `full_cycle_completed_count` por worker.
- `full_cycle_per_minute` (agregado y p95 por worker).
- `resume_work_latency_ticks`.

**Rollback (solo fase 6)**
- Revert de transición resume-work introducida en esta fase.
- Mantener contador de ciclos para validar estabilidad al volver al baseline previo.

---

## Checkpoints (sin big rewrite)

1. **Checkpoint A (fin fase 2):** acquire+drop query estables.
2. **Checkpoint B (fin fase 4):** pickup/cargo/return_home sin oscilación crítica.
3. **Checkpoint C (fin fase 6):** ciclo completo repetible multi-NPC validado.

Cada checkpoint exige:
- Diff acotado a la fase.
- Métricas before/after.
- Resultado de smoke/regresión focal.

## Criterio de done global del plan
- Plan ejecutable por fases, con gates y rollback por fase (no global).
- Evidencia medible de ciclos completos repetibles con múltiples NPCs.
- Sin necesidad de reescritura grande del sistema.
