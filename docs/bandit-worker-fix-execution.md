# Plan de ejecución: fix de worker bandido

Este documento define una ejecución por fases para estabilizar el pipeline de comportamiento de “bandit workers” (scavenger/bodyguard/leader en ciclos de detección, desplazamiento, interacción y retorno), con foco en trazabilidad por logs, criterios de aceptación y rollback seguro.

## Fase 1 — Instrumentación y línea base

### Problema actual por etapa
No existe suficiente visibilidad para distinguir si una falla ocurre en detección de señales, decisión de intención grupal, transición de estado del NPC o ejecución del movimiento/recolección.

### Cambios a aplicar
- Agregar logs estructurados con prefijo único (ej. `[BANDIT_FIX]`) en:
  - `BanditGroupIntel.tick()` y cálculo de score/intent.
  - `BanditWorldBehavior` al cambiar de estado.
  - `BanditBehaviorLayer._handle_collection()` y descarga de cargo en home.
- Incluir en cada log: `group_id`, `member_id`, `role`, `intent`, `state`, `chunk`, `pos`, `cycle_id`.
- Definir `cycle_id` incremental por grupo para correlacionar ciclo completo en múltiples ticks.

### Criterio de done
- Se puede reconstruir un ciclo completo por grupo (detección → acción → retorno) sólo leyendo logs.
- Todos los logs críticos contienen IDs de correlación (`group_id`, `member_id`, `cycle_id`).

### Riesgos
- Exceso de ruido y caída de rendimiento por logging.
- Duplicación de logs en paths de update muy frecuentes.

### Rollback
- Feature flag global (`bandit_fix_debug_logs=false`) para apagar instrumentación sin tocar la lógica.
- Revert de commits de observabilidad si impacta frame-time.

---

## Fase 2 — Corrección del gating de señales de interés

### Problema actual por etapa
Las señales de interés (markers/base detection) pueden llegar tarde, caducar antes de ser consumidas o no mapear correctamente al grupo líder, dejando workers en `IDLE/PATROL` cuando deberían entrar en `ALERTED/HUNTING`.

### Cambios a aplicar
- Alinear ventana temporal entre `SettlementIntel` y `BanditGroupIntel`:
  - Verificar TTL útil para markers temporales.
  - Confirmar que `SCAN_INTERVAL` no “saltea” eventos de corta vida.
- Registrar trigger seleccionado (`trigger_kind`) y score final por scan.
- Añadir guardas para “no downgrade prematuro” de intent (histeresis mínima de N scans o cooldown de salida).

### Criterio de done
- Ante actividad del jugador cerca del radio de interés, al menos 1 scan consecutivo mueve al grupo de `idle` a `alerted/hunting` según score esperado.
- No hay oscilación errática `hunting ↔ idle` en menos de dos scans sin causa.

### Riesgos
- Histeresis excesiva: grupos “pegados” en hunting.
- Cambios de score afectan balance global de agresividad.

### Rollback
- Mantener pesos y umbrales previos como preset alternativo.
- Parametrizar umbrales por constantes para restauración inmediata.

---

## Fase 3 — Normalización de máquina de estados de worker

### Problema actual por etapa
Transiciones ambiguas entre `APPROACH_INTEREST`, `FOLLOW_LEADER`, `RETURN_HOME`, `RESOURCE_WATCH` y estados de idle/patrulla provocan loops sin progreso o retorno incompleto.

### Cambios a aplicar
- Definir tabla explícita de transiciones válidas por `role`.
- Añadir timeout por estado para evitar estancamiento (con razón de salida logueada).
- Homogeneizar condiciones de “arrived” (distancia, tolerancia, cooldown de transición).
- Validar que `scout_npc_id` sólo afecte al NPC designado.

### Criterio de done
- Cada estado tiene entradas/salidas explícitas y medibles.
- No existen estados terminales sin salida salvo condiciones intencionales.
- En logs no aparecen más de X repeticiones de un mismo estado sin evento de progreso.

### Riesgos
- Cambiar la semántica de roles (bodyguard/scavenger) sin querer.
- Mayor complejidad de transición si no se centraliza la tabla.

### Rollback
- Mantener implementación anterior detrás de flag (`bandit_state_machine_v1`).
- Revert focalizado del archivo de behavior sin tocar intel.

---

## Fase 4 — Ejecución física y recolección/cargo

### Problema actual por etapa
El worker decide correctamente pero no materializa progreso físico (fricción, velocidad efectiva, obstáculos), o recolecta sin consolidar cargo/descarga coherente en home.

### Cambios a aplicar
- Ajustar compensación de fricción vs velocidad objetivo para estados de movimiento.
- Log de delta de posición por tick y razón de “no avance”.
- Validar flujo de cargo:
  - pickup incrementa `cargo_count`.
  - retorno a home descarga a 0.
- Incorporar detección de bloqueo simple (stuck counter) para forzar `RETURN_HOME` o repath simplificado.

### Criterio de done
- Workers en movimiento reducen distancia al objetivo de forma consistente.
- `cargo_count` nunca excede `cargo_capacity` y vuelve a 0 al descargar.
- No quedan NPCs activos en “approach” inmóviles por más de umbral definido.

### Riesgos
- Sobrecompensación de velocidad (movimiento antinatural).
- “Falsos stuck” en zonas estrechas.

### Rollback
- Restaurar constantes previas de velocidad/fricción.
- Desactivar stuck recovery por flag.

---

## Fase 5 — Robustez multi-NPC y concurrencia de grupos

### Problema actual por etapa
Con varios grupos/NPCs simultáneos aparecen condiciones de carrera lógicas: scouts duplicados, intents pisados, sobreconsumo de drops, o spam de extorsión.

### Cambios a aplicar
- Enforce de invariantes por grupo:
  - máximo 1 scout activo.
  - no encolar extorsión si existe pending/cooldown.
- Dedupe robusto de targets de interés por grupo y ciclo.
- Tests de stress con múltiples grupos dentro de radios solapados.
- Métricas agregadas por frame: grupos evaluados, cambios de intent, pickups, resets por stuck.

### Criterio de done
- Bajo carga (multi-grupo), se mantienen invariantes sin violaciones en logs.
- No hay explosión de eventos duplicados por ciclo.

### Riesgos
- Locks lógicos demasiado estrictos que reduzcan respuesta del sistema.
- Coste adicional de validación por frame/tick.

### Rollback
- Mantener chequeos de invariantes en modo warning-only.
- Deshabilitar dedupe extra si degrada comportamiento.

---

## Fase 6 — Hardening, release controlado y monitoreo post-fix

### Problema actual por etapa
Aunque el fix funcione en pruebas dirigidas, puede degradarse en sesiones largas o escenarios no cubiertos.

### Cambios a aplicar
- Activación gradual del fix (flag por entorno/perfil de test).
- Dashboard mínimo basado en logs: tasa de ciclos completos, stuck rate, tiempo medio de ciclo.
- Definir alertas operativas (ej. stuck rate > umbral durante N minutos).
- Congelar parámetros finales y documentar defaults de producción.

### Criterio de done
- Métricas estables durante sesiones prolongadas.
- Sin regresiones críticas en rendimiento ni comportamiento emergente.
- Configuración final versionada y documentada.

### Riesgos
- Observabilidad incompleta que oculte regresiones.
- Dependencia de logs sin herramientas de agregación suficientes.

### Rollback
- Rollback de feature flag a comportamiento previo.
- Mantener rama/tag de seguridad con versión estable anterior.

---

## Matriz breve — señal esperada en logs por transición clave

| Transición clave del pipeline | Señal esperada en logs |
|---|---|
| Marker/Base detectado → evaluación de grupo | `[BANDIT_FIX][INTEL_SCAN] group_id=<id> score=<n> markers=<n> bases=<n>` |
| Evaluación → cambio de intent | `[BANDIT_FIX][INTENT_CHANGE] group_id=<id> from=<idle> to=<alerted/hunting/extorting> reason=<score_trigger>` |
| Intent `alerted` → scout asignado | `[BANDIT_FIX][SCOUT_ASSIGN] group_id=<id> scout_npc_id=<id> role=<scavenger/bodyguard>` |
| Intent `hunting/extorting` → transición de estado leader | `[BANDIT_FIX][STATE_CHANGE] member_id=<id> role=leader from=<...> to=APPROACH_INTEREST target=<pos>` |
| Estado movimiento → progreso físico | `[BANDIT_FIX][MOVE_PROGRESS] member_id=<id> state=<...> dist_before=<x> dist_after=<y>` |
| Recolección drop → incremento cargo | `[BANDIT_FIX][PICKUP] member_id=<id> drop_id=<id> cargo=<k>/<cap>` |
| Return home → descarga | `[BANDIT_FIX][UNLOAD] member_id=<id> group_id=<id> cargo_before=<k> cargo_after=0` |
| Anti-spam extorsión activo | `[BANDIT_FIX][EXTORT_GUARD] group_id=<id> skipped=<pending|cooldown>` |
| Detección de stuck → recuperación | `[BANDIT_FIX][STUCK_RECOVERY] member_id=<id> state=<...> action=<return_home|repath>` |

---

## Validación global de aceptación del fix

Evidencia mínima obligatoria para aceptar el fix:

1. **Escenario multi-NPC real**
   - Al menos 3 grupos activos simultáneamente.
   - Cada grupo con leader + bodyguard + scavenger presentes y vivos durante la prueba.

2. **Múltiples ciclos completos por grupo**
   - Mínimo 3 ciclos completos por grupo, donde un ciclo completo =
     `detección interés → cambio intent → ejecución estado (approach/follow/watch) → (pickup opcional) → retorno home → descarga/reset`.

3. **Trazabilidad por logs**
   - Cada ciclo debe poder correlacionarse por `group_id` + `cycle_id`.
   - Sin huecos de transición crítica (no saltos invisibles entre intent/state).

4. **Invariantes funcionales**
   - No más de 1 scout activo por grupo en un mismo ciclo.
   - `cargo_count <= cargo_capacity` siempre.
   - No extorsión duplicada en ventana de cooldown.

5. **Estabilidad temporal**
   - Ejecución continua de al menos 15 minutos sin degradación crítica.
   - Stuck rate bajo umbral acordado (ej. < 5% de ticks de movimiento por NPC).

6. **No regresión perceptible**
   - Sin caída severa de rendimiento asociada al fix.
   - Comportamiento base de patrol/return conservado cuando no hay señales de interés.

Si alguno de los puntos falla, el fix no se considera aceptado y debe volver a fase de corrección correspondiente.
