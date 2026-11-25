class_name PlanetLODManager
extends Node

const PRESETS: Dictionary = {
	"LOW": {"max_lod": 3, "split": 2.0, "merge": 2.6, "res": 9},
	"MEDIUM": {"max_lod": 4, "split": 2.3, "merge": 2.9, "res": 13},
	"HIGH": {"max_lod": 5, "split": 2.6, "merge": 3.2, "res": 17},
	"ULTRA": {"max_lod": 5, "split": 3.2, "merge": 4.0, "res": 25},
}

var faces: Array[PlanetFace] = []
var cfg: TerrainConfig
var noise: TerrainNoiseStack
var material: Material
var camera_pos: Vector3 = Vector3.ZERO
var explorer_pos: Vector3 = Vector3.ZERO
var update_interval: float = 0.0

var _accum: float = 0.0
var _origin: Vector3 = Vector3.ZERO


func setup(p_cfg: TerrainConfig, p_noise: TerrainNoiseStack, p_material: Material) -> void:
	cfg = p_cfg
	noise = p_noise
	material = p_material
	for f in faces:
		f.queue_free()
	faces.clear()
	for i in 6:
		var face := PlanetFace.new()
		add_child(face)
		face.setup(i, cfg, noise, material)
		faces.append(face)


func update_lod(camera_planet_pos: Vector3, explorer_planet_pos: Vector3, delta: float = 0.0) -> void:
	camera_pos = camera_planet_pos
	explorer_pos = explorer_planet_pos
	_accum += delta
	if update_interval > 0.0 and _accum < update_interval:
		_process_builds()
		return
	_accum = 0.0
	for f in faces:
		f.update_lod(camera_pos, explorer_pos)
	_process_builds()


func _process_builds() -> void:
	var budget: int = cfg.max_patch_builds_per_frame
	for f in faces:
		if budget <= 0:
			break
		budget -= f.process_builds(budget, camera_pos)


func rebuild_all() -> void:
	for f in faces:
		f.rebuild()


func apply_origin(current_origin: Vector3) -> void:
	_origin = current_origin
	for f in faces:
		f.apply_origin(current_origin)


## Writes preset values into the terrain config without rebuilding any geometry.
func set_preset_values(preset: String, p_cfg: TerrainConfig = null) -> bool:
	if p_cfg != null:
		cfg = p_cfg
	var key: String = preset.to_upper()
	if not PRESETS.has(key):
		push_warning("PlanetLODManager: unknown quality preset '%s'" % preset)
		return false
	var p: Dictionary = PRESETS[key]
	cfg.max_lod = p["max_lod"] as int
	cfg.split_distance_factor = p["split"] as float
	cfg.merge_distance_factor = p["merge"] as float
	cfg.patch_resolution = p["res"] as int
	cfg.collision_lod_threshold = mini(cfg.collision_lod_threshold, cfg.max_lod)
	return true


func apply_quality_preset(preset: String) -> void:
	if set_preset_values(preset):
		rebuild_all()


func force_detail_at(planet_pos: Vector3, target_depth: int) -> PlanetPatch:
	var face_idx: int = CubeSphereBuilder.face_from_direction(planet_pos.normalized())
	explorer_pos = planet_pos
	return faces[face_idx].force_descend(planet_pos, target_depth)


func get_leaf_patches() -> Array[PlanetPatch]:
	var out: Array[PlanetPatch] = []
	for f in faces:
		f.collect_leaves(out)
	return out


func get_stats() -> Dictionary:
	var stats: Dictionary = {
		"total_patches": 0,
		"visible_patches": 0,
		"lod_counts": {},
		"queued_builds": 0,
		"collision_patches": 0,
	}
	for f in faces:
		f.collect_stats(stats)
		stats["queued_builds"] = int(stats["queued_builds"]) + f.queue_size()
	return stats
