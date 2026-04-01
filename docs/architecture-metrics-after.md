# Medición arquitectónica (DESPUÉS de primeros cortes)

Fecha de medición: 2026-04-01.

Contexto: corte posterior a primeras intervenciones reales (Phase 7 Cut 1, Cut 2 y Cut 3).

## Resultado por KPI

| KPI | Antes | Después | Reducción | ¿Cumple mínimo? |
|---|---:|---:|---:|---|
| Duplicaciones conceptuales activas (pipeline de asalto) | 2 | 0 | 100% | ✅ Sí (>=30%) |
| Clases en lista roja (2+ reglas rotas) | 3 | 3 | 0% | ❌ No (>=20%) |
| Dependencias a autoload por módulo crítico (promedio Top 4) | 9.75 | 9.50 | 2.56% | ❌ No (>=15%) |
| Timers de gameplay crítico fuera de cadence | 6 | 4 | 33.33% | ✅ Sí (>=25%) |
| Conflictos `DOUBLE_TRUTH` P0 | 1 | 0 | 100% | ✅ Sí (P0=100%) |

## Detalle de medición DESPUÉS

### 1) Duplicaciones conceptuales activas

- En el scope del asalto bandido (Cut 2):
  - Tipos de re-decisión detectados: 2
  - Tipos eliminados: 2
  - Activos en la ruta principal: 0

### 2) Clases en lista roja

- Se mantiene en **3** clases con 2+ reglas rotas (con excepción temporal y plan activo).

### 3) Dependencias a autoload por módulo crítico

Medición actual (working tree) con conteo automático contra `[autoload]` de `project.godot`:

| Módulo | Baseline | Después |
|---|---:|---:|
| `scripts/systems/SaveManager.gd` | 13 | 14 |
| `scripts/world/world.gd` | 13 | 14 |
| `scripts/world/BanditGroupIntel.gd` | 7 | 7 |
| `scripts/world/BanditBehaviorLayer.gd` | 6 | 3 |

- Promedio baseline: `(13+13+7+6)/4 = 9.75`
- Promedio después: `(14+14+7+3)/4 = 9.50`

### 4) Timers locales vs cadence

- Casos críticos fuera de cadence:
  - Antes: 6
  - Después: 4
- Migraciones ejecutadas en los primeros cortes:
  - `director_pulse` en `BanditBehaviorLayer` a cadence.
  - `bandit_group_scan_slice` en `BanditGroupIntel` a cadence.

### 5) Conflictos de doble verdad

- `DOUBLE_TRUTH` P0 (hostilidad de facción) pasa de **1 -> 0** (resuelto).

---

## Lectura ejecutiva

- **KPIs cumplidos:** 3/5.
- **Mejoras fuertes:** deduplicación de decisión de asalto, migración de timers críticos a cadence, cierre de `DOUBLE_TRUTH` P0.
- **Brechas pendientes:** reducción real de lista roja y desacople a autoload en `SaveManager`/`world.gd`.

## Próximo gate recomendado

No cerrar la iteración de remediación global hasta cumplir ambos:

1. Lista roja <= 2 clases (o reducción >=20% sostenida).
2. Reducción >=15% en dependencias a autoload promedio de módulos críticos.
