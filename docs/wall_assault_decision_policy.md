# Wall assault decision catalog (estado actual)

## Owner canónico

- **Owner elegido:** `BanditWallAssaultPolicy` (`scripts/world/BanditWallAssaultPolicy.gd`).
- **Responsabilidad:** decidir si se puede emitir/ejecutar ataque a walls y cuál es el objetivo estructural (wall/placeable) sin que capas consumidoras redecidan intención.

## Puntos que disparan o bloquean ataque a walls

### 1) Raid / structure assault (ejecución táctica)

Consumidor: `BanditWorkCoordinator._handle_structure_assault`.

Ahora delega a `BanditWallAssaultPolicy.evaluate_structure_directive`:

- Bloqueos:
  - mundo no disponible,
  - sin contexto de raid (`assault_active` / `intent == raiding` / react lock),
  - cooldown de ataque activo,
  - NPC fuera de radio de engage del ancla de asalto.
- Disparadores:
  - target estructural resoluble por prioridad (placeable vs wall por distancia),
  - fallback local a wall válida si no hay target estructural.

### 2) Oportunista individual a walls (no raid)

Consumidor: `BanditWorldBehavior._try_opportunistic_wall_assault`.

Ahora delega a `BanditWallAssaultPolicy.evaluate_opportunistic_wall_order`:

- Bloqueos:
  - cooldown personal activo,
  - hostilidad < 6,
  - gate probabilístico fallido,
  - callback de búsqueda de wall ausente,
  - no se encontró wall válida.
- Disparadores:
  - hostilidad suficiente + roll exitoso + wall cercana válida.

### 3) Sabotaje de propiedad (workbench/storage) que reutiliza flujo de wall assault

Consumidor: `BanditWorldBehavior._try_property_sabotage`.

Ahora delega a `BanditWallAssaultPolicy.evaluate_property_sabotage_order`:

- Bloqueos:
  - cooldown personal activo,
  - hostilidad < 7,
  - gate probabilístico fallido,
  - sin target de workbench/storage válido.
- Disparadores:
  - hostilidad y probabilidad habilitan target, con prioridad por distancia entre workbench/storage.

## Reglas consolidadas en una sola policy

`BanditWallAssaultPolicy` concentra reglas de:

- distancia (engage, búsqueda, strike local),
- hostilidad mínima por modo,
- prioridad de target (placeable vs wall),
- cooldown (raid y oportunista/sabotaje),
- contexto de raid.

## Verificación de rutas alternativas

- `BanditWorkCoordinator` ya no resuelve target estructural internamente ni corrige con rutas paralelas posteriores.
- La decisión táctica se toma en la policy y el coordinador **solo ejecuta** la directiva (`kind`, `pos`, `next_attack_at`).
- Se removieron rutas internas de re-decisión de target (`_resolve_structure_attack_target`) y strikes locales fuera de la policy.
