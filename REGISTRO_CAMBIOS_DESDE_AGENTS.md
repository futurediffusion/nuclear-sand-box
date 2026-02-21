# Registro de cambios desde la última actualización de `AGENTS.MD`

Fecha de corte usada: último commit que modificó `AGENTS.MD`.

- **Commit de referencia (última actualización de AGENTS):** `f8d6a2f` — *Add reusable inventory component and player debug hotkeys* (2026-02-17).
- **Rango auditado:** `f8d6a2f..HEAD`.

## Resumen ejecutivo

Después de la última actualización de `AGENTS.MD`, el proyecto evolucionó principalmente en 3 frentes:

1. **Combate defensivo del player** (bloqueo con stamina y cono de bloqueo).
2. **Sistema de mundo por chunks** (streaming, generación y persistencia de entidades).
3. **Nuevo contenido de mundo/minería** (cobre, campamentos bandido, tiles y audio de minado).

---

## Cambios por commit (semi breve)

### `55c6f1a` — Add stamina-based blocking behavior to player
- Se añadió el **bloqueo** al jugador dentro de `player.gd`.
- El bloqueo consume/depende de stamina e introduce lógica defensiva directa en combate.
- Impacto: mejora supervivencia del player y abre decisiones tácticas (atacar vs bloquear).

Archivos:
- `scripts/gameplay/player.gd`

### `d496823` — Sistema de bloqueo con cono + ajuste stamina
- Se refinó el sistema de bloqueo con **cono frontal** (bloqueo direccional).
- Se ajustó la integración con stamina y la configuración de input/proyecto.
- También hubo ajustes en escenas principales (`main`, `player`) y metadatos `.uid`.
- Impacto: defensa más precisa y menos “bloqueo universal 360°”.

Archivos principales:
- `project.godot`
- `scenes/main.tscn`
- `scenes/player.tscn`
- `scripts/components/StaminaComponent.gd`
- `scripts/gameplay/player.gd`

### `a193bd0` — world + chunk system + copper + bandit camps working
- Se incorporó el núcleo del **mundo por chunks** (`scripts/world/world.gd`).
- Se agregaron recursos/minería de **cobre** y escena/scripts asociados.
- Se agregaron **campamentos de bandidos** con escena/script dedicados.
- Se incorporaron nuevos assets visuales/sonoros (tiles, sprites, audio de minado).
- Impacto: salto de prototipo de combate a loop de exploración/recolección en mundo más grande.

Archivos principales:
- `scripts/world/world.gd`
- `scripts/resources/copper_ore.gd`
- `scripts/world/bandit_camp.gd`
- `scenes/copper_ore.tscn`
- `scenes/bandit_camp.tscn`
- `art/tiles/terrain.tres`
- `art/Sounds/mining.ogg`

### `eec0ffa` — Implement chunk entity save/load persistence
- Se añadió **persistencia de entidades por chunk** (guardar/cargar estado).
- Reduce pérdida de estado al salir/entrar de chunks.
- Impacto: mundo más consistente durante la sesión y base para guardado más completo.

Archivos:
- `scripts/world/world.gd`

### `66be7c9` — Improve world chunk streaming performance
- Se optimizó el **streaming de chunks** para reducir lag/microcortes.
- Ajustes adicionales en `player.gd` y `blood_droplet.gd` para acompañar rendimiento/flujo.
- Impacto: experiencia más fluida en desplazamiento por mapa.

Archivos:
- `scripts/world/world.gd`
- `scripts/gameplay/player.gd`
- `scripts/fx/blood_droplet.gd`

---

## Commits de merge en el rango (trazabilidad)

- `d233b34` — Merge PR #19 (inventory)
- `d551f45` — Merge PR #20 (blocking)
- `4b75ebf` — Merge PR #21 (chunk save/load)
- `ee36bc9` — Merge PR #22 (lag fixes world)

> Nota: estos commits consolidan ramas/PRs; los cambios técnicos están reflejados arriba en los commits funcionales.

---

## Conclusión rápida

Desde la última actualización de `AGENTS.MD`, el proyecto pasó de mejoras de combate local a una fase más de **mundo sistémico**:
- defensa del player más avanzada,
- loop de minería/contenido de mundo,
- arquitectura de chunks con persistencia y optimización de rendimiento.
