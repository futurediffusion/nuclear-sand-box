# Política de side effects prohibidos por dominio

Este documento define **side effects estrictamente prohibidos** para cada dominio crítico del juego, enlazados a su owner de soberanía en `docs/sovereignty-map.md`. Su objetivo es bloquear mutaciones laterales y facilitar revisiones de PR.

## Referencia de owners (fuente de soberanía)

- Tiempo del mundo → **`WorldTime`**.
- Bandit AI → **`BanditGroupMemory`**.
- Territorialidad / hostilidad → **`FactionHostilityManager`**.
- Coerción bandida (extorsión e incursión) → **`ExtortionFlow` / `RaidFlow`** (en transición hacia coordinador único).
- Botín e inventario → **`ItemDrop`** (runtime de drop) y frontera hacia **`InventoryComponent`**.
- Construcción y estructuras → **`PlacementSystem`**.
- Pathing → **`NpcPathService`**.
- World save / persistencia → **`SaveManager` + `WorldSave`**.
- Telemetry / debug → **`EventLogger`**.

> Nota: los owners y conflictos vigentes salen de `docs/sovereignty-map.md`; este documento **no los reemplaza**, los operacionaliza como política de PR.

---

## 1) Tiempo del mundo (owner: `WorldTime`)

### Side effects estrictamente prohibidos

- Mutar hostilidad de facciones (no escribir en `FactionHostilityManager`).
- Encolar extorsiones/raids directamente.
- Escribir inventarios, oro o economía.

### Violaciones típicas (red flags en PR)

- Handler de `day_passed` que aumenta hostilidad “por conveniencia”.
- Tick de tiempo que crea jobs en `ExtortionQueue`/`RaidQueue` sin policy explícita.
- Ajuste de loot diario directamente desde `WorldTime`.

---

## 2) Bandit AI (owner: `BanditGroupMemory`)

### Side effects estrictamente prohibidos

- Escribir hostilidad global directamente (debe pasar por flujos/políticas).
- Mutar `WorldSave` estructural en caliente.
- Resolver persistencia de mundo o reglas económicas finales.

### Violaciones típicas (red flags en PR)

- Nodo de comportamiento que llama directo a `FactionHostilityManager.add_points(...)`.
- Capa táctica que serializa estado de mundo para “checkpoint rápido”.
- AI que decide recompensas económicas finales sin pasar por dominio económico/inventario.

---

## 3) Territorialidad / hostilidad (owner: `FactionHostilityManager`)

### Side effects estrictamente prohibidos

- Spawn/despawn directo de entidades.
- Mutación de inventario o gold del jugador.
- Escritura de colas de raid/extorsión sin mediación de política de coerción.

### Violaciones típicas (red flags en PR)

- Subida de nivel de hostilidad que instancia bandits inmediatamente.
- Decay diario que retira recursos del inventario del player.
- Cambio de hostilidad que mete jobs en cola “para ahorrar un paso”.

---

## 4) Coerción bandida (owners: `ExtortionFlow` / `RaidFlow`)

### Side effects estrictamente prohibidos

- Alterar sistema de placement/estructuras directamente.
- Persistir estado fuera de colas/flows autorizados.
- Editar reglas de pathing o cachés de navegación.

### Violaciones típicas (red flags en PR)

- Resolución de extorsión que destruye walls llamando APIs de construcción.
- `RaidFlow` escribiendo snapshots en `WorldSave` por fuera de `SaveManager`.
- Flow de encounter que altera pesos o bloqueos de `NpcPathService` en runtime.

---

## 5) Botín e inventario (owner de runtime: `ItemDrop`; owner final de inventario: `InventoryComponent`)

### Side effects estrictamente prohibidos

- Escribir hostilidad de facción.
- Encolar raids/extorsión.
- Modificar estructuras de paredes/placeables.

### Violaciones típicas (red flags en PR)

- Pickup de ítem que reduce hostilidad de facción como “bonus oculto”.
- Loot raro que dispara una incursión directo en `RaidQueue`.
- Item magnet que abre huecos de pared al recoger materiales.

---

## 6) Construcción y estructuras (owner: `PlacementSystem`)

### Side effects estrictamente prohibidos

- Cambiar niveles de facción directamente.
- Manipular colas de raids/extorsión.
- Alterar path service global fuera de contrato (solo emitir cambios estructurales y dejar recálculo al dominio de pathing).

### Violaciones típicas (red flags en PR)

- Colocar una pared aumenta hostilidad de facción en el mismo método.
- Remover estructura crea una extorsión directa en cola.
- Builder tool parchea manualmente nodos internos de `NpcPathService`.

---

## 7) Pathing (owner: `NpcPathService`)

### Side effects estrictamente prohibidos

- Escribir inventario/oro.
- Modificar `FactionHostilityManager`.
- Spawn de entidades de juego.

### Violaciones típicas (red flags en PR)

- Fallo de ruta que cobra moneda por “penalización de recálculo”.
- Resultado de LOS que sube hostilidad de facción.
- Servicio de path que instancia NPCs bloqueados al no encontrar ruta.

---

## 8) World save / persistencia (owner: `SaveManager` + `WorldSave`)

### Side effects estrictamente prohibidos

- Decidir outcomes de combate/AI en runtime.
- Emitir hostilidad como regla de negocio.
- Resolver pickups en vivo durante serialización.

### Violaciones típicas (red flags en PR)

- Durante `load`, persistencia “corrige” resultados de pelea pendientes.
- `save()` que recalcula hostilidad territorial antes de escribir archivo.
- `SaveManager` otorgando ítems no confirmados para “reparar desync”.

---

## 9) Telemetry / debug (owner: `EventLogger`)

### Side effects estrictamente prohibidos

- Mutar estado de juego canónico (inventario, hostilidad, placement, pathing).
- Escribir persistencia operativa.
- Disparar decisiones de AI.

### Violaciones típicas (red flags en PR)

- Flag de debug que agrega recursos al inventario desde logger.
- Pipeline de telemetría que persiste snapshots como fuente de verdad.
- Hook de métricas que fuerza cambio de comportamiento de bandits.

---

## Checklist corta de revisión de PR

Usar esta checklist en cualquier cambio de sistemas:

- [ ] ¿Este cambio introduce un side effect prohibido para su dominio?
- [ ] ¿La mutación ocurre en el owner de soberanía correcto según `docs/sovereignty-map.md`?
- [ ] ¿Si cruza dominios, usa eventos/comandos explícitos en lugar de escrituras directas?
- [ ] ¿Se añadieron guardas/logs de violación de soberanía donde corresponde?

Si alguna respuesta es “no” o “no está claro”, el PR debe volver a diseño antes de merge.
