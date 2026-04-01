# Loot / Cargos Contract (flujo único)

Owner canónico: `BanditCampStashSystem` (`scripts/world/BanditCampStashSystem.gd`).

## 1) Inventario de rutas que mutan drops/cargo/pickups

### Ruta A — pickup de drop por órbita de recurso
- Entrada: `BanditWorkCoordinator._handle_collection_and_deposit()` → `sweep_collect_orbit(...)`.
- Mutaciones: marca `pending_collect_id`, consume `ItemDrop`, agrega cargo al bandido.

### Ruta B — pickup de drop al llegar a objetivo
- Entrada: `BanditWorkCoordinator._handle_collection_and_deposit()` → `sweep_collect_arrive(...)`.
- Mutaciones: iguales a Ruta A, pero disparada desde llegada a `pending_collect_id`.

### Ruta C — loot de contenedor durante asalto
- Entrada: `BanditWorkCoordinator._try_loot_nearby_container()`.
- Mutaciones: `extract_items_for_raid`, transferencia a cargo, reinserción de sobrantes en contenedor.

### Ruta D — descarga o vaciado de cargo
- `handle_cargo_deposit(...)`: mueve cargo hacia barril/base.
- `drop_carry_on_aggro(...)`: re-spawnea/reativa drops al entrar en combate.

---

## 2) Flujo canónico único

Todas las rutas de pickup/loot de cargo deben pasar por:

- `BanditCampStashSystem.collect_entries_canonical(beh, entries, route_key)`

### Orden canónico
1. **Validar actor/entrada** (`beh != null`, `entries` no vacío).
2. **Validar capacidad** (`is_cargo_full` y capacidad restante).
3. **Aplicar cooldown uniforme por ruta+miembro** (`PICKUP_ROUTE_COOLDOWN`).
4. **Aplicar transferencia de cantidades** usando `append_manifest_entries`.
5. **Retornar `taken/leftovers`** para que la ruta concreta haga side effects externos (reinserción en contenedor, mantener remanente en drop, etc.).

---

## 3) Side effects permitidos por caller (y no permitidos)

### Permitidos
- Reinsertar `leftovers` al contenedor origen (Ruta C).
- Dejar `leftover` en `ItemDrop.amount` cuando el pickup es parcial (Rutas A/B).
- Marcar `force_return_home()` cuando hubo loot válido en raid.

### No permitidos
- Modificar `cargo_count` directamente desde rutas secundarias.
- Saltarse `collect_entries_canonical` para “sumar cargo rápido”.
- Aplicar cooldown en una ruta sí y otra no.

---

## 4) Invariantes del flujo único

1. `cargo_count` nunca supera `cargo_capacity` por rutas de pickup/loot.
2. Si una ruta no puede tomar todo, el remanente queda explícito en `leftovers`.
3. El cooldown de pickup se evalúa igual para rutas de drops y ruta de raid container.
4. Toda alta de cargo por loot/pickup ocurre a través del owner `BanditCampStashSystem`.
5. Las rutas secundarias sólo orquestan contexto (qué drop/contenedor atacar), no reglas de negocio de transferencia.
