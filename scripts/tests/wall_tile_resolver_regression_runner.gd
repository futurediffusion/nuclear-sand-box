extends SceneTree

const WallTileResolverScript := preload("res://scripts/world/WallTileResolver.gd")

const TILE_SIZE := 32.0

var _results: Array[Dictionary] = []
var _player_tiles: Dictionary = {}
var _structural_tiles: Dictionary = {}

func _initialize() -> void:
	call_deferred("_run")

func _record(name: String, ok: bool, evidence: String) -> void:
	_results.append({"case": name, "status": ok, "evidence": evidence})
	print("[WALL_RESOLVER] ", name, " => ", ("PASS" if ok else "FAIL"), " :: ", evidence)

func _world_to_tile(pos: Vector2) -> Vector2i:
	return Vector2i(int(floor(pos.x / TILE_SIZE)), int(floor(pos.y / TILE_SIZE)))

func _tile_to_world(tile_pos: Vector2i) -> Vector2:
	return Vector2(float(tile_pos.x) * TILE_SIZE + TILE_SIZE * 0.5, float(tile_pos.y) * TILE_SIZE + TILE_SIZE * 0.5)

func _is_valid_world_tile(tile_pos: Vector2i) -> bool:
	return tile_pos.x >= 0 and tile_pos.x < 32 and tile_pos.y >= 0 and tile_pos.y < 32

func _is_player_wall_tile(tile_pos: Vector2i) -> bool:
	return _player_tiles.has(tile_pos)

func _is_structural_wall_tile(tile_pos: Vector2i) -> bool:
	return _structural_tiles.has(tile_pos)

func _run() -> void:
	_player_tiles.clear()
	_structural_tiles.clear()

	var target_tile := Vector2i(10, 10)
	_player_tiles[target_tile] = true

	var direct_hit := _tile_to_world(target_tile)
	var resolved_direct: Vector2i = WallTileResolverScript.resolve_player_wall_tile_from_contact(
		direct_hit,
		Vector2.ZERO,
		Callable(self, "_world_to_tile"),
		Callable(self, "_is_valid_world_tile"),
		Callable(self, "_is_player_wall_tile"),
		Callable(self, "_tile_to_world"),
		Vector2(TILE_SIZE, TILE_SIZE),
		1
	)
	_record("hit directo a tile", resolved_direct == target_tile, "resolved=%s expected=%s" % [str(resolved_direct), str(target_tile)])

	var corner_hit := Vector2(float(target_tile.x + 1) * TILE_SIZE + 0.1, float(target_tile.y + 1) * TILE_SIZE + 0.1)
	var resolved_corner: Vector2i = WallTileResolverScript.resolve_player_wall_tile_from_contact(
		corner_hit,
		Vector2(1.0, 1.0).normalized(),
		Callable(self, "_world_to_tile"),
		Callable(self, "_is_valid_world_tile"),
		Callable(self, "_is_player_wall_tile"),
		Callable(self, "_tile_to_world"),
		Vector2(TILE_SIZE, TILE_SIZE),
		1
	)
	_record("hit borde/esquina", resolved_corner == target_tile, "resolved=%s expected=%s" % [str(resolved_corner), str(target_tile)])

	_player_tiles.clear()
	var fallback_tile := Vector2i(12, 11)
	_player_tiles[fallback_tile] = true
	var miss_center := _tile_to_world(Vector2i(11, 11))
	var resolved_fallback: Vector2i = WallTileResolverScript.find_nearest_player_wall_tile_in_neighborhood(
		miss_center,
		Vector2i(11, 11),
		Callable(self, "_world_to_tile"),
		Callable(self, "_is_valid_world_tile"),
		Callable(self, "_is_player_wall_tile"),
		Callable(self, "_tile_to_world"),
		Vector2(TILE_SIZE, TILE_SIZE),
		1
	)
	_record("fallback por vecindad", resolved_fallback == fallback_tile, "resolved=%s expected=%s" % [str(resolved_fallback), str(fallback_tile)])

	_player_tiles.clear()
	_structural_tiles.clear()
	var structural_tile := Vector2i(15, 15)
	var player_tile := Vector2i(15, 16)
	_structural_tiles[structural_tile] = true
	_player_tiles[player_tile] = true
	var structural_pick: Vector2i = WallTileResolverScript.find_nearest_structural_wall_tile(
		_tile_to_world(structural_tile),
		20.0,
		Callable(self, "_world_to_tile"),
		Callable(self, "_is_valid_world_tile"),
		Callable(self, "_is_structural_wall_tile"),
		Callable(self, "_tile_to_world"),
		Vector2(TILE_SIZE, TILE_SIZE)
	)
	_record("resolución structural vs player wall", structural_pick == structural_tile and structural_pick != player_tile, "resolved=%s structural=%s player=%s" % [str(structural_pick), str(structural_tile), str(player_tile)])

	_finalize_and_quit()

func _finalize_and_quit() -> void:
	var total := _results.size()
	var passed := 0
	for row in _results:
		if bool(row.get("status", false)):
			passed += 1
	print("[WALL_RESOLVER] SUMMARY passed=", passed, " total=", total)
	quit(0 if passed == total else 1)
