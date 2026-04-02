# Sprint cierre temporal fallbacks — 2026-04-02

Objetivo del sprint: **cero fallback permanente disfrazado de temporal**.

## 1) Inventario de wrappers/puentes activos (runtime)

| Wrapper / puente | Contrato final | Consumidores reales en repo | Estado |
|---|---|---|---|
| `ChestComponent` (`ChestWorld`) | `ContainerPlaceable` | `scenes/placeables/chest_world.tscn`, `scenes/placeables/barrel_world.tscn`, test de fill | **RETIRADO (migrado)** |
| `chest_ui` (`ChestUi`) | `ContainerUi` | `scenes/main.tscn`, `scenes/tests/chest_random_fill_test.tscn`, resoluciones UI por path/grupo | **RETIRADO (migrado)** |
| `FactionRelationService` | `FactionHostilityManager` | Sin consumidores runtime en repo | **RETIRADO (sin compat efectiva)** |
| `ShopService` API legacy | `ShopService.get_port()` (`ShopPort`) | `keeper_menu_ui.gd` usa API legacy; `inventory_panel.gd` usa `get_port` | **VIGENTE (compat efectiva parcial)** |

## 2) Priorización por riesgo gameplay

1. **P0 — UI de contenedores con rutas paralelas**: mantener `UI/ChestUi` + grupo `chest_ui` en paralelo a `UI/ContainerUi` abría lookup dual innecesario.
2. **P0 — Wrapper de contenedor en escenas**: `ChestComponent` era herencia vacía (`extends ContainerPlaceable`) y sostenía contrato duplicado sin semántica propia.
3. **P0 — Hostilidad bridge sin consumidores**: `FactionRelationService` no aportaba compatibilidad efectiva al no tener lectores/escritores activos en runtime.

## 3) Wrappers retirados en este sprint

- Se migra `chest_world` y `barrel_world` a `ContainerPlaceable` directo.
- Se migra `main` y `chest_random_fill_test` a `container_ui.tscn`.
- Se eliminan los lookups legacy `UI/ChestUi` y grupo `chest_ui` de `ContainerPlaceable` y `player_inventory_menu`.
- Se elimina `FactionRelationService` por ausencia de consumidores reales en el código del repo.

## 4) Excepciones que se mantienen (con fecha y salida verificable)

### EXC-SHOP-PORT-WRAPPER-001
- **Wrapper:** API legacy de `ShopService` (`get_buy_price`, `sell`, etc.).
- **Motivo técnico estricto:** `keeper_menu_ui.gd` todavía consume la API legacy del autoload.
- **Owner:** `Runtime-Commerce`.
- **Fecha de revisión:** `2026-05-01`.
- **Fecha de retiro comprometida:** `2026-09-30`.
- **Condición exacta de salida:** migrar `keeper_menu_ui.gd` a `ShopService.get_port()` y verificar telemetría `get_legacy_telemetry_snapshot()` en `0` para todas las rutas legacy.

## 5) Resultado del sprint

- **Agregado vs retirado:** `+1 / -3` (deuda neta: `-2`).
- Se elimina ruta paralela de UI de contenedores y puente de hostilidad sin uso.
- No se reintroduce doble verdad: hostilidad queda solo en `FactionHostilityManager` y contenedores/UI quedan en contrato neutral `Container*`.
