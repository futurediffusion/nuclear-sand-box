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

- Se separó captura/restauración de payload de `WorldSave` en:
  - `_capture_world_save_payload()`
  - `_restore_world_save_payload(data)`
- Se agregó validación estructural sin semántica de gameplay:
  - `_validate_world_save_payload(payload)`
  - Verifica tipos esperados (`Dictionary`/`Array`) y sanea forma mínima.
- Resultado: SaveManager restaura únicamente estado autorizado por owners (`WorldSave` y sistemas dueños) y reporta warnings de integridad sin decidir gameplay.

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
