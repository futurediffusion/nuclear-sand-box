# world.gd boundary contract

`world.gd` es la **raíz de composición** del mundo y un **facade de orquestación**.
No es un módulo de reglas de negocio.

## Allowlist de `world.gd` (qué SÍ puede vivir aquí)

1. **Composición y wiring**
   - Instanciar sistemas.
   - Conectar puertos/callables/señales entre módulos.
   - Registrar callbacks de fachada.
2. **Lifecycle framework-level**
   - `_ready`.
   - `_process`.
   - `_notification` de cierre.
   - Hooks de input de alto nivel para guardar/cargar/nueva partida.
3. **Despacho de alto nivel**
   - Reenviar incidentes/eventos a orquestadores de dominio.
   - Disparar pipelines/cadencias, sin decidir semántica de negocio.
4. **Orquestación de save/reset**
   - Llamadas de snapshot/save coordinadas.
   - Reset central vía coordinador dedicado.

## Blocklist explícita (qué NO debe vivir en `world.gd`)

- Reglas de negocio de autoridad social o sanción.
- Árboles de decisión de sanción, castigo o escalamiento.
- Heurísticas de targeting táctico (selección fina de objetivo).
- Tablas semánticas incidente → ofensa/sanción.
- Lógica detallada de ownership/reconciliación/drops de paredes.
- Decisiones de política territorial específicas (más allá de delegar).
- Implementaciones internas de AI (bandits/sentinels/keeper).

## Dominios y responsabilidades

### 1) World Composition & Lifecycle
**Responsabilidad:** bootstrapping, cadence global, ciclo de vida y dispatch central.

### 2) Chunk/Terrain Streaming Orchestration
**Responsabilidad:** ventana activa de chunks, carga/descarga, coordinación con pipeline.

### 3) Walls Facade
**Responsabilidad:** exponer APIs públicas para gameplay y delegar en `PlayerWallSystem`/infra de colisión.

### 4) Tavern/Authority Orchestration Ports
**Responsabilidad:** wiring de componentes de taberna/autoridad y routing de incidentes.

### 5) Territory & Interest Query Ports
**Responsabilidad:** puertos de consulta/registro de intel territorial y eventos de interés.

### 6) Persistence / Runtime Reset Orchestration
**Responsabilidad:** save hooks, snapshots y reset de runtime vía coordinador.

## APIs públicas que `world.gd` puede invocar por dominio

> Nota: esta lista define **superficie permitida de invocación** para `world.gd`.

### Composition & Lifecycle
- `WorldCadenceCoordinator.*`
- `ChunkPipeline.*`
- `EntitySpawnCoordinator.*`
- `RuntimeResetCoordinator.reset_new_game()`

### Chunk/Terrain
- `ChunkGenerator.*`
- `VegetationRoot.load_chunk/unload_chunk`
- `TilePainter.*`
- `ChunkWallColliderCache.*`
- `CliffGenerator.*`

### Walls
- `PlayerWallSystem.*`
- `WallRefreshQueue.*`
- `WallPersistence.*`
- `StructuralWallPersistence.*`
- `WallFeedback.*`

### Tavern/Authority
- `TavernAuthorityOrchestrator.report_incident(...)`
- `TavernAuthorityOrchestrator.tick_defense_posture(...)`
- `TavernAuthorityOrchestrator.build_perimeter_patrol_points(...)`
- `TavernAuthorityOrchestrator.remember_perimeter_patrol(...)`
- `TavernLocalMemory.is_service_denied(...)`

### Territory/Interest
- `SettlementIntel.*`
- `WorldTerritoryPolicy.validate_placement(...)`
- `WorldTerritoryPolicy.record_interest_event(...)`
- `WorldSpatialIndex.*` (queries)

### Runtime persistence / telemetry
- `SaveManager.save_world/new_game/has_save`
- `WorldSimTelemetry.*`

## Regla operativa para PRs

Si un cambio en `world.gd` introduce lógica no allowlisted, se debe mover a un servicio/orquestador/puerto de dominio antes de merge.

## Ejemplos concretos de violaciones

- `if incident_type == "x" then sanction = "y"` dentro de `world.gd`.
- Cálculo de “mejor objetivo” para raids usando score heurístico local.
- Implementar en `world.gd` cuándo un faction puede atacar o no, en vez de delegar.
- Resolver drops/reconciliación de paredes manualmente, evitando `PlayerWallSystem`.
- Ejecutar `some_domain.reset()` directo fuera de coordinadores/puertos aprobados.
