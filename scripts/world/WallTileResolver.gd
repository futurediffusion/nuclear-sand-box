extends RefCounted
class_name WallTileResolver

static func resolve_player_wall_tile_from_contact(
		hit_pos: Vector2,
		hit_normal: Vector2,
		world_to_tile: Callable,
		is_valid_world_tile: Callable,
		is_player_wall_tile: Callable,
		tile_to_world: Callable,
		tile_size_vec: Vector2,
		tile_radius: int = 1
	) -> Vector2i:
	if not world_to_tile.is_valid() or not is_valid_world_tile.is_valid() or not is_player_wall_tile.is_valid():
		return Vector2i(-1, -1)

	var contact_tile: Vector2i = world_to_tile.call(hit_pos)
	if bool(is_valid_world_tile.call(contact_tile)) and bool(is_player_wall_tile.call(contact_tile)):
		return contact_tile

	var inward: Vector2 = -hit_normal
	if inward.length_squared() > 0.000001:
		inward = inward.normalized()
		var probe_offsets: Array[float] = [0.5, 1.0, 2.0, 4.0, 8.0, 12.0]
		for offset in probe_offsets:
			var probe_pos: Vector2 = hit_pos + inward * offset
			var probe_tile: Vector2i = world_to_tile.call(probe_pos)
			if not bool(is_valid_world_tile.call(probe_tile)):
				continue
			if bool(is_player_wall_tile.call(probe_tile)):
				return probe_tile

	return find_nearest_player_wall_tile_in_neighborhood(
		hit_pos,
		contact_tile,
		world_to_tile,
		is_valid_world_tile,
		is_player_wall_tile,
		tile_to_world,
		tile_size_vec,
		tile_radius
	)

static func find_nearest_player_wall_tile_in_neighborhood(
		world_center: Vector2,
		center_tile: Vector2i,
		_world_to_tile: Callable,
		is_valid_world_tile: Callable,
		is_player_wall_tile: Callable,
		tile_to_world: Callable,
		tile_size_vec: Vector2,
		tile_radius: int = 1
	) -> Vector2i:
	if not is_valid_world_tile.is_valid() or not is_player_wall_tile.is_valid() or not tile_to_world.is_valid():
		return Vector2i(-1, -1)
	var radius: int = maxi(0, tile_radius)
	var best_tile: Vector2i = Vector2i(-1, -1)
	var best_dist_sq: float = 1.0e30
	var found: bool = false

	for oy in range(-radius, radius + 1):
		for ox in range(-radius, radius + 1):
			var candidate: Vector2i = center_tile + Vector2i(ox, oy)
			if not bool(is_valid_world_tile.call(candidate)):
				continue
			if not bool(is_player_wall_tile.call(candidate)):
				continue
			var dist_sq: float = distance_sq_to_tile_bounds(world_center, candidate, tile_to_world, tile_size_vec)
			var better: bool = false
			if not found:
				better = true
			elif dist_sq < best_dist_sq - 0.0001:
				better = true
			elif absf(dist_sq - best_dist_sq) <= 0.0001:
				better = candidate.y < best_tile.y or (candidate.y == best_tile.y and candidate.x < best_tile.x)
			if not better:
				continue
			found = true
			best_dist_sq = dist_sq
			best_tile = candidate

	if found:
		return best_tile
	return Vector2i(-1, -1)

static func find_nearest_structural_wall_tile(
		world_center: Vector2,
		world_radius: float,
		world_to_tile: Callable,
		is_valid_world_tile: Callable,
		is_structural_wall_tile: Callable,
		tile_to_world: Callable,
		tile_size_vec: Vector2
	) -> Vector2i:
	if not world_to_tile.is_valid() or not is_valid_world_tile.is_valid() or not is_structural_wall_tile.is_valid() or not tile_to_world.is_valid():
		return Vector2i(-1, -1)

	var center_tile: Vector2i = world_to_tile.call(world_center)
	var radius: float = maxf(world_radius, 0.0)
	var tile_size: float = maxf(tile_size_vec.x, tile_size_vec.y)
	var tile_radius: int = maxi(1, int(ceili(radius / tile_size)) + 1)
	var best_tile: Vector2i = Vector2i(-1, -1)
	var best_dist_sq: float = 1.0e30
	var found: bool = false

	for oy in range(-tile_radius, tile_radius + 1):
		for ox in range(-tile_radius, tile_radius + 1):
			var candidate: Vector2i = center_tile + Vector2i(ox, oy)
			if not bool(is_valid_world_tile.call(candidate)):
				continue
			if not bool(is_structural_wall_tile.call(candidate)):
				continue
			var dist_sq: float = distance_sq_to_tile_bounds(world_center, candidate, tile_to_world, tile_size_vec)
			if radius > 0.0 and dist_sq > radius * radius:
				continue
			if not found or dist_sq < best_dist_sq:
				found = true
				best_dist_sq = dist_sq
				best_tile = candidate

	if found:
		return best_tile
	return Vector2i(-1, -1)

static func distance_sq_to_tile_bounds(world_pos: Vector2, tile_pos: Vector2i, tile_to_world: Callable, tile_size_vec: Vector2) -> float:
	if not tile_to_world.is_valid():
		return 1.0e30
	var tile_center: Vector2 = tile_to_world.call(tile_pos)
	var half_ext: Vector2 = tile_size_vec * 0.5
	var min_p: Vector2 = tile_center - half_ext
	var max_p: Vector2 = tile_center + half_ext
	var closest: Vector2 = Vector2(
		clampf(world_pos.x, min_p.x, max_p.x),
		clampf(world_pos.y, min_p.y, max_p.y)
	)
	return world_pos.distance_squared_to(closest)
