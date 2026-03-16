# Phase 0 Smoke Test (Deterministic Seed + Chunk Lifecycle)

## 1) Configurar determinismo del run

1. Abrir `Seed` (autoload) en el inspector de proyecto.
2. Confirmar:
   - `use_debug_seed = true`
   - `debug_seed = 123456`
3. Iniciar el juego.
4. Verificar en logs de arranque:
   - `RUN_SEED=123456 use_debug_seed=true`

## 2) Checklist manual rápido

- [ ] Spawn inicial correcto en taberna.
- [ ] Tavern keeper visible y props de taberna presentes.
- [ ] Colisiones/bounds de paredes de taberna correctas.
- [ ] Ores visibles en chunks cercanos (y/o conteo en logs de chunk).
- [ ] Caminar lo suficiente para disparar descarga/carga de chunks.
- [ ] Volver a chunks previos y confirmar que no hay duplicación (keeper/ores/camps).

## 3) Logs esperados (ejemplos)

- `GENERATE chunk=(x,y) run_seed=... chunk_seed=...`
- `LOAD_ENTITIES chunk=(x,y) placements=... ores=... camps=...`
- `SPAWNED chunk=(x,y) props=... npcs=... ores=... camps=... saveables=...`
- `UNLOAD chunk=(x,y) entities=... saveables=...`

> Nota: El formato final incluye categoría según `Debug.log(cat, msg)`.

## 4) Smoke test manual de ShopService (loop real)

- [ ] Comprar item **INFINITE** (ej. `medkit`) con oro suficiente:
  - baja `gold` del player.
  - item entra al inventario del player.
  - stock del vendor no baja.
- [ ] Comprar item **STOCKED** (ej. `copper`) con stock:
  - baja `gold` del player.
  - item entra al inventario del player.
  - stock del vendor baja.
  - al llegar a 0, siguiente compra bloquea con `NO_STOCK`.
- [ ] Vender `copper` al vendor:
  - sale item del player.
  - sube `gold` del player.
  - si `buyback_mode=STOCKED_TO_INVENTORY`, el vendor recibe stock.
- [ ] Bloqueos:
  - sin oro => `NO_GOLD`.
  - sin espacio => `NO_SPACE`.
  - vender sin item => `NO_ITEM`.

Logs esperados:
- `[SHOP][BUY] item=... amt=... cost=... ok=... reason=... offer_mode=...`
- `[SHOP][SELL] item=... amt=... payout=... ok=... reason=... buyback_mode=...`


## 5) Cierre de corte — PlayerWallSystem (sin lógica fantasma)

### A) Verificación de arquitectura (rápida)

- [ ] `scripts/world/world.gd` mantiene solo wrappers/hooks para player walls.
- [ ] `scripts/world/PlayerWallSystem.gd` concentra reglas de dominio (place/damage/drop/reconnect).
- [ ] `PlayerWallSystem` no accede por rutas absolutas ni depende de estructura interna de `world.gd`; usa contexto/callables de integración.

### B) Regresión funcional obligatoria

- [ ] **Place**: colocar pared player en tile válido, rechazar tile ocupado/cliff/entidad.
- [ ] **Save/Load**: guardar, recargar escena, confirmar HP y presencia de paredes player.
- [ ] **Damage melee** (`slash.gd`): contacto cercano y fallback radial siguen dañando pared player.
- [ ] **Damage flechas** (`arrow_projectile.gd`): impacto sigue aplicando daño a pared player.
- [ ] **Reconnect visual**: al colocar/quitar pared, el autotile reconecta vecinos correctamente.
- [ ] **Chunk borders**: paredes en bordes de chunk sobreviven carga/descarga sin duplicar ni desaparecer.
- [ ] **Drops**: al romper pared player, drop de `wallwood` respeta toggle/cantidad.
- [ ] **Collider refresh**: cambios de paredes marcan dirty + reconstruyen/reciclan collider del chunk.

Sugerencia de pasada manual:
1. Colocar 3-5 paredes cruzando borde de chunk.
2. Aplicar daño mixto melee + flechas hasta romper algunas.
3. Salir del chunk y volver.
4. Guardar/cargar y repetir daño en las restantes.
