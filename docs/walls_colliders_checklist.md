# Checklist manual reproducible — Walls & Colliders (Gate previo a Fase 4)

## Escena/mundo controlado
- Escena objetivo: `scenes/main.tscn`.
- Semilla recomendada: `Seed.use_debug_seed=true`, `Seed.debug_seed=123456`.
- Entorno de ejecución esperado: Godot 4.x con proyecto en modo local.

## Casos críticos

### 1) Colocar wood walls
- **Precondición:** Player con al menos 1 `wallwood` en inventario; tile libre sin cliffs, sin estructura y sin entidad colocada.
- **Pasos:**
  1. Activar colocación de `wallwood`.
  2. Apuntar a tile válido.
  3. Confirmar colocación.
- **Resultado esperado:** La pared aparece en `StructureWallsMap`, se registra en `WorldSave.player_walls_by_chunk`, y se refresca collider del chunk.
- **Criterio de aceptación:** `PASS` si pared visible/registrada y sin errores en consola.

### 2) Romper wood walls
- **Precondición:** Al menos 1 `wallwood` colocada y alcanzable por el player.
- **Pasos:**
  1. Aplicar daño hasta agotar HP de la pared.
  2. Observar remoción del tile.
  3. Validar drop (si `player_wall_drop_enabled=true`).
- **Resultado esperado:** La pared se elimina de tilemap y de `WorldSave`; collider se actualiza.
- **Criterio de aceptación:** `PASS` si no queda tile fantasma, no duplica drops, y no quedan colisiones residuales.

### 3) Guardar/cargar walls
- **Precondición:** Mundo con varias `wallwood` colocadas (incluyendo borde de chunk).
- **Pasos:**
  1. Guardar partida (`SaveManager.save_world()`).
  2. Cerrar/reabrir escena.
  3. Cargar (`SaveManager.load_world_save()`).
- **Resultado esperado:** Se restauran paredes y HP por chunk sin duplicación ni pérdida.
- **Criterio de aceptación:** `PASS` si layout + HP coinciden antes/después de cargar.

### 4) Daño por melee y por proyectil
- **Precondición:** Pared colocada y player equipado con melee + arco/flechas.
- **Pasos:**
  1. Golpear pared con melee (`slash`).
  2. Disparar proyectil (`arrow_projectile`) a la misma pared.
- **Resultado esperado:** Ambos tipos de daño descuentan HP de la pared y respetan destrucción al llegar a 0.
- **Criterio de aceptación:** `PASS` si ambos canales de daño afectan la misma entidad y no atraviesan colisión.

### 5) Rebuild de colliders sin regresión
- **Precondición:** Chunk cargado con paredes antes y después de una mutación (place/remove).
- **Pasos:**
  1. Colocar/romper paredes en un mismo chunk.
  2. Verificar recomputo de hash/dirty.
  3. Moverse fuera y volver al chunk.
- **Resultado esperado:** Collider se reconstruye/reutiliza correctamente; no bloqueos fantasmas.
- **Criterio de aceptación:** `PASS` si el movimiento del player/NPC coincide con geometría actual sin desincronización.

### 6) No regresión: `doorwood`, `floorwood`, `chest`, `barrel`, `workbench`
- **Precondición:** Registro de placeables activo en `PlacementSystem`.
- **Pasos:**
  1. Verificar que cada item esté mapeado a una escena válida.
  2. Instanciar/colocar cada item en un tile válido.
  3. Revalidar tras acciones sobre walls/colliders.
- **Resultado esperado:** Los 5 placeables siguen colocándose/interactuando sin colisiones erróneas por cambios de walls.
- **Criterio de aceptación:** `PASS` si no hay ruptura de placement ni escenas faltantes.

---

## Ejecución actual (este entorno)

### Evidencia de ejecución
- Comando intentado para test en mundo controlado:
  - `godot --path . --headless --script res://scripts/tests/walls_colliders_checklist_runner.gd`
- Resultado:
  - `bash: command not found: godot`

### Resultado por caso
| Caso | Estado | Evidencia breve |
|---|---|---|
| Colocar wood walls | BLOCKED | No se pudo iniciar runtime Godot en este entorno. |
| Romper wood walls | BLOCKED | No se pudo iniciar runtime Godot en este entorno. |
| Guardar/cargar walls | BLOCKED | No se pudo iniciar runtime Godot en este entorno. |
| Daño melee/proyectil | BLOCKED | No se pudo iniciar runtime Godot en este entorno. |
| Rebuild de colliders | BLOCKED | No se pudo iniciar runtime Godot en este entorno. |
| No regresión placeables críticos | PASS (estático) | Verificación de registry + paths + API por script Python local. |

### Gate de avance
- **Fase 4 NO debe continuar**: checklist crítico de `walls/colliders` aún no está en verde por bloqueo de entorno (runtime Godot ausente).
