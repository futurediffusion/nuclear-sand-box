# Sprint cierre temporal fallbacks — 2026-04-02

Objetivo del sprint: **cero fallback permanente disfrazado de temporal**.

## 1) Barrido de marcadores temporales (gameplay crítico)

| Prioridad | Área gameplay | Marcador detectado | Archivo | Estado sprint |
|---|---|---|---|---|
| P0 | Daño a walls en asalto | `TEMP EXCEPTION` + `legacy wall damage fallback` | `scripts/world/BanditWorkCoordinator.gd` | **RETIRADO** |
| P0 | Hostilidad/cadena de ownership | `REMOVE_AFTER` en wrapper de hostilidad | `scripts/systems/FactionRelationService.gd` | **VIGENTE (renovado con owner + fecha corta)** |
| P0 | Hostilidad/raids scheduling | Documentación mencionaba fallback local de cadence | `docs/phase-7-time-inventory.md` | **CORREGIDO (sin fallback local)** |

## 2) Priorización por riesgo gameplay

1. **P0 — Walls damage / assault runtime**: si se mantiene dual API (`hit_wall_at_world_pos` + `damage_player_wall_at_world_pos`) se puede bifurcar daño estructural y generar comportamiento no determinista de raid.
2. **P0 — Hostility ownership bridge**: wrapper legacy sin salida explícita puede perpetuar dependencia indirecta y opacar el owner canónico (`FactionHostilityManager`).
3. **P0 — Hostility cooldown/scheduling docs drift**: documentación desactualizada induce a reintroducir fallback local en futuros cambios de cadence.

## 3) Fallbacks retirados en este sprint

- Se elimina el fallback legacy de daño a pared en `BanditWorkCoordinator`.
- El coordinador ahora exige API canónica `hit_wall_at_world_pos` y emite warning explícito cuando falta wiring.

## 4) Excepciones que no se pueden retirar hoy

### EXC-HOSTILITY-WRAPPER-001
- **Motivo técnico estricto:** mantener puente de señal/API legacy de hostilidad para listeners externos aún no migrados.
- **Owner:** `Runtime-Hostility`.
- **Fecha de revisión:** `2026-04-09`.
- **Fecha de retiro comprometida:** `2026-05-15`.
- **Condición de retiro:** migrar listeners restantes a `FactionHostilityManager` y eliminar wrapper.

## 5) Resultado del sprint

- **Agregado vs retirado:** `+1 / -1` (deuda neta: `0`).
- El único marcador temporal restante queda registrado con owner, revisión y fecha de retiro verificable.
