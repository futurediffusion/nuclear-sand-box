# Sprint corto de cierre (temporales, wrappers y validación runtime) — 2026-04-02

Objetivo del sprint: **cero fallback permanente disfrazado de temporal**, con foco exclusivo en:

1. temporales de runtime,
2. wrappers/puentes de compatibilidad,
3. validación runtime de salida.

> Alcance explícito: durante este sprint **no** se abre trabajo de features ni refactors adyacentes.

## 1) Inventario de wrappers/puentes activos (runtime)

| Wrapper / puente | Contrato final | Consumidores reales en repo | Estado |
|---|---|---|---|
| `ChestComponent` (`ChestWorld`) | `ContainerPlaceable` | `scenes/placeables/chest_world.tscn`, `scenes/placeables/barrel_world.tscn`, test de fill | **RETIRADO (migrado)** |
| `chest_ui` (`ChestUi`) | `ContainerUi` | `scenes/main.tscn`, `scenes/tests/chest_random_fill_test.tscn`, resoluciones UI por path/grupo | **RETIRADO (migrado)** |
| `FactionRelationService` | `FactionHostilityManager` | Sin consumidores runtime en repo | **RETIRADO (sin compat efectiva)** |
| `ShopService` API legacy | `ShopService.get_port()` (`ShopPort`) | Sin consumidores runtime tras migración de `keeper_menu_ui.gd` | **RETIRADO (consumo=0)** |
| Constantes compat de `PlacementSystem` | `PlacementCatalog` | Solo runner legacy de checklist (`walls_colliders_checklist_runner.gd`) | **RETIRADO (sin consumidores runtime)** |

## 2) Priorización por riesgo gameplay

1. **P0 — Commerce loop bloqueado por wrapper legacy** (`ShopService` API legacy): impacta compra/venta del keeper y puede introducir divergencia entre `keeper_menu_ui` y `ShopPort`.
2. **P1 — Compat symbols de placement sin uso runtime** (`PlacementSystem.PLACEABLE_SCENES` etc.): ruido de contrato que facilita reintroducir lookup legacy en pruebas y tooling.
3. **P2 — Wrappers ya retirados** (`ChestUi`, `ChestComponent`, `FactionRelationService`): mantener trazabilidad histórica pero sin deuda activa.

## 3) Búsqueda consolidada de marcadores temporales (única)

Marcadores auditados: `REMOVE_AFTER`, `legacy fallback`, excepciones temporales, compat wrappers (`compat temporal`, `wrapper legacy`).

| Tipo | Hallazgo único | Ubicación | Impacto gameplay | Decisión |
|---|---|---|---|---|
| Compat wrapper | API legacy `ShopService` | Sin consumidores runtime (`rg` de llamadas legacy en scripts) | Alto (economía de gameplay) | **Retirar ahora (consumo=0)** |
| Compat temporal | Símbolos legacy de `PlacementSystem` | `scripts/systems/PlacementSystem.gd` | Medio (riesgo de recaída en contrato legacy) | **Retirar ahora** |
| `REMOVE_AFTER` | `FactionRelationService` (histórico) | Solo trazas en docs/registro | Bajo (sin consumo runtime) | **Ya retirado; mantener evidencia documental** |
| Excepción temporal | `EXC-SHOP-PORT-WRAPPER-001` | `docs/incidencias/registro-unico-deuda-tecnica.md` | Alto | **Retirada (salida verificada)** |

## 4) Wrappers retirados en este sprint

- Se migra `chest_world` y `barrel_world` a `ContainerPlaceable` directo.
- Se migra `main` y `chest_random_fill_test` a `container_ui.tscn`.
- Se eliminan los lookups legacy `UI/ChestUi` y grupo `chest_ui` de `ContainerPlaceable` y `player_inventory_menu`.
- Se elimina `FactionRelationService` por ausencia de consumidores reales en el código del repo.
- Se eliminan símbolos compat de `PlacementSystem` y el runner de checklist pasa a leer `PlacementCatalog` directo.

## 5) Excepciones que se mantienen (con fecha y salida verificable)

_No quedan excepciones activas de wrappers de compatibilidad._

## 6) Resultado del sprint

- **Agregado vs retirado:** `+0 / -4` (deuda neta: `-4`).
- Se elimina ruta paralela de UI de contenedores y puente de hostilidad sin uso.
- No se reintroduce doble verdad: hostilidad queda solo en `FactionHostilityManager` y contenedores/UI quedan en contrato neutral `Container*`.

## 7) KPIs de salida (gate obligatorio)

Para cerrar formalmente el sprint se fijan estos KPIs:

- **KPI-TEMP-OPEN (temporales abiertos):** `0` para wrappers de compatibilidad en runtime.
- **KPI-WRAP-LIVE (wrappers vivos en runtime):** `0` (**objetivo explícito: cero compat wrappers**).
- **KPI-RUNTIME-P0 (incidentes runtime críticos):** `0` incidentes críticos activos en `docs/incidencias/`.

Interpretación operativa:

- Si cualquiera de los 3 KPIs no cumple, el sprint sigue abierto.
- Si los 3 KPIs cumplen, se habilita congelamiento de arquitectura suficiente (sección 7).

## 8) Regla de congelamiento al cumplir KPIs

Cuando `KPI-TEMP-OPEN`, `KPI-WRAP-LIVE` y `KPI-RUNTIME-P0` estén en verde:

- se declara **freeze suficiente** del frente de cleanup,
- se prohíbe continuar “limpieza por inercia” sin incidente o métrica que lo justifique,
- todo cambio adicional de arquitectura requiere nuevo disparador explícito (incidente, regresión o objetivo de producto).

## 9) Reapertura de features (condición de entrada)

Al reabrir desarrollo de features, se exige:

1. **Owner único por decisión/cambio de estado** (sin co-ownership difuso).
2. **Respeto estricto a `docs/pr-smell-blacklist.md`** como blacklist activa de olores.
3. Si aparece un temporal nuevo, debe nacer con:
   - ticket/registro de excepción,
   - fecha de retiro,
   - criterio verificable de salida.

## 10) Vigilancia ligera anti-recaída

Para evitar volver a “refactor perpetuo”, se mantiene una vigilancia mínima:

- chequeo semanal breve de:
  - temporales abiertos,
  - wrappers vivos,
  - incidentes runtime críticos;
- auditoría puntual solo ante desvío de KPI;
- sin reabrir programa masivo de limpieza mientras no haya evidencia de recaída.
