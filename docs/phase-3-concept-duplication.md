# Phase 3 — Duplicación conceptual por dominio crítico

## Objetivo
Mapear **dónde se decide hoy** cada regla en los dominios críticos y registrar conflictos de soberanía/duplicación que pueden explicar comportamientos raros en runtime.

---

## 1) Mapa rápido: dónde se calcula cada decisión hoy

### Combate
- **LOS/bloqueo por paredes para melee**: `CombatQuery.has_wall_between`, `is_melee_target_blocked_by_wall`, `find_first_wall_hit`, `shape_overlaps_wall`.
- **Selección de target de daño y aplicación por swing**: `slash.gd::_try_damage`, `_is_target_blocked_by_wall`, `_try_damage_player_walls_prioritized`, `_damage_wall_at_world_pos`.
- **Daño real a walls**: fachada `world.gd::hit_wall_at_world_pos` -> `PlayerWallSystem.damage_wall_at_world_pos` y derivados.

### Raids / extortion
- **Intent policy (qué puede pasar)**: `BanditIntentPolicy.evaluate` (`next_intent`, `can_extort_now`, `can_light_raid_now`, `can_full_raid_now`, `can_wall_probe_now`).
- **Enqueue/gates de coerción (si pasa ahora)**: `BanditGroupIntel._maybe_enqueue_extortion/_raid/_light_raid/_wall_probe`.
- **Consumo y ejecución runtime**:
  - Extorsión: `ExtortionFlow.process_flow` (`_abort_invalid_jobs`, `_consume_extortion_queue`, `_check_retaliation`).
  - Raid: `RaidFlow.process_flow` (`_consume_raid_queue`, `_tick_jobs`, `_abort_invalid_jobs`).
- **Trabajo táctico durante asalto**: `BanditWorkCoordinator._handle_structure_assault` (ataque, fallback local, loot de contenedores).

### Walls
- **Validez de colocación**: `PlayerWallSystem.can_place_player_wall_at_tile`.
- **Resolución de tile impactado**: `WallTileResolver` + heurísticas en `PlayerWallSystem` (`damage_player_wall_from_contact`, `damage_player_wall_at_world_pos`, `damage_wall_at_world_pos`).
- **Propiedad/persistencia de wall**: `WallPersistence` y `StructuralWallPersistence`.
- **Bloqueo de línea por tiles** (combat/path style): `world.gd::_has_wall_tile_between/_tile_line_has_wall` (inyectado vía `WorldSave.wall_tile_blocker_fn`) y `CombatQuery` (ray/shape fallback).

### Drops / cargos
- **Spawn y límites globales de drops**: `LootSystem.spawn_drop` (`MAX_ITEM_DROPS`, scatter/física).
- **Ciclo runtime del drop**: `item_drop.gd` (lifetime, pickup, fade/cleanup).
- **Decisión de recoger/depositar cargo NPC**:
  - intención local: `NpcWorldBehavior` (`LOOT_APPROACH`, `RETURN_HOME`, `pending_collect_id`, timeout de retorno);
  - ejecución efectiva: `BanditWorkCoordinator._handle_collection_and_deposit` + `BanditCampStashSystem`.

### Cooldowns
- **Readiness social**: `BanditIntentPolicy` (`internal_cooldown <= 0`).
- **Cooldowns de enqueue por cola**: `BanditGroupIntel` + `ExtortionQueue.get_last_request_time` + `RaidQueue.get_last_raid_time/get_last_wall_probe_time`.
- **Cooldowns de ejecución runtime**:
  - `BanditWorkCoordinator` (`_raid_attack_next_at`, `_raid_loot_next_at`),
  - `BanditTerritoryResponse` (`_territory_react_cooldown`),
  - `BanditBehaviorLayer` (recognition/idle chat cooldowns).

### Intención AI
- **Intención social grupal**: `BanditIntentPolicy` + `BanditGroupIntel` + `BanditGroupMemory.update_intent`.
- **Intención táctica/operativa de NPC**: `NpcWorldBehavior.state`, `BanditWorkCoordinator` (fallbacks/ataques/loot), `AIComponent`/`BanditBehaviorLayer` para señales de combate y dispatch.

---

## 2) Casos de duplicación conceptual (formato solicitado)

### Caso A (P0)
- **Decisión:** ¿El grupo puede iniciar coerción ahora (extorsión/raid/probe)?
- **Sistema A:** `BanditIntentPolicy.evaluate` define `can_extort_now/can_*_raid_now/can_wall_probe_now` usando thresholds + `internal_cooldown`.
- **Sistema B/C:** `BanditGroupIntel._maybe_enqueue_*` vuelve a gatear con `has_pending`, `RunClock.now()-last_time`, factores de riqueza/compliance/chance.
- **Diferencia observable:** un grupo sale “ready” en policy pero no encola nada por gates secundarios; o encola tarde respecto a intención visible.
- **Riesgo:** desincronía intención vs acción, difícil debug de “por qué no actuaron si estaban hunting/raiding-ready”.

### Caso B (P0)
- **Decisión:** ¿Un job activo de extorsión/raid sigue siendo válido o se aborta/finaliza?
- **Sistema A:** `ExtortionFlow._abort_invalid_jobs/_get_abort_reason` (grupo, líder, composición, distancia, fuerza de intent).
- **Sistema B/C:** `RaidFlow._abort_invalid_jobs/_tick_attacking/_structure_assault_finish_reason` (timeouts, líder, grupo, no-target grace) y `BanditWorkCoordinator` fallbacks locales.
- **Diferencia observable:** extorsión puede abortar por “stronger intent” mientras raid paralelo sigue o viceversa; cierres con reglas temporales distintas.
- **Riesgo:** correcciones tardías y loops de entrar/salir de estados (job churn), con comportamiento errático entre sistemas.

### Caso C (P0)
- **Decisión:** ¿Qué pared recibe daño en un swing y cómo se resuelve player vs structural?
- **Sistema A:** `slash.gd` decide candidatos, mezcla con hits no-wall, y llama `hit_wall_at_world_pos` (o legacy `damage_player_wall_at_world_pos`).
- **Sistema B/C:** `PlayerWallSystem.damage_wall_at_world_pos` resuelve prioridad player/structural por distancia a bounds + flags `allow_structural_feedback`; `WallTileResolver` aporta heurísticas distintas según vía (contact, nearest, circle).
- **Diferencia observable:** mismo hit visual puede dañar distinta pared según ruta (raycast/sampler/contact), especialmente cerca de paredes superpuestas o bordes.
- **Riesgo:** dobles validaciones + resultados no deterministas percibidos (“pegué aquí y rompió otra pared”).

### Caso D (P1)
- **Decisión:** ¿Una entidad está bloqueada por wall para combate melee?
- **Sistema A:** `CombatQuery.has_wall_between` usa `WorldSave.wall_tile_blocker_fn` (línea en tile grid).
- **Sistema B/C:** `CombatQuery.find_first_wall_hit/shape_overlaps_wall` usa físicas (ray/shape), y `slash.gd` además aplica su propio pipeline de prioridad de wall-hit.
- **Diferencia observable:** tile-line puede bloquear aunque ray no impacte collider (o al revés) según geometría/collider cache.
- **Riesgo:** desincronía visual-física: golpes que “no deberían entrar” sí entran, o ataques bloqueados sin feedback claro.

### Caso E (P1)
- **Decisión:** ¿Qué objetivo estructural ataca un bandido en raid (wall/placeable/container)?
- **Sistema A:** `RaidFlow._resolve_structure_target` prioriza storage/placeable/workbench/wall y despacha grupo.
- **Sistema B/C:** `BanditWorkCoordinator._resolve_structure_attack_target` vuelve a resolver target local (placeable vs wall por distancia), con fallback local wall strike y loot de contenedor.
- **Diferencia observable:** director despacha a un tipo de objetivo pero NPC individual pega a otro al llegar (retarget local).
- **Riesgo:** movimientos “nerviosos” o zig-zag, reasignaciones frecuentes, pérdida de coherencia táctica.

### Caso F (P1)
- **Decisión:** ¿Cuándo priorizar loot/deposit vs seguir agresión/asalto?
- **Sistema A:** `NpcWorldBehavior` decide transiciones locales (`LOOT_APPROACH`, `RETURN_HOME`, timeouts, `cargo_count`).
- **Sistema B/C:** `BanditWorkCoordinator` fuerza decisiones por contexto (`_maybe_drop_carry_on_aggro`, `structure no-target -> return home with cargo`) y stash policy.
- **Diferencia observable:** NPC alterna entre atacar y volver al barril según quién “gane” el tick actual.
- **Riesgo:** jitter de estados, retrasos en depósito, pérdida de DPS de raid o drops abandonados.

### Caso G (P2)
- **Decisión:** semántica de cola e historial temporal por grupo.
- **Sistema A:** `ExtortionQueue` persiste intents + `last_request_time_by_group`.
- **Sistema B/C:** `RaidQueue` no persiste, pero mantiene `last_raid_time` y `last_wall_probe_time` runtime-only; ambos replican APIs (`has_pending`, `consume_for_group`).
- **Diferencia observable:** tras save/load, extorsión puede respetar historial y raid “olvidarlo”.
- **Riesgo:** comportamiento post-carga inconsistente (picos de coerción inesperados).

---

## 3) Priorización de conflictos que explican rarezas runtime

### Prioridad P0 (impacto alto + visible)
1. **Gates duplicados de intención social** (Caso A).
2. **Abort/finalización repartidos entre flows** (Caso B).
3. **Resolución de wall hit en múltiples rutas** (Caso C).

### Prioridad P1 (impacto medio-alto)
4. **Bloqueo de combate por wall con modelos distintos tile/física** (Caso D).
5. **Selección de target de asalto duplicada director vs ejecutor local** (Caso E).
6. **Arbitraje loot/cargo vs agresión en dos capas** (Caso F).

### Prioridad P2 (impacto acumulativo / post-load)
7. **Semántica de colas no homogénea extortion vs raid** (Caso G).

---

## 4) Señales concretas a vigilar en runtime

- **Desincronías:** `current_group_intent` cambia a `raiding/extorting`, pero no aparece job consumido en el flow correspondiente durante varias ventanas de tick.
- **Correcciones tardías:** jobs que nacen y abortan repetidamente por condiciones revalidadas en otra capa.
- **Dobles validaciones:** misma acción (hit wall / dispatch target) pasa por 2+ resolutores con criterios no equivalentes.
- **Post-load drift:** diferencias de cadencia entre extorsión y raid después de cargar partida.

---

## 5) Conclusión ejecutiva
La mayor fuente de riesgo no es la duplicación de líneas, sino la **duplicación de intención de negocio**: readiness, validez de job, selección de objetivo y arbitraje de prioridad (ataque vs loot/cargo) están decididos en más de una capa. Esto explica síntomas típicos de runtime: comportamiento aparentemente contradictorio, correcciones tardías y validaciones redundantes.
