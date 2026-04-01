# Phase 7 — Cut 1 Exit Report

Fecha de corte: 2026-04-01.

Documento base de este cierre:
- `docs/phase-7-time-inventory.md`
- `docs/phase-7-cut1-time-scheduling.md`

## 1) Publicación del corte

Se publica el presente reporte de salida para el **primer corte vertical de Phase 7** con evidencia de:

1. métricas mínimas de inventario/migración;
2. validación de timers locales activos (motivo + revisión);
3. verificación de cumplimiento de regla Cadence para scheduling de gameplay recurrente;
4. shortlist priorizada para el segundo corte vertical.

## 2) Métricas mínimas del corte

### Snapshot de clasificación (inventario total)

| Métrica | Valor |
|---|---:|
| Timers/puntos de scheduling inventariados | 17 |
| Marcados como `MIGRADO_A_CADENCE` | 2 |
| Marcados como `MIGRAR_A_CADENCE` (pendiente) | 4 |
| Marcados como `MANTENER_LOCAL_BY_DESIGN` | 7 |
| Marcados como `DUDOSO_REVISAR` | 4 |

### Conteo operativo solicitado

| Métrica mínima solicitada | Valor | Criterio aplicado |
|---|---:|---|
| Timers totales inventariados | 17 | Total de filas del inventario de Phase 7 |
| Migrados a Cadence | 2 | Casos ya migrados y operativos sobre lane Cadence |
| Locales permitidos | 7 | Casos clasificados como `MANTENER_LOCAL_BY_DESIGN` |
| Casos dudosos | 4 | Casos clasificados como `DUDOSO_REVISAR` |

## 3) Confirmación de timers locales activos (motivo explícito + revisión programada)

Criterio obligatorio de fase: timer local solo con excepción explícita, motivo y fecha de revisión.

### 3.1 Timers locales permitidos por diseño (activos)

| Timer local activo | Motivo explícito | Categoría | Revisión programada |
|---|---|---|---|
| `world.gd` lanes/consumo Cadence + autosave orchestration | Núcleo de orquestación temporal global del mundo; no es timer gameplay “paralelo”, es el runtime owner de Cadence | `MANTENER_LOCAL_BY_DESIGN` | 2026-04-15 |
| `WorldTime.gd` (`day_passed`) | Reloj calendárico sistémico (día/noche) con contrato de dominio | `MANTENER_LOCAL_BY_DESIGN` | 2026-04-15 |
| `RunClock.gd` monotónico | Base de cooldown técnico transversal (lectura de tiempo monotónico) | `MANTENER_LOCAL_BY_DESIGN` | 2026-04-15 |
| `item_drop.gd` (`MagnetDelay` + autodespawn) | UX y limpieza efímera de pickups, sin ownership de gameplay autoritativo global | `LOCAL_TIMER_BY_DESIGN` | 2026-04-15 |
| `VFXComponent.gd` (`create_timer`) | Delays puramente visuales (slash/cleanup de partículas) | `LOCAL_TIMER_BY_DESIGN` | 2026-04-15 |

### 3.2 Timers locales activos **no permitidos como estado final** (con seguimiento explícito)

| Timer local activo | Estado | Motivo explícito de permanencia temporal | Revisión programada |
|---|---|---|---|
| `BanditBehaviorLayer::_tick_timer` | `DUDOSO_REVISAR` | Tick interno de behavior NPC con acople LOD; pendiente decidir ownership final Cadence vs local encapsulado | 2026-04-08 |
| `RaidFlow::_tick_jobs` (`wall_assault_next_at`) | `MIGRAR_A_CADENCE` | Scheduler de raid distribuido aún local; requiere migración de ventanas/jitter a lanes | 2026-04-08 |
| `ExtortionFlow::_tick_scheduled_callbacks` | `MIGRAR_A_CADENCE` | Scheduler diferido de callbacks de hostilidad/combat aún por delta local | 2026-04-08 |
| `NpcPathService::get_next_waypoint` (repath interval) | `DUDOSO_REVISAR` | Repath cacheado por agente; falta decisión de ownership temporal por lane vs contrato local | 2026-04-08 |
| `AIComponent` (`_lod_timer`, `_warmup_tick_timer`) | `DUDOSO_REVISAR` | Cadencia local de IA por distancia; pendiente definir frontera runtime-vs-actor | 2026-04-08 |
| `AIComponent::_schedule_sleep_check` (`create_timer`) | `MIGRAR_A_CADENCE` | Sleep/wake hysteresis recursiva por actor sin ownership centralizado | 2026-04-08 |
| `NpcSimulator::_tick_lite_mode/_tick_data_only` | `DUDOSO_REVISAR` | Loops de simulación por distancia todavía con control local | 2026-04-08 |
| `SettlementIntel::process` (fallback local) | `MIGRAR_A_CADENCE` | Fallback se mantiene para wiring incompleto; target final = lanes dedicadas únicamente | 2026-04-08 |

**Conclusión de control:** cada timer local activo queda con motivo explícito y fecha de revisión definida en este corte.

## 4) Verificación: no nuevo scheduling de gameplay fuera de Cadence sin excepción

Resultado del gate de corte: **cumple condicionalmente**.

- No se identificó en este corte evidencia de **nuevo scheduling gameplay recurrente** introducido fuera de Cadence sin estar inventariado/clasificado.
- Los timers locales gameplay que persisten están explícitamente catalogados como:
  - `MIGRAR_A_CADENCE` (deuda activa), o
  - `DUDOSO_REVISAR` (ownership en definición),
  con revisión programada en ventana corta (2026-04-08).

### Evidencia operativa usada en verificación

1. Inventario consolidado de scheduling (`phase-7-time-inventory`).
2. Política de corte (`phase-7-cut1-time-scheduling`) con regla Cadence-first + excepciones válidas.
3. Barrido de patrones de scheduling local (`create_timer`, contadores por `delta`, `Timer.new`) para contraste contra inventario.

## 5) Candidatos siguientes para segundo corte vertical (Cut 2)

Ordenado por impacto en combate/hostilidad/raids/pathing:

1. **RaidFlow → lanes Cadence para jobs y ventanas de assault/probe**
   - Objetivo: migrar `_tick_jobs` + `wall_assault_next_at` a ownership Cadence.
2. **ExtortionFlow → scheduler diferido centralizado**
   - Objetivo: remover `_schedule_callback/_tick_scheduled_callbacks` local.
3. **AIComponent sleep-check recurrente**
   - Objetivo: eliminar recursión `create_timer` por actor y gobernar con lane/slot dedicado.
4. **NpcPathService repath governance**
   - Objetivo: definir contrato único para repath interval (global cadence o actor policy formal).
5. **NpcSimulator loops (lite/data-only)**
   - Objetivo: consolidar ticks de distancia en Cadence sin degradar rendimiento.
6. **SettlementIntel fallback removal**
   - Objetivo: dejar exclusivamente lanes Cadence para rescans de settlement.
7. **BanditBehaviorLayer `_tick_timer`**
   - Objetivo: resolver ownership final (migrar o justificar `LOCAL_TIMER_BY_DESIGN` acotado).

## 6) Criterio de salida del Cut 1

Cut 1 queda **cerrado** con las siguientes condiciones:

- Inventario temporal completo y clasificado (17/17).
- Dos migraciones efectivas a Cadence ya operativas.
- Excepciones/locales activas con motivo explícito y revisión programada.
- Backlog priorizado y accionable para Cut 2.

Estado final: **READY FOR CUT 2**.
