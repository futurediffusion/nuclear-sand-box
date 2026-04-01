# Persistence boundary: `Persistence = storage only`

## Contrato

La capa de **Persistence** en este proyecto solo puede:

- serializar y deserializar datos,
- validar integridad estructural (tipos, shape, campos obligatorios),
- aplicar migraciones de schema sin semántica de gameplay.

La capa de **Persistence no puede**:

- decidir outcomes de gameplay (`remove`, `spawn`, `raid`, `extortion`, `hostility`, etc.),
- corregir estado semántico por conveniencia al cargar,
- introducir o resolver reglas de combate/AI/economía durante save/load.

## Delimitación explícita de estado

### 1) Estado solo runtime (transitorio)

Debe existir únicamente en runtime y **nunca** entrar al snapshot durable:

- índices auxiliares de lookup/rebuild (`placed_entity_chunk_by_uid`),
- revisiones o contadores de invalidación (`placed_entities_revision`),
- contexto de tick/callables inyectados (`wall_tile_blocker_fn`),
- configuración operativa que viene del mundo activo (`chunk_size`).

### 2) Estado serializable como save truth

Persisten solo los hechos durables necesarios para continuidad:

- `worldsave_chunks`,
- `worldsave_enemy_state`,
- `worldsave_enemy_spawns`,
- `worldsave_global_flags`,
- `worldsave_player_walls`,
- `placed_entities_by_chunk`,
- `placed_entity_data_by_uid`.

### 3) Persistencia sin gameplay

Persistencia se limita a guardar/restaurar snapshots autorizados.
No interpreta intención del jugador/AI ni corrige outcomes por conveniencia.

### 4) Mapeo explícito runtime <-> save

El mapeo vive explícitamente en `WorldSave`:

- `to_save_snapshot()` para `runtime -> save`.
- `apply_save_snapshot(snapshot)` para `save -> runtime`.

Este mapeo es estructural: sin reinterpretación semántica.

### 5) Invariantes de carga

Al cargar snapshot:

- **Debe reconstruirse**: índices runtime derivados (`placed_entity_chunk_by_uid`).
- **Debe recalcularse**: contadores/revisiones transitorias (`placed_entities_revision`) y wiring runtime (`wall_tile_blocker_fn`).
- **No debe persistirse**: contexto de tick/decisiones activas no durables ni callables runtime.

---

## Rutas auditadas (save/load con impacto potencial sobre decisiones activas)

1. `scripts/systems/SaveManager.gd`
   - Save global (`save_world`) y restore (`load_world_save`).
   - Riesgo: mezcla de restauración + decisiones implícitas si no hay validación de contrato por owner.

2. `scripts/world/WallPersistence.gd`
   - Persistencia de paredes del jugador por chunk.
   - Riesgo detectado: decisión implícita de remover pared desde `save_wall` cuando `hp <= 0`.

3. `scripts/world/StructuralWallPersistence.gd`
   - Persistencia de paredes estructurales (`chunk_save[chunk].placed_tiles`).
   - Riesgo detectado: decisión implícita de remover/corregir estado desde persistencia.

---

## Medidas aplicadas

### 1) SaveManager con restore autorizado + validación de integridad

- SaveManager delega el límite runtime/save a `WorldSave`:
  - `WorldSave.to_save_snapshot()`
  - `WorldSave.apply_save_snapshot(snapshot)`
- La validación estructural vive junto al owner del estado (`WorldSave._validate_and_sanitize_save_snapshot`).
- Resultado: SaveManager orquesta IO/migración legacy y `WorldSave` aplica exclusivamente snapshots autorizados, sin decidir gameplay.

### 2) WallPersistence sin decisiones de dominio

- `save_wall(...)` ya no decide `remove_wall(...)` si llega payload inválido.
- Ahora solo acepta payload serializable válido o lo rechaza con `push_warning`.
- La decisión de romper/quitar pared queda en `PlayerWallSystem` (behavior owner).

### 3) StructuralWallPersistence sin semántica de gameplay

- `save_wall(...)` ya no remueve por su cuenta ante payload inválido.
- `serialize_wall_data(...)` y `deserialize_wall_data(...)` validan estructura mínima (`hp` presente y `> 0`) sin aplicar reglas de diseño.
- La decisión de daño/rotura/estado final permanece en capas de comportamiento.

---

## Validaciones de integridad permitidas en Persistence

Permitido:

- tipo de contenedor (`Dictionary`, `Array`),
- presencia de claves técnicas requeridas,
- parseo seguro de claves/string IDs,
- descarte de entradas corruptas,
- warnings de integridad.

No permitido:

- derivar intenciones de AI,
- recalcular hostilidad o cooldowns por conveniencia,
- otorgar/remover ítems por reglas de diseño,
- resolver victorias/derrotas o escaladas tácticas.

---

## Ownership

- **Behavior/Policies owners**: deciden reglas semánticas de gameplay.
- **Persistence owners**: almacenan y restauran snapshots autorizados por esos owners.

Regla operativa: si una línea de código en save/load responde “qué debería pasar en gameplay”, está en la capa equivocada.
