extends SceneTree

const CollisionBuilderScript := preload("res://scripts/world/CollisionBuilder.gd")

var _results: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("_run")

func _record(name: String, ok: bool, evidence: String) -> void:
	_results.append({"case": name, "status": ok, "evidence": evidence})
	print("[COLLISION_BUILDER_INNER] ", name, " => ", ("PASS" if ok else "FAIL"), " :: ", evidence)

func _lookup_from_tiles(tiles: Array[Vector2i]) -> Dictionary:
	var lookup: Dictionary = {}
	for tile in tiles:
		lookup[tile] = true
	return lookup

func _range_from_tiles(tiles: Array[Vector2i]) -> Dictionary:
	if tiles.is_empty():
		return {"start_x": 0, "end_x": -1, "start_y": 0, "end_y": -1}
	var min_x: int = tiles[0].x
	var max_x: int = tiles[0].x
	var min_y: int = tiles[0].y
	var max_y: int = tiles[0].y
	for tile in tiles:
		min_x = min(min_x, tile.x)
		max_x = max(max_x, tile.x)
		min_y = min(min_y, tile.y)
		max_y = max(max_y, tile.y)
	return {
		"start_x": min_x,
		"end_x": max_x,
		"start_y": min_y,
		"end_y": max_y,
	}

func _edge_keys_for_tiles(builder: CollisionBuilder, tiles: Array[Vector2i]) -> Array[String]:
	var lookup: Dictionary = _lookup_from_tiles(tiles)
	var r: Dictionary = _range_from_tiles(tiles)
	var best_by_edge: Dictionary = builder.call(
		"_collect_best_inner_corner_by_edge",
		lookup,
		{},
		int(r.get("start_x", 0)),
		int(r.get("end_x", -1)),
		int(r.get("start_y", 0)),
		int(r.get("end_y", -1))
	)
	var keys: Array = best_by_edge.keys()
	keys.sort()
	var out: Array[String] = []
	for raw_key in keys:
		out.append(String(raw_key))
	return out

func _run() -> void:
	var builder: CollisionBuilder = CollisionBuilderScript.new()

	var y_both: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(2, 0),
		Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1),
		Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2),
	]
	var y_both_edges: Array[String] = _edge_keys_for_tiles(builder, y_both)
	var y_both_ok: bool = y_both_edges.size() == 2 and y_both_edges.has("V:1:2") and y_both_edges.has("V:2:2")
	_record("Y bilateral mantiene plugs internos", y_both_ok, "edges=%s" % [str(y_both_edges)])
	var y_both_lookup: Dictionary = _lookup_from_tiles(y_both)
	var y_both_left_strip: bool = bool(builder.call("_should_keep_spine_side_strip", y_both_lookup, Vector2i(0, 1), 1))
	var y_both_right_strip: bool = bool(builder.call("_should_keep_spine_side_strip", y_both_lookup, Vector2i(2, 1), -1))
	_record("Y bilateral mantiene cierre lateral en columnas", y_both_left_strip and y_both_right_strip, "left=%s right=%s" % [str(y_both_left_strip), str(y_both_right_strip)])

	var y_one_side: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(2, 0),
		Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1),
		Vector2i(1, 2), Vector2i(2, 2),
	]
	var y_one_side_edges: Array[String] = _edge_keys_for_tiles(builder, y_one_side)
	var y_one_side_ok: bool = y_one_side_edges.size() == 2 and y_one_side_edges.has("V:1:1") and y_one_side_edges.has("V:2:2")
	_record("Y con un refuerzo no abre seam", y_one_side_ok, "edges=%s" % [str(y_one_side_edges)])

	var cross_plus: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(0, -1), Vector2i(0, 1),
		Vector2i(-1, 0), Vector2i(1, 0),
	]
	var cross_edges: Array[String] = _edge_keys_for_tiles(builder, cross_plus)
	_record("Cruz no agrega plugs laterales extra", cross_edges.is_empty(), "edges=%s" % [str(cross_edges)])
	var cross_lookup: Dictionary = _lookup_from_tiles(cross_plus)
	var cross_center_keep_east: bool = bool(builder.call("_should_keep_spine_side_strip", cross_lookup, Vector2i(0, 0), 1))
	var cross_center_keep_west: bool = bool(builder.call("_should_keep_spine_side_strip", cross_lookup, Vector2i(0, 0), -1))
	_record("Cruz conserva regla previa de spine strips", cross_center_keep_east and cross_center_keep_west, "east=%s west=%s" % [str(cross_center_keep_east), str(cross_center_keep_west)])

	var t_up: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(1, 0),
	]
	var t_up_edges: Array[String] = _edge_keys_for_tiles(builder, t_up)
	_record("T superior no agrega plugs laterales", t_up_edges.is_empty(), "edges=%s" % [str(t_up_edges)])

	var l_right: Array[Vector2i] = [
		Vector2i(0, -1), Vector2i(0, 0), Vector2i(1, 0),
	]
	var l_right_edges: Array[String] = _edge_keys_for_tiles(builder, l_right)
	var l_right_ok: bool = l_right_edges.size() == 1 and l_right_edges[0] == "V:1:0"
	_record("L derecha mantiene solo un plug valido", l_right_ok, "edges=%s" % [str(l_right_edges)])

	var l_left: Array[Vector2i] = [
		Vector2i(0, -1), Vector2i(0, 0), Vector2i(-1, 0),
	]
	var l_left_edges: Array[String] = _edge_keys_for_tiles(builder, l_left)
	var l_left_ok: bool = l_left_edges.size() == 1 and l_left_edges[0] == "V:0:0"
	_record("L izquierda mantiene solo un plug valido", l_left_ok, "edges=%s" % [str(l_left_edges)])

	_finalize_and_quit()

func _finalize_and_quit() -> void:
	var total: int = _results.size()
	var passed: int = 0
	for row in _results:
		if bool(row.get("status", false)):
			passed += 1
	print("[COLLISION_BUILDER_INNER] SUMMARY passed=", passed, " total=", total)
	quit(0 if passed == total else 1)
