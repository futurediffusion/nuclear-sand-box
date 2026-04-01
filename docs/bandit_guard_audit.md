# Auditoría de guards/checks repetidos (9 archivos)

## Alcance

Archivos revisados:
1. `scripts/world/BanditBehaviorLayer.gd`
2. `scripts/world/ExtortionFlow.gd`
3. `scripts/world/BanditRaidDirector.gd`
4. `scripts/world/BanditExtortionDirector.gd`
5. `scripts/world/ExtortionUIAdapter.gd`
6. `scripts/world/BanditTerritoryResponse.gd`
7. `scripts/world/BanditIntentPolicy.gd`
8. `scripts/world/NpcWorldBehavior.gd`
9. `scripts/world/ExtortionJob.gd`

---

## 1) Condiciones repetidas detectadas

### A. Guard de validez de nodos (`node == null` / `is_instance_valid`)
- Se repite transversalmente en `ExtortionFlow`, `BanditBehaviorLayer`, `BanditRaidDirector`, `BanditExtortionDirector`, `BanditTerritoryResponse` y `NpcWorldBehavior`.
- Patrones equivalentes:
  - `if _player == null or not is_instance_valid(_player): return`
  - `if enemy == null or not is_instance_valid(enemy): return`
  - `if _flow != null: ...` vs `if _flow != null and is_instance_valid(_flow): ...`

### B. Guard de elegibilidad de NPC runtime
- Check replicado varias veces en `BanditBehaviorLayer`:
  - `node == null or not node.has_method("is_world_behavior_eligible") or not node.is_world_behavior_eligible()`
- Aparece en loops de physics, tick y debug-scout.

### C. Guard de fase de extorsión (estado de `ExtortionJob`)
- En `ExtortionFlow` hay múltiples bloques con combinaciones similares:
  - `job == null or job.is_finished()`
  - `job.is_aggressive()` / `job.needs_warning_strike()` / `job.is_collecting()`
  - `job.can_open_choice()`
- Estas mismas semánticas dependen de queries en `ExtortionJob`.

### D. Guard de recursos UI/modal
- En `ExtortionUIAdapter` y `ExtortionFlow`:
  - disponibilidad del manager (`_bubble_manager == null`)
  - callables válidos (`_show_choice_ui.is_valid()`, `_close_choice_ui.is_valid()`)
  - razón/modal vigente (`reason != "extortion_choice"`, `gid == ""`).

### E. Guard de cooldown/timing
- `BanditTerritoryResponse`, `BanditBehaviorLayer` y `BanditIntentPolicy` tienen checks de timing/cooldown paralelos:
  - `now - last < cooldown`
  - `RunClock.now() < until`
  - `internal_cooldown <= 0.0`.

---

## 2) Flags/booleans de contexto que sugieren parche incremental

### Claros (intención relativamente explícita)
- `raid_ready` (`BanditIntentPolicy`): puerta para activar acciones ofensivas.
- `state_ok` (`BanditBehaviorLayer` idle chat): filtro de estados permitidos.
- `from_selection` (`ExtortionUIAdapter`): diferencia cierre intencional vs descarte externo.

### Ambiguos o acumulativos (riesgo de deuda semántica)
- `_closing_from_selection` (`ExtortionUIAdapter`): booleano temporal mutable que codifica origen de evento; sensible a reentrancia/orden de señales.
- `was_hit` (`ExtortionFlow` retaliación post-pago): booleano acumulado por loop, mezcla detección + decisión de release.
- `is_minimum` (`ExtortionFlow`): nombre poco soberano (¿mínimo de pago? ¿mínimo de UI?); hoy deriva de una heurística local (`player_gold_pre * 0.2 < 1`).
- `state_ok` (`BanditBehaviorLayer`): genérico; no expresa dominio (idle social vs tactical idle).
- `carrying` (`NpcWorldBehavior`): correcto localmente, pero su semántica cambia reglas de path/arrival/cooldown y puede crecer en alcance.

### “Feature flags” de capacidad con solapamiento
- `can_extort_now`, `can_light_raid_now`, `can_full_raid_now`, `can_wall_probe_now` (`BanditIntentPolicy`): buenos como salida de policy, pero son acumulativos y dependen de exclusiones mutuas distribuidas.

---

## 3) Duplicados agrupados por intención funcional

### Hostilidad / postura social
- Fuente principal: `BanditIntentPolicy` (`next_intent`, thresholds, hysteresis).
- Consumo distribuido en `BanditBehaviorLayer` (`hunting/alerted` para burbujas, movimiento debug) y `ExtortionFlow` (transiciones a aggro/warn).

### Timing / cadencia / cooldown
- `BanditBehaviorLayer`: cooldown de reconocimiento/idle chat.
- `BanditTerritoryResponse`: cooldown de reacción territorial.
- `BanditIntentPolicy`: readiness de raid por `internal_cooldown`.
- `ExtortionFlow`: scheduler local (`_scheduled_callbacks`) + delays de re-enable AI.

### Permisos/eligibilidad de actor (runtime safety)
- `node valid`, `is_world_behavior_eligible`, `is_instance_valid`, `has_method`.
- Mismo objetivo (evitar operar sobre nodos inválidos) repetido con variantes locales.

### Estado de raid/extorsión
- `BanditIntentPolicy` decide “si puede iniciar” (can_*).
- `BanditRaidDirector`/`BanditExtortionDirector` enrutan a flows.
- `ExtortionFlow` decide “en qué fase está” (`ExtortionJob` phase queries).

### UI/UX modal de extorsión
- `ExtortionFlow` decide cuándo abrir/cerrar.
- `ExtortionUIAdapter` decide cómo distinguir cierre por selección vs descarte.

---

## 4) Contradicciones potenciales por divergencia de checks

1. **`_flow != null` sin `is_instance_valid` en directores**
   - `BanditRaidDirector` y `BanditExtortionDirector` usan guards de nulidad para invocar `_flow.process...`, pero en `setup` sí se usa `is_instance_valid` al liberar.
   - Potencial: asimetría de criterio de validez entre setup y runtime.

2. **Player validity inconsistente (`null` vs `is_instance_valid`)**
   - En `ExtortionFlow.apply_movement` se exige `null + is_instance_valid`; en `BanditBehaviorLayer._maybe_show_recognition_bubble` solo `null`; en `_maybe_show_idle_chat` sí se usa ambos.
   - Potencial: ramas que asumen `_player` vivo sin el mismo nivel de garantía.

3. **Elegibilidad de nodo repetida en varios bucles con pequeñas variantes**
   - Misma intención, diferentes lugares (`_physics_process`, `_tick_behaviors`, debug scout).
   - Potencial: un ajuste de criterio en un lugar y olvido en otro (deriva comportamental).

4. **Cooldowns paralelos no normalizados**
   - `RunClock.now() < until` vs `now - last < cooldown` vs `internal_cooldown <= 0.0`.
   - Potencial: semánticas equivalentes expresadas distinto, dificultando auditoría y telemetría uniforme.

5. **Fase de extorsión repartida entre múltiples guards ad-hoc**
   - `is_finished`, `is_collecting`, `can_open_choice`, `is_aggressive` se consultan en varios bloques.
   - Potencial: transición nueva en `ExtortionJob` que no quede reflejada homogéneamente en todos los callers.

---

## 5) Propuesta de consolidación (policy/helper + dueño soberano)

### Grupo A — Validez/eligibilidad de nodos runtime
- **Helper propuesto:** `BanditRuntimeGuards.gd`
  - `is_live_node(node: Node) -> bool`
  - `is_world_behavior_eligible_node(node: Node) -> bool`
  - `is_live_player(player: Node2D) -> bool`
- **Dueño soberano:** `BanditBehaviorLayer` (infra runtime de NPCs activos).

### Grupo B — Estado de encounter extorsión
- **Helper propuesto:** extender `ExtortionJob` con queries de alto nivel:
  - `is_terminal()`, `is_ui_openable()`, `requires_scripted_movement()`, `blocks_choice_reopen()`
- **Dueño soberano:** `ExtortionFlow` (orquestación de encuentro), con `ExtortionJob` como modelo de estado autorizado.

### Grupo C — Cooldowns y ventanas temporales
- **Helper/policy propuesto:** `BanditCooldownPolicy.gd`
  - `ready_at(now, until)` / `is_on_cooldown(now, last, duration)` / `consume_pulse(...)`
- **Dueño soberano:** `BanditIntentPolicy` para readiness social; `BanditBehaviorLayer` para cooldowns de runtime/UI diegética.
- **Nota:** mantener `ExtortionFlow` scheduler local, pero delegar cálculo de readiness a policy común.

### Grupo D — Capacidades ofensivas (can_extort/can_raid...)
- **Policy propuesto:** mantener y ampliar `BanditIntentPolicy.evaluate()` como única fuente de verdad de permisos de acción.
- **Dueño soberano:** `BanditIntentPolicy`.
- **Acción:** prohibir recrear lógica `can_*` fuera de esta policy; consumidores solo leen snapshot.

### Grupo E — Cierre modal / causa de resolución UI
- **Helper propuesto:** `ExtortionUiSessionState` (objeto pequeño o enum explícito en adapter)
  - Reemplazar `_closing_from_selection` bool por estado explícito (`NONE`, `SELECTION`, `EXTERNAL_DISMISS`).
- **Dueño soberano:** `ExtortionUIAdapter`.

---

## Plan de implementación incremental sugerido

1. Extraer `is_world_behavior_eligible_node` y reemplazar 3-4 puntos de uso en `BanditBehaviorLayer`.
2. Introducir 2 queries compuestas en `ExtortionJob` y migrar guards repetidos en `ExtortionFlow`.
3. Normalizar checks de player live (`null + is_instance_valid`) en capa world.
4. Introducir policy de cooldown mínima (sin mover scheduler de extorsión en primera iteración).
5. Endurecer directores para usar el mismo criterio de validez de `_flow` en setup y process.

