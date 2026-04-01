# Migraciones de decisión fuera de autoloads

Fecha: 2026-04-01.

## 1) `ExtortionQueue.is_request_available` → `BanditGroupIntel` (owner de presión social)

- **Antes:** el autoload `ExtortionQueue` decidía disponibilidad de cooldown con `is_request_available(group_id, cooldown)`.
- **Después:** la decisión quedó en `BanditGroupIntel` usando puerto `extortion_queue_port` + helper local `_cooldown_remaining(...)`.
- **Razón arquitectónica:** el autoload queda como almacenamiento/infra de cola y timestamps; la política de *si corresponde extorsionar ahora* pertenece al coordinador de dominio que evalúa contexto (compliance, wealth, score e intent).

## 2) `RaidQueue.is_raid_available` → `BanditGroupIntel` (owner de raids)

- **Antes:** `RaidQueue` exponía `is_raid_available(group_id, cooldown)` y la regla se resolvía en el singleton global.
- **Después:** `BanditGroupIntel` consulta `get_last_raid_time` por puerto `raid_queue_port` y calcula localmente el cooldown restante.
- **Razón arquitectónica:** la elegibilidad de raid es decisión táctica de dominio (depende de nivel de hostilidad y riqueza); el autoload solo provee estado y operaciones de cola.

## 3) `RaidQueue.is_wall_probe_available` → `BanditGroupIntel` (owner de probes)

- **Antes:** el autoload decidía si el probe estaba habilitado vía `is_wall_probe_available(group_id, cooldown)`.
- **Después:** `BanditGroupIntel` usa `get_last_wall_probe_time` vía puerto y aplica el gating en su política local.
- **Razón arquitectónica:** la decisión se integra con otros guards del owner (intent actual, pending work, probabilidad, configuración por nivel), evitando reglas de negocio distribuidas en globales.

## 4) `DownedEncounterCoordinator` verdict/loot → `AIComponent` (owner de combate NPC)

- **Antes:** el autoload `DownedEncounterCoordinator` resolvía el veredicto (`SPARE/FINISH`), calculaba chance por hostilidad y ejecutaba el saqueo del player KO.
- **Después:** `AIComponent` resuelve el veredicto cuando detecta un target downed y persiste el resultado en el coordinador vía `resolve_session(encounter_key, resolution)`.
- **Razón arquitectónica:** la semántica de combate KO (rematar o no, y consecuencias inmediatas) pertenece al owner de dominio de combate del actor (`AIComponent`). El autoload queda como **infra compartida** de sesión/participantes + acceso controlado (`force_spare_for`, `is_force_spare_active`).

## Cambios de integración (puertos)

- `world.gd` ahora inyecta `extortion_queue_port` y `raid_queue_port` al setup de `BanditGroupIntel`.
- `BanditBehaviorLayer.gd` propaga esos puertos al owner.
- `BanditGroupIntel.gd` reemplaza invocaciones directas a `ExtortionQueue`/`RaidQueue` por `_queue_call(...)` contra puertos.

Con esto, los autoloads quedan orientados a **registro/servicio/infraestructura** y no a decisión de negocio.

## 5) Cooldowns de `ExtortionQueue`/`RaidQueue` → `BanditGroupIntel` (owner táctico)

- **Antes:** los autoloads exponían helpers decisionales (`get_cooldown_remaining`, `get_raid_cooldown_remaining`, `get_wall_probe_cooldown_remaining`) que resolvían elegibilidad temporal.
- **Después:** `BanditGroupIntel` consume solo timestamps (`get_last_request_time`, `get_last_raid_time`, `get_last_wall_probe_time`) vía puertos y calcula cooldown local con `_cooldown_remaining(...)`.
- **Razón arquitectónica:** la ventana temporal de acciones (extorsión/raid/probe) forma parte de la política táctica del owner; los autoloads quedan como storage de estado de cola + telemetría.

## 6) Reacción a construcción (`world.gd`) usando contrato de cola (sin tentáculo directo)

- **Antes:** `_trigger_placement_react` accedía `RaidQueue` de forma directa (`has_structure_assault_for_group`, `enqueue_structure_assault`).
- **Después:** `world.gd` inicializa `_raid_queue_port` y `_extortion_queue_port` y usa esos contratos para wiring con `BanditGroupIntel` y para la reacción a construcción.
- **Razón arquitectónica:** el consumidor deja de depender del singleton global concreto y opera con un puerto explícito, reduciendo acoplamiento y preparando inyección de dobles de prueba.
