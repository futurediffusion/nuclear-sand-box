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

- **`/sripts`** (sic)
  - Carpeta de scripts GDScript del proyecto. El nombre está mal escrito intencionalmente en repo actual (`sripts` en lugar de `scripts`), por lo que **no renombrar sin migración completa de rutas**.
  - Incluye lógica de player, cámara, slash, spawner, partículas y UI principal.

- **`/art/sprites`**
  - Sprites de personajes, arma, cursor y sangre.
  - `.import` son metadatos de importación de Godot.

- **`/art/Sounds`**
  - SFX de slash y de impacto.

- **Raíz (`project.godot`, `icon.svg`)**
  - Configuración de proyecto, InputMap, capas de colisión y ajustes de ventana/render.

### Grupos de scripts por responsabilidad

- **Core gameplay**: `sripts/player.gd`, `scenes/enemy.gd`, `sripts/slash.gd`.
- **Spawning/flujo de partida**: `sripts/enemy_spawner.gd`, `sripts/main.gd`.
- **Cámara/cursor**: `sripts/camera.gd`, `sripts/Cursor2D.gd`.
- **FX sangre**: `sripts/blood_droplet.gd`, `sripts/blood_burst.gd` (este último parece helper no conectado directamente en escenas actuales).

---

## 2) 🧱 Mapa de escenas

> Resumen de cada `.tscn` y sus nodos más relevantes.

### `scenes/main.tscn`
**Rol:** escena principal del juego.

Nodos clave:
- `Main (Node2D)` + script `sripts/main.gd`: coordina Game Over y retry.
- `BackgroundLayer/ColorRect`: fondo de color.
- `Player` (instancia de `player.tscn`): protagonista.
- `MouseCursor` (instancia de `cursor_2d.tscn`): cursor custom.
- `Enemy` (instancia de `enemy.tscn`): enemigo inicial ya en mapa.
- `EnemySpawner` (instancia de `enemy_spawner.tscn`): spawner periódico.
- `UI/GameOverPanel` + botones (`RetryButton`, `QUIT`): interfaz de fin de partida (el botón quit no tiene lógica conectada actualmente).

### `scenes/player.tscn`
**Rol:** prefab del player.

Nodos clave:
- `Player (CharacterBody2D)` + script `sripts/player.gd`.
- `AnimatedSprite2D`: animaciones `idle`, `walk`, `hurt`, `death`.
- `CollisionShape2D`: colisión del cuerpo.
- `WeaponPivot` + `WeaponSprite`: rotación visual del arma.
- `SlashSpawn (Marker2D)`: punto de spawn del ataque.
- `Camera2D` + script `sripts/camera.gd`: look-ahead y shake.

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
- `EnemySpawner (Node2D)` + script `sripts/enemy_spawner.gd`.
- Exporta `enemy_scene`, `spawn_interval`, `max_enemies`, `spawn_radius`.

### `scenes/slash.tscn`
**Rol:** hitbox + animación + audio del corte.

Nodos clave:
- `Slash (Node2D)` + script `sripts/slash.gd`.
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
- `BloodDroplet (RigidBody2D)` + script `sripts/blood_droplet.gd`.
- `CollisionShape2D`: detecta contacto para splat.
- `Sprite2D`: textura de sangre.

### `scenes/cursor_2d.tscn`
**Rol:** cursor visual 2D que sigue al mouse.

Nodos clave:
- `MouseCursor (Node2D)`.
- `Sprite2D` + script `sripts/Cursor2D.gd` (el script está puesto en el hijo Sprite).

---

## 3) 📌 Lista de scripts principales

### `sripts/player.gd`
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

### `sripts/slash.gd`
- **Nodo:** `Slash` (`scenes/slash.tscn`).
- **Propósito:** vida corta del golpe, ventana de hitbox, aplicación de daño y knockback.
- **Funciones clave:**
  - `setup(team, owner)` para friendly-fire filtering.
  - Configura `collision_mask` según equipo (`player` pega a layer Enemy; `enemy` pega a layer Player).
  - Evita múltiples hits al mismo target con `already_hit`.
  - Aplica `take_damage`, `apply_knockback`, y opcional `apply_hitstop`.

### `sripts/enemy_spawner.gd`
- **Nodo:** `EnemySpawner`.
- **Propósito:** spawn periódico con límite de enemigos vivos.
- **Funciones clave:**
  - Timer creado por código.
  - Spawneo alrededor de radio configurable.
  - Contador decrementado al `tree_exited` del enemigo.

### `sripts/main.gd`
- **Nodo:** `Main`.
- **Propósito:** estado de Game Over y reload de escena.
- **Funciones clave:**
  - `on_player_died()` pausa árbol y muestra panel.
  - `_on_retry_pressed()` reanuda y recarga escena.

### `sripts/camera.gd`
- **Nodo:** `Camera2D` hijo del Player.
- **Propósito:** look-ahead hacia mouse + shake procedural.

### `sripts/Cursor2D.gd`
- **Nodo usado:** `Sprite2D` dentro de `cursor_2d.tscn`.
- **Propósito:** ocultar cursor del SO y mover cursor visual a `get_global_mouse_position()`.

### `sripts/blood_droplet.gd`
- **Nodo:** `BloodDroplet` (`RigidBody2D`).
- **Propósito:** al colisionar se congela como mancha, desactiva colisión y se limpia por tiempo.

### `sripts/blood_burst.gd`
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
2. Basarte en `sripts/slash.gd` o derivar script (daño, knockback, tiempo activo, SFX).
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

- Hay duplicación de bloques de knockback/move_and_slide en `sripts/player.gd` dentro de `_physics_process`; conviene consolidarlo para evitar aplicar fuerzas dos veces por frame.
- Existen escenas `.tmp` en `scenes/`; ideal ignorarlas en control de versiones si no son necesarias.
- `sripts/blood_burst.gd` usa `CPUParticles2D`, pero el pipeline activo de sangre utiliza `GPUParticles2D` (`blood_burst.tscn`).

