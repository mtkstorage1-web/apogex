extends SceneTree
## Headless bootstrap validation for the Vesper-9 world.
## Run: Godot --headless --path . -s res://tests/world_validation/test_world_bootstrap.gd

const WORLD_SCENE := "res://scenes/world/WorldRoot.tscn"
const SAMPLE_DIRS: Array[Vector3] = [
	Vector3(0, 0, 1), Vector3(0.1, 0.05, 1), Vector3(-0.2, 0.15, 0.97),
	Vector3(0.35, -0.1, 0.9), Vector3(-0.34, 0.0, 0.94), Vector3(0.0, 0.31, 0.95),
]

var _failures: int = 0
var _world: WorldRoot


func _initialize() -> void:
	_run()


func _run() -> void:
	var packed: PackedScene = load(WORLD_SCENE) as PackedScene
	_check(packed != null, "WorldRoot.tscn loads")
	if packed == null:
		quit(1)
		return
	_world = packed.instantiate() as WorldRoot
	root.add_child(_world)
	await _frames(4)

	_test_components()
	await _test_landmark_surface_teleports()
	await _test_gravity_alignment_and_walk()
	_test_prop_grounding()
	await _test_seed_determinism()
	await _test_quality_presets()
	_test_diagnostics()
	_test_actions()
	await _frames(2)

	_world.queue_free()
	await _frames(2)
	print("World bootstrap %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(0 if _failures == 0 else 1)


func _frames(n: int) -> void:
	for i in n:
		await physics_frame
	await process_frame


# ---------------------------------------------------------------------------------------------

func _test_components() -> void:
	_check(_world.ready_complete, "WorldRoot finished _ready")
	_check(_world.planet is PlanetGenerator and _world.planet.lod_manager != null, "PlanetGenerator initialised")
	_check(_world.coord_system is WorldCoordinateSystem, "WorldCoordinateSystem exists")
	_check(_world.floating_origin is FloatingOriginManager, "FloatingOriginManager exists")
	_check(_world.explorer is ExplorerController, "Explorer exists")
	_check(_world.debug_ui is WorldDebugUI, "WorldDebugUI exists")
	_check(_world.atmosphere is AtmosphereController, "Atmosphere exists")
	_check(_world.star != null and _world.star.get_node_or_null("StarSphere") != null, "Star exists")
	_check(_world.space_environment is SpaceEnvironmentController, "SpaceEnvironment exists")
	_check(_world.world_lighting is WorldLighting, "WorldLighting exists")
	_check(_world.landmark_manager is LandmarkManager, "LandmarkManager exists")
	_check(_world.prop_scatterer is SurfacePropScatterer, "SurfacePropScatterer exists")
	_check(_world.surface_effects is SurfaceEffectsController, "SurfaceEffectsController exists")
	_check(_world.landmark_manager.get_count() >= 8, "at least 8 landmarks registered (%d)" % _world.landmark_manager.get_count())
	_check(_world.prop_scatterer.get_instance_count() > 100, "props scattered (%d)" % _world.prop_scatterer.get_instance_count())
	_check(_world.space_environment.starfield.multimesh.visible_instance_count > 1000, "starfield populated")
	_check(_world.world_lighting.environment.tonemap_mode == Environment.TONE_MAPPER_ACES, "ACES tonemapping")
	_check(_world.explorer.altitude > 4000.0, "explorer starts in orbital vantage (alt %.0f)" % _world.explorer.altitude)
	# Faces must be built exactly once at startup: one root patch per face plus no leftovers.
	var stats: Dictionary = _world.planet.get_stats()
	_check(int(stats["total_patches"]) < 200, "no duplicate face build at startup (%d patches)" % int(stats["total_patches"]))


func _test_landmark_surface_teleports() -> void:
	var targets: Array[int] = [1, 3, 5, 6]
	for index in targets:
		_world.teleport_to_landmark(index)
		await _frames(4)
		var lm: Dictionary = _world.landmark_manager.get_landmark(index)
		var label: String = str(lm["name"])
		var ex: ExplorerController = _world.explorer
		var up: Vector3 = ex.get_planet_position().normalized()

		# Terrain collision exists underneath the explorer.
		var space := _world.get_world_3d().direct_space_state
		var from: Vector3 = ex.global_position + up * 12.0
		var query := PhysicsRayQueryParameters3D.create(from, from - up * 60.0, 1)
		var hit: Dictionary = space.intersect_ray(query)
		_check(not hit.is_empty(), "collision under explorer at %s" % label)
		if not hit.is_empty():
			var hit_planet: Vector3 = _world.floating_origin.render_to_planet(hit["position"])
			var surf_r: float = _world.planet.get_surface_radius(hit_planet.normalized())
			_check(absf(hit_planet.length() - surf_r) < 8.0, "collision matches terrain at %s (delta %.2f)" % [label, hit_planet.length() - surf_r])

		# Foundation sits exactly 0.5 m below terrain (never floating).
		var terrain_r: float = _world.planet.get_surface_radius(lm["unit_dir"])
		var base_r: float = (lm["base_pos"] as Vector3).length()
		var delta: float = terrain_r - base_r
		_check(delta >= -0.01 and delta <= 0.5 + 0.01, "no floating foundation at %s (delta %.3f)" % [label, delta])
		var node: Node3D = lm["node"]
		var expect: Vector3 = _world.floating_origin.planet_to_render(lm["base_pos"])
		_check(node.global_position.distance_to(expect) < 0.05, "landmark node matches planet space at %s" % label)
		_check(node.global_basis.y.dot(lm["unit_dir"]) > 0.9999, "landmark oriented to local up at %s" % label)
		_check(node.get_node_or_null("FoundationCollision") != null, "foundation collision at %s" % label)
		# Teleport spot is above ground, not buried.
		_check(ex.height_above_ground > -0.2 and ex.height_above_ground < 3.0, "explorer rests above ground at %s (agl %.2f)" % [label, ex.height_above_ground])
		_check(str(_world.planet.get_biome_name_at(lm["unit_dir"])) != "", "biome resolved at %s" % label)


func _test_gravity_alignment_and_walk() -> void:
	_world.teleport_to_landmark(1)
	await _frames(3)
	var ex: ExplorerController = _world.explorer
	ex.set_move_mode(ExplorerController.MoveMode.WALK)
	ex.gravity_alignment = true
	# Tilt the body away from local up, then let gravity alignment recover it.
	ex.global_basis = (Basis(Vector3.RIGHT, 0.6) * ex.global_basis).orthonormalized()
	await _frames(70)
	var up: Vector3 = ex.get_planet_position().normalized()
	_check(ex.global_basis.y.dot(up) > 0.999, "explorer aligned to planet normal (dot %.5f)" % ex.global_basis.y.dot(up))
	_check(ex.gravity_dir.dot(-up) > 0.999, "gravity direction points to planet centre")
	_check(ex.is_on_floor(), "explorer grounded in walk mode")
	_check(ex.height_above_ground > -0.3 and ex.height_above_ground < 2.2, "walking explorer neither floats nor sinks (agl %.2f)" % ex.height_above_ground)
	var up_dir_ok: bool = ex.up_direction.dot(up) > 0.999
	_check(up_dir_ok, "up_direction = -gravity_dir")
	# Camera planes scale with altitude.
	var near_ground: float = ex.get_camera().near
	_world.teleport_to_landmark(0)
	await _frames(3)
	_check(ex.get_camera().near > near_ground and ex.get_camera().far > 100000.0, "near/far scale with altitude (%.2f / %.0f)" % [ex.get_camera().near, ex.get_camera().far])
	_check(near_ground <= 0.3 and ex.get_camera().far >= 100000.0, "surface planes tight (near %.2f)" % near_ground)
	ex.set_move_mode(ExplorerController.MoveMode.FLY)


func _test_prop_grounding() -> void:
	var scatter: SurfacePropScatterer = _world.prop_scatterer
	var placements: PackedVector3Array = scatter.get_placements()
	_check(placements.size() > 100, "placements recorded (%d)" % placements.size())
	var worst_float: float = -INF
	var worst_sink: float = INF
	var step: int = maxi(placements.size() / 200, 1)
	var i: int = 0
	var blocked_pad: int = 0
	while i < placements.size():
		var p: Vector3 = placements[i]
		var dir: Vector3 = p.normalized()
		var depth: float = _world.planet.get_surface_radius(dir) - p.length()
		worst_float = maxf(worst_float, -depth)
		worst_sink = minf(worst_sink, depth)
		if _world.planet.get_natural_factor(dir) < 0.99:
			blocked_pad += 1
		i += step
	# Foot is embedded between ~0 and 0.31 m below the surface (normal tilt shortens the radial depth).
	_check(worst_float <= 0.02, "no floating props (worst above-ground %.3f)" % worst_float)
	_check(worst_sink > -0.01 and worst_sink < 0.4, "props embedded (min depth %.3f)" % worst_sink)
	_check(blocked_pad == 0, "no props on landing pads")


func _test_seed_determinism() -> void:
	var noise: TerrainNoiseStack = _world.planet.noise_stack
	var original_seed: int = _world.world_config.world_seed
	var base: Array[float] = _heights(noise)
	var base_landmark: Vector3 = _world.landmark_manager.get_landmark(1)["base_pos"]
	_world.regenerate_world(original_seed)
	await _frames(2)
	_check(_heights(noise) == base, "same seed -> identical heights")
	_world.regenerate_world(original_seed + 911)
	await _frames(2)
	_check(_heights(noise) != base, "different seed -> different terrain")
	_check(_world.world_config.world_seed == original_seed + 911, "seed stored")
	# Landmarks follow the new terrain with a valid foundation.
	for idx in [1, 3, 5, 6]:
		var lm: Dictionary = _world.landmark_manager.get_landmark(idx)
		var delta: float = _world.planet.get_surface_radius(lm["unit_dir"]) - (lm["base_pos"] as Vector3).length()
		_check(delta >= -0.01 and delta <= 0.51, "foundation valid after regenerate (landmark %d, %.3f)" % [idx, delta])
	_world.regenerate_world(original_seed)
	await _frames(2)
	_check(_heights(noise) == base, "returning to original seed restores identical heights")
	_check((_world.landmark_manager.get_landmark(1)["base_pos"] as Vector3).is_equal_approx(base_landmark), "landmark placement deterministic")


func _heights(noise: TerrainNoiseStack) -> Array[float]:
	var out: Array[float] = []
	for d in SAMPLE_DIRS:
		out.append(noise.sample_height(d.normalized()))
	return out


func _test_quality_presets() -> void:
	var counts: Dictionary = {}
	var expected_res: Dictionary = {"LOW": 9, "ULTRA": 25, "HIGH": 17}
	for preset in ["LOW", "ULTRA", "HIGH"]:
		_world.set_quality_preset(preset)
		await _frames(3)
		counts[preset] = _world.prop_scatterer.get_instance_count()
		_check(_world.world_config.quality_preset == preset, "%s stored in config" % preset)
		_check(_world.planet.quality_preset == preset, "%s applied to planet" % preset)
		_check(_world.planet.terrain_cfg.patch_resolution == expected_res[preset], "%s patch resolution" % preset)
		_check(_world.prop_scatterer.quality_preset == preset, "%s applied to props" % preset)
		_check(_world.planet.get_stats()["quality_preset"] == preset, "%s reported in stats" % preset)
	_check(counts["LOW"] < counts["HIGH"] and counts["HIGH"] < counts["ULTRA"], "prop density scales with quality %s" % str(counts))
	_check(_world.space_environment.starfield.multimesh.visible_instance_count == SpaceEnvironmentController.STAR_COUNT["HIGH"], "starfield tier follows preset")


func _test_diagnostics() -> void:
	var d: Dictionary = _world.get_diagnostics()
	for key in ["fps", "frame_ms", "memory_mb", "total_patches", "visible_patches", "lod_counts", "collision_patches", "planet_pos", "render_pos", "lat_deg", "lon_deg", "altitude", "biome", "origin_shifts", "move_mode", "camera_mode", "speed"]:
		_check(d.has(key), "diagnostics has %s" % key)
	_check(d.get("origin_shifts", 0) >= 1, "floating origin shifted during landmark travel (%d)" % int(d.get("origin_shifts", 0)))


func _test_actions() -> void:
	var before: int = _world.landmark_manager.current_index
	_world.cycle_landmark()
	_check(_world.landmark_manager.current_index == posmod(before + 1, _world.landmark_manager.get_count()), "cycle_landmark advances")
	_world.toggle_orbit_surface_view()
	_world.toggle_orbit_surface_view()
	_world.toggle_lod_heatmap()
	_check(_world.planet.material_controller.lod_debug_enabled, "LOD heatmap on")
	_world.toggle_lod_heatmap()
	_world.toggle_collision_debug()
	_world.toggle_collision_debug()
	for mode in ExplorerController.CameraMode.size():
		_world.set_camera_mode(mode)
		_check(_world.explorer.camera_mode == mode, "camera mode %d selectable" % mode)
	_world.set_camera_mode(ExplorerController.CameraMode.FREE_FLIGHT)


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL %s" % label)
