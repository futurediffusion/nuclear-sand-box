# Phase 7 — Cut 2 Exit Report

Fecha de corte: 2026-04-01.

Documento de contrato de este corte:
- `docs/phase-7-cut2-bandit-assault.md`

## 1) Publicación del corte

Se publica este reporte de salida para el **Cut 2 de Phase 7** con foco en:

1. eliminación de re-decisión en el pipeline de asalto de estructuras;
2. retiro de rutas alternativas silenciosas;
3. consolidación de ownership por etapa para el flujo de asalto;
4. confirmación de una sola ruta principal en runtime para `detectar -> atacar -> loot -> volver`;
5. listado de riesgos remanentes y shortlist mínimo para Cut 3.

---

## 2) Métricas del corte

### 2.1 Decisiones duplicadas eliminadas

| Métrica | Valor | Evidencia de cierre |
|---|---:|---|
| Tipos de re-decisión detectados en el contrato Cut 2 | 2 | `targeting`, `engage` estaban marcados como `DUP_DECISION_IN_PIPELINE` |
| Tipos de re-decisión eliminados en este corte | 2 | `canonical_target + consume_canonical_only=true` fuerza consumo canónico sin fallback de re-decisión |
| Eliminación neta | **100% (2/2)** | Ya no hay doble decisión entre Behavior/Coordinator/Policy para target de asalto |

### 2.2 Rutas alternativas retiradas

| Métrica | Valor | Evidencia de cierre |
|---|---:|---|
| Atajos silenciosos retirados | 2 | (a) re-decisión por fallback alternativo cuando se exige target canónico, (b) corrección tardía de retorno a campamento sin transición explícita |
| Rutas alternativas silenciosas activas en la ruta principal | 0 | Transiciones cerradas por handoff explícito (`attacked`, `container_looted`, cierre de raid) |

### 2.3 Owners consolidados

| Métrica | Valor | Owner canónico consolidado |
|---|---:|---|
| Etapas del flujo `detectar -> atacar -> loot -> volver` | 4 | Detectar/target canónico (`BanditWorldBehavior` + dispatch de grupo), atacar (`BanditWallAssaultPolicy` + `BanditWorkCoordinator`), loot (`BanditWorkCoordinator`), volver (`RaidFlow`/`force_return_home` por evento explícito) |
| Etapas con owner ambiguo en la ruta principal | 0 | No se deja promoción implícita de etapa por el ejecutor |

---

## 3) Confirmación de ruta principal única (`detectar -> atacar -> loot -> volver`)

### Resultado

**Confirmado**: el recorrido principal queda en una sola ruta canónica y en este orden:

1. **detectar** (`canonical_target` definido en handoff de ejecución);
2. **atacar** (gate canónico de `evaluate_structure_directive`);
3. **loot** (habilitado solo tras `breach_resolved` y dentro de rango);
4. **volver** (cierre de etapa y retorno por evento explícito: `container_looted`, fin de raid, timeout controlado).

### Reglas de integridad activas

- Si `consume_canonical_only=true`, el policy **no re-decide** por búsquedas alternativas.
- Si no hay brecha resuelta, **no se habilita loot**.
- El retorno no se activa como “arreglo por si acaso”; se activa por eventos declarados de cierre.

---

## 4) Riesgos remanentes y próximos ajustes mínimos

### Riesgos remanentes

1. **Doble gate de aproximación aún sensible a drift temporal**
   - Aunque la ruta principal está cerrada, persiste riesgo de desalineación entre timing de `RaidFlow` y evaluación táctica fina por NPC.
2. **Dependencia de calidad de `canonical_target`**
   - Si el target canónico envejece o queda stale, puede aumentar el ratio de `canonical_target_missing`.
3. **Acople parcial entre cierre de raid y feedback de comportamiento**
   - La ruta está explícita, pero aún depende de consistencia entre `RaidFlow._finish_raid` y consumo de feedback en comportamiento.
4. **Telemetría de cumplimiento aún mínima**
   - Falta un contador agregado de runs `mainline_compliant` vs `non_mainline_compliant` por grupo/raid.

### Próximos ajustes mínimos (sin rediseño)

1. Agregar métrica runtime por raid: `mainline_stage_entered[]` + `mainline_violation_count`.
2. Unificar códigos de razón de cierre (`reason_code`) entre Coordinator/Policy/RaidFlow.
3. Añadir guardrail de stale target: TTL corto para `canonical_target` previo a strike.
4. Incluir smoke test de transición obligatoria `breach -> loot -> return`.

---

## 5) Módulos candidatos para Cut 3

Priorizados por impacto y bajo riesgo de regresión:

1. `scripts/world/RaidFlow.gd`
   - Consolidar contrato de cierre y reason codes; reducir riesgo de drift en aproximación/ataque.
2. `scripts/world/BanditWorkCoordinator.gd`
   - Endurecer telemetría de handoff por etapa y auditoría de `stage_closed`.
3. `scripts/world/BanditWallAssaultPolicy.gd`
   - Formalizar TTL/validez de target canónico y códigos de rechazo estables.
4. `scripts/world/BanditWorldBehavior.gd`
   - Endurecer emisión de `canonical_target` y trazas de transición por intent.
5. `scripts/world/BanditBehaviorLayer.gd`
   - Instrumentar métricas agregadas de cumplimiento de ruta principal por grupo.
6. `scripts/tests/extortion_e2e_test.gd` (+ suite de runtime de world)
   - Incorporar prueba E2E específica de ruta única `detectar -> atacar -> loot -> volver`.

---

## 6) Criterio de salida del Cut 2

Cut 2 queda **cerrado** con estado:

- **Publicado** reporte de salida de corte.
- **Reportadas** métricas de de-duplicación, retiro de rutas alternativas y ownership consolidado.
- **Confirmada** una sola ruta principal para `detectar -> atacar -> loot -> volver`.
- **Listado** de riesgos remanentes y ajustes mínimos para continuidad.
- **Preparado** shortlist de módulos candidatos para Cut 3.

Estado final: **READY FOR CUT 3 PREP**.
