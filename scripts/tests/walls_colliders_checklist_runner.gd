extends SceneTree

var _results: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("_run")

func _record(name: String, ok: bool, evidence: String) -> void:
	_results.append({"case": name, "status": ok, "evidence": evidence})
	print("[CHECKLIST] ", name, " => ", ("PASS" if ok else "FAIL"), " :: ", evidence)

func _wait_frames(n: int) -> void:
	for _i in range(n):
		await process_frame

func _find_valid_tile(world: Node, origin: Vector2i, radius: int = 6) -> Vector2i:
	for r in range(1, radius + 1):
		for y in range(origin.y - r, origin.y + r + 1):
			for x in range(origin.x - r, origin.x + r + 1):
				var t := Vector2i(x, y)
				if world.call("can_place_player_wall_at_tile", t):
					return t
	return Vector2i(-1, -1)

func _wall_world_pos(walls_tm: TileMap, tile: Vector2i) -> Vector2:
	return walls_tm.to_global(walls_tm.map_to_local(tile))

func _run() -> void:
	var main_scene: PackedScene = load("res://scenes/main.tscn")
	if main_scene == null:
		_record("bootstrap", false, "No se pudo cargar scenes/main.tscn")
		_finalize_and_quit()
		return

	var main := main_scene.instantiate()
	root.add_child(main)
	current_scene = main
	await _wait_frames(20)

	var world := main.get_node_or_null("World")
	var player := main.get_node_or_null("Player")
	var walls_tm := world.get_node_or_null("StructureWallsMap") as TileMap
	if world == null or player == null or walls_tm == null:
		_record("bootstrap", false, "World/Player/StructureWallsMap no disponibles")
		_finalize_and_quit()
		return

	# Caso 1: colocar wall
	var origin_tile: Vector2i = walls_tm.local_to_map(walls_tm.to_local((player as Node2D).global_position))
	var tile := _find_valid_tile(world, origin_tile, 8)
	if tile.x < 0:
		_record("colocar wood walls", false, "No se encontró tile válido")
		_finalize_and_quit()
		return
	var placed: bool = bool(world.call("place_player_wall_at_tile", tile))
	var cpos: Vector2i = world.call("_tile_to_chunk", tile)
	var has_wall: bool = WorldSave.has_player_wall(cpos.x, cpos.y, tile)
	_record("colocar wood walls", placed and has_wall, "tile=%s chunk=%s" % [str(tile), str(cpos)])
	await _wait_frames(2)

	# Caso 2: daño melee (proxy cercano)
	var hit_pos := _wall_world_pos(walls_tm, tile)
	var hp_before: int = int(WorldSave.get_player_wall(cpos.x, cpos.y, tile).get(WorldSave.PLAYER_WALL_HP_KEY, -1))
	var melee_ok: bool = bool(world.call("damage_player_wall_near_world_pos", hit_pos, 1))
	var hp_after_melee: int = int(WorldSave.get_player_wall(cpos.x, cpos.y, tile).get(WorldSave.PLAYER_WALL_HP_KEY, -1))
	_record("daño melee a wall", melee_ok and hp_after_melee == hp_before - 1, "hp %d -> %d" % [hp_before, hp_after_melee])

	# Caso 3: daño proyectil (proxy at_world_pos)
	var projectile_ok: bool = bool(world.call("damage_player_wall_at_world_pos", hit_pos, 1))
	var hp_after_projectile: int = int(WorldSave.get_player_wall(cpos.x, cpos.y, tile).get(WorldSave.PLAYER_WALL_HP_KEY, -1))
	_record("daño proyectil a wall", projectile_ok and hp_after_projectile == hp_after_melee - 1, "hp %d -> %d" % [hp_after_melee, hp_after_projectile])

	# Caso 4: romper wall
	var break_ok: bool = bool(world.call("damage_player_wall_at_world_pos", hit_pos, 10))
	var removed: bool = not WorldSave.has_player_wall(cpos.x, cpos.y, tile)
	_record("romper wood walls", break_ok and removed, "tile=%s removed=%s" % [str(tile), str(removed)])
	await _wait_frames(2)

	# Caso 5: save/load walls
	var save_tile := _find_valid_tile(world, origin_tile + Vector2i(2, 0), 10)
	var save_case_ok := false
	if save_tile.x >= 0 and bool(world.call("place_player_wall_at_tile", save_tile, 2)):
		var save_chunk: Vector2i = world.call("_tile_to_chunk", save_tile)
		SaveManager.register_world(world)
		SaveManager.save_world()
		WorldSave.player_walls_by_chunk.clear()
		walls_tm.erase_cell(0, save_tile)
		var loaded := SaveManager.load_world_save()
		save_case_ok = loaded and WorldSave.has_player_wall(save_chunk.x, save_chunk.y, save_tile)
		_record("guardar/cargar walls", save_case_ok, "tile=%s load_ok=%s" % [str(save_tile), str(loaded)])
	else:
		_record("guardar/cargar walls", false, "No se pudo preparar pared de guardado")

	# Caso 6: rebuild colliders sin regresión (hash cambia tras mutate y queda no-dirty)
	var col_tile := _find_valid_tile(world, origin_tile + Vector2i(4, 0), 12)
	var collider_ok := false
	if col_tile.x >= 0 and bool(world.call("place_player_wall_at_tile", col_tile)):
		await _wait_frames(2)
		var col_chunk: Vector2i = world.call("_tile_to_chunk", col_tile)
		var hash_before: int = int(WorldSave.get_chunk_flag(col_chunk.x, col_chunk.y, "walls_hash"))
		var dirty_before := bool(WorldSave.get_chunk_flag(col_chunk.x, col_chunk.y, "walls_dirty"))
		var removed_ok: bool = bool(world.call("remove_player_wall_at_tile", col_tile, false))
		await _wait_frames(2)
		var hash_after: int = int(WorldSave.get_chunk_flag(col_chunk.x, col_chunk.y, "walls_hash"))
		var dirty_after := bool(WorldSave.get_chunk_flag(col_chunk.x, col_chunk.y, "walls_dirty"))
		collider_ok = removed_ok and (hash_before != hash_after) and (not dirty_after)
		_record("rebuild de colliders", collider_ok, "chunk=%s hash %d->%d dirty %s->%s" % [str(col_chunk), hash_before, hash_after, str(dirty_before), str(dirty_after)])
	else:
		_record("rebuild de colliders", false, "No se pudo preparar tile de collider")


	# Caso 8: ciclo mínimo place -> save -> unload/reload chunk -> restore -> remove -> save
	var cycle_tile := _find_valid_tile(world, origin_tile + Vector2i(6, 0), 14)
	var cycle_ok := false
	if cycle_tile.x >= 0 and bool(world.call("place_player_wall_at_tile", cycle_tile, 2)):
		var cycle_chunk: Vector2i = world.call("_tile_to_chunk", cycle_tile)
		SaveManager.register_world(world)
		var save_a_ok: bool = bool(SaveManager.save_world())
		world.call("unload_chunk", cycle_chunk)
		var loaded_chunks: Dictionary = world.get("loaded_chunks")
		loaded_chunks[cycle_chunk] = true
		world.set("loaded_chunks", loaded_chunks)
		var pws := world.get("_player_wall_system")
		if pws != null:
			pws.call("apply_saved_walls_for_chunk", cycle_chunk)
		var restored_ok: bool = WorldSave.has_player_wall(cycle_chunk.x, cycle_chunk.y, cycle_tile)
		var removed_ok2: bool = bool(world.call("remove_player_wall_at_tile", cycle_tile, false))
		var save_b_ok: bool = bool(SaveManager.save_world())
		cycle_ok = save_a_ok and restored_ok and removed_ok2 and save_b_ok and (not WorldSave.has_player_wall(cycle_chunk.x, cycle_chunk.y, cycle_tile))
		_record("ciclo mínimo de persistencia de wall", cycle_ok, "tile=%s chunk=%s restored=%s" % [str(cycle_tile), str(cycle_chunk), str(restored_ok)])
	else:
		_record("ciclo mínimo de persistencia de wall", false, "No se pudo preparar tile de ciclo")

	# Caso 7: no regresión placeables críticos (registro cargable)
	var required := ["doorwood", "floorwood", "chest", "barrel", "table", "workbench"]
	var missing: Array[String] = []
	for item_id in required:
		if not PlacementSystem.PLACEABLE_SCENES.has(item_id):
			missing.append(item_id)
			continue
		var scene_path: String = String(PlacementSystem.PLACEABLE_SCENES[item_id])
		var packed := load(scene_path)
		if packed == null:
			missing.append(item_id + "(scene)")
	var regress_ok := missing.is_empty()
	_record("no regresión doorwood/floorwood/chest/barrel/table/workbench", regress_ok, ("ok" if regress_ok else "faltantes=%s" % [str(missing)]))

	_finalize_and_quit()

func _finalize_and_quit() -> void:
	var total := _results.size()
	var passed := 0
	for row in _results:
		if bool(row.get("status", false)):
			passed += 1
	var report := {
		"total": total,
		"passed": passed,
		"failed": total - passed,
		"results": _results,
	}
	var file := FileAccess.open("user://walls_colliders_checklist_results.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	print("[CHECKLIST] SUMMARY passed=", passed, " total=", total)
	quit(0 if passed == total else 1)
