class_name PlanetCollisionManager
extends Node

var lod: PlanetLODManager
var cfg: TerrainConfig
var active: Array[PlanetPatch] = []
var max_new_per_frame: int = 3


func setup(p_lod: PlanetLODManager, p_cfg: TerrainConfig) -> void:
	lod = p_lod
	cfg = p_cfg


func update_collision(explorer_planet_pos: Vector3) -> void:
	if lod == null:
		return
	var leaves: Array[PlanetPatch] = lod.get_leaf_patches()
	var wanted: Dictionary = {}
	var closest: PlanetPatch = null
	var best: float = INF
	for leaf in leaves:
		var d: float = explorer_planet_pos.distance_to(leaf.center_planet_pos)
		if d < best:
			best = d
			closest = leaf
		var detailed: bool = leaf.depth >= cfg.collision_lod_threshold and d < leaf.patch_extent * 1.5
		if detailed or d < leaf.patch_extent * 0.9:
			wanted[leaf] = true
	if closest != null:
		wanted[closest] = true

	var keep: Array[PlanetPatch] = []
	for p in active:
		if not is_instance_valid(p):
			continue
		if wanted.has(p) and not p.discarded:
			keep.append(p)
		else:
			p.remove_collision()
	active = keep

	var built: int = 0
	for key in wanted.keys():
		var patch: PlanetPatch = key as PlanetPatch
		if patch.has_collision:
			if not active.has(patch):
				active.append(patch)
			continue
		if patch == closest or built < max_new_per_frame:
			patch.build_collision()
			built += 1
			active.append(patch)


## Synchronously guarantees solid ground beneath planet_pos (e.g. right after teleport).
func ensure_collision_at(planet_pos: Vector3) -> void:
	if lod == null:
		return
	# Descend to the finest LOD so flattened pads / fissures are matched by the collision mesh.
	var leaf: PlanetPatch = lod.force_detail_at(planet_pos, cfg.max_lod)
	leaf.build_collision()
	if not active.has(leaf):
		active.append(leaf)
	update_collision(planet_pos)


func get_collision_count() -> int:
	var n: int = 0
	for p in active:
		if is_instance_valid(p) and p.has_collision:
			n += 1
	return n
