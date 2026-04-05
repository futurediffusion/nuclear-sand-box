# Sandbox Contract

## Fase 1: Freeze de `world.gd`

A partir de esta fase, `scripts/world/world.gd` queda en **freeze funcional**.

### Reglas explícitas

1. `world.gd` solo puede contener:
   - composición de dependencias,
   - bootstrap/inicialización,
   - tick principal,
   - wiring entre sistemas,
   - puentes con APIs de Godot.
2. Queda prohibido agregar lógica de dominio nueva en `world.gd` (por ejemplo: raids, reactions, territory, AI intent logic, policy social, scoring, sanciones, etc.).
3. Toda lógica nueva debe vivir en un módulo/sistema dedicado (servicio, layer, policy, coordinator, monitor, etc.) y entrar por interfaz pública.

### Ejemplos (permitido / no permitido)

- ✅ **Permitido**: extender wiring/arranque en `_ready()` para registrar un sistema nuevo y conectarlo por señales o puertos.
- ❌ **No permitido**: agregar dentro de `_ready()` reglas de negocio para decidir prioridad de raids o evaluación de hostilidad.

- ✅ **Permitido**: mantener `_process(delta)` como orquestador de ticks (`_cadence`, colas, refresh, autosave).
- ❌ **No permitido**: implementar dentro de `_process(delta)` una máquina de decisiones de IA o scoring táctico de grupos.

- ✅ **Permitido**: que `_on_placement_completed(...)` actúe como puente y delegue a un sistema especializado.
- ❌ **No permitido**: incorporar en `_on_placement_completed(...)` heurísticas nuevas de reacción territorial o selección de escuadras.

- ✅ **Permitido**: exponer hooks/fachada como `record_interest_event(...)` o `report_tavern_incident(...)` que delegan en módulos.
- ❌ **No permitido**: mover lógica de cálculo/validación de incidentes o intención de facción directamente a `world.gd`.

- ✅ **Permitido**: funciones de adaptación a Godot como `_notification(...)`, `_unhandled_input(...)`, conversión tile/world, y acceso a nodos.
- ❌ **No permitido**: acoplar en esos handlers reglas nuevas de dominio (territory control, AI intent planning, reactions).

### Criterio de aceptación para PRs

Si un cambio agrega o modifica reglas de dominio, el PR debe demostrar:

- módulo nuevo o extensión de módulo existente fuera de `world.gd`, y
- integración en `world.gd` limitada a composición/wiring/puente por interfaz.

## Fase 2: `GameplayCommandDispatcher` como puerta de comandos

Archivo: `scripts/runtime/world/GameplayCommandDispatcher.gd`.

`world.gd` mantiene la API pública para gameplay, pero **solo delega** al dispatcher.
El dispatcher centraliza el contrato de enrutamiento de comandos y deriva cada caso
al sistema especializado que corresponde.

### Comandos que deben pasar por este punto

- **Player walls**
  - `can_place_player_wall_at_tile`
  - `place_player_wall_at_tile`
  - `damage_player_wall_from_contact`
  - `damage_player_wall_near_world_pos`
  - `damage_player_wall_at_world_pos`
  - `damage_player_wall_in_circle`
  - `hit_wall_at_world_pos`
  - `damage_player_wall_at_tile`
  - `remove_player_wall_at_tile`
  - **Ruta**: `world.gd` → `GameplayCommandDispatcher` → `PlayerWallSystem`.

- **Settlement / territory write commands**
  - `record_interest_event`
  - `rescan_workbench_markers`
  - `mark_interest_scan_dirty`
  - **Ruta**: `world.gd` → `GameplayCommandDispatcher` → `SettlementIntel` / `WorldTerritoryPolicy`
    + side effects operativos (`drop compaction hotspot`, `player_territory_dirty`) vía callbacks inyectados.

- **Autoridad local (incidentes de taberna)**
  - `report_tavern_incident`
  - **Ruta**: `world.gd` → `GameplayCommandDispatcher` →
    `TavernAuthorityPolicy.evaluate()` → `TavernLocalMemory.record()` → `TavernSanctionDirector.dispatch()`.

### Regla explícita de frontera

Si se agrega un comando gameplay nuevo, el primer punto de entrada en `world.gd`
debe ser una delegación al dispatcher. Las decisiones de dominio y validaciones de
outcome van en módulos/sistemas, no en `world.gd`.
