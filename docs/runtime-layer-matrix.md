# Runtime Layer Matrix (Behavior / Coordination / Persistence / Debug-Telemetry / Cadence / SpatialIndex)

## Estado

- Fecha: 2026-04-01
- Base normativa: `docs/runtime-architecture-pact.md`
- Cruce operativo: `docs/system-inventory.md` + `docs/side-effects-policy.md`

---

## 1) Matriz de fronteras por capa

> Objetivo: explicitar **qué sí**, **qué no**, **entradas permitidas**, **salidas/eventos permitidos** y **side effects prohibidos** para cada capa.

| Capa | Puede hacer | No puede hacer | Inputs permitidos | Outputs / eventos permitidos | Side effects prohibidos |
|---|---|---|---|---|---|
| **Behavior** | Decidir intención semántica de gameplay (`idle/alerted/hunting/extorting/raid`), priorizar objetivos, evaluar contexto táctico. | Ejecutar side effects irreversibles del mundo sin mediación; persistir estado canónico directamente; redefinir contratos técnicos de scheduler/índice. | Estado de dominio, señales de contexto, consultas de proximidad/territorio, snapshots de memoria grupal, tiempo leído. | Intents, targets, comandos declarativos (`enqueue_intent`, `desired_state`), hints de prioridad. | Mutar inventario/placement/pathing/save directamente; spawnear/despawnear por cuenta propia; escribir hostilidad fuera de flujo formal. |
| **Coordination** | Orquestar ejecución: orden, precondiciones técnicas, dispatch de acciones, integración entre módulos. | Reescribir intención de negocio de Behavior; introducir reglas de negocio ocultas por conveniencia operacional. | Intents de Behavior, estado runtime, respuestas de colas, resultados de servicios técnicos. | Llamadas de ejecución (`dispatch_group_to_target`, `process_*`), emisión de eventos de transición, handoff a flows/sistemas. | Cambiar semántica de intención; usar persistencia como motor de decisión; “decidir por timeout” reglas de dominio sin owner explícito. |
| **Persistence** | Serializar/deserializar, snapshot, restore, versionado de datos, adapters de guardado. | Decidir outcomes de combate/AI/economía; corregir gameplay en caliente durante save/load. | Estado canónico entregado por owners, comandos de save/load, schemas declarados. | Datos persistidos/restaurados, callbacks de carga, reportes de migración de schema. | Encolar raids/extorsiones desde save/load, mutar hostilidad por conveniencia, otorgar/revocar ítems en serialización. |
| **Debug / Telemetry** | Observar, medir, registrar, exponer métricas/logs, trazabilidad de eventos. | Gobernar flujo de gameplay en producción, convertirse en fuente de verdad de estado. | Señales/eventos de runtime, timers de instrumentación, snapshots read-only. | Logs, métricas, contadores, eventos de diagnóstico, alertas de integridad. | Mutar estado canónico (inventario, hostilidad, placement, pathing), persistencia operativa, decisiones de AI. |
| **Cadence** | Definir cuándo corre cada proceso (frecuencia, budgets, lanes, ventanas temporales). | Definir significado de negocio de lo ejecutado; cambiar outcomes semánticos por tick/paridad. | `delta`, config de lanes/budgets, colas de tareas agendables. | Pulsos/turnos de ejecución (`consume_lane`, ventanas), señales de scheduling. | Reescribir intención (ej. cancelar raid por “tick impar”), mutar reglas de hostilidad/inteligencia fuera de Behavior/Policy. |
| **SpatialIndex** | Responder queries espaciales: proximidad, ocupación, bloqueo, vecindad y lookup de entidades indexadas. | Declarar verdad semántica de dominio (enemigo legal, culpable, prioridad táctica final). | Registro/unregister de entidades, posiciones, geometría, tags técnicos de consulta. | Resultados de query (arrays, distancias, ocupación, candidatos). | Disparar hostilidad/combate por sí solo, spawns automáticos, mutaciones de inventario/persistencia. |

---

## 2) Mapeo de módulos actuales por capa

### Behavior (decisión semántica)

- `scripts/world/BanditWorldBehavior.gd`
- `scripts/world/NpcWorldBehavior.gd`
- `scripts/world/BanditGroupIntel.gd` *(scoring/intent)*
- `scripts/world/WorldTerritoryPolicy.gd` *(reglas de interés/territorio con efectos de hostilidad)*

### Coordination (orquestación)

- `scripts/world/BanditBehaviorLayer.gd`
- `scripts/world/BanditExtortionDirector.gd`
- `scripts/world/BanditRaidDirector.gd`
- `scripts/world/ExtortionFlow.gd`
- `scripts/world/RaidFlow.gd`
- `scripts/world/world.gd` *(composición y wiring de subsistemas)*

### Persistence (estado)

- `scripts/systems/SaveManager.gd`
- `scripts/systems/WorldSave.gd`
- `scripts/world/WallPersistence.gd`
- `scripts/world/StructuralWallPersistence.gd`
- `scripts/systems/ExtortionQueue.gd` *(cola persistible)*

### Debug / Telemetry (observabilidad)

- `scripts/debug/EventLogger.gd`
- `scripts/world/WorldSimTelemetry.gd`
- `scripts/world/ChunkPerfMonitor.gd`

### Cadence (cuándo corre)

- `scripts/world/WorldCadenceCoordinator.gd`
- `scripts/systems/WorldTime.gd`
- `scripts/systems/RunClock.gd`
- `scripts/world/WallRefreshQueue.gd` *(drain por budget)*

### SpatialIndex (consultas espaciales)

- `scripts/world/WorldSpatialIndex.gd`
- Consumidores principales: `NpcPathService`, `BanditBehaviorLayer`, `ItemDrop`.

---

## 3) Cruce de matriz vs módulos actuales (desalineaciones detectadas)

## D-01 — Duplicación de autoridad temporal en Cadence

**Síntoma:** existen dos relojes globales persistidos (`WorldTime` y `RunClock`) con propósitos distintos pero simultáneos.  
**Riesgo de capa:** Cadence mezcla “tiempo diegético” y “tiempo técnico” sin frontera formal de uso por dominio.  
**Impacto:** deriva conceptual y reglas nuevas atadas al reloj incorrecto.

## D-02 — Behavior + Coordination acoplados en gating de coerción

**Síntoma:** `BanditGroupIntel` concentra decisión y parte del gating operativo (`cooldowns`, `pending`, variantes de enqueue).  
**Riesgo de capa:** lógica semántica y lógica de coordinación/cola repartidas en el mismo módulo con duplicación de patrones.  
**Impacto:** difícil auditar quién decide intención vs quién decide ejecución.

## D-03 — Persistencia de walls fragmentada en dos adapters

**Síntoma:** `WallPersistence` y `StructuralWallPersistence` exponen operaciones casi gemelas (`save/remove/load`).  
**Riesgo de capa:** frontera de Persistence correcta en intención, pero duplicada en implementación.  
**Impacto:** divergencia futura de schema/reglas de serialización y costo de mantenimiento.

## D-04 — Validación espacial duplicada fuera de un contrato único

**Síntoma:** chequeos de bloqueo/ocupación aparecen en `PlacementSystem`, `PlayerWallSystem` y `WorldSpatialIndex`.  
**Riesgo de capa:** SpatialIndex queda como proveedor parcial, mientras coordinación/sistemas replican verdad espacial local.  
**Impacto:** inconsistencias entre “se puede colocar”, “bloquea movimiento” y “pathing navegable”.

## D-05 — Coerción en transición con owners múltiples

**Síntoma:** extorsión/incursión repartidas entre queues, directors, flows y behavior layer.  
**Riesgo de capa:** Coordination dispersa; límites entre pipeline de ejecución y decisión táctica no completamente cerrados.  
**Impacto:** incrementa riesgo de side effects cruzados (hostilidad, movement dispatch, lifecycle) difíciles de trazar.

---

## 4) Ambigüedades que requieren decisión explícita de arquitectura

## A-01 — Contrato oficial de tiempo: ¿qué dominios usan `WorldTime` y cuáles `RunClock`?

- Definir matriz de uso obligatoria por dominio (AI, coerción, hostilidad, autosave, cooldowns, UX).
- Prohibir usos mixtos para una misma regla de negocio.

## A-02 — Owner único del “gating coercitivo”

- Decidir si los checks `cooldown/pending/eligibilidad` viven en:
  1) Behavior (antes de generar intent), o
  2) Coordination (al consumir intent), o
  3) un Policy/Service dedicado.
- Debe quedar uno solo como autoridad para evitar duplicación.

## A-03 — Unificación de persistencia de paredes

- Definir si habrá:
  - adapter único con `wall_kind`, o
  - dos adapters con contrato compartido y tests de conformidad obligatorios.

## A-04 — Fuente canónica de “ocupación/bloqueo de tile”

- Decidir si `WorldSpatialIndex` pasa a ser la única API de consulta espacial para placement/pathing, o si se mantiene modelo híbrido con contrato explícito de precedencia.

## A-05 — Frontera entre Flow y Director en coerción

- Clarificar qué capa tiene la autoridad de:
  - transición de estado del encounter,
  - emisión de side effects (hostilidad/dispatch),
  - aborto/cleanup.
- Objetivo: evitar que la semántica quede implícita en el orden de llamadas.

---

## 5) Recomendación de adopción incremental

1. Formalizar ADR corto para A-01 y A-02 (máxima prioridad).  
2. Crear tests de contrato de capa (smoke) para side effects prohibidos por dominio.  
3. Cerrar D-03 y D-04 con refactor pequeño guiado por API canónica.  
4. Mantener este documento como checklist de revisión de PR en cambios de runtime.
