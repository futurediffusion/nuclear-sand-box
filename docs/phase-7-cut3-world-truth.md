# Phase 7 — Cut 3: World Truth Taxonomy

## Objetivo
Definir una taxonomía canónica y exclusiva para clasificar todos los datos del mundo, reduciendo ambigüedad de ownership y evitando que estructuras auxiliares se conviertan en fuente de verdad.

## Regla canónica (obligatoria)
Cada dato del mundo pertenece **a una sola categoría canónica**.

- No se permite doble pertenencia (`Save Truth + Cache`, por ejemplo).
- Si un dato parece pertenecer a varias, se debe elegir la categoría que define su autoridad semántica.
- Las demás representaciones del mismo dato se consideran derivaciones o aceleradores, nunca verdad paralela.

---

## 1) Runtime Truth
**Definición:** estado vivo y autoritativo durante ejecución.

### Quién puede escribir
- Sistemas soberanos de runtime del dominio correspondiente (p. ej. coordinadores de mundo/simulación en memoria).
- Lógica de juego que posee explícitamente la autoridad del dato en el frame actual.

### Quién solo lee
- UI, telemetría, debug, herramientas de observabilidad.
- Sistemas secundarios que reaccionan al estado, pero no lo gobiernan.

### Ciclo de vida
- Nace al inicializar sesión/escena o al activar un chunk.
- Cambia frame a frame según simulación e interacciones.
- Muere al cerrar sesión, descargar chunk o destruir entidad runtime.
- Puede exportarse a `Save Truth` mediante snapshot/serialización controlada.

---

## 2) Save Truth
**Definición:** estado persistible y restaurable.

### Quién puede escribir
- Capa de persistencia autorizada (adaptadores/repositorios de guardado).
- Flujos explícitos de save/load o checkpoints del dominio.

### Quién solo lee
- Sistemas de bootstrap/restauración.
- Runtime que consume estado al cargar chunks/entidades.
- Herramientas de inspección y migración.

### Ciclo de vida
- Nace al serializar verdad canónica desde runtime.
- Permanece fuera del loop de frame como registro persistente.
- Se versiona/migra cuando cambia el schema.
- Se consume para reconstruir `Runtime Truth` en restauración.

---

## 3) Derived Index
**Definición:** proyecciones calculadas desde verdad canónica.

### Quién puede escribir
- Constructores de índice/proyección autorizados.
- Jobs de recomputación incremental o batch derivados de `Runtime Truth` o `Save Truth`.

### Quién solo lee
- Consultas de gameplay, sistemas de búsqueda, validaciones rápidas.
- Herramientas que requieren lookup eficiente sin tocar la verdad base.

### Ciclo de vida
- Nace por cálculo determinista desde verdad canónica.
- Se invalida/reconstruye cuando cambia la verdad fuente.
- Puede descartarse y recomputarse sin pérdida de semántica del dominio.

---

## 4) Cache
**Definición:** aceleración temporal sin autoridad semántica.

### Quién puede escribir
- Capas de performance (memoization, pools, buffers temporales, cachés de consulta).
- Sistemas que optimizan latencia/costo, no significado de negocio.

### Quién solo lee
- Cualquier consumidor que acepte datos potencialmente stale.
- Sistemas que implementan fallback a verdad canónica ante miss/invalidez.

### Ciclo de vida
- Nace por demanda o warmup.
- Expira por TTL, presión de memoria o invalidación explícita.
- Puede borrarse en cualquier momento sin afectar integridad del dominio.

---

## Anti-regla explícita (innegociable)
**Los `Derived Index` y las `Cache` nunca se convierten en verdad de dominio.**

- No se promueve un índice/cache a fuente autoritativa por conveniencia.
- No se escribe `Save Truth` tomando como origen único un índice/cache no validado contra verdad canónica.
- Toda decisión semántica crítica debe resolver contra `Runtime Truth` o `Save Truth` (según contexto).

## Criterio operativo de resolución
Ante duda de clasificación, responder en orden:
1. ¿Este dato define el estado real del mundo ahora? → `Runtime Truth`.
2. ¿Este dato define el estado restaurable del mundo? → `Save Truth`.
3. ¿Este dato es una proyección derivada para consulta? → `Derived Index`.
4. ¿Este dato existe solo para acelerar acceso/cálculo? → `Cache`.
