# Baseline de métricas arquitectónicas (ANTES)

Fecha de baseline: 2026-04-01.

Objetivo: fijar KPIs mínimos antes de los primeros cortes reales de remediación (Cut 1/2/3) para poder medir reducción real de deuda arquitectónica.

## KPIs mínimos definidos

| KPI | Definición operativa | Unidad |
|---|---|---|
| Duplicaciones conceptuales activas | Casos abiertos donde la misma decisión de negocio vive en más de un owner. | # casos |
| Clases en lista roja | Clases con 2+ reglas del pacto runtime rotas. | # clases |
| Dependencias a autoload por módulo | # de autoloads distintos referenciados por módulo crítico. | # autoloads/módulo |
| Timers locales vs cadence | # timers/schedulers de gameplay crítico aún fuera de `WorldCadenceCoordinator`. | # casos |
| Conflictos de doble verdad | # conflictos `DOUBLE_TRUTH` abiertos en estado crítico de datos. | # conflictos |

## Snapshot ANTES (pre-cortes)

> Este baseline usa los valores de referencia declarados en los documentos de diagnóstico inicial de cada frente.

### 1) Duplicaciones conceptuales activas

- Total de casos activos en dominios críticos: **7** (Casos A..G).

### 2) Clases en lista roja

- Clases con 2+ reglas rotas: **3**
  - `SaveManager`
  - `world.gd`
  - `BanditGroupIntel`

### 3) Dependencias a autoload por módulo crítico (baseline de hotspots)

| Módulo | Baseline autoloads |
|---|---:|
| `scripts/systems/SaveManager.gd` | 13 |
| `scripts/world/world.gd` | 13 |
| `scripts/world/BanditGroupIntel.gd` | 7 |
| `scripts/world/BanditBehaviorLayer.gd` | 6 |

### 4) Timers de gameplay crítico fuera de cadence

- Casos críticos aún fuera de cadence (pendientes): **6**
  - `RaidFlow`
  - `ExtortionFlow`
  - `AIComponent::_schedule_sleep_check`
  - `SettlementIntel` (fallback)
  - `BanditBehaviorLayer` directors (pre-migración)
  - `BanditGroupIntel` social scan (pre-migración)

### 5) Conflictos de doble verdad abiertos

- Conflictos `DOUBLE_TRUTH` P0 abiertos: **1**
  - Hostilidad de facción en dos servicios.

---

## Criterio de éxito mínimo (reducción esperada por KPI)

| KPI | Reducción mínima exigida |
|---|---:|
| Duplicaciones conceptuales activas | **>= 30%** |
| Clases en lista roja | **>= 20%** |
| Dependencias a autoload por módulo crítico | **>= 15%** (promedio Top 4) |
| Timers de gameplay crítico fuera de cadence | **>= 25%** |
| Conflictos de doble verdad | **>= 50%** (y **100%** en P0) |

## Fórmula estándar de reducción

`reducción (%) = ((antes - después) / antes) * 100`
