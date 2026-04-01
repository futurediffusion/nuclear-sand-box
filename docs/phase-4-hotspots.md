# Phase 4 — Hotspots por acoplamiento a autoloads

Fecha de corte: 2026-04-01.
Fuente: autoloads declarados en `[autoload]` dentro de `project.godot` y referencias en scripts `.gd`.

## Metodología de conteo

- **Módulo hotspot**: script que consulta **múltiples autoloads**.
- **`ALTO_ACOPLAMIENTO`**: módulo que necesita **5 o más** autoloads para operar.
- **Frecuencia de acceso**: número total de ocurrencias de nombres de autoload en el archivo.
- **Lectura vs escritura**:
  - `read`: referencia al autoload sin asignación directa.
  - `write`: detección heurística de asignación directa sobre propiedad de autoload (`Autoload.prop = ...`).
- Nota: la mayoría de escrituras reales pueden estar encapsuladas en llamadas (`Autoload.set_x(...)`) y no siempre aparecen como `write` en esta heurística.

## Hotspots detectados (`ALTO_ACOPLAMIENTO`)

| Módulo | # autoloads consultados | Frecuencia total | Estado |
|---|---:|---:|---|
| `scripts/systems/SaveManager.gd` | 13 | 68 | `ALTO_ACOPLAMIENTO` |
| `scripts/world/world.gd` | 13 | 61 | `ALTO_ACOPLAMIENTO` |
| `scenes/enemy.gd` | 10 | 28 | `ALTO_ACOPLAMIENTO` |
| `scripts/world/NpcSimulator.gd` | 8 | 39 | `ALTO_ACOPLAMIENTO` |
| `scripts/placeables/ContainerPlaceable.gd` | 8 | 29 | `ALTO_ACOPLAMIENTO` |
| `scripts/world/BanditGroupIntel.gd` | 7 | 68 | `ALTO_ACOPLAMIENTO` |
| `scripts/components/AIComponent.gd` | 7 | 37 | `ALTO_ACOPLAMIENTO` |
| `scripts/gameplay/player.gd` | 7 | 21 | `ALTO_ACOPLAMIENTO` |
| `scripts/systems/FactionViabilitySystem.gd` | 7 | 14 | `ALTO_ACOPLAMIENTO` |
| `scripts/world/BanditBehaviorLayer.gd` | 6 | 43 | `ALTO_ACOPLAMIENTO` |
| `scripts/systems/DownedEncounterCoordinator.gd` | 6 | 20 | `ALTO_ACOPLAMIENTO` |
| `scripts/placeables/WorkbenchComponent.gd` | 6 | 12 | `ALTO_ACOPLAMIENTO` |

## Detalle por módulo hotspot

### 1) `scripts/systems/SaveManager.gd`
- **Autoloads**: 13.
- **Frecuencia**: 68 (read: 62, write directo: 6).
- **Más usados**: `WorldSave` (30), `SaveManager` (5), `Debug` (4), `Seed` (4).
- **Necesarias (núcleo)**:
  - `WorldSave`, `Seed`, `RunClock`, `WorldTime`.
- **Conveniencia histórica (acoplamiento evitable)**:
  - `BanditGroupMemory`, `ExtortionQueue`, `FactionHostilityManager`, `FactionSystem`, `NpcProfileSystem`, `SiteSystem`, `PlacementSystem`, `Debug`.

### 2) `scripts/world/world.gd`
- **Autoloads**: 13.
- **Frecuencia**: 61 (read: 59, write directo: 2).
- **Más usados**: `Debug` (22), `SaveManager` (8), `BanditGroupMemory` (7), `PlacementSystem` (4), `WorldSave` (4).
- **Necesarias (núcleo)**:
  - `SaveManager`, `WorldSave`, `RunClock`, `Seed`.
- **Conveniencia histórica (acoplamiento evitable)**:
  - `Debug`, `BanditGroupMemory`, `RaidQueue`, `FactionSystem`, `FactionHostilityManager`, `NpcPathService`, `GameEvents`, `AudioSystem`, `PlacementSystem`.

### 3) `scripts/world/BanditGroupIntel.gd`
- **Autoloads**: 7.
- **Frecuencia**: 68 (read: 68, write directo: 0).
- **Más usados**: `BanditGroupMemory` (31), `FactionHostilityManager` (12), `Debug` (11), `RaidQueue` (9).
- **Necesarias (núcleo)**:
  - `BanditGroupMemory`, `FactionHostilityManager`, `RaidQueue`, `ExtortionQueue`.
- **Conveniencia histórica (acoplamiento evitable)**:
  - `Debug`, `NpcProfileSystem`, `RunClock`.

### 4) `scripts/world/NpcSimulator.gd`
- **Autoloads**: 8.
- **Frecuencia**: 39 (read: 39, write directo: 0).
- **Más usados**: `WorldSave` (14), `Debug` (7), `BanditGroupMemory` (6), `NpcProfileSystem` (5).
- **Necesarias**: `WorldSave`, `NpcProfileSystem`, `EnemyRegistry`.
- **Conveniencia histórica**: `Debug`, `BanditGroupMemory`, `RunClock`, `Seed`, `FactionViabilitySystem`.

### 5) `scripts/components/AIComponent.gd`
- **Autoloads**: 7.
- **Frecuencia**: 37 (read: 37, write directo: 0).
- **Más usados**: `RunClock` (12), `AwakeRampQueue` (7), `NpcPathService` (6), `AggroTrackerService` (4), `DownedEncounterCoordinator` (4).
- **Necesarias**: `NpcPathService`, `AggroTrackerService`, `AwakeRampQueue`.
- **Conveniencia histórica**: `RunClock`, `DownedEncounterCoordinator`, `FactionHostilityManager`, `Debug`.

### 6) `scripts/placeables/ContainerPlaceable.gd`
- **Autoloads**: 8.
- **Frecuencia**: 29 (read: 29, write directo: 0).
- **Más usados**: `UiManager` (9), `WorldSave` (5), `AudioSystem` (3), `DownedEncounterCoordinator` (3), `FactionHostilityManager` (3).
- **Necesarias**: `WorldSave`, `UiManager`, `LootSystem`.
- **Conveniencia histórica**: `Debug`, `AudioSystem`, `DownedEncounterCoordinator`, `FactionHostilityManager`, `PlacementSystem`.

## Priorización — Top 3 hotspots para refactor inicial

1. **`scripts/systems/SaveManager.gd`**
   - Máximo acoplamiento (13 autoloads) y alto volumen de acceso (68).
   - Mezcla persistencia con consultas a dominios de facciones/raids/hostilidad.
2. **`scripts/world/world.gd`**
   - Máximo acoplamiento (13 autoloads) en módulo orquestador central.
   - Dependencia fuerte de `Debug` y de varios sistemas de dominio a la vez.
3. **`scripts/world/BanditGroupIntel.gd`**
   - Menos autoloads que los dos anteriores, pero frecuencia extrema (68) concentrada en memoria/hostilidad/colas.
   - Candidato ideal para separar en read-model + policy + command handlers.

## Recomendación de primer corte técnico

- **Fase A (rápida):** introducir interfaces locales (puertos) para `WorldSave`, `BanditGroupMemory`, `FactionHostilityManager` y `RaidQueue` en los Top 3.
- **Fase B:** reemplazar lecturas globales directas por inyección de dependencias en `_ready`/constructor.
- **Fase C:** mover `Debug` detrás de feature-flags de módulo para reducir dependencia transversal.
