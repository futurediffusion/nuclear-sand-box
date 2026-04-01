# BanditWorkCoordinator — auditoría de responsabilidades activas

Fecha: 2026-04-01.

## 1) Responsabilidades activas detectadas

### Coordinación/orquestación (legítimo en coordinator)
- Encadenar post-behavior runtime (`process_post_behavior`) y fan-out a mining/assault/loot/deposit.
- Mantener estado de ejecución por miembro para la corrida de raid:
  - stage actual (`engage` → `breach` → `loot` → `retreat` → `closed`),
  - timestamps runtime de cooldown (`_raid_attack_next_at`, `_raid_loot_next_at`, `_raid_breach_resolved_at`),
  - resultado terminal (`success`/`abort`/`retreat`).
- Ejecutar side-effects del mundo ya decididos por policy/behavior:
  - aplicar `hit` sobre placeables,
  - invocar daño de pared (`hit_wall_at_world_pos`/legacy fallback),
  - ordenar `force_return_home`,
  - aplicar feedback a behavior.

### Decisión de dominio (no debería vivir en coordinator)
- Reglas semánticas de **retreat por razón de denegación** (ataque/loot).
- Selección del **container raidable** más apropiado en raid (búsqueda de candidatos, filtros semánticos de lootabilidad y prioridad por distancia).

## 2) Clasificación (coordinación legítima vs dominio)

| Área | Estado previo | Owner correcto | Acción aplicada |
|---|---|---|---|
| Stage machine + transiciones | En coordinator | Coordinator | Se mantiene en coordinator (es orquestación pura). |
| Cooldowns runtime por miembro | En coordinator | Coordinator | Se mantiene en coordinator (estado efímero de ejecución). |
| Retreat on deny reasons | En coordinator | Policy | Extraído a `BanditRaidRuntimePolicy.should_retreat_on_*`. |
| Selección de container raidable | En coordinator | Policy/behavior runtime policy | Extraído a `BanditRaidRuntimePolicy.find_nearest_raidable_container` + validación. |
| Ejecución de hits/loot/deposit | En coordinator + stash/world APIs | Coordinator + systems ejecutores | Se mantiene (ejecución, no decisión semántica). |

## 3) Extracciones realizadas

Se introdujo owner explícito:
- `scripts/world/BanditRaidRuntimePolicy.gd`
  - `should_retreat_on_attack_deny(reason)`
  - `should_retreat_on_loot_deny(reason)`
  - `find_nearest_raidable_container(...)`
  - `is_valid_raid_container(container)`

Y `BanditWorkCoordinator` ahora consume esa policy en lugar de decidir localmente.

## 4) Resultado estructural

`BanditWorkCoordinator` queda centrado en:
- orquestación de comandos runtime,
- transición de etapas de raid,
- ejecución de interacciones concretas del mundo/sistemas (world + stash),
- cierre y limpieza de corrida.

Sin decidir semántica de priorización de objetivos de loot ni reglas de retreat por razones de negocio.

## 5) Verificación de cierre

Checklist final:
- [x] Reglas críticas de retreat por denegación tienen owner explícito (`BanditRaidRuntimePolicy`).
- [x] Selección semántica de container raidable tiene owner explícito (`BanditRaidRuntimePolicy`).
- [x] Coordinator conserva solo orquestación/stage machine + ejecución de efectos.
- [x] No quedaron decisiones semánticas críticas nuevas embebidas en coordinator fuera de su owner.
