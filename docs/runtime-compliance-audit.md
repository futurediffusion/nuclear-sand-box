# Runtime Compliance Audit

Fecha: 2026-04-01  
Base: fases previas (`runtime-red-list`, inventarios de autoload/estado) + verificación en código runtime actual.

## 1) Alcance y reglas del pacto usadas

Reglas del pacto runtime auditadas:
- **R1** Comportamiento decide intención.
- **R2** Coordinación ejecuta interacción con mundo (no redefine intención/negocio).
- **R3** Persistencia no decide gameplay.
- **R4** Debug/telemetry observa, no gobierna.
- **R5** Cadence decide cuándo corre algo, no su semántica.
- **R6** Spatial index responde consultas, no define verdad semántica.

Referencias normativas: `docs/runtime-architecture-pact.md`.

## 2) Mapeo de archivos críticos vs reglas del pacto

| Archivo crítico | Capa esperada | R1 | R2 | R3 | R4 | R5 | R6 | Estado |
|---|---|---:|---:|---:|---:|---:|---:|---|
| `scripts/systems/SaveManager.gd` | Persistencia | ⚠️ | ⚠️ | ❌ | ✅ | ⚠️ | ✅ | **No cumple** |
| `scripts/world/world.gd` | Coordinación/fachada | ❌ | ❌ | ✅ | ⚠️ | ✅ | ✅ | **No cumple** |
| `scripts/world/BanditGroupIntel.gd` | Behavior | ⚠️ | ❌ | ✅ | ✅ | ⚠️ | ✅ | **No cumple** |
| `scripts/world/SettlementIntel.gd` | Runtime derivado/intel | ✅ | ✅ | ✅ | ✅ | ✅ | ⚠️ | **Riesgo activo** |
| `scripts/systems/Debug.gd` + consumidores | Debug/telemetry | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | **No cumple** |

Leyenda: ❌ violación activa, ⚠️ frontera difusa/riesgo material, ✅ sin evidencia activa en este corte.

## 3) Violaciones activas por tipo

## A. MULTI-OWNER (múltiples owners de decisión semántica)

### A1) Reacción a placement decide intención en dos capas
- **Archivo/método 1:** `scripts/world/world.gd::_trigger_placement_react`.
- **Archivo/método 2:** `scripts/world/BanditGroupIntel.gd::_scan_group` + `_maybe_enqueue_*`.
- **Evidencia:** ambos escriben `BanditGroupMemory.update_intent(..., "raiding"/...)` y ambos emiten `issue_execution_intent(...)` sobre el mismo dominio social.
- **Regla rota:** **R1** (owner de intención) y **R2** (coordinación reintroduciendo semántica).
- **Severidad:** **Alta** (inconsistencias de prioridad y race de intención).

## B. LÓGICA DE GAMEPLAY EN AUTOLOAD

### B1) SaveManager reinicia y gobierna sistemas de gameplay
- **Archivo/método:** `scripts/systems/SaveManager.gd::new_game`.
- **Evidencia:** ejecuta reset de `FactionSystem`, `SiteSystem`, `NpcProfileSystem`, `BanditGroupMemory`, `ExtortionQueue`, `RunClock`, `WorldTime`, `FactionHostilityManager` y limpia runtime de `PlacementSystem`.
- **Regla rota:** **R3** (persistencia no decide gameplay) y deriva sobre **R2** por orquestación transversal desde autoload de persistencia.
- **Severidad:** **Crítica**.

### B2) Debug autoload expone flags que alteran gameplay
- **Archivo/módulo:** `scripts/systems/Debug.gd` + `scripts/systems/CommandSystem.gd::_cmd_ghost`.
- **Evidencia:** `Debug.ghost_mode` es mutable en runtime vía comando y su propósito declarado impacta visibilidad/daño del player.
- **Regla rota:** **R4**.
- **Severidad:** **Alta** (si se fuga a runtime productivo o tests acoplados).

## C. PERSISTENCIA DECIDIENDO GAMEPLAY

### C1) SaveManager mezcla serialización con snapshot operativo de mundo
- **Archivo/método:** `scripts/systems/SaveManager.gd::save_world`.
- **Evidencia:** llama `entity_coordinator.snapshot_entities_to_world_save()` antes de serializar.
- **Regla rota:** **R3** y frontera con **R2**.
- **Severidad:** **Alta**.

### C2) SaveManager centraliza restauración de relojes semánticos globales
- **Archivo/método:** `scripts/systems/SaveManager.gd::load_world_save`.
- **Evidencia:** restaura en el mismo flujo `RunClock` y `WorldTime`.
- **Regla rota:** **R5** (acoplamiento temporal-semántico desde persistencia).
- **Severidad:** **Media-Alta**.

## D. CACHE/ÍNDICE COMO VERDAD

### D1) SettlementIntel usa índice derivado para detectar semántica social
- **Archivo/método:** `scripts/world/SettlementIntel.gd::_scan_workbenches`, `_collect_candidate_doors`.
- **Evidencia:** prioriza `WorldSpatialIndex.get_all_placeables_by_item_id(...)` y `get_placeables_by_item_ids_near(...)` para inferir señales semánticas (base/workbench) con fallback a `WorldSave`.
- **Regla rota:** **R6** (riesgo de cache-as-truth).
- **Severidad:** **Alta** por efecto en raids/extorsión.

## E. DEBUG MUTANDO ESTADO

### E1) Ghost mode cambia estado operativo
- **Archivo/método:** `scripts/systems/CommandSystem.gd::_cmd_ghost`.
- **Evidencia:** cambia `Debug.ghost_mode` on/off en runtime.
- **Regla rota:** **R4**.
- **Severidad:** **Alta**.

## 4) Registro de evidencia consolidado

| ID | Tipo | Archivo | Método/sector | Regla rota | Severidad | Evidencia resumida |
|---|---|---|---|---|---|---|
| V-001 | multi-owner | `scripts/world/world.gd` | `_trigger_placement_react` | R1, R2 | Alta | Fuerza `raiding`, lock e `issue_execution_intent` desde coordinación global. |
| V-002 | multi-owner | `scripts/world/BanditGroupIntel.gd` | `_scan_group`, `_maybe_enqueue_*` | R1, R2 | Alta | Decide intención y además encola ejecución/colas de raid/extorsión. |
| V-003 | lógica en autoload | `scripts/systems/SaveManager.gd` | `new_game` | R3 | Crítica | Resetea múltiples subsistemas gameplay/sociales. |
| V-004 | persistencia decide gameplay | `scripts/systems/SaveManager.gd` | `save_world` | R3, R2 | Alta | Mezcla snapshot operativo de entidades con serialización persistente. |
| V-005 | persistencia/tiempo semántico | `scripts/systems/SaveManager.gd` | `load_world_save` | R5 | Media-Alta | Restaura `RunClock` + `WorldTime` en un solo owner de persistencia. |
| V-006 | cache como verdad | `scripts/world/SettlementIntel.gd` | `_scan_workbenches`, `_collect_candidate_doors` | R6 | Alta | Índice derivado guía inferencia semántica de base/workbench. |
| V-007 | debug mutando estado | `scripts/systems/Debug.gd`, `scripts/systems/CommandSystem.gd` | `ghost_mode`, `_cmd_ghost` | R4 | Alta | Debug flags y comando alteran estado efectivo de gameplay. |

## 5) Backlog único priorizado (orden de ejecución)

## P0 (bloqueantes de soberanía)
1. **Separar SaveManager de resets gameplay**  
   - Extraer `NewGameRuntimeResetService` (owner coordinación/runtime) y dejar `SaveManager` solo como adapter de IO/snapshot persistente.  
   - Cierra: V-003.
2. **Eliminar decisión de intención en `world.gd` placement react**  
   - `world.gd` emite evento estructurado; `BanditGroupIntel`/policy decide intención.  
   - Cierra: V-001 (y reduce V-002).

## P1 (frontera behavior/coordination y cache-as-truth)
3. **Partir `BanditGroupIntel` en DecisionService + IntentDispatchPort**  
   - `BanditGroupIntel` retorna decisión declarativa (intent + reason + cooldown metadata); encolado real en director/coordinator.  
   - Cierra: V-002.
4. **Blindaje de `SettlementIntel` contra staleness de índice**  
   - Verificación de revisión/UID contra `WorldSave` en paths críticos (door/workbench) antes de concluir semántica.  
   - Cierra: V-006.

## P2 (debug governance)
5. **Encapsular `ghost_mode` fuera de runtime productivo**  
   - Gate fuerte por build/profile + canal de tooling separado y no enlazado a decisiones de combate/daño en producción.  
   - Cierra: V-007.

## P3 (hardening temporal)
6. **Contrato temporal explícito por dominio (`RunClock` vs `WorldTime`)**  
   - Persistencia recibe/entrega snapshot temporal por adapter de dominio, no decide mezcla temporal.  
   - Cierra: V-005 y reduce regresiones de cooldown.
7. **Mover snapshot de entidades fuera de `SaveManager.save_world()`**  
   - Coordinación prepara snapshot; SaveManager solo serializa payload ya consolidado.  
   - Cierra: V-004.

## 6) Criterio de cierre de auditoría

La auditoría se considera cerrada cuando:
- No haya violaciones **Críticas/Altas** activas en V-001..V-007.
- `SaveManager` quede limitado a serialización/deserialización + integridad de snapshot.
- Ningún flujo debug cambie estado de gameplay en runtime productivo.
- Toda inferencia semántica de `SettlementIntel` tenga guardas contra cache stale.
