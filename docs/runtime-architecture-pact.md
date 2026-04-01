# Runtime Architecture Pact

## Estado del documento

- **Versión:** 1.0.0 (inicial)
- **Fecha de publicación:** 2026-04-01
- **Responsable técnico:** GPT-5.3-Codex

## Propósito

Este pacto define fronteras de autoridad en runtime para evitar duplicación de decisiones, efectos colaterales inesperados y ambigüedad entre capas.

## Prioridad normativa

Este pacto tiene **prioridad explícita** sobre convenciones previas ambiguas, implícitas o conflictivas.

Regla de resolución:

1. Si una convención previa coincide con este pacto, se mantiene.
2. Si una convención previa es ambigua, se interpreta según este pacto.
3. Si una convención previa entra en conflicto con este pacto, **prevalece este pacto**.

---

## Reglas del pacto

### 1) Comportamiento decide intención

**Regla:** la capa de comportamiento es la autoridad para decidir la intención de gameplay (qué quiere hacer el actor y por qué).

- ✅ **Ejemplo de cumplimiento:** `BehaviorLayer` evalúa contexto y selecciona `intent = RAID`, mientras que otras capas solo consumen esa intención.
- ❌ **Ejemplo de violación:** un sistema de persistencia o una cola de infraestructura recalcula y reemplaza la intención de `RAID` por `LOOT` durante ejecución.

### 2) Coordinación ejecuta interacción con mundo

**Regla:** la capa de coordinación orquesta ejecución (orden, llamadas, secuencia de side-effects), pero no redefine intención.

- ✅ **Ejemplo de cumplimiento:** `WorldCoordinator` recibe intención `EXTORT`, valida precondiciones técnicas y ejecuta spawn/movimiento/eventos.
- ❌ **Ejemplo de violación:** `WorldCoordinator` descarta una intención válida y decide otra nueva por criterio de negocio sin pasar por comportamiento.

### 3) Persistencia no decide gameplay

**Regla:** persistencia serializa/deserializa estado y provee almacenamiento; no decide reglas de negocio ni outcomes de runtime.

- ✅ **Ejemplo de cumplimiento:** `SaveManager` guarda `last_raid_time` y lo restaura sin modificar la política de elegibilidad de raid.
- ❌ **Ejemplo de violación:** durante `load`, `SaveManager` altera hostilidad o fuerza un encounter porque “parece conveniente”.

### 4) Debug/telemetry observa, no gobierna

**Regla:** debug y telemetría miden, registran y exponen señales; no gobiernan flujo de gameplay en producción.

- ✅ **Ejemplo de cumplimiento:** `DebugMetrics` registra duración de un ciclo y emite counters sin alterar decisiones.
- ❌ **Ejemplo de violación:** un flag de telemetría activa/desactiva lógica de combate o cambia prioridades tácticas fuera de un mecanismo formal de configuración de gameplay.

### 5) Cadence decide cuándo corre algo, no su semántica

**Regla:** cadence/scheduler define frecuencia, ventanas y orden temporal de ejecución; no define significado de negocio de lo ejecutado.

- ✅ **Ejemplo de cumplimiento:** `WorldCadenceCoordinator` ejecuta cada 0.5 s el chequeo de intents pendientes.
- ❌ **Ejemplo de violación:** `WorldCadenceCoordinator` decide que “si corre en tick impar entonces raid no aplica”, incorporando regla semántica de gameplay.

### 6) Spatial index responde consultas, no define verdad semántica

**Regla:** el índice espacial responde queries de proximidad/ocupación; no es fuente soberana de verdad semántica de dominio.

- ✅ **Ejemplo de cumplimiento:** `WorldSpatialIndex` responde entidades cercanas y el sistema dueño decide si son objetivo válido.
- ❌ **Ejemplo de violación:** `WorldSpatialIndex` etiqueta por sí mismo un actor como “enemigo legal” y dispara consecuencias de hostilidad.

---

## Criterios de cumplimiento operativo

- Toda regla de negocio nueva debe declarar owner de decisión (comportamiento) y owner de ejecución (coordinación).
- Cambios en persistencia, debug/telemetry, cadence o spatial index deben demostrar que no invaden soberanía semántica.
- En conflicto entre implementaciones heredadas y este pacto, se crea tarea de migración y se aplica este documento como referencia de arquitectura.

## Vigencia

Este pacto entra en vigor desde su fecha de publicación y aplica a cambios nuevos y refactors sobre runtime.
