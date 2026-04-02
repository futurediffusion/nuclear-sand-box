# Bandit Worker Regression Analysis (`5c434da` vs `dev`)

## Alcance y objetivo
Este documento define una lectura **accionable** de regresiones del loop worker bandido para ejecutar fixes en orden.

- Baseline solicitado: commit `5c434da` (**pipeline funcional**).
- Estado actual: rama `dev` (en este workspace, equivalente al estado actual de `work`/HEAD).
- Restricción: **no tocar raids/assault fuera del loop worker**, salvo dependencias directas de transición worker.

> Nota de trazabilidad: el commit `5c434da` no está presente en el historial local de este repositorio. La sección "antes" se arma con contrato funcional histórico del pipeline y señales de cambios posteriores verificables en commits disponibles.

---

## 1) Pipeline funcional en `5c434da` (baseline esperado)

Pipeline esperado (contrato estable de 7 etapas):

1. **acquire_resource**
   - Entrada: `RESOURCE_WATCH` + `_resource_node_id` válido.
   - Salida: `pending_mine_id != 0`.
2. **hit_resource**
   - Entrada: `pending_mine_id` listo para consumir.
   - Salida: hit exitoso o reintento de adquisición.
3. **drop_candidate**
   - Entrada: recurso golpeado y drop en mundo.
   - Salida: `pending_collect_id != 0`.
4. **pickup_intent**
   - Entrada: collect id válido + alcance al drop.
   - Salida: `cargo_manifest/cargo_count` > 0.
5. **cargo_loaded**
   - Entrada: carga en inventario worker.
   - Salida: intent explícito de `RETURN_HOME`.
6. **return_home**
   - Entrada: navegación de regreso activa.
   - Salida: llegada a home/deposit y flag de arribo consumible.
7. **deposit**
   - Entrada: cargo presente + deposit target resoluble.
   - Salida: `cargo_count == 0` y ciclo relanza a `acquire_resource` o patrol.

---

## 2) Pipeline actual en `dev`

Estado observado en código actual:

- El coordinador mantiene contrato explícito de etapas y ownership de transiciones.
- Se agregaron logs parseables (`bandit_pipeline`) por evento de etapa y guardas de pérdida de estado.
- El work loop fue movido a cadence lane dedicada (riesgo de starvation si cadence/config no corre).
- Se reforzó prioridad de `return_home` luego de pickup/cargo.
- Se endureció resolución de target de depósito y saneo de IDs inválidos.
- Las queries de pickup usan posición real de worker (no proxy/offset ambiguo).

---

## 3) Tabla de diferencias por etapa

| Tema | Antes (`5c434da`) | Ahora (`dev`) | Riesgo de regresión | Confianza |
|---|---|---|---|---|
| Cadencia del loop worker | Tick compartido/no dedicado | Lane dedicada para work loop | **Alto**: si la lane no se ejecuta/queda infra-frecuente, se frena todo el pipeline | Alta |
| Acquire → Hit (fuente de posición) | Query de proximidad potencialmente con origen no canónico | Query con posición de worker como source de verdad | Medio: diferencias de rango pueden cambiar candidatos válidos/invalidar mine intent | Alta |
| Hit → Drop candidate (índices de recurso) | Registro de recursos más inmediato | Registro espacial diferido tras posicionamiento final | Medio: ventana corta de “no visible en índice” puede atrasar pickup | Media |
| Drop/Pickup → Cargo | Recolección más permisiva, menor telemetría | Sweep + logs parseables + guardas de IDs | Bajo-Medio: mayor robustez, pero más early-reset puede ocultar causa raíz si no se monitorea | Alta |
| Cargo → Return home | Retorno no siempre priorizado tras pickup | Retorno priorizado explícitamente cuando hay cargo | Bajo: mejora funcional; riesgo si compite con intents externos | Alta |
| Return home → Deposit | Resolución de depósito menos robusta | Resolución harden + hooks de bloqueo | Medio: menos fallos silenciosos, pero expone bloqueos previos no tratados | Alta |
| Observabilidad del pipeline | Logs parciales/no estructurados | Eventos parseables por etapa (`BWC_PIPE`) | Bajo: mejora diagnóstico; riesgo solo de sobrecarga si se habilita en producción | Alta |

---

## 4) Hallazgos P0 (alta confianza) vs hipótesis

### P0 — Alta confianza (ejecutar primero)

1. **Starvation del worker loop por cadencia**
   - Síntoma: no avanza `acquire_resource -> hit_resource` de forma sostenida.
   - Evidencia: migración a lane dedicada + múltiples ajustes de coordinación de ticks.
   - Impacto: bloquea pipeline completo.

2. **Corte de ciclo por invalidación temprana de IDs (`pending_mine_id` / `pending_collect_id`)**
   - Síntoma: workers vuelven a adquirir recurso repetidamente sin completar ciclo.
   - Evidencia: guardas y saneos agresivos en coordinador.
   - Impacto: throughput de recolección cae a casi cero.

3. **Bloqueo en retorno/deposito con cargo presente**
   - Síntoma: `cargo_count > 0` persistente sin vaciado.
   - Evidencia: historial reciente endureciendo return-home y depósito.
   - Impacto: inventario worker se "atasca" y no reinicia ciclo.

### Hipótesis (validar con telemetría antes de fix profundo)

1. **Ventana de invisibilidad de drops por registro espacial diferido**
   - Posible efecto: pickup no encuentra candidato en primeros ticks tras spawn.

2. **Interferencia de intents de assault/raid en transición worker->return_home**
   - Posible efecto: oscilación entre estados sin depositar.

3. **Cambios de arma/ataque en `hit_resource` introducen reintentos extra**
   - Posible efecto: latencia adicional antes de generar drop.

---

## 5) Qué no tocar (guardrails)

- No modificar lógica global de **raids/assault** fuera del loop worker.
- Solo se permiten cambios en assault/raid cuando sean dependencia directa para:
  - `cargo_loaded -> return_home`, o
  - consumo de flags que destraban `deposit`.
- No cambiar balance/IA de combate como parte del fix de regresión worker.

---

## Backlog de fixes (orden recomendado, accionable)

> Objetivo de medición: **cada fix referencia una diferencia concreta de la tabla anterior**.

1. **Fix-01 (P0): Asegurar ejecución mínima de cadence lane worker**
   - Referencia diferencia: *Cadencia del loop worker*.
   - Acción: garantizar frecuencia/tick budget mínimo y alerta si lane cae por debajo de umbral.
   - DoD: eventos `resource_acquired` y `resource_hit` aparecen de forma continua por grupo activo.

2. **Fix-02 (P0): Telemetría de resets de IDs y causa de invalidación**
   - Referencia diferencia: *Acquire → Hit* y *Drop/Pickup → Cargo*.
   - Acción: loggear motivo estructurado de reset (`invalid_id`, `out_of_range`, `deleted_node`, etc.).
   - DoD: top-3 causas cuantificadas; caída del loop-break por invalidación.

3. **Fix-03 (P0): Watchdog de cargo estancado**
   - Referencia diferencia: *Cargo → Return home* y *Return home → Deposit*.
   - Acción: detectar `cargo_count > 0` por N ticks y forzar transición segura a depósito.
   - DoD: reducción de casos con cargo persistente sin depósito.

4. **Fix-04 (P1): Mitigación de ventana de índice espacial**
   - Referencia diferencia: *Hit → Drop candidate*.
   - Acción: reintento corto/backoff para búsqueda de drop post-hit antes de reset.
   - DoD: mejora en ratio `resource_hit -> pickup_intent`.

5. **Fix-05 (P1): Aislar dependencia assault solo en borde de retorno/deposito**
   - Referencia diferencia: *Cargo → Return home*.
   - Acción: prioridad explícita worker cuando hay cargo, sin tocar lógica de assault general.
   - DoD: no hay oscilación de estado con cargo cargado.

---

## Plan de validación por fix

- Métrica primaria por etapa: tasa de transición `etapa_n -> etapa_n+1`.
- Métrica de negocio: ciclos completos por worker (`deposit` exitoso) por minuto.
- Evidencia requerida por fix:
  - diff referenciado a una fila de la tabla,
  - telemetría antes/después,
  - verificación de no-regresión en raids/assault (solo smoke, sin cambios funcionales).

---

## Rollback

**N/A (documentación).**
