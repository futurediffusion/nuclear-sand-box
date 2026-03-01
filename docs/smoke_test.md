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
