# Contratos de Puertos por Dominio

## Objetivo
Este documento define los **puertos (interfaces de aplicación)** que deben consumir los sistemas del juego para interactuar con capacidades de runtime (tiempo, territorio, raids, loot, pathing, persistencia y telemetría) sin acoplarse a singletons concretos.

> Regla principal: el dominio depende de contratos estables; la infraestructura implementa esos contratos.

---

## Reglas globales de arquitectura

### R1. Dependencia por puerto, no por singleton concreto
Todo sistema consumidor debe depender de un puerto inyectado (`setup(ctx)` / constructor / propiedad tipada), no de acceso directo a un autoload específico.

- ✅ Válido: `raid_flow.setup({"world_time_port": world_time_port})`
- ❌ Inválido: `WorldTime.now_minutes()` desde cualquier consumidor de dominio.

### R2. Autoload sin lógica decisional de negocio
Los autoloads pueden actuar como:
- registro de estado,
- adaptador técnico,
- fachada de infraestructura.

Los autoloads **no** deben:
- decidir estrategias,
- resolver políticas de dominio,
- evaluar reglas de negocio de facciones/raids/extorsión/loot.

> Decidir *qué hacer* pertenece a servicios/sistemas de dominio; el autoload solo expone datos/operaciones del puerto.

### R3. Contratos explícitos de errores
Cada operación de puerto debe documentar fallas esperadas con códigos o etiquetas de error (`ERR_*`) para evitar `null` ambiguo y ramas implícitas.

### R4. I/O mínimo y estable
Entradas y salidas deben representarse con `Dictionary`/tipos primitivos estables, evitando exponer nodos concretos cuando no sea imprescindible.

---

## 1) Puerto de Tiempo (`ITimePort`)

### Responsabilidad
Proveer lectura del reloj de simulación y suscripción a eventos temporales.

### Operaciones permitidas
- `get_now_minutes() -> int`
- `get_now_seconds() -> float`
- `get_day_cycle_phase() -> String` (`"dawn" | "day" | "dusk" | "night"`)
- `subscribe_tick(listener: Callable) -> int` (retorna token)
- `unsubscribe_tick(token: int) -> void`

### Entrada / salida
- Entrada principal: `listener: Callable`.
- Salida principal: marcas de tiempo y fase de ciclo diario.

### Errores esperados
- `ERR_TIME_NOT_READY`: reloj aún no inicializado.
- `ERR_INVALID_SUBSCRIBER`: callable inválido o liberado.
- `ERR_SUBSCRIPTION_NOT_FOUND`: token inexistente.

---

## 2) Puerto de Territorio (`ITerritoryPort`)

### Responsabilidad
Consultar y registrar estado territorial (control, presencia, conflicto, zonas de interés).

### Operaciones permitidas
- `get_controller(tile: Vector2i) -> String` (facción/owner_id)
- `get_influence_at(world_pos: Vector2) -> Dictionary`
- `mark_claim(request: Dictionary) -> Dictionary`
- `mark_incident(incident: Dictionary) -> void`
- `list_hotspots(center: Vector2, radius: float) -> Array[Dictionary]`

### Entrada / salida
- `mark_claim(request)` entrada sugerida:
  - `{"faction_id": String, "center": Vector2, "radius": float, "reason": String}`
- `mark_claim` salida sugerida:
  - `{"accepted": bool, "claim_id": String, "conflicts": Array[String]}`

### Errores esperados
- `ERR_INVALID_FACTION`
- `ERR_OUT_OF_BOUNDS`
- `ERR_TERRITORY_LOCKED` (freeze/ventana protegida)
- `ERR_CONFLICT_UNRESOLVED`

---

## 3) Puerto de Raids (`IRaidPort`)

### Responsabilidad
Encolar, consultar y transicionar ciclos de raid sin exponer la cola concreta.

### Operaciones permitidas
- `enqueue_raid(intent: Dictionary) -> Dictionary`
- `cancel_raid(raid_id: String, reason: String) -> bool`
- `get_raid_state(raid_id: String) -> Dictionary`
- `list_pending_raids(filter: Dictionary = {}) -> Array[Dictionary]`
- `ack_raid_transition(raid_id: String, state: String, metadata: Dictionary = {}) -> void`

### Entrada / salida
- `intent` sugerido:
  - `{"group_id": String, "target_id": String, "trigger_kind": String, "severity": int, "world_pos": Vector2}`
- `enqueue_raid` salida sugerida:
  - `{"accepted": bool, "raid_id": String, "scheduled_at": float}`

### Errores esperados
- `ERR_DUPLICATE_PENDING`
- `ERR_RAID_CAP_REACHED`
- `ERR_INVALID_TRANSITION`
- `ERR_RAID_NOT_FOUND`

---

## 4) Puerto de Loot (`ILootPort`)

### Responsabilidad
Resolver drops y transferencias de botín con reglas de inventario/capacidad desacopladas del origen.

### Operaciones permitidas
- `roll_drop(context: Dictionary) -> Array[Dictionary]`
- `spawn_drop(drop: Dictionary, world_pos: Vector2) -> Dictionary`
- `collect_drop(drop_id: String, collector_id: String) -> Dictionary`
- `reserve_drop(drop_id: String, actor_id: String, ttl_seconds: float) -> bool`
- `release_drop(drop_id: String, actor_id: String) -> void`

### Entrada / salida
- `context` sugerido:
  - `{"source_kind": String, "source_id": String, "threat_level": int, "biome_id": int}`
- `collect_drop` salida sugerida:
  - `{"ok": bool, "transferred": Array[Dictionary], "rejected": Array[Dictionary]}`

### Errores esperados
- `ERR_DROP_NOT_FOUND`
- `ERR_DROP_RESERVED`
- `ERR_INVENTORY_FULL`
- `ERR_INVALID_COLLECTOR`

---

## 5) Puerto de Pathing (`IPathingPort`)

### Responsabilidad
Consultar navegación y validaciones espaciales sin acoplar a `NavigationServer`/servicio concreto.

### Operaciones permitidas
- `find_path(start: Vector2, goal: Vector2, options: Dictionary = {}) -> Dictionary`
- `is_reachable(start: Vector2, goal: Vector2, options: Dictionary = {}) -> bool`
- `sample_patrol_point(origin: Vector2, radius: float, options: Dictionary = {}) -> Vector2`
- `get_blockers_in_radius(center: Vector2, radius: float) -> Array[Dictionary]`

### Entrada / salida
- `find_path` salida sugerida:
  - `{"ok": bool, "points": PackedVector2Array, "cost": float, "partial": bool}`

### Errores esperados
- `ERR_NAV_NOT_READY`
- `ERR_NO_PATH`
- `ERR_INVALID_QUERY`
- `ERR_NAV_REGION_MISSING`

---

## 6) Puerto de Persistencia (`IPersistencePort`)

### Responsabilidad
Persistir y recuperar estado agregado por bounded-context (mundo, actores, estructuras, colas).

### Operaciones permitidas
- `save_snapshot(scope: String, payload: Dictionary) -> Dictionary`
- `load_snapshot(scope: String, key: String = "") -> Dictionary`
- `upsert_entity(scope: String, entity_id: String, data: Dictionary) -> void`
- `delete_entity(scope: String, entity_id: String) -> bool`
- `list_entities(scope: String, query: Dictionary = {}) -> Array[Dictionary]`

### Entrada / salida
- `save_snapshot` salida sugerida:
  - `{"ok": bool, "version": int, "saved_at": float}`
- `load_snapshot` salida sugerida:
  - `{"ok": bool, "version": int, "payload": Dictionary}`

### Errores esperados
- `ERR_SCOPE_UNKNOWN`
- `ERR_SERIALIZATION_FAILED`
- `ERR_VERSION_CONFLICT`
- `ERR_STORAGE_UNAVAILABLE`

---

## 7) Puerto de Telemetría (`ITelemetryPort`)

### Responsabilidad
Emitir eventos, métricas y trazas de forma uniforme, sin acoplar lógica de gameplay al backend de observabilidad.

### Operaciones permitidas
- `emit_event(name: String, attrs: Dictionary = {}) -> void`
- `increment(metric: String, value: float = 1.0, tags: Dictionary = {}) -> void`
- `gauge(metric: String, value: float, tags: Dictionary = {}) -> void`
- `timing(metric: String, ms: float, tags: Dictionary = {}) -> void`
- `flush() -> void`

### Entrada / salida
- Entrada: nombre semántico + atributos serializables.
- Salida: sin retorno funcional (fire-and-forget), salvo errores controlados.

### Errores esperados
- `ERR_TELEMETRY_DISABLED`
- `ERR_EVENT_REJECTED`
- `ERR_PAYLOAD_TOO_LARGE`

---

## Ejemplos de uso

### ✅ Uso correcto (dependencia por puerto)

```gdscript
# RaidFlow.gd
class_name RaidFlow

var _time_port
var _raid_port
var _telemetry_port

func setup(ctx: Dictionary) -> void:
	_time_port = ctx.get("time_port")
	_raid_port = ctx.get("raid_port")
	_telemetry_port = ctx.get("telemetry_port")

func request_raid(intent: Dictionary) -> Dictionary:
	intent["requested_at"] = _time_port.get_now_seconds()
	var result := _raid_port.enqueue_raid(intent)
	if result.get("accepted", false):
		_telemetry_port.emit_event("raid_enqueued", {"raid_id": result.get("raid_id", "")})
	return result
```

**Por qué es correcto:** el sistema consume contratos, no conoce ni nombra autoloads concretos.

### ❌ Uso tentáculo (acceso directo múltiple a globals)

```gdscript
# Anti-patrón
func request_raid(intent: Dictionary) -> Dictionary:
	intent["requested_at"] = WorldTime.get_now_seconds()
	if RaidQueue.has_pending_for_group(intent.get("group_id", "")):
		Debug.log("duplicate")
		return {"accepted": false}
	GameEvents.emit_signal("raid_requested", intent)
	WorldSave.last_raid_intent = intent
	return RaidQueue.enqueue(intent)
```

**Por qué es tentáculo:** mezcla negocio + infraestructura + estado global en una sola función, rompe testabilidad, sustituibilidad y control de errores.

---

## Checklist de cumplimiento para nuevos sistemas

- [ ] El sistema declara los puertos que consume en `setup(ctx)`.
- [ ] No accede directo a autoloads para decisiones de negocio.
- [ ] Cada operación maneja errores esperados del contrato.
- [ ] Los tests pueden inyectar dobles/mocks de cada puerto.
- [ ] La telemetría se emite vía `ITelemetryPort` (sin acoplar backend).

---

## Política de adopción incremental

1. Introducir puerto + adaptador del singleton actual.
2. Migrar consumidores críticos al puerto.
3. Eliminar accesos directos residuales a globals.
4. Agregar tests con dobles de puerto.
5. Recién entonces ajustar/retirar la implementación concreta previa.
