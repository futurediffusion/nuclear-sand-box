# Phase 3 — Shortlist de refactor (entrada a ejecución técnica)

## Fuente del shortlist
Tablero de riesgo tomado de `docs/phase-2-suspicious-files.md` (ranking por score total).

Top del tablero:
1. `scripts/world/world.gd` — **21**
2. `scripts/world/BanditBehaviorLayer.gd` — **17**
3. `scripts/world/ExtortionFlow.gd` — **12** *(desempate: se prioriza sobre `BanditGroupIntel.gd` por impacto directo en resolución de flujo activo y side-effects visibles en runtime).* 

---

## 1) `scripts/world/world.gd` (score 21)

### Por qué es crítico
- Es el núcleo operativo del mundo y mezcla generación de chunks, persistencia, territorio, colocación/daño de estructuras y coordinación de múltiples subsistemas.
- Ya fue clasificado como macro-script con surface area excesiva (2044 líneas, 42 métodos públicos), lo que amplifica riesgo de regresiones cruzadas.

### Responsabilidades que sobran
- Orquestación de ciclo de vida de chunks + reglas de dominio territorial + mutaciones de paredes + wiring de servicios de intel en una misma unidad.
- Combina query, policy y ejecución en rutas calientes (`update_chunks`, `damage_player_wall_at_world_pos`, `_tick_player_territory`).

### Límites de soberanía que viola
- **Soberanía de dominio:** World runtime y policy territorial se pisan entre sí.
- **Soberanía de persistencia:** decisiones de gameplay invocan mutaciones de estado persistente sin frontera explícita.
- **Soberanía de ejecución:** una misma API decide y ejecuta side-effects sobre varios bounded contexts.

### Secuencia de refactor (pequeña y reversible)
1. Introducir wrappers internos `*_query`, `*_policy`, `*_executor` sin cambiar firmas públicas.
2. Extraer `update_chunks` a planificador puro (`collect_window_diff`) + aplicador (`apply_chunk_plan`).
3. Extraer daño de walls a pipeline `resolve_hit -> eval_damage -> apply_damage` con tests de regresión.
4. Mover `_tick_player_territory` a `TerritoryTickService` (RefCounted) inyectado desde `world.gd`.
5. Reducir `world.gd` a orquestador/wiring; mantener adapters legacy temporales por una versión.

### Criterios de éxito
- Dependencias directas de `world.gd`: **-25%** mínimo.
- Métodos públicos en `world.gd`: de **42** a **<=30**.
- Métodos con mezcla R+D+E en `world.gd`: reducción **>=40%**.
- Flags de contexto en rutas críticas (`update_chunks`, walls, territory): **-30%**.

---

## 2) `scripts/world/BanditBehaviorLayer.gd` (score 17)

### Por qué es crítico
- Controla tick, aplicación de velocidad, caches del mundo y coordinación de behaviors para bandidos; está en el path de CPU recurrente.
- Concentra decisiones de LOD/estado/intención con side-effects de movimiento y recolección.

### Responsabilidades que sobran
- Selección de intención + coordinación de trabajo + gestión de cache world_resource/item_drop + aplicación física de resultado.
- Convergencia de reglas de comportamiento grupal y reglas operativas (loot/cargo) en el mismo módulo.

### Límites de soberanía que viola
- **Soberanía de IA táctica vs ejecución física:** decide estrategia y aplica movimiento en la misma capa.
- **Soberanía de recolección/economía:** manipula drops/cargo dentro de la capa de behavior.
- **Soberanía de observabilidad de mundo:** cachea y filtra recursos/drops sin un servicio dedicado.

### Secuencia de refactor (pequeña y reversible)
1. Extraer lectura de contexto a `BanditRuntimeContextBuilder` (solo query).
2. Extraer decisión de tarea a `BanditTaskPolicy` (sin side-effects).
3. Encapsular side-effects de loot/cargo en `BanditCollectionExecutor`.
4. Mantener `BanditBehaviorLayer` como coordinador de tick + bridge temporal.
5. Activar feature flag de rollback (`use_new_bandit_task_pipeline`) por 1 ciclo de validación.

### Criterios de éxito
- Dependencias directas de `BanditBehaviorLayer.gd`: **-20%** mínimo.
- Flags/booleans de contexto internos: **-30%**.
- Funciones >80 líneas: reducción **>=50%**.
- Rutas de decisión puras (sin side-effects): al menos **3** (`pick_task`, `pick_target`, `pick_state_transition`).

---

## 3) `scripts/world/ExtortionFlow.gd` (score 12)

### Por qué es crítico
- Maneja pipeline multi-etapa de extorsión (warnings, strike, resolución), sensible a errores de transición y spam.
- Está en frontera entre intención social y ejecución operacional; cualquier fuga impacta estabilidad de comportamiento de bandas.

### Responsabilidades que sobran
- Gestión de lifecycle de jobs + evaluación de transición + movimiento/acciones concretas de NPCs dentro del mismo proceso.
- Validación de reglas anti-spam y ejecución de callbacks/eventos operativos en la misma pasada.

### Límites de soberanía que viola
- **Soberanía de estado de flujo:** transiciones y efectos colaterales no están desacoplados.
- **Soberanía social vs combate:** reglas de presión/extorsión comparten capa con ejecución táctica.
- **Soberanía de cola:** consumo de intent y ejecución runtime carecen de frontera explícita.

### Secuencia de refactor (pequeña y reversible)
1. Crear `ExtortionStateMachine` pura (tabla de transición por stage/evento).
2. Mover side-effects a `ExtortionEffectsExecutor` con interfaz explícita.
3. Cambiar `process_flow` a patrón: `snapshot -> decide -> apply`.
4. Migrar un stage por PR (warn → strike → resolve) para rollback simple.
5. Añadir métricas de transición inválida y reintentos para corte de riesgo.

### Criterios de éxito
- Condicionales por stage en `process_flow`: **-40%**.
- Flags de etapa/contexto: **-30%**.
- Transiciones modeladas en tabla/estado: **100%** de stages críticos.
- Funciones que mezclan R+D+E en el archivo: reducción **>=35%**.

---

## Secuencia global recomendada (ejecución técnica)
1. **Primero `world.gd`**: separa hotspots de chunk/walls/territorio para bajar riesgo sistémico.
2. **Luego `BanditBehaviorLayer.gd`**: desacopla decisiones de IA de side-effects operativos.
3. **Después `ExtortionFlow.gd`**: estabiliza la máquina de estados social-operativa.

Cada paso debe salir en PRs pequeños, con rollback directo y tests de regresión por ruta caliente.

---

## Shortlist final (entrada a la siguiente fase)
- `scripts/world/world.gd` — score **21** — prioridad **P0**.
- `scripts/world/BanditBehaviorLayer.gd` — score **17** — prioridad **P0**.
- `scripts/world/ExtortionFlow.gd` — score **12** — prioridad **P1**.

Estado: **aprobado como backlog de ejecución técnica fase siguiente**.
