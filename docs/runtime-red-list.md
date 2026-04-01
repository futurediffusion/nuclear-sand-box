# Runtime Red List (violaciones 2+ reglas)

Fecha: 2026-04-01  
Base de evaluación: `docs/runtime-layer-matrix.md` + `docs/runtime-architecture-pact.md`

## 1) Clases críticas revisadas y cumplimiento

> Criterio de criticidad: módulos núcleo de runtime ya identificados como hotspots de acoplamiento/orquestación (persistencia, world orchestration, decisión social bandit, coordinación bandit, cadence, spatial index).

| Clase / módulo | Capa esperada | Reglas rotas | Estado | Plan / refactor | Excepción aprobada |
|---|---|---:|---|---|---|
| `scripts/systems/SaveManager.gd` | Persistence | **3** | 🔴 Lista roja | Plan de corrección definido en `docs/phase-5-exit-report.md` (Epic P1 + hito de segregación por adapters) | `EXC-RUNTIME-001` |
| `scripts/world/world.gd` | Coordination (fachada global) | **2** | 🔴 Lista roja | Plan de corrección definido en `docs/phase-5-exit-report.md` (Epic C1 + reducción de globals) | `EXC-RUNTIME-002` |
| `scripts/world/BanditGroupIntel.gd` | Behavior (decisión semántica) | **2** | 🔴 Lista roja | Plan de corrección definido en `docs/phase-5-exit-report.md` (Epic B1 + separación intent/enqueue) | `EXC-RUNTIME-003` |
| `scripts/world/BanditBehaviorLayer.gd` | Coordination | 1 | 🟡 Vigilar | Refactor parcial ya ejecutado en fase 4 (reducción de globals) | N/A |
| `scripts/world/WorldSpatialIndex.gd` | SpatialIndex | 0 | 🟢 Cumple | Sin acción requerida | N/A |
| `scripts/world/WorldCadenceCoordinator.gd` | Cadence | 0 | 🟢 Cumple | Sin acción requerida | N/A |

## 2) Conteo por clase (0, 1, 2, 3+)

- **0 reglas rotas:** 2 clases (`WorldSpatialIndex`, `WorldCadenceCoordinator`).
- **1 regla rota:** 1 clase (`BanditBehaviorLayer`).
- **2 reglas rotas:** 2 clases (`world.gd`, `BanditGroupIntel`).
- **3+ reglas rotas:** 1 clase (`SaveManager`).

---

## 3) Lista roja (2+ reglas) con evidencia concreta

## P1 — `scripts/systems/SaveManager.gd` (3 reglas)  
**Riesgo operativo: MUY ALTO** (efecto cascada de reset/load, acoplamiento transversal, bugs de estado canónico).

### Regla rota R-P3: Persistence no decide gameplay
- **Método/evidencia:** `new_game()` llama `PlacementSystem.clear_runtime_instances()`, `FactionSystem.reset()`, `SiteSystem.reset()`, `NpcProfileSystem.reset()`, `BanditGroupMemory.reset()`, `ExtortionQueue.reset()`, `FactionHostilityManager.reset()`, y además `seed(new_seed)`.
- **Responsabilidad indebida:** no solo serializa/restaura; también gobierna reinicio de sistemas de gameplay y estado social runtime.
- **Impacto:** un cambio en flujo de guardado puede romper lógica de facciones/hostilidad/extorsión en cascada (desincronización entre owners de dominio).

### Regla rota R-C5: Cadence no debe mezclar semántica de negocio
- **Método/evidencia:** `save_world()` y `load_world_save()` persisten/restauran simultáneamente dos relojes globales (`RunClock` y `WorldTime`) desde el mismo owner.
- **Responsabilidad indebida:** el adapter de persistencia toma decisiones implícitas sobre temporalidad canónica multi-dominio sin contrato de ownership temporal por dominio.
- **Impacto:** deriva temporal (cooldowns/coerción/sistemas técnicos) y bugs intermitentes por usar reloj incorrecto tras load.

### Regla rota R-Co2: Coordination ejecuta; Persistence no debe orquestar runtime
- **Método/evidencia:** `save_world()` realiza snapshot activo vía `_world.entity_coordinator.snapshot_entities_to_world_save()` antes de serializar.
- **Responsabilidad indebida:** mezcla pipeline de coordinación/runtime con adapter de persistencia.
- **Impacto:** side effects previos a save pueden cambiar orden/consistencia del snapshot según estado de escena, elevando riesgo de corrupción lógica “save-dependent”.

---

## P2 — `scripts/world/world.gd` (2 reglas)  
**Riesgo operativo: ALTO** (nodo central, alto acoplamiento, radio de impacto amplio).

### Regla rota R-B1: Behavior decide intención
- **Método/evidencia:** en `_on_placement_completed(...)` se ejecuta decisión semántica directa: `BanditGroupMemory.update_intent(gid, "raiding")`, locks (`set_placement_react_lock`), y emisión de intención de ejecución (`issue_execution_intent`).
- **Responsabilidad indebida:** la fachada de coordinación/world decide intención social/táctica que debería vivir en capa Behavior/Policy.
- **Impacto:** múltiples owners de intención (world + behavior) → conflictos de prioridad y bugs difíciles de reproducir.

### Regla rota R-Co2: Coordination no debe introducir reglas de negocio ocultas
- **Método/evidencia:** mismo flujo `_on_placement_completed(...)` filtra hostilidad (`_is_faction_hostile_for_structure_assault`) y define política operativa de reacción (`_PLACEMENT_REACT_*`, enqueue a `RaidQueue`).
- **Responsabilidad indebida:** reglas de coerción quedan embebidas en orquestación técnica del world loop.
- **Impacto:** fuerte acoplamiento entre placement, memoria de grupos y raids; cambios locales generan efecto cascada en AI social.

---

## P3 — `scripts/world/BanditGroupIntel.gd` (2 reglas)  
**Riesgo operativo: ALTO** (núcleo de coerción social, frecuencia alta, gating disperso).

### Regla rota R-B1/R-Co2 (frontera Behavior↔Coordination difusa)
- **Método/evidencia:** `_maybe_enqueue_extortion`, `_maybe_enqueue_raid`, `_maybe_enqueue_light_raid`, `_maybe_enqueue_wall_probe` no solo deciden intención: también encolan (`RaidQueue`/`ExtortionQueue`) y fuerzan transición (`BanditGroupMemory.update_intent(... "raiding"/"extorting")`).
- **Responsabilidad indebida:** módulo de comportamiento asume parte de ejecución operacional de colas/directores.
- **Impacto:** duplicación de gating con directores/capas de coordinación; rechazo/reintento puede desalinear intención vs ejecución real.

### Regla rota R-C5: Cadence no define semántica
- **Método/evidencia:** `_get_cooldown_remaining(...)` y decisiones de enqueue dependen de `RunClock.now()` para resolver elegibilidad semántica de coerción.
- **Responsabilidad indebida:** la semántica de política queda atada a reloj técnico concreto (sin contrato explícito de dominio temporal).
- **Impacto:** cambios de reloj/sincronía alteran outcomes de gameplay (raid/extorsión) sin tocar la policy declarada.

---

## 4) Priorización final por riesgo operativo

1. **`SaveManager` (P1, muy alto):** toca persistencia + reset de múltiples sistemas + tiempo global; cualquier bug impacta carga/partida completa.
2. **`world.gd` (P2, alto):** concentración de decisiones de coerción en nodo más acoplado del runtime; alto efecto cascada.
3. **`BanditGroupIntel` (P3, alto):** mezcla decisión+ejecución en flujo crítico de hostilidad/raids/extorsión; alta probabilidad de inconsistencias por rechazo/retry.

## 5) Gate de cumplimiento (fase 5)

- ✅ Cada clase en lista roja tiene **plan de corrección explícito** o refactor ejecutado.
- ✅ No hay clases con 2+ reglas rotas sin excepción temporal aprobada.
- ✅ Excepciones temporales registradas en `docs/incidencias/INC-TECH-003-runtime-layer-excepciones-fase-5.md`.
