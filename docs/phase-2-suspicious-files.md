# Phase 2 — Suspicious Files Scoring

## Escala de scoring (0–3 por señal)
- **0 = limpio**: complejidad baja, señal prácticamente ausente.
- **1 = leve**: señal presente pero acotada.
- **2 = alto**: señal frecuente o con impacto claro en mantenibilidad.
- **3 = crítico**: señal dominante; archivo candidato prioritario para refactor.

## Señales evaluadas
1. **tamaño**
2. **métodos públicos**
3. **dependencias directas**
4. **acceso a singletons/autoloads**
5. **mezcla lectura+decisión+ejecución**
6. **duplicación de checks**
7. **flags/booleans de contexto**

## Ranking (mayor a menor score total)

| Archivo | tamaño | métodos públicos | dependencias directas | singletons/autoloads | mezcla R+D+E | duplicación checks | flags/booleans | **Total** |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| `world.gd` | 3 | 3 | 3 | 3 | 3 | 3 | 3 | **21** |
| `BanditBehaviorLayer.gd` | 3 | 1 | 3 | 1 | 3 | 3 | 3 | **17** |
| `ExtortionFlow.gd` | 2 | 1 | 2 | 0 | 3 | 2 | 2 | **12** |
| `BanditGroupIntel.gd` | 2 | 1 | 2 | 0 | 2 | 2 | 3 | **12** |
| `BanditWorkCoordinator.gd` | 2 | 0 | 1 | 0 | 2 | 2 | 2 | **9** |
| `SettlementIntel.gd` | 2 | 2 | 1 | 0 | 2 | 1 | 1 | **9** |
| `WorldSpatialIndex.gd` | 1 | 2 | 1 | 0 | 1 | 1 | 1 | **7** |
| `WorldTerritoryPolicy.gd` | 0 | 1 | 1 | 0 | 1 | 1 | 1 | **5** |
| `WorldCadenceCoordinator.gd` | 0 | 1 | 0 | 0 | 1 | 0 | 0 | **2** |

---

## `world.gd`
- **Total: 21 (crítico).**
- Macro-script (≈2k líneas), superficie pública muy amplia y acoplamiento alto con sistemas de mundo y utilidades.
- Mezcla de responsabilidades (consulta de estado, policy checks, side-effects, spawning/daño/gestión) en el mismo archivo.
- Múltiples checks condicionales similares y abundancia de flags/contexto (estado temporal, gating, dirty/pending).

## `BanditBehaviorLayer.gd`
- **Total: 17 (muy alto).**
- Tamaño alto y fuerte rol orquestador con varias dependencias de dominio (territorio, grupos, flujos, selección de objetivos).
- Aunque expone pocos métodos públicos, concentra mucha lógica de decisión y ejecución en cascada.
- Alta densidad de flags de contexto y ramas condicionales repetidas por tipo de situación/L0D/estado de grupo.

## `BanditWorkCoordinator.gd`
- **Total: 9 (alto moderado).**
- Tamaño medio-alto para un coordinador y acoplamiento operativo con el loop post-behavior.
- Menor API pública, pero mezcla lectura de contexto con scheduling/ejecución.
- Presencia apreciable de checks y banderas operativas.

## `BanditGroupIntel.gd`
- **Total: 12 (alto).**
- Archivo de tamaño medio-alto con densidad de estado contextual del grupo (memoria/intel/timers).
- API pública pequeña, pero interno con múltiples rutas condicionales y flags.
- Mezcla de lectura de señales, inferencia y actualización de estado utilizable por capas de comportamiento.

## `SettlementIntel.gd`
- **Total: 9 (alto moderado).**
- Tamaño medio-alto y API pública relativamente grande para utilidades de escaneo/interés.
- Dependencias directas contenidas y bajo acceso global, pero combina escaneo, registro de eventos y decisiones de marcación.
- Riesgo medio por duplicación de checks alrededor de “scan dirty”/“base near”.

## `WorldCadenceCoordinator.gd`
- **Total: 2 (bajo).**
- Archivo pequeño, API compacta y propósito acotado (cadencia/lanes).
- Baja señal de riesgo estructural: poca dependencia y casi sin flags o lógica duplicada.

## `WorldSpatialIndex.gd`
- **Total: 7 (medio).**
- Tamaño intermedio con API pública relativamente amplia (consultas y registro de nodos/placeables).
- Responsabilidad principalmente de indexación/consulta, con mezcla moderada de lectura y lógica de acceso.
- Riesgo más por superficie pública que por acoplamiento global.

## `ExtortionFlow.gd`
- **Total: 12 (alto).**
- Tamaño medio-alto y flujo multi-etapa (proceso, movimiento, resolución de elección).
- Mezcla fuerte de evaluación + decisión + ejecución durante el mismo pipeline.
- Densidad media-alta de checks y flags por etapa/contexto del flujo.

## `WorldTerritoryPolicy.gd`
- **Total: 5 (medio-bajo).**
- Archivo chico y focalizado, con pocas entradas públicas.
- Riesgo principal en policy checks que pueden duplicarse con otros validadores de colocación/interés.
- Carga de estado/contexto baja comparada con otros archivos del dominio.
