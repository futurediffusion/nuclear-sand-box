# AGENTS.MD — Nuclear Sand Box (Estado actual)

> Guía operativa para contributors **hoy**.
> Arquitectura vigente (fuente única): `docs/architecture/current_sandbox_architecture.md`.
> Contexto histórico: `REGISTRO_CAMBIOS_DESDE_AGENTS.md`.

---

## 1) Alcance y referencia de arquitectura

La arquitectura vigente del sandbox se define en:

- `docs/architecture/current_sandbox_architecture.md` (**fuente de verdad**)

Este `AGENTS.MD` mantiene reglas operativas de colaboración y límites prácticos para cambios.

Reglas operativas:

1. El estado de gameplay no debe depender de nodos visuales/transitorios.
2. Las proyecciones deben ser reconstruibles desde inputs canónicos.
3. Compatibilidad legacy solo como superficie **deprecated** y de salida controlada; no forma parte del diseño objetivo.

---

## 2) Resumen de ownership (sin reemplazar la fuente única)

### 2.1 Mundo y orquestación runtime

- `scripts/world/world.gd` orquesta subsistemas y wiring.
- `scripts/world/ChunkPipeline.gd`, `EntitySpawnCoordinator.gd`, `NpcSimulator.gd` gestionan streaming, lifecycle y simulación por chunk.
- `scripts/runtime/world/GameplayCommandDispatcher.gd` enruta comandos de gameplay sin convertir `world.gd` en lógica de dominio.

`world.gd` coordina; no debe convertirse en fuente de verdad de building, IA o persistencia.

### 2.2 Dominio de building (canónico)

Ownership actual de construcción/paredes:

- **Comandos y reglas:**
  - `scripts/domain/building/BuildingCommands.gd`
  - `scripts/domain/building/BuildingSystem.gd`
  - `scripts/domain/building/BuildingState.gd`
  - `scripts/domain/building/BuildingEvents.gd`
- **Workflow de paredes de player:**
  - `scripts/domain/building/BuildingWallWorkflow.gd`
- **Repositorio de estado:**
  - `scripts/domain/building/BuildingRepository.gd`
  - `scripts/persistence/save/WorldSaveBuildingRepository.gd`

Lenguaje canónico de estructura:

- `scripts/domain/building/SandboxStructureContract.gd`
- `scripts/world/SandboxStructureRepository.gd`

Campos canónicos esperados: `structure_id`, `kind`, `owner`, `chunk_pos`, `tile_pos`, `hp`, `max_hp`, `metadata`, `persistence_bucket`.

**Regla:** el dominio decide cambios; tilemap/collider/persistencia reaccionan a eventos o snapshots.

### 2.3 IA de bandidos (pipeline canónico)

Pipeline vigente y ownership:

1. **Perception** → `scripts/domain/factions/BanditPerceptionSystem.gd`
2. **Intent** → `scripts/domain/factions/BanditIntentSystem.gd`
3. **Task Planning** → `scripts/domain/factions/BanditTaskPlanner.gd`
4. **Execution runtime** → `scripts/world/BanditBehaviorLayer.gd`, `BanditWorldBehavior.gd`, `BanditGroupBrain.gd`

Notas clave:

- `Perception/Intent/Task` producen datos trazables y no ejecutan movimiento/combate directo.
- La ejecución runtime consume órdenes declarativas (`order.task`) y aplica side-effects.
- Inputs/hints legacy existentes son **solo de compatibilidad deprecated** e instrumentada (contadores/warnings), nunca authority ni camino por defecto.

---

## 3) Persistencia actual (canónica)

Componentes principales:

- `scripts/core/WorldSnapshot.gd`, `ChunkSnapshot.gd`
- `scripts/persistence/save/WorldSnapshotSerializer.gd`
- `scripts/persistence/save/WorldSnapshotVersioning.gd`
- `scripts/persistence/save/WorldSaveAdapter.gd`
- `scripts/systems/SaveManager.gd`

Disciplina vigente:

1. Persistencia de mundo mediante **WorldSnapshot canónico**.
2. Payloads con `snapshot_version` y migraciones determinísticas paso a paso.
3. `WorldSnapshotVersioning` valida versiones soportadas y registra `migration_path` + warnings.
4. Migración legacy es **one-way** hacia snapshot canónico (no reintroducir formato legacy como salida).
5. Proyecciones/runtime caches no son fuente de verdad persistida.

---

## 4) Proyecciones actuales (read-models derivables)

Proyecciones vigentes:

- **Tilemap de building:** `scripts/projections/tilemap/BuildingTilemapProjection.gd`
- **Colliders de walls:** `scripts/projections/collision/WallColliderProjection.gd`
- **Territorio player:** `scripts/projections/territory/TerritoryProjection.gd`

Contrato esperado:

- Se alimentan con eventos/snapshots/inputs canónicos.
- Deben soportar rebuild determinista.
- No aceptan que nodos runtime se vuelvan autoridad implícita.

Caso explícito: `TerritoryProjection` rechaza entrypoints runtime legacy y exige `workbench_anchors` + `detected_bases` canónicos.

---

## 5) Compatibilidad y deprecaciones (estado actual)

Superficies deprecated aún presentes (ejemplos):

- `scripts/world/PlayerTerritoryMap.gd` (wrapper legacy de `TerritoryProjection`).
- `scripts/projections/collider/BuildingColliderRefreshProjection.gd` (wrapper legacy).
- `scripts/world/contracts/*CallableAdapter.gd` (adaptadores transicionales de puertos).
- Wrappers UI/placeables (`Chest*` sobre `Container*`).

Política:

- No crear nuevos puentes/bridges legacy salvo bloqueo real y temporal de migración.
- Toda superficie legacy debe estar marcada como deprecated, con telemetría/observabilidad.
- El camino canónico de diseño y mantenimiento es end-to-end sin wrappers de transición.

Clasificación explícita:

- **Actual**: APIs/owners canónicos de dominio, proyección y snapshot.
- **Deprecated**: wrappers/adapters legacy solo para compatibilidad de callers pendientes.
- **Histórico**: decisiones y fases cerradas; consultar solo en `REGISTRO_CAMBIOS_DESDE_AGENTS.md`.

---

## 6) Guía práctica para contribuciones

Cuando cambies código:

1. Preserva separación **Dominio / Persistencia / Proyección / Runtime**.
2. Si tocas building, valida flujo completo: comando → evento → proyección → persistencia.
3. Si tocas IA, respeta pipeline **Perception → Intent → Task → Execution**.
4. Si tocas persistencia, actualiza versionado/migración y evita reintroducir fallback legacy como flujo primario.
5. Si agregas o reemplazas un subsistema arquitectural, actualiza este documento en términos de estado actual (no cronología histórica).

---

## 7) Historial y contexto de migración

Para contexto histórico/migraciones de fases anteriores, usar:

- `REGISTRO_CAMBIOS_DESDE_AGENTS.md`

Este `AGENTS.MD` se mantiene deliberadamente como guía operativa.
La referencia de arquitectura actual es `docs/architecture/current_sandbox_architecture.md`.
