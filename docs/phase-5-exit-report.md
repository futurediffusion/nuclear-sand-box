# Phase 5 — Exit Report

Fecha de corte: 2026-04-01.  
Baseline de comparación: `docs/runtime-red-list.md` (snapshot inicial de fase 5) + `docs/runtime-layer-matrix.md`.

## 1) Verificación de clases en `runtime-red-list.md`

Resultado del gate solicitado:

- ✅ `scripts/systems/SaveManager.gd`: mantiene plan de corrección activo (Epic P1) y excepción temporal aprobada `EXC-RUNTIME-001`.
- ✅ `scripts/world/world.gd`: mantiene plan de corrección activo (Epic C1) y excepción temporal aprobada `EXC-RUNTIME-002`.
- ✅ `scripts/world/BanditGroupIntel.gd`: mantiene plan de corrección activo (Epic B1) y excepción temporal aprobada `EXC-RUNTIME-003`.

Conclusión: **toda clase en lista roja tiene plan de corrección o refactor parcial ejecutado**.

## 2) Confirmación de clases con 2+ reglas sin excepción

- Clases con 2+ reglas rotas detectadas: **3**.
- Clases con excepción temporal aprobada: **3**.
- Clases con 2+ reglas rotas sin excepción aprobada: **0**.

✅ Cumple condición de salida operativa para fase 5.

## 3) Métricas solicitadas

### 3.1 Violaciones por capa (snapshot actual)

| Capa | Violaciones activas |
|---|---:|
| Persistence | 3 |
| Coordination | 3 |
| Behavior | 2 |
| Cadence | 2 |
| SpatialIndex | 0 |
| Debug/Telemetry | 0 |

Notas:
- Un mismo hallazgo puede impactar más de una capa por cruce de fronteras (ej. `BanditGroupIntel` afecta Behavior+Coordination).
- La métrica refleja violaciones activas de clases auditadas en lista roja.

### 3.2 Clases en lista roja (antes/después)

| Métrica | Antes (inicio fase 5) | Después (cierre fase 5) |
|---|---:|---:|
| Clases en lista roja (2+ reglas) | 3 | 3 |
| Clases en lista roja sin plan | 3 | 0 |
| Clases en lista roja sin excepción aprobada | 3 | 0 |

Interpretación:
- El número de clases en rojo aún no baja, pero se cerró el gap de gobernanza: ahora todas tienen plan + excepción temporal aprobada.

### 3.3 Reglas con mayor recurrencia de incumplimiento

| Regla | Recurrencia | Clases afectadas |
|---|---:|---|
| R-Co2 (frontera Coordination) | 3 | `SaveManager`, `world.gd`, `BanditGroupIntel` |
| R-C5 (frontera Cadence/semántica) | 2 | `SaveManager`, `BanditGroupIntel` |
| R-B1 (owner de intención en Behavior) | 2 | `world.gd`, `BanditGroupIntel` |
| R-P3 (Persistence no decide gameplay) | 1 | `SaveManager` |

## 4) Check de revisión en PRs contra `runtime-layer-matrix.md`

Se establece check obligatorio de arquitectura en PR template:

- Confirmar revisión explícita de fronteras por capa usando `docs/runtime-layer-matrix.md`.
- Confirmar si el cambio introduce violaciones nuevas o excepciones.
- Bloquear merge si el PR no declara capa responsable y regla del pacto que respeta.

Implementación: `.github/PULL_REQUEST_TEMPLATE.md`.

## 5) Gate para nuevas features

A partir de este reporte, una feature nueva solo se habilita si en PR declara:

1. **Capa responsable** (Behavior/Coordination/Persistence/Debug-Telemetry/Cadence/SpatialIndex).
2. **Regla del pacto que respeta** (`docs/runtime-architecture-pact.md`).
3. **Evidencia de verificación** contra `docs/runtime-layer-matrix.md`.

Si falta cualquiera de estos tres campos, el cambio queda en estado **No Ready** para merge.
