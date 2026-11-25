class_name PlanetGenerator
extends Node3D

var world_cfg: WorldConfig
var terrain_cfg: TerrainConfig
var coord_sys = null
var noise_stack: TerrainNoiseStack
var material_controller: PlanetMaterialController
var lod_manager: PlanetLODManager
var collision_manager: PlanetCollisionManager
var quality_preset: String = "HIGH"

var _origin: Vector3 = Vector3.ZERO


func initialize(world_cfg_in: WorldConfig, terrain_cfg_in: TerrainConfig, coord_sys_in) -> void:
	world_cfg = world_cfg_in
	terrain_cfg = terrain_cfg_in if terrain_cfg_in != null else TerrainConfig.new()
	coord_sys = coord_sys_in
	terrain_cfg.planet_radius = world_cfg.planet_radius
	if not world_cfg.quality_preset.is_empty():
		quality_preset = world_cfg.quality_preset.to_upper()

	noise_stack = TerrainNoiseStack.new(world_cfg.world_seed, world_cfg.planet_radius)

	material_controller = PlanetMaterialController.new()
	material_controller.name = "MaterialController"
	add_child(material_controller)
	material_controller.set_star_direction(world_cfg.star_direction)
	material_controller.set_planet_center(-_origin)
	material_controller.apply_quality(quality_preset)

	lod_manager = PlanetLODManager.new()
	lod_manager.name = "LODManager"
	add_child(lod_manager)
	# Preset values go into the config BEFORE the faces are built so they are built once.
	lod_manager.set_preset_values(quality_preset, terrain_cfg)
	lod_manager.setup(terrain_cfg, noise_stack, material_controller.material)

	collision_manager = PlanetCollisionManager.new()
	collision_manager.name = "CollisionManager"
	add_child(collision_manager)
	collision_manager.setup(lod_manager, terrain_cfg)


func _apply_preset_to_cfg(preset: String) -> void:
	# Applies preset values and rebuilds the face roots with the new resolution.
	lod_manager.apply_quality_preset(preset)


func regenerate(new_seed: int) -> void:
	world_cfg.world_seed = new_seed
	noise_stack.configure(new_seed, world_cfg.planet_radius)
	collision_manager.active.clear()
	lod_manager.rebuild_all()


func update_for_camera(camera_planet_pos: Vector3, explorer_planet_pos: Vector3) -> void:
	lod_manager.update_lod(camera_planet_pos, explorer_planet_pos, get_process_delta_time())
	collision_manager.update_collision(explorer_planet_pos)


func apply_floating_origin(current_origin: Vector3) -> void:
	_origin = current_origin
	lod_manager.apply_origin(current_origin)
	material_controller.set_planet_center(-current_origin)


func set_quality_preset(preset: String) -> void:
	quality_preset = preset.to_upper()
	world_cfg.quality_preset = quality_preset
	material_controller.apply_quality(quality_preset)
	collision_manager.active.clear()
	lod_manager.apply_quality_preset(quality_preset)


func set_lod_debug(enabled: bool) -> void:
	material_controller.set_lod_debug(enabled)


func ensure_area_ready(planet_pos: Vector3) -> void:
	collision_manager.ensure_collision_at(planet_pos)


func get_stats() -> Dictionary:
	var stats: Dictionary = lod_manager.get_stats()
	stats["collision_patches"] = collision_manager.get_collision_count()
	stats["quality_preset"] = quality_preset
	stats["world_seed"] = world_cfg.world_seed
	stats["lod_debug"] = material_controller.lod_debug_enabled
	return stats


func get_surface_radius(unit_dir: Vector3) -> float:
	return noise_stack.sample_surface_radius(unit_dir)


func get_biome_id_at(unit_dir: Vector3) -> int:
	return noise_stack._biomes.get_dominant_biome(unit_dir)


func get_biome_name_at(unit_dir: Vector3) -> String:
	return noise_stack._biomes.get_biome_name(get_biome_id_at(unit_dir))


## Natural-terrain factor: 1.0 on untouched ground, falls to 0.0 on flattened industrial pads.
func get_natural_factor(unit_dir: Vector3) -> float:
	return noise_stack._biomes.get_exclusion_factor(unit_dir)


func set_wireframe(enabled: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if enabled:
		RenderingServer.set_debug_generate_wireframes(true)
	get_viewport().debug_draw = (
		Viewport.DEBUG_DRAW_WIREFRAME if enabled else Viewport.DEBUG_DRAW_DISABLED
	)
