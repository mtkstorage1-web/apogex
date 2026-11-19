## Shared terrain-aware routing for friendly and rival crews.
class_name ArenaNavigation
extends RefCounted

var grid := AStarGrid2D.new()
var paths := {}

func build(blockers: Array) -> void:
	grid.region = Rect2i(-42, -42, 85, 85)
	grid.cell_size = Vector2(2, 2)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()
	for x in range(-42, 43):
		for z in range(-42, 43):
			var point := Vector2(x * 2.0, z * 2.0)
			for obstacle in blockers:
				var blocked := false
				if obstacle.has("half"):
					var half: Vector2 = obstacle["half"] + Vector2.ONE * 0.8
					var delta: Vector2 = (point - obstacle["c"]).abs()
					blocked = delta.x < half.x and delta.y < half.y
				else:
					blocked = point.distance_to(obstacle["c"]) < float(obstacle["r"]) + 0.8
				if blocked:
					grid.set_point_solid(Vector2i(x, z))
					break

func safe_cell(at: Vector3) -> Vector2i:
	var base := Vector2i(roundi(at.x / 2.0), roundi(at.z / 2.0))
	var best := base
	var cost := INF
	for x in range(-6, 7):
		for z in range(-6, 7):
			var cell := base + Vector2i(x, z)
			if not grid.is_in_boundsv(cell) or grid.is_point_solid(cell): continue
			var distance := Vector2(cell.x * 2.0 - at.x, cell.y * 2.0 - at.z).length_squared()
			if distance < cost:
				cost = distance
				best = cell
	return best

func next_point(id: int, at: Vector3, target: Vector3) -> Vector3:
	var end := safe_cell(target)
	var start := safe_cell(at)
	if grid.is_point_solid(start) or grid.is_point_solid(end): return at
	var cached: Dictionary = paths.get(id, {})
	if cached.is_empty() or cached["goal"] != end:
		cached = {"goal": end, "path": grid.get_point_path(start, end), "index": 0}
		paths[id] = cached
	var path: PackedVector2Array = cached["path"]
	if path.is_empty(): return at
	var index: int = cached["index"]
	while index < path.size() - 1 and Vector2(at.x, at.z).distance_to(path[index]) < 1.1:
		index += 1
	cached["index"] = index
	if index == path.size() - 1 and Vector2(at.x, at.z).distance_to(path[index]) < 1.1: return target
	return Vector3(path[index].x, 0, path[index].y)
