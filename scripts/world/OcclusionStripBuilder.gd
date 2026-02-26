extends RefCounted
class_name OcclusionStripBuilder

const STRIP_HEIGHT := 8.0

func build_strips(
    tilemap: TileMap,
    chunk_pos: Vector2i,
    chunk_size: int,
    walls_layer: int,
    walls_source_id: int
) -> Node2D:
    if tilemap == null:
        return null

    var tile_size := Vector2(32, 32)
    if tilemap.tile_set:
        tile_size = Vector2(tilemap.tile_set.tile_size)

    var start_x := chunk_pos.x * chunk_size
    var start_y := chunk_pos.y * chunk_size
    var end_x   := start_x + chunk_size - 1
    var end_y   := start_y + chunk_size - 1
    var margin  := 1

    var wall_lookup: Dictionary = {}
    for y in range(start_y - margin, end_y + margin + 1):
        for x in range(start_x - margin, end_x + margin + 1):
            var cell := Vector2i(x, y)
            if tilemap.get_cell_source_id(walls_layer, cell) == walls_source_id:
                wall_lookup[cell] = true

    var container := Node2D.new()
    container.name = "OcclusionStrips_%d_%d" % [chunk_pos.x, chunk_pos.y]

    for y in range(start_y, end_y + 1):
        var run_start_x := start_x
        var in_run := false

        for x in range(start_x, end_x + 2):
            var cell := Vector2i(x, y)
            var north_exposed := (
                wall_lookup.has(cell) and
                not wall_lookup.has(cell + Vector2i(0, -1))
            )

            if north_exposed:
                if not in_run:
                    run_start_x = x
                    in_run = true
                continue

            if not in_run:
                continue

            var run_end_x := x - 1
            var len_tiles := run_end_x - run_start_x + 1
            in_run = false
            if len_tiles <= 0:
                continue

            var area := Area2D.new()
            area.name = "NorthStrip_%d_%d_%d" % [run_start_x, y, run_end_x]
            area.collision_layer = 0
            area.collision_mask  = 1   # detecta player (layer 1)

            var shape := CollisionShape2D.new()
            var rect  := RectangleShape2D.new()
            rect.size = Vector2(float(len_tiles) * tile_size.x, STRIP_HEIGHT)
            shape.shape = rect

            var lc := tilemap.map_to_local(Vector2i(run_start_x, y))
            var rc := tilemap.map_to_local(Vector2i(run_end_x, y))
            area.position = Vector2(
                (lc.x + rc.x) * 0.5,
                lc.y - tile_size.y * 0.5 + STRIP_HEIGHT * 0.5
            )
            area.add_child(shape)
            container.add_child(area)

    if container.get_child_count() == 0:
        container.queue_free()
        return null

    return container
