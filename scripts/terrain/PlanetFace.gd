class_name PlanetFace
extends Node3D

var face_index: int = 0
var root: PlanetPatch
var cfg: TerrainConfig
var noise: TerrainNoiseStack
var material: Material
var origin: Vector3 = Vector3.ZERO

var _queue: Array[PlanetPatch] = []


func setup(p_face: int, p_cfg: TerrainConfig, p_noise: TerrainNoiseStack, p_material: Material) -> void:
	face_index = p_face
	cfg = p_cfg
	noise = p_noise
	material = p_material
	name = "Face%d" % face_index
	rebuild()


func rebuild() -> void:
	_queue.clear()
	if root != null and is_instance_valid(root):
		root.free_subtree()
	for c in get_children():
		if c is PlanetPatch:
			var pp: PlanetPatch = c as PlanetPatch
			if not pp.discarded:
				pp.free_subtree()
	root = PlanetPatch.new()
	add_child(root)
	root.setup(face_index, 0, Vector2(-1, -1), Vector2(1, 1), noise, cfg.planet_radius, origin, material)
	root.want_visible = true
	_build_now(root)


func _build_now(p: PlanetPatch) -> void:
	p.build_mesh(noise, cfg.patch_resolution, cfg.skirt_depth_ratio)


func update_lod(cam: Vector3, explorer: Vector3) -> void:
	if root != null:
		_evaluate(root, cam, explorer)


func _evaluate(p: PlanetPatch, cam: Vector3, explorer: Vector3) -> void:
	if not p.mesh_built:
		_enqueue(p)
		return
	var d: float = cam.distance_to(p.center_planet_pos)
	if p.children_patches.is_empty():
		if _wants_split(p, d, cam, explorer):
			p.create_children()
			for c in p.children_patches:
				_enqueue(c)
		return
	if _wants_merge(p, d, explorer):
		p.merge()
		return
	if not p.is_split:
		for c in p.children_patches:
			if not c.mesh_built:
				_enqueue(c)
		if p.children_ready():
			p.split()
	if p.is_split:
		for c in p.children_patches:
			_evaluate(c, cam, explorer)


func _is_pinned(p: PlanetPatch, explorer: Vector3) -> bool:
	if explorer == Vector3.ZERO:
		return false
	return p.depth < cfg.collision_lod_threshold and explorer.distance_to(p.center_planet_pos) < p.patch_extent * 0.8


func _wants_split(p: PlanetPatch, d: float, cam: Vector3, explorer: Vector3) -> bool:
	if p.depth >= cfg.max_lod:
		return false
	if p.depth < cfg.min_lod:
		return true
	if _is_pinned(p, explorer):
		return true
	if p.depth >= 2 and _is_behind_horizon(p, cam):
		return false
	return d < p.patch_extent * cfg.split_distance_factor


func _wants_merge(p: PlanetPatch, d: float, explorer: Vector3) -> bool:
	if p.depth < cfg.min_lod:
		return false
	if _is_pinned(p, explorer):
		return false
	return d > p.patch_extent * cfg.merge_distance_factor


func _is_behind_horizon(p: PlanetPatch, cam: Vector3) -> bool:
	var cam_len: float = cam.length()
	if cam_len < 1.0:
		return false
	var cos_a: float = clampf((cam / cam_len).dot(p.center_planet_pos.normalized()), -1.0, 1.0)
	var ang: float = acos(cos_a)
	var horizon: float = acos(clampf(cfg.planet_radius / cam_len, 0.0, 1.0))
	return ang > horizon + p.patch_extent * 0.75 / cfg.planet_radius + 0.1


func _enqueue(p: PlanetPatch) -> void:
	if p.build_queued or p.mesh_built or p.discarded:
		return
	p.build_queued = true
	_queue.append(p)


func queue_size() -> int:
	var n: int = 0
	for p in _queue:
		if is_instance_valid(p) and not p.discarded and not p.mesh_built:
			n += 1
	return n


## Drops freed / discarded / already-built patches (typed sort lambdas cannot take freed objects).
func _purge_queue() -> void:
	var live: Array[PlanetPatch] = []
	for i in _queue.size():
		var item: Variant = _queue[i]
		if not is_instance_valid(item):
			continue
		var p: PlanetPatch = item as PlanetPatch
		if p.discarded or p.mesh_built:
			continue
		live.append(p)
	_queue = live


## Builds up to `budget` queued patches, nearest first. Returns number built.
func process_builds(budget: int, cam: Vector3) -> int:
	if _queue.is_empty() or budget <= 0:
		return 0
	_purge_queue()
	if _queue.is_empty():
		return 0
	_queue.sort_custom(func(a: PlanetPatch, b: PlanetPatch) -> bool:
		return a.center_planet_pos.distance_squared_to(cam) < b.center_planet_pos.distance_squared_to(cam))
	var built: int = 0
	var remaining: Array[PlanetPatch] = []
	for p in _queue:
		if not is_instance_valid(p) or p.discarded or p.mesh_built:
			continue
		if built < budget:
			_build_now(p)
			built += 1
		else:
			remaining.append(p)
	_queue = remaining
	return built


## Synchronously subdivides toward planet_pos until target_depth. Returns the leaf.
func force_descend(planet_pos: Vector3, target_depth: int) -> PlanetPatch:
	var p: PlanetPatch = root
	var target: int = mini(target_depth, cfg.max_lod)
	while p.depth < target:
		if p.children_patches.is_empty():
			p.create_children()
		for c in p.children_patches:
			if not c.mesh_built:
				_build_now(c)
		p.split()
		var best: PlanetPatch = p.children_patches[0]
		var best_d: float = INF
		for c in p.children_patches:
			var dd: float = planet_pos.distance_squared_to(c.center_planet_pos)
			if dd < best_d:
				best_d = dd
				best = c
		p = best
	return p


func collect_leaves(out: Array[PlanetPatch]) -> void:
	if root != null:
		_collect(root, out)


func _collect(p: PlanetPatch, out: Array[PlanetPatch]) -> void:
	if p.is_split:
		for c in p.children_patches:
			_collect(c, out)
	elif p.mesh_built:
		out.append(p)


func collect_stats(stats: Dictionary) -> void:
	for c in get_children():
		if c is PlanetPatch:
			var p: PlanetPatch = c as PlanetPatch
			if p.discarded:
				continue
			stats["total_patches"] = int(stats["total_patches"]) + 1
			if p.mesh_built and p.mesh_instance != null and p.mesh_instance.visible:
				stats["visible_patches"] = int(stats["visible_patches"]) + 1
				var counts: Dictionary = stats["lod_counts"]
				counts[p.depth] = int(counts.get(p.depth, 0)) + 1
			if p.has_collision:
				stats["collision_patches"] = int(stats["collision_patches"]) + 1


func apply_origin(new_origin: Vector3) -> void:
	origin = new_origin
	for c in get_children():
		if c is PlanetPatch:
			(c as PlanetPatch).apply_origin(new_origin)
