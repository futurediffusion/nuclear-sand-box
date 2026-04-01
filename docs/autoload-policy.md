# Política de uso de Autoloads / Singletons globales

Fecha: 2026-04-01  
Estado: **obligatorio para revisión técnica**

## Objetivo
Definir límites claros para evitar que los autoloads se conviertan en centros de decisión de gameplay o en agregadores de estado entre dominios.

---

## 1) Qué está permitido en un autoload

Un autoload puede existir como **infraestructura transversal** cuando cumple uno o más de estos roles:

1. **Servicio transversal técnico**
   - tiempo (`RunClock`), audio global, guardado, cola técnica, reloj, identidad.
2. **Registro/Fachada de estado global de infraestructura**
   - diccionarios/índices globales y APIs CRUD simples.
3. **Utilidades de infraestructura**
   - logging, telemetría, helpers de serialización, adaptación a APIs del engine.

> Regla: el autoload expone datos u operaciones técnicas; no decide política de dominio.

---

## 2) Qué está prohibido en un autoload

### 2.1 Decidir gameplay o política de dominio
Queda prohibido decidir “qué debe pasar” en facciones, raids, extorsión, loot o respuestas sociales desde el autoload.

### 2.2 Acumular estado de múltiples dominios
Queda prohibido mezclar estado y reglas de dominios distintos en un singleton “dios”.

### 2.3 Orquestar flujos completos end-to-end
Queda prohibido que un autoload escanee, evalúe, elija estrategia y ejecute efectos globales en la misma pieza.

---

## 3) Convención de naming

Para distinguir responsabilidades, se adopta la siguiente convención:

- **Puerto (contrato):** prefijo `I` + sufijo `Port`.
  - Ejemplos: `ITimePort`, `IRaidPort`, `IPersistencePort`.
- **Adaptador (implementación de puerto):** sufijo `*Adapter`.
  - Ejemplos: `RunClockAdapter`, `WorldSavePersistenceAdapter`, `ExtortionUIAdapter`.
- **Singleton de infraestructura (autoload):** sufijo `*Service`, `*Registry`, `*Queue`, `*Manager`.
  - Ejemplos: `EnemyRegistry`, `ExtortionQueue`, `FactionHostilityManager`, `SaveManager`.

Reglas adicionales:
- Ningún `*Service/*Manager/*Registry/*Queue` debe exponer métodos con semántica de política (`decide_*`, `choose_*`, `resolve_strategy_*`).
- Si una pieza decide política, debe vivir en `Policy`, `Flow`, `Director` o servicio de dominio **inyectado por puerto**.

---

## 4) Checklist obligatorio para PR

Agregar este checklist en toda PR que toque `scripts/world`, `scripts/systems` o cualquier integración social:

- [ ] **¿Este cambio agrega dependencia directa a un global/autoload?**
- [ ] **¿Existe puerto equivalente para esa dependencia?**
- [ ] Si no existe puerto: ¿se creó contrato mínimo (`I*Port`) y adaptador en vez de acoplar al singleton?
- [ ] ¿El autoload modificado quedó limitado a registro/infra y sin decisiones de gameplay?
- [ ] ¿La orquestación de flujo completo quedó fuera del autoload?

Criterio de rechazo:
- Si la respuesta a la primera pregunta es “sí” y a la segunda “sí”, la PR debe usar el puerto.
- Si la respuesta a la primera pregunta es “sí” y a la segunda “no”, la PR debe justificar creación de puerto o dejar deuda técnica explícita con ticket.

---

## 5) Anti-patrones concretos detectados en el repo

1. **Orquestador de mundo mutando intención social y colas globales**
   - `scripts/world/world.gd` realiza lecturas + decisiones + escrituras sobre `BanditGroupMemory`, `RaidQueue` y `WorldSave`.
   - Riesgo: el boundary de composición termina decidiendo gameplay.

2. **Scanner de inteligencia que también despacha comandos globales**
   - `scripts/world/BanditGroupIntel.gd` combina assessment + actualización de intención + encolado en `ExtortionQueue/RaidQueue`.
   - Riesgo: una sola pieza concentra evaluación y ejecución.

3. **Flow de extorsión con lógica transaccional y side-effects faccionales**
   - `scripts/world/ExtortionFlow.gd` mezcla outcome de interacción con escrituras en `FactionHostilityManager`, `BanditGroupMemory` y consumo de `ExtortionQueue`.
   - Riesgo: difícil de testear por frontera; alta probabilidad de acoplamiento circular.

4. **Capa de comportamiento de NPC con escritura de estado grupal**
   - `scripts/world/BanditBehaviorLayer.gd` combina locomoción con mutaciones de `BanditGroupMemory`.
   - Riesgo: la capa motriz invade soberanía social.

> Estos casos no implican rollback inmediato, pero sí marcan prioridad de migración a puertos/adaptadores.

---

## 6) Requisito de revisión técnica

Desde esta política, cualquier PR que toque singletons/autoloads o dependencias globales:

1. Debe pasar el checklist del punto 4.
2. Debe explicar explícitamente por qué usa (o evita) acceso directo a autoload.
3. Debe indicar el puerto actual o propuesto para desacoplar el cambio.

Sin estos puntos, la revisión técnica debe marcar la PR como **“changes requested”**.
