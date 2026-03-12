# CLAUDE.md

## Correr el proyecto

```bash
godot --path . scenes/main.tscn
godot --path . --check-only --script scripts/world/world.gd
```

MCP bridge activo en `addons/mcp_bridge/` — usar `mcp__godot-mcp__*` cuando Godot esté abierto.

## Arquitectura

Ver `AGENTS.MD` para visión completa. Resumen clave:

- `world.gd` — orquestador, delega a subsistemas via `setup(ctx: Dictionary)`
- `ChunkPipeline` — generación, prefetch, terrain-paint, stage queues
- `EntitySpawnCoordinator` — spawn jobs, ciclo de vida de entidades
- `NpcSimulator` — tracking enemigos, lite-mode por distancia
- `ChunkPerfMonitor` — timings, percentiles, auto-calibración

**Inyección de dependencias:** subsistemas reciben callables y refs en `setup()`, nunca referencias directas a nodos.

**Persistencia:** `WorldSave` (autoload), UIDs deterministas via `UID.make_uid()`. Un chunk nunca respawnea entidades que ya tiene en `entities_spawned_chunks`.

**Capas de colisión:** usar siempre `CollisionLayers.gd` — nunca números hardcodeados. `1=Player`, `2=Attacks`, `3=EnemyNCP`, `4=resources`, `5=WALLPROPS`.

**CharacterBase:** todo override de `_ready()` debe llamar `super._ready()` como primera línea.

## Agregar una entidad de mundo nueva

1. Definir spawn en `ChunkGenerator` / `PropSpawner`
2. Agregar rama `kind` en `EntitySpawnCoordinator.enqueue_entities()`
3. Manejar `job_spawned` en `EntitySpawnCoordinator._on_job_spawned()`
4. Si tiene estado persistente: `get_save_state()` + registrar en `chunk_saveables`
5. Documentar en `AGENTS.MD`
