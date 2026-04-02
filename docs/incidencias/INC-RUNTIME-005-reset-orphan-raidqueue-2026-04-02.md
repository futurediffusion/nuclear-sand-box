# INC-RUNTIME-005 — RaidQueue huérfana tras `new_game`/reset runtime

## Prioridad
- **P0** (afecta continuidad canónica de pipeline de raid tras reset)

## Fecha
- 2026-04-02 (UTC)

## Hallazgo
Durante revisión del flujo de reset (`SaveManager.new_game()` → `RuntimeResetCoordinator.reset_new_game()`),
la cola de raids (`RaidQueue`) no se limpiaba. Esto dejaba intents y memoria temporal
(`_intents`, `_last_raid_time_by_group`, `_last_wall_probe_time_by_group`, `_run_summary`) vivos después de reset.

## Impacto
- Riesgo de **estado huérfano** post-reset.
- Posible re-disparo o gating inconsistente de raids/extorsión al iniciar partida nueva.
- Riesgo de inestabilidad en `structure_assault` / wall-hit pipeline por arrastre de estado previo.

## Corrección aplicada
1. `RuntimeResetCoordinator.reset_new_game()` ahora ejecuta `RaidQueue.reset()` en el tramo de limpieza canónica.
2. `RaidQueue` expone `reset()` como alias explícito de `clear_all()` para contrato consistente con otros autoloads.

## Validación disponible en este entorno
- Se validó el wiring de código y la consistencia del contrato de reset.
- **Bloqueo de runtime**: no fue posible ejecutar validación in-game/headless porque el binario `godot` no está disponible en el entorno actual.

## Estado de cierre
- **No cerrar gate runtime aún**.
- Pendiente correr validación runtime completa (new game/reset + hostility/raids/extortion/loot/settlement rescans/cadence/save-load)
en un entorno con Godot instalado.
