# AGENTS.MD — Guía de colaboración para **NUCLEAR SAND BOX** (Godot 4.4)

Este documento resume la estructura, escenas, scripts y convenciones del proyecto para que cualquier persona (o IA) pueda mantenerlo y extenderlo rápidamente.

---

## 1) 🧠 Descripción general del proyecto

### ¿Qué es?
**NUCLEAR SAND BOX** es un prototipo de juego 2D top-down en Godot 4.4 centrado en combate cuerpo a cuerpo: controlas un personaje con movimiento WASD, ataque con mouse, enemigos con IA táctica, sangre/partículas, knockback y pantalla de game over.

### Estructura principal de carpetas

- **`/scenes`**
  - Contiene las escenas jugables (`main.tscn`, `player.tscn`, `enemy.tscn`, `slash.tscn`, etc.).
  - También hay archivos temporales `*.tmp` generados por editor/autoguardado. No forman parte del flujo jugable.
  - Nota: existe un script dentro de esta carpeta (`scenes/enemy.gd`), usado por `enemy.tscn`.

- **`/scripts`**
  - Carpeta única de scripts GDScript del proyecto.
  - Organizada por dominio (`gameplay`, `camera`, `ui`, `fx`, `components`).

- **`/art/sprites`**
  - Sprites de personajes, arma, cursor y sangre.
  - `.import` son metadatos de importación de Godot.

- **`/art/Sounds`**
  - SFX de slash y de impacto.

- **Raíz (`project.godot`, `icon.svg`)**
  - Configuración de proyecto, InputMap, capas de colisión y ajustes de ventana/render.

### Grupos de scripts por responsabilidad

- **Core gameplay**: `scripts/gameplay/player.gd`, `scenes/enemy.gd`, `scripts/gameplay/slash.gd`.
- **Spawning/flujo de partida**: `scripts/gameplay/enemy_spawner.gd`, `scripts/gameplay/main.gd`.
- **Cámara/cursor**: `scripts/camera/camera.gd`, `scripts/ui/cursor_2d.gd`.
- **FX sangre**: `scripts/fx/blood_droplet.gd`, `scripts/fx/blood_burst.gd` (este último parece helper no conectado directamente en escenas actuales).

---

## 2) 🧱 Mapa de escenas

> Resumen de cada `.tscn` y sus nodos más relevantes.

### `scenes/main.tscn`
**Rol:** escena principal del juego.

Nodos clave:
- `Main (Node2D)` + script `scripts/gameplay/main.gd`: coordina Game Over y retry.
- `BackgroundLayer/ColorRect`: fondo de color.
- `Player` (instancia de `player.tscn`): protagonista.
- `MouseCursor` (instancia de `cursor_2d.tscn`): cursor custom.
- `Enemy` (instancia de `enemy.tscn`): enemigo inicial ya en mapa.
- `EnemySpawner` (instancia de `enemy_spawner.tscn`): spawner periódico.
- `UI/GameOverPanel` + botones (`RetryButton`, `QUIT`): interfaz de fin de partida (el botón quit no tiene lógica conectada actualmente).

### `scenes/player.tscn`
**Rol:** prefab del player.

Nodos clave:
- `Player (CharacterBody2D)` + script `scripts/gameplay/player.gd`.
- `AnimatedSprite2D`: animaciones `idle`, `walk`, `hurt`, `death`.
- `CollisionShape2D`: colisión del cuerpo.
- `WeaponPivot` + `WeaponSprite`: rotación visual del arma.
- `SlashSpawn (Marker2D)`: punto de spawn del ataque.
- `Camera2D` + script `scripts/camera/camera.gd`: look-ahead y shake.

### `scenes/enemy.tscn`
**Rol:** prefab de enemigo con IA.

Nodos clave:
- `Enemy (CharacterBody2D)` + script `scenes/enemy.gd`.
- `AnimatedSprite2D`: animaciones del goblin.
- `CollisionShape2D`: colisión del enemigo.
- `WeaponPivot` + `WeaponSprite`.
- `SlashSpawn`: punto de ataque melee.

### `scenes/enemy_spawner.tscn`
**Rol:** emisor de enemigos.

Nodos clave:
- `EnemySpawner (Node2D)` + script `scripts/gameplay/enemy_spawner.gd`.
- Exporta `enemy_scene`, `spawn_interval`, `max_enemies`, `spawn_radius`.

### `scenes/slash.tscn`
**Rol:** hitbox + animación + audio del corte.

Nodos clave:
- `Slash (Node2D)` + script `scripts/gameplay/slash.gd`.
- `Anim (AnimatedSprite2D)`: animación del golpe.
- `Hitbox (Area2D)` + `CollisionShape2D`: detección de impacto.
- `Sfx`, `ImpactSound` (AudioStreamPlayer2D): sonido de ataque y de impacto.

### `scenes/blood_burst.tscn`
**Rol:** explosión de sangre en GPU particles.

Nodos clave:
- `BloodBurst (GPUParticles2D)`: one-shot configurable.

### `scenes/blood_droplet.tscn`
**Rol:** gota física que “salpica” y se congela como mancha.

Nodos clave:
- `BloodDroplet (RigidBody2D)` + script `scripts/fx/blood_droplet.gd`.
- `CollisionShape2D`: detecta contacto para splat.
- `Sprite2D`: textura de sangre.

### `scenes/cursor_2d.tscn`
**Rol:** cursor visual 2D que sigue al mouse.

Nodos clave:
- `MouseCursor (Node2D)`.
- `Sprite2D` + script `scripts/ui/cursor_2d.gd` (el script está puesto en el hijo Sprite).

---

## 3) 📌 Lista de scripts principales

### `scripts/gameplay/player.gd`
- **Nodo:** `Player` (`scenes/player.tscn`).
- **Propósito:** movimiento, ataque, animaciones, daño/vida, muerte, knockback, blood FX y droplets.
- **Funciones clave:**
  - Movimiento con `Input.get_vector` (`move_left/right/up/down`) + aceleración/fricción.
  - Apuntado al mouse y swing alternado con offsets izquierda/derecha.
  - Spawneo de `slash.tscn` con `setup(&"player", self)`.
  - `take_damage()`, `apply_knockback()`, `die()`, sangre y droplets.

### `scenes/enemy.gd`
- **Nodo:** `Enemy` (`scenes/enemy.tscn`).
- **Propósito:** IA táctica + combate enemigo + daño/animaciones.
- **Funciones clave:**
  - Máquina de estados (`IDLE`, `PATROL`, `CHASE`, `COMBAT`, `RETREAT`, `CIRCLE`, `FEINT`).
  - Detección de player por grupo `player`.
  - Ataque con slash (`setup(&"enemy", self)`) y cooldown.
  - Hitstop sobre enemigo al recibir impacto (vía slash).

### `scripts/gameplay/slash.gd`
- **Nodo:** `Slash` (`scenes/slash.tscn`).
- **Propósito:** vida corta del golpe, ventana de hitbox, aplicación de daño y knockback.
- **Funciones clave:**
  - `setup(team, owner)` para friendly-fire filtering.
  - Configura `collision_mask` según equipo (`player` pega a layer Enemy; `enemy` pega a layer Player).
  - Evita múltiples hits al mismo target con `already_hit`.
  - Aplica `take_damage`, `apply_knockback`, y opcional `apply_hitstop`.

### `scripts/gameplay/enemy_spawner.gd`
- **Nodo:** `EnemySpawner`.
- **Propósito:** spawn periódico con límite de enemigos vivos.
- **Funciones clave:**
  - Timer creado por código.
  - Spawneo alrededor de radio configurable.
  - Contador decrementado al `tree_exited` del enemigo.

### `scripts/gameplay/main.gd`
- **Nodo:** `Main`.
- **Propósito:** estado de Game Over y reload de escena.
- **Funciones clave:**
  - `on_player_died()` pausa árbol y muestra panel.
  - `_on_retry_pressed()` reanuda y recarga escena.

### `scripts/camera/camera.gd`
- **Nodo:** `Camera2D` hijo del Player.
- **Propósito:** look-ahead hacia mouse + shake procedural.

### `scripts/ui/cursor_2d.gd`
- **Nodo usado:** `Sprite2D` dentro de `cursor_2d.tscn`.
- **Propósito:** ocultar cursor del SO y mover cursor visual a `get_global_mouse_position()`.

### `scripts/fx/blood_droplet.gd`
- **Nodo:** `BloodDroplet` (`RigidBody2D`).
- **Propósito:** al colisionar se congela como mancha, desactiva colisión y se limpia por tiempo.

### `scripts/fx/blood_burst.gd`
- **Nodo esperado:** no hay escena que lo use directamente hoy.
- **Propósito:** helper de spawn de partículas CPU (`_spawn_blood`).
- **Observación:** el juego actual usa `blood_burst.tscn` como `GPUParticles2D` directamente desde player/enemy.

---

## 4) 📦 Explicación de subsistemas

### Movimiento
- Player: locomoción con aceleración/fricción/turn speed sobre `CharacterBody2D.velocity`.
- Enemy: locomoción según estado de IA (persecución, circular, retirada).
- Cámara: offset dinámico al mouse + smoothing.

### Ataque / combate
- Input `attack` (click izquierdo) en player.
- El ataque crea un `Slash` con hitbox activa por `hitbox_active_time` y animación corta.
- Enemigo usa mismo prefab `Slash`, con team `enemy`.

### Partículas de sangre
- **Burst:** `blood_burst.tscn` (`GPUParticles2D`) instanciado en hit/death.
- **Droplets:** `blood_droplet.tscn` (`RigidBody2D`) usado por player para salpicaduras físicas.

### IA de enemigos
- Máquina de estados con timers tácticos:
  - Patrulla/espera fuera de rango,
  - Chase con predicción simple del movimiento del jugador,
  - Combat para mantener distancia ideal y atacar,
  - Retreat/circle/feint para variar comportamiento.

### Knockback / hit logic
- `slash.gd` calcula dirección desde atacante → objetivo.
- Llama `apply_knockback(force)` si existe en target.
- Objetivos amortiguan `knock_vel` con fricción (player y enemy).
- Hitstop opcional si target implementa `apply_hitstop()` (enemigo sí, player no).

---

## 5) 🛠 Convenciones de código

### Nombres de variables
- Proyecto usa **snake_case** para variables/funciones (`max_speed`, `take_damage`, `_physics_process`).
- Exportadas con `@export var ...` agrupadas por `@export_group("...")`.
- Recomendación: mantener comentarios por bloques (MOVIMIENTO, COMBATE, etc.) para legibilidad.

### Uso de grupos (`add_to_group`)
- Actualmente el player se registra en grupo `"player"` en `_ready()`.
- Enemy busca player con `get_nodes_in_group("player")`.
- Convención recomendada:
  - Agregar grupo en `_ready()` del actor raíz.
  - Usar nombre singular consistente (`"player"`, `"enemy"`, etc.).
  - No depender de rutas absolutas de nodos cuando puede usarse grupo.

### Conexiones de señales
- Predominio de conexiones por código:
  - `timer.timeout.connect(...)`
  - `button.pressed.connect(...)`
  - `hitbox.body_entered.connect(...)`
- Convención recomendada:
  - Conectar en `_ready()`.
  - Si hay lambdas, que sean cortas y solo para cleanup/simple callbacks.
  - Para lógica importante, preferir método dedicado (`_on_*`).

---

## 6) 📍 Cómo extender el proyecto

### Agregar nuevos enemigos
1. Duplicar `scenes/enemy.tscn` y ajustar sprite/animaciones/colisión.
2. Reutilizar `scenes/enemy.gd` o crear variante heredada (ej. `enemy_ranged.gd`).
3. Exponer stats vía `@export` para tunear desde inspector.
4. Asignar nuevo `enemy_scene` en `enemy_spawner.tscn` o crear spawners adicionales.

### Crear nuevas armas
1. Crear una nueva escena tipo ataque (ej. `slash_heavy.tscn`) con `Area2D` + animación.
2. Basarte en `scripts/gameplay/slash.gd` o derivar script (daño, knockback, tiempo activo, SFX).
3. En el actor que ataque, cambiar `slash_scene` exportado.
4. Mantener contrato mínimo de API:
   - `setup(team, owner)` para filtrar equipos.
   - Aplicar `take_damage/apply_knockback` solo si target tiene método.

### Crear nuevos efectos de sangre
1. Duplicar `blood_burst.tscn` y ajustar material (spread, velocidad, gravedad, escala).
2. O crear otra escena de droplet con física diferente.
3. Exponer PackedScene en actor (`blood_scene`, `droplet_scene`) para alternar variantes por enemigo/player.

---

## 7) 📚 Referencias rápidas

### Pasos para crear escenas reutilizables
1. Nodo raíz con tipo correcto (`CharacterBody2D`, `Node2D`, etc.).
2. Componentes internos (sprite, colisión, audio).
3. Script en el nodo raíz con variables `@export`.
4. Guardar en `scenes/` y exponer como `PackedScene` donde se instancia.

### Cómo hacer que un script sea reutilizable
- Evitar hardcode de paths a nodos externos.
- Usar API mínima clara (`setup`, `take_damage`, `apply_knockback`).
- Separar config (`@export`) de estado interno.
- Favorecer `has_method()` para interoperabilidad entre actores distintos.

### Tips específicos para Godot 4.4
- Usar tipado estático progresivo (`var x: Type`) para menos errores.
- Revisar layers/masks en `project.godot` y en cada `Area2D/PhysicsBody2D`.
- Si se usa `Engine.time_scale` (hitstop), siempre restaurar estado con cuidado.

---

## 8) 🧪 Tips para debugging

### Si no se ven partículas
- Confirmar que `blood_scene` está asignado en inspector (player/enemy).
- Revisar que `amount`, `one_shot` y `emitting` se setean al instanciar.
- Verificar `z_index`, escala global y cámara (puede estar fuera de pantalla).
- Probar con `print("spawn blood", global_position)` en `_spawn_blood`.

### Cómo usar `print`/`prints` con contexto
- Incluir prefijo de sistema:
  - `print("[PLAYER] hp=", hp)`
  - `print("[ENEMY AI] state=", current_state)`
- Loggear al entrar/salir de estados y al conectar señales para encontrar timing bugs.

### Cómo probar colisiones
- Activar **Debug > Visible Collision Shapes** en el editor.
- Verificar `collision_layer`/`collision_mask` de:
  - `Player` (layer Player),
  - `Enemy` (layer Enemy),
  - `Slash/Hitbox` (layer Attacks, mask dinámico por equipo).
- Si no hay impacto:
  - confirmar `hitbox.monitoring = true` durante ventana activa,
  - revisar que target implemente `take_damage`.

---

## Notas técnicas observadas durante la revisión

- Hay duplicación de bloques de knockback/move_and_slide en `scripts/gameplay/player.gd` dentro de `_physics_process`; conviene consolidarlo para evitar aplicar fuerzas dos veces por frame.
- Existen escenas `.tmp` en `scenes/`; ideal ignorarlas en control de versiones si no son necesarias.
- `scripts/fx/blood_burst.gd` usa `CPUParticles2D`, pero el pipeline activo de sangre utiliza `GPUParticles2D` (`blood_burst.tscn`).


---

## 9) ✅ Actualización del AGENTS.MD (estado actual del proyecto)

Esta sección agrega lo que hoy existe en el repo y no estaba explícito/centralizado en la versión inicial del documento.

### Nuevas piezas detectadas en arquitectura

- La raíz de scripts está unificada en **`/scripts`**, con subcarpetas por dominio.
- Se incorporó un componente reutilizable de vida:
  - `scripts/components/HealthComponent.gd`
- Se incorporaron scripts de UI/HUD en uso real:
  - `scripts/ui/hud.gd`
  - `scripts/ui/hearts.gd`
- Existe además un script alternativo/legacy de corazones:
  - `scripts/ui/hearts_ui.gd` (no cableado en `main.tscn` actual).

### Escenas y nodos que ahora forman parte del flujo principal

#### `scenes/main.tscn`
Además de lo ya documentado, hoy contiene:

- `UI/HUD` con script `scripts/ui/hud.gd`.
- `UI/HUD/StaminaBar2` como `TextureProgressBar` con texturas:
  - `stamina-under.png`
  - `stamina-over..png`
  - `stamina-progress.png`
- `UI/HUD/Control/Hearts` con script `scripts/ui/hearts.gd` y texturas:
  - `heart.png`
  - `heart-empty.png`

#### `scenes/player.tscn` y `scenes/enemy.tscn`
- Ambos incluyen nodo hijo `HealthComponent` con script `scripts/components/HealthComponent.gd`.
- Esto formaliza un patrón de composición para vida/daño y señales (`damaged`, `died`).

### Sistemas agregados/expandidos respecto a la primera versión

#### Sistema de salud por componente
- `HealthComponent` encapsula:
  - `max_hp`, `hp`, `armor`
  - `take_damage(amount)` con daño mínimo de 1
  - `heal(amount)`
  - señales `damaged(amount)` y `died`
- `player.gd` puede crear el componente en runtime si falta y se conecta a sus señales.
- `hearts.gd` se conecta al `HealthComponent` del player para reflejar vida en UI.

#### Sistema de stamina visible en HUD
- `player.gd` emite `stamina_changed(stamina, max_stamina)`.
- `hud.gd` busca player por grupo `"player"` y sincroniza `StaminaBar2`.
- El binding es robusto: si no existe player al inicio, reintenta en diferido.

### Script inventory actualizado (además de los ya descritos)

- `scripts/components/HealthComponent.gd` → componente reusable de HP/armor/señales.
- `scripts/ui/hud.gd` → controlador HUD de stamina.
- `scripts/ui/hearts.gd` → render y actualización de corazones por señales de daño/muerte.
- `scripts/ui/hearts_ui.gd` → implementación alternativa simple de corazones (`set_hearts`).

### Convenciones adicionales importantes

- **Asumir una sola carpeta de scripts (`/scripts`)** con subcarpetas por dominio.
- Cualquier refactor de nombres/rutas debe actualizar también `ext_resource` en escenas `.tscn`.

### Estado de assets UI (nuevo en comparación al enfoque inicial de solo combate)

- Hearts:
  - `art/sprites/heart.png`
  - `art/sprites/heart-empty.png`
- Stamina:
  - `art/sprites/stamina-under.png`
  - `art/sprites/stamina-over..png`
  - `art/sprites/stamina-progress.png`

### Riesgos actuales a tener en cuenta

- Persisten múltiples `.tmp` en `scenes/`.
- Se mantiene coexistencia entre scripts usados y scripts alternativos no conectados (ej. `hearts_ui.gd`, `blood_burst.gd` helper).
- El botón `QUIT` del panel de game over sigue sin lógica conectada.

---

## 10) 🆕 Cambios recientes pendientes de registro (post actualización anterior)

Esta sección documenta cambios introducidos después de la última actualización grande del AGENTS (la de HUD/Health), para dejar trazabilidad de arquitectura vigente.

### 10.1 Autoload de sistema global

- Se agregó **`GameManager`** como singleton en `project.godot`:
  - `[autoload] GameManager="*res://scripts/systems/game_manager.gd"`
- `GameManager` centraliza señales/eventos globales del run actual:
  - `player_died`
  - `player_healed(amount)`
  - `zone_entered(zone_name)`
- También expone estado global inicial (`current_wave`, `gold`) para futura progresión.

### 10.2 Flujo de Game Over desacoplado vía manager

- `scripts/gameplay/main.gd` ahora escucha `GameManager.player_died` en `_ready()`.
- Al recibir señal:
  - muestra `UI/GameOverPanel`
  - pausa el árbol (`get_tree().paused = true`)
  - fuerza cursor visible.
- Se mantiene método de compatibilidad `on_player_died()` que redirige al nuevo flujo basado en manager.

### 10.3 Datos de mundo formalizados en Resource

- Se añadió `scripts/resources/WorldData.gd` (`class_name WorldData`, `extends Resource`).
- `main.gd` exporta:
  - `world_data`
  - `world_map_size`
  - `default_tavern_position`
- En `_ready()`, `main.gd` ejecuta `_ensure_world_data()` para garantizar inicialización.
- `WorldData` encapsula:
  - tamaño de mapa (`map_size`)
  - posición de taberna (`tavern_position`)
  - tiles (`tile_ids`) y nodos de recurso (`resource_nodes`)
  - helpers `set_tile/get_tile` y `set_resource_amount/get_resource_amount`.

### 10.4 Stamina separada a componente reusable

- Se agregó `scripts/components/StaminaComponent.gd`.
- Responsabilidades del componente:
  - stamina máxima/actual
  - costo por ataque
  - regeneración en `_physics_process`
  - API reusable:
    - `can_attack()`
    - `spend_attack_cost()`
    - `get_current_stamina()`
    - `get_max_stamina()`
  - señal `stamina_changed(current_stamina, max_stamina)`.

### 10.5 Integración del Player con componentes Health + Stamina

- `player.gd` ahora pre-carga ambos componentes:
  - `HealthComponent.gd`
  - `StaminaComponent.gd`
- Si faltan en la escena, el player puede crearlos runtime (`_setup_health_component`, `_setup_stamina_component`).
- La UI de stamina se alimenta por forwarding de señal:
  - componente `stamina_changed` → player `stamina_changed`.
- La lógica de ataque consulta/gasta stamina mediante el componente (sin depender de variables inline de stamina en `player.gd`).

### 10.6 Convenciones nuevas a respetar

- **Eventos globales de partida**: priorizar señales del `GameManager` (autoload) para evitar acoplamiento directo entre escenas.
- **Estado de mundo persistible**: usar `WorldData` como contenedor único para mapa/tiles/recursos y pasar este recurso entre sistemas.
- **Recursos jugables reutilizables**: preferir componentes (`HealthComponent`, `StaminaComponent`) frente a duplicar lógica en actores.

### 10.7 Sistema mínimo de Inventario + Monedas (MVP sin UI)

- Se añadió `scripts/components/InventoryComponent.gd` como componente reusable (`Node`) para economía base.
- Estado encapsulado:
  - `gold: int`
  - `items: Dictionary` (`item_id -> cantidad`)
- API genérica implementada para loop minar/vender/comprar:
  - `add_item`, `remove_item`, `get_count`, `sell_item`, `sell_all`, `buy_item`, `debug_print`.
- Reglas clave:
  - Sin hardcode de recursos (ej. `"copper"` se maneja como `item_id` string).
  - Upgrades quedan fuera del inventario (se tratarán en otro sistema).
  - Flujo de prueba por `print()` sin UI.
- Integración en `scripts/gameplay/player.gd`:
  - preload del nuevo componente y creación runtime si falta como hijo `InventoryComponent`.
  - hotkeys de test en `_input`:
    - `KEY_1`: `add_item("copper", 3)`
    - `KEY_2`: `sell_all("copper", 5)`
    - `KEY_3`: `buy_item("medkit", 1, 20)`
    - `KEY_4`: cheat `gold += 50`
  - tras cada acción se llama `inventory.debug_print()`.
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

