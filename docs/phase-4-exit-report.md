# Phase 4 — Exit Report

Fecha de corte: 2026-04-01.
Baseline de comparación: `docs/phase-4-hotspots.md` + `docs/phase-4-autoload-inventory.md`.

## Objetivo 1 — Verificar que autoloads de alto riesgo ya no contienen decisiones de negocio

### Verificación aplicada

- Se validó que `ExtortionQueue` y `RaidQueue` ya **no** exponen decisiones de elegibilidad tipo `is_*_available`.
- Ambos autoloads quedaron acotados a operaciones de cola/estado (`enqueue`, `has_pending_for_group`, `get_last_*`) y helpers de cooldown genéricos.
- La decisión de **si corresponde** extorsionar, hacer wall probe, light raid o raid completo ahora vive en `BanditGroupIntel` (owner de dominio social/táctico), usando puertos (`_extortion_queue_port`, `_raid_queue_port`).

### Resultado

✅ **Cumplido para la migración objetivo de colas sociales** (extorsión/raid).

### Deuda remanente (autoloads aún con mezcla de decisión+ejecución)

Según inventario de Phase 4, permanecen autoloads `ALTO RIESGO` que requieren refactor adicional profundo:

- `PlacementSystem`
- `LootSystem`
- `DownedEncounterCoordinator`
- `BanditGroupMemory`
- `FactionHostilityManager`
- `FactionViabilitySystem`

Estado: ⚠️ **Parcial a nivel global de plataforma**.

## Objetivo 2 — Confirmar reducción de globals directos en hotspots `ALTO_ACOPLAMIENTO`

### Métrica (baseline vs estado actual)

| Módulo hotspot | Baseline (#autoloads/frecuencia) | Actual (#autoloads/frecuencia) | Delta |
|---|---:|---:|---:|
| `scripts/world/BanditBehaviorLayer.gd` | 6 / 43 | 2 / 14 | **-4 / -29** |
| `scripts/world/BanditGroupIntel.gd` | 7 / 68 | 7 / 67 | 0 / -1 |
| `scripts/systems/SaveManager.gd` | 13 / 68 | 13 / 68 | 0 / 0 |
| `scripts/world/world.gd` | 13 / 61 | 14 / 72 | +1 / +11 |

### Resultado

✅ **Hay reducción comprobable en el hotspot prioritario de social world** (`BanditBehaviorLayer`).

⚠️ **No hay reducción homogénea en todos los hotspots**; `world.gd` incrementó acoplamiento y queda como deuda prioritaria para Fase 5.

## Objetivo 3 — Asegurar ownership de decisiones críticas en dominio (no singleton transversal)

### Decisiones críticas verificadas en owner de dominio

- Cooldown/eligibilidad de extorsión: `BanditGroupIntel`.
- Cooldown/eligibilidad de raid y wall probe: `BanditGroupIntel`.
- Encolado final se hace por puerto, manteniendo los autoloads de cola en rol de infraestructura.

### Resultado

✅ **Cumplido para el dominio bandit social pressure (extorsión/raid/probe)**.

⚠️ **Parcial para el resto del juego**: todavía existen decisiones críticas de otros dominios en autoloads transversales (ver deuda remanente).

## Objetivo 4 — Métricas de acoplamiento y deuda remanente

### KPIs de salida Fase 4

- Migraciones de decisión fuera de singleton: **3** (extorsión, raid, wall probe).
- Hotspots con reducción fuerte demostrada: **1 principal** (`BanditBehaviorLayer`).
- Hotspots `ALTO_ACOPLAMIENTO` sin mejora o con regresión: **múltiples**, destacando `world.gd`.
- Autoloads `ALTO RIESGO` aún abiertos: **6**.

### Deuda remanente priorizada

1. `world.gd` como orquestador con dependencia global elevada.
2. `SaveManager.gd` con mezcla de persistencia + consultas a dominios sociales.
3. `PlacementSystem` y `LootSystem` con patrón lectura+decisión+ejecución.
4. `FactionHostilityManager` como punto transversal con lógica de política de dominio.

## Objetivo 5 — Backlog Fase 5 (refactor profundo adicional)

## Epic A — Desacoplar orquestación central (`world.gd`)

- [ ] Introducir puertos por bounded context (`hostility_port`, `social_memory_port`, `raid_port`, `path_port`) y eliminar acceso directo progresivamente.
- [ ] Extraer coordinador `WorldRuntimeOrchestrator` para separar ciclo principal de wiring de infraestructura.
- [ ] KPI: bajar de **14** a **<=9** autoloads referenciados en `world.gd`.

## Epic B — Segregar `SaveManager` por agregados

- [ ] Crear adaptadores de serialización por dominio (`bandit`, `faction`, `site`, `hostility`) invocados desde SaveManager sin leer autoloads directamente.
- [ ] Sustituir lecturas directas por snapshots inyectados al momento de save/load.
- [ ] KPI: bajar de **13** a **<=8** autoloads referenciados en `SaveManager.gd`.

## Epic C — Partir `PlacementSystem` (read model + decision service + executor)

- [ ] `PlacementReadModel`: consultas de ocupación/catálogo/collision.
- [ ] `PlacementPolicyService`: validaciones y reglas de negocio de colocación.
- [ ] `PlacementExecutor`: comandos de spawn/persistencia/feedback.
- [ ] KPI: eliminar decisiones de policy del singleton global.

## Epic D — Partir `LootSystem` por ownership de dominio

- [ ] Mover reglas de drop contextual (facción, downed, rareza) a servicio de dominio `LootPolicy`.
- [ ] Dejar `LootSystem` como broker técnico de spawn/dispersion.
- [ ] KPI: autoload sin branching de política de gameplay.

## Epic E — Reducir transversalidad de hostilidad

- [ ] Encapsular `FactionHostilityManager` detrás de `HostilityPort` por dominio consumidor.
- [ ] Mover decisiones tácticas de escalado al owner de facción/grupo y dejar al manager como estado derivado + eventos.
- [ ] KPI: cortar accesos directos desde AI/World/Downed a un contrato único por caso de uso.

## Gate sugerido de salida para Fase 5

- Ningún autoload marcado `ALTO RIESGO` debe contener simultáneamente lectura + decisión + ejecución de gameplay.
- `world.gd` y `SaveManager.gd` deben salir de categoría `ALTO_ACOPLAMIENTO` (umbral <5 autoloads ideal, <9 aceptable intermedio).
- Cada decisión crítica debe mapear a owner explícito en `docs/decision-ledger.md`.
