class_name WorldStreamingManager
extends Node
## Top-level streaming coordinator: regions + threaded chunk loader + residency budget + LOD. Authoritative
## per-region state is mirrored into the residency manager when a region retires and restored when it activates.

signal region_activated(id: StringName)
signal region_retired(id: StringName)

var loader: SceneChunkLoader
var residency: AssetResidencyManager
var lod: EnvironmentLODController
var regions: RegionStreamingController
var quality_preset: String = "HIGH"
var _debris_field: Node = null

const ACTIVATIONS := {"LOW": 1, "MEDIUM": 1, "HIGH": 2, "ULTRA": 3}


func setup(world_cfg: WorldConfig) -> void:
	quality_preset = world_cfg.quality_preset.to_upper()
	loader = SceneChunkLoader.new()
	loader.name = "SceneChunkLoader"
	add_child(loader)
	residency = AssetResidencyManager.new()
	residency.name = "AssetResidencyManager"
	add_child(residency)
	lod = EnvironmentLODController.new()
	lod.name = "EnvironmentLODController"
	add_child(lod)
	regions = RegionStreamingController.new()
	regions.name = "RegionStreamingController"
	add_child(regions)
	regions.setup(world_cfg.planet_radius)
	regions.set_budget_check(func(mb: float) -> bool: return residency.can_fit(mb))
	regions.region_activated.connect(_on_region_activated)
	regions.region_retired.connect(_on_region_retired)
	regions.bind_chunk_path(&"orbital_debris_belt", "res://scenes/orbital/DebrisField.tscn")
	set_quality(quality_preset)


func set_quality(preset: String) -> void:
	quality_preset = preset.to_upper()
	residency.set_quality(quality_preset)
	regions.max_activations_per_frame = ACTIVATIONS.get(quality_preset, 2)


func bind_debris_field(field: Node) -> void:
	_debris_field = field


## Registers a node with the LOD controller (ranges default to the standard tiers).
func register_lod(id: StringName, node: Node3D, ranges: Array = EnvironmentLODController.DEFAULT_RANGES) -> void:
	lod.register(id, node, ranges)


func update_streaming(focus_planet_pos: Vector3, velocity: Vector3, camera_forward: Vector3, altitude: float, _delta: float, camera_render_pos: Vector3 = Vector3.INF) -> void:
	for id in regions.get_region_ids():
		if loader.get_status(regions.get_region(id)["chunk_path"]) == SceneChunkLoader.Status.IDLE and regions.get_state(id) == RegionStreamingController.ChunkState.REQUESTED:
			var p: String = regions.get_region(id)["chunk_path"]
			if p != "":
				loader.request(p)
	loader.poll()
	loader.take_ready(2)
	regions.update(focus_planet_pos, velocity, camera_forward, func(path: String) -> bool:
		return loader.get_status(path) != SceneChunkLoader.Status.LOADING)
	if camera_render_pos != Vector3.INF:
		lod.update(camera_render_pos, altitude)
	else:
		lod.global_tier = EnvironmentLODController.resolve_tier(altitude, [800.0, 1800.0, 4000.0], lod.global_tier)


func _on_region_activated(id: StringName) -> void:
	var rg: Dictionary = regions.get_region(id)
	# Restore authoritative state captured at the last retirement (if any).
	if residency.has_world_state(id):
		residency.get_world_state(id)
	residency.make_resident(id, rg["mb"])
	if id == &"orbital_debris_belt" and _debris_field != null and is_instance_valid(_debris_field):
		_debris_field.call("set_detail_active", true)
	region_activated.emit(id)


func _on_region_retired(id: StringName) -> void:
	residency.set_world_state(id, {"retired_transitions": regions.transitions_count, "region": String(id)})
	residency.retire(id)
	if id == &"orbital_debris_belt" and _debris_field != null and is_instance_valid(_debris_field):
		_debris_field.call("set_detail_active", false)
	region_retired.emit(id)


func get_streaming_stats() -> Dictionary:
	var C = RegionStreamingController.ChunkState
	return {
		"active_regions": regions.get_count(C.ACTIVE),
		"ready_regions": regions.get_count(C.READY),
		"loading_regions": regions.get_count(C.REQUESTED) + regions.get_count(C.LOADING),
		"unloaded_regions": regions.get_count(C.UNLOADED),
		"retiring_regions": regions.get_count(C.RETIRING),
		"residency_mb": residency.get_residency_mb(),
		"budget_mb": residency.get_budget_mb(),
		"transitions_count": regions.transitions_count,
		"lod_tier": lod.global_tier,
	}
