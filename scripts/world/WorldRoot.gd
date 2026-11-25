class_name WorldRoot
extends Node3D
## APOGEX Vesper-9 world bootstrap: builds, wires and drives every world subsystem.

const WORLD_CONFIG_PATH := "res://resources/world_configs/vesper9_world_config.tres"
const TERRAIN_CONFIG_PATH := "res://resources/terrain_configs/vesper9_terrain_config.tres"
const Transforms = preload("res://scripts/coordinates/CoordinateTransformUtils.gd")

const PlanetScene: PackedScene = preload("res://scenes/world/Planet.tscn")
const AtmosphereScene: PackedScene = preload("res://scenes/world/Atmosphere.tscn")
const SpaceScene: PackedScene = preload("res://scenes/world/SpaceEnvironment.tscn")
const SurfaceFacilityScript = preload("res://scripts/environment/SurfaceFacilityManager.gd")
const MothershipScript = preload("res://scripts/environment/MothershipManager.gd")
const OrbitalScript = preload("res://scripts/environment/OrbitalEnvironmentManager.gd")
const StarScene: PackedScene = preload("res://scenes/world/Star.tscn")
const LightingScene: PackedScene = preload("res://scenes/world/WorldLighting.tscn")
const ExplorerScene: PackedScene = preload("res://scenes/testing/Explorer.tscn")
const Fleet = preload("res://scripts/vehicles/VehicleManager.gd")
const Vehicle = preload("res://scripts/vehicles/VehicleBase.gd")
const VehicleHUDScene = preload("res://scenes/vehicles/VehicleHUD.tscn")
const DebugUIScene: PackedScene = preload("res://scenes/testing/WorldDebugUI.tscn")

const Engineering = preload("res://scripts/gameplay/EngineeringBuildManager.gd")
const Commander = preload("res://scripts/gameplay/CommanderSystem.gd")
const Feel = preload("res://scripts/gameplay/GameFeelController.gd")
const Match = preload("res://scripts/gameplay/MatchManager.gd")
const AI = preload("res://scripts/ai/AIManager.gd")
const Combat = preload("res://scripts/combat/PlayerCombatComponent.gd")
const Network = preload("res://scripts/multiplayer/NetworkAuthorityManager.gd")
const ObjectiveScene = preload("res://scenes/combat/CaptureObjective.tscn")
const CombatHUDScene = preload("res://scenes/gameplay/CombatHUD.tscn")
const FrontendScene = preload("res://scenes/ui/GameFrontendUI.tscn")

const OBJECTIVE_SITES := [
	{"id": "alpha", "name": "Terminus Extraction Spire", "facility": "extraction", "lat": 0.0, "lon": 0.0, "offset": Vector3(0, 0, -33)},
	{"id": "bravo", "name": "Northern Mining Excavation", "facility": "mining", "lat": 18.0, "lon": 0.0, "offset": Vector3(13, 0, 25)},
	{"id": "charlie", "name": "Eastern Iron Refinery", "facility": "refinery", "lat": 0.0, "lon": 20.0, "offset": Vector3(2, 0.07, 43)},
]

const STAR_ANGULAR_RADIUS := 0.0454  # 2.6 degrees in radians
const STAR_DISTANCE_FRACTION := 0.9
const ORBIT_ALTITUDE_THRESHOLD := 2500.0

signal world_regenerated(new_seed: int)
signal quality_changed(preset: String)
signal teleported(landmark_index: int)

var world_config: WorldConfig
var terrain_config: TerrainConfig
var coord_system: WorldCoordinateSystem
var floating_origin: FloatingOriginManager
var planet: PlanetGenerator
var atmosphere: AtmosphereController
var space_environment: SpaceEnvironmentController
var star: Node3D
var world_lighting: WorldLighting
var prop_scatterer: SurfacePropScatterer
var landmark_manager: LandmarkManager
var surface_facilities: Node3D
var surface_effects: SurfaceEffectsController
var mothership_manager: Node3D
var orbital_environment: OrbitalEnvironmentManager
var streaming: WorldStreamingManager
var weather: WeatherEffectsController
var destruction: DestructionStateController
var world_audio: WorldAudioController
var explorer: ExplorerController
var debug_ui: WorldDebugUI
var vehicle_manager: Fleet
var match_manager: Match
var ai_manager: AI
var player_combat: Combat
var combat_hud: CanvasLayer
var vehicle_hud: CanvasLayer
var frontend_ui: CanvasLayer
var network_authority: Network
var combat_effects: Node3D
var engineering_build_manager: Engineering
var commander_system: Commander
var game_feel: Feel
var capture_objectives: Array[Node3D] = []

var wireframe_enabled: bool = false
var collision_debug_enabled: bool = false
var lod_heatmap_enabled: bool = false
var regeneration_count: int = 0
var ready_complete: bool = false

var _fx_timer: float = 0.0
var _fx_biome: int = 0
var _fx_biome_name: String = ""
var _last_ex_pos: Vector3 = Vector3.ZERO
var _velocity: Vector3 = Vector3.ZERO
var _highlighted: Array[PlanetPatch] = []
var _highlight_material: StandardMaterial3D


func _ready() -> void:
	world_config = (load(WORLD_CONFIG_PATH) as WorldConfig).duplicate() as WorldConfig
	terrain_config = (load(TERRAIN_CONFIG_PATH) as TerrainConfig).duplicate() as TerrainConfig
	_build_world()
	ready_complete = true
	frontend_ui = FrontendScene.instantiate()
	add_child(frontend_ui)
	frontend_ui.setup(self)


func _build_world() -> void:
	coord_system = WorldCoordinateSystem.new()
	coord_system.name = "WorldCoordinateSystem"
	coord_system.planet_radius = world_config.planet_radius
	coord_system.surface_gravity = world_config.surface_gravity
	add_child(coord_system)

	floating_origin = FloatingOriginManager.new()
	floating_origin.name = "FloatingOriginManager"
	add_child(floating_origin)
	coord_system.floating_origin = floating_origin
	floating_origin.origin_shifted.connect(_on_origin_shifted)

	planet = PlanetScene.instantiate() as PlanetGenerator
	planet.name = "Planet"
	add_child(planet)
	planet.initialize(world_config, terrain_config, coord_system)

	world_lighting = LightingScene.instantiate() as WorldLighting
	world_lighting.name = "WorldLighting"
	add_child(world_lighting)
	world_lighting.setup(world_config)

	space_environment = SpaceScene.instantiate() as SpaceEnvironmentController
	space_environment.name = "SpaceEnvironment"
	add_child(space_environment)
	space_environment.setup(world_config)

	star = StarScene.instantiate() as Node3D
	star.name = "Star"
	add_child(star)

	atmosphere = AtmosphereScene.instantiate() as AtmosphereController
	atmosphere.name = "Atmosphere"
	add_child(atmosphere)
	atmosphere.setup(world_config)

	prop_scatterer = SurfacePropScatterer.new()
	prop_scatterer.name = "SurfacePropScatterer"
	add_child(prop_scatterer)
	prop_scatterer.setup(planet.noise_stack, world_config)

	landmark_manager = LandmarkManager.new()
	landmark_manager.name = "LandmarkManager"
	add_child(landmark_manager)
	landmark_manager.setup(planet.noise_stack, world_config)

	surface_facilities = SurfaceFacilityScript.new()
	surface_facilities.name = "SurfaceFacilityManager"
	add_child(surface_facilities)
	surface_facilities.setup(planet.noise_stack, world_config)

	surface_effects = SurfaceEffectsController.new()
	surface_effects.name = "SurfaceEffectsController"
	add_child(surface_effects)
	surface_effects.setup(world_config.quality_preset)

	mothership_manager = MothershipScript.new()
	mothership_manager.name = "MothershipManager"
	add_child(mothership_manager)
	mothership_manager.setup(world_config)

	orbital_environment = OrbitalScript.new()
	orbital_environment.name = "OrbitalEnvironmentManager"
	add_child(orbital_environment)
	orbital_environment.setup(world_config)

	streaming = WorldStreamingManager.new()
	streaming.name = "WorldStreamingManager"
	add_child(streaming)
	streaming.setup(world_config)
	streaming.bind_debris_field(orbital_environment.debris_field)

	weather = WeatherEffectsController.new()
	weather.name = "WeatherEffectsController"
	add_child(weather)
	weather.setup(planet.noise_stack, world_config, world_lighting.environment)

	destruction = DestructionStateController.new()
	destruction.name = "DestructionStateController"
	add_child(destruction)
	destruction.setup(planet.noise_stack, world_config.quality_preset)

	world_audio = Feel.CombatAudio.new()
	world_audio.name = "WorldAudioController"
	add_child(world_audio)
	world_audio.setup(planet.noise_stack, world_config)
	destruction.audio_event.connect(world_audio.on_destruction_audio)

	explorer = ExplorerScene.instantiate() as ExplorerController
	explorer.name = "Explorer"
	add_child(explorer)
	explorer.setup(planet, coord_system, floating_origin)
	explorer.mothership_manager = mothership_manager
	explorer.action_requested.connect(handle_action)

	debug_ui = DebugUIScene.instantiate() as WorldDebugUI
	debug_ui.name = "WorldDebugUI"
	add_child(debug_ui)
	debug_ui.setup(self)
	debug_ui.panel_visibility_changed.connect(_sync_mouse_capture)

	vehicle_manager = Fleet.new()
	vehicle_manager.name = "VehicleManager"
	add_child(vehicle_manager)
	vehicle_manager.setup(self)
	vehicle_manager.active_vehicle_changed.connect(_on_active_vehicle_changed)

	vehicle_hud = VehicleHUDScene.instantiate()
	add_child(vehicle_hud)
	vehicle_hud.get_node("Display").setup(vehicle_manager, explorer, debug_ui)

	_build_gameplay()

	# Orbital vantage over Terminus Basin and the sunlit limb.
	teleport_to_landmark(0)
	_update_environment(0.0)


func _build_gameplay() -> void:
	combat_effects = Node3D.new()
	combat_effects.name = "CombatEffects"
	add_child(combat_effects)
	match_manager = Match.new()
	match_manager.name = "MatchManager"
	add_child(match_manager)
	network_authority = Network.new()
	network_authority.name = "NetworkAuthorityManager"
	add_child(network_authority)
	network_authority.setup(self)
	network_authority.session_changed.connect(_on_network_mode_changed)

	var objectives_root := Node3D.new()
	objectives_root.name = "CaptureObjectives"
	add_child(objectives_root)
	for site in OBJECTIVE_SITES:
		var objective := ObjectiveScene.instantiate() as Node3D
		objective.name = site.id.capitalize()
		objective.objective_id = site.id
		objective.display_name = site.name
		objective.latitude = site.lat
		objective.longitude = site.lon
		objectives_root.add_child(objective)
		objective.captured.connect(match_manager.record_capture)
		capture_objectives.append(objective)
	match_manager.objectives.assign(capture_objectives)
	_place_objectives()

	player_combat = Engineering.FieldCombat.new()
	player_combat.name = "PlayerCombatComponent"
	explorer.add_child(player_combat)
	explorer.combat = player_combat
	player_combat.setup(self, explorer)

	ai_manager = AI.new()
	ai_manager.name = "AIManager"
	add_child(ai_manager)
	ai_manager.setup(self)

	engineering_build_manager = Engineering.new()
	engineering_build_manager.name = "EngineeringBuildManager"
	add_child(engineering_build_manager)
	engineering_build_manager.setup(self)
	commander_system = Commander.new()
	commander_system.name = "CommanderSystem"
	add_child(commander_system)
	commander_system.setup(self)
	game_feel = Feel.new()
	game_feel.name = "GameFeelController"
	add_child(game_feel)
	game_feel.setup(self)
	for faction in Match.FACTIONS:
		mothership_manager.get_ship(faction).setup_defense(self)

	combat_hud = CombatHUDScene.instantiate()
	add_child(combat_hud)
	combat_hud.setup(self)
	combat_hud.panel_visibility_changed.connect(_sync_mouse_capture)


func _place_objectives() -> void:
	for index in capture_objectives.size():
		var site: Dictionary = OBJECTIVE_SITES[index]
		var pad: Dictionary = surface_facilities.get_facility_info(site.facility)
		capture_objectives[index].place_on_pad(pad, site.offset, floating_origin.current_origin)


func _physics_process(delta: float) -> void:
	if not ready_complete:
		return
	if can_simulate_combat():
		ai_manager.update_objectives(delta)
		if not ai_manager.origin_is_resyncing():
			for faction in Match.FACTIONS:
				mothership_manager.get_ship(faction).tick_defense(delta)
	var craft := get_active_vehicle()
	if craft != null and craft.controls_enabled:
		craft.look_delta *= explorer.mouse_sensitivity
	network_authority.poll_local_actions(delta)


# ---------------------------------------------------------------------------------------------
# Per-frame drive
# ---------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not ready_complete or explorer == null:
		return
	if can_simulate_combat():
		match_manager.tick(delta)
	network_authority.tick(delta)
	frontend_ui.update_menu_camera(delta)
	var vehicle := get_active_vehicle()
	var cam := _get_view_camera()
	var ex_pos := _get_focus_position()
	var cam_pos := floating_origin.render_to_planet(cam.global_position)
	planet.update_for_camera(cam_pos, ex_pos)
	floating_origin.check_and_shift(ex_pos)
	if delta > 0.0:
		_velocity = vehicle.velocity if vehicle != null else (ex_pos - _last_ex_pos) / delta
	_last_ex_pos = ex_pos
	_update_environment(delta)
	if streaming != null:
		streaming.update_streaming(ex_pos, _velocity, -cam.global_basis.z, _get_focus_altitude(), delta, cam.global_position)
	if collision_debug_enabled:
		_update_collision_highlight()


func _update_environment(delta: float) -> void:
	var cam := _get_view_camera()
	var cam_render: Vector3 = cam.global_position
	var alt := _get_focus_altitude()
	var up := (_get_focus_position() - coord_system.planet_center).normalized()
	world_lighting.update_for_altitude(alt)
	var fade: float = 1.0 - smoothstep(0.0, 0.85, world_lighting.atmosphere_factor)
	space_environment.set_star_visibility(fade)
	space_environment.track_camera(cam_render, cam.far)
	_update_star(cam_render, cam.far)
	_fx_timer -= delta
	if _fx_timer <= 0.0:
		_fx_timer = 0.25
		_fx_biome = planet.get_biome_id_at(up)
		_fx_biome_name = planet.get_biome_name_at(up)
	surface_effects.follow(cam_render, up, _fx_biome, _get_focus_height())
	weather.follow(cam_render, up, _fx_biome_name, alt, delta)
	world_audio.update_audio(cam_render, alt, _is_focus_inside_ship(), weather.get_storm_intensity(), delta, delta <= 0.0)


func _update_star(cam_render: Vector3, far_plane: float) -> void:
	var dist: float = far_plane * STAR_DISTANCE_FRACTION
	var radius: float = dist * tan(STAR_ANGULAR_RADIUS)
	star.global_position = cam_render + world_config.star_direction.normalized() * dist
	star.scale = Vector3(radius, radius, radius)


func _on_origin_shifted(delta: Vector3, new_origin: Vector3) -> void:
	planet.apply_floating_origin(new_origin)
	atmosphere.apply_origin(new_origin)
	space_environment.apply_origin(new_origin)
	prop_scatterer.apply_origin(new_origin)
	landmark_manager.apply_origin(new_origin)
	surface_facilities.apply_origin(new_origin)
	if mothership_manager != null:
		mothership_manager.apply_origin(new_origin)
	orbital_environment.apply_origin(new_origin)
	weather.apply_origin(new_origin)
	destruction.apply_origin(new_origin)
	world_audio.apply_origin(new_origin)
	if vehicle_manager != null:
		vehicle_manager.apply_origin(new_origin)
	for objective in capture_objectives:
		objective.apply_origin(new_origin)
	if ai_manager != null:
		ai_manager.apply_origin(new_origin)
	if engineering_build_manager != null:
		engineering_build_manager.apply_origin(new_origin)
	if network_authority != null:
		network_authority.replication.apply_origin(new_origin)
	if combat_effects != null:
		for effect in combat_effects.get_children():
			effect.global_position -= delta
			effect.reset_physics_interpolation()
	if player_combat != null:
		player_combat.shift_effects(delta)
	if frontend_ui != null and frontend_ui.menu_camera != null:
		frontend_ui.menu_camera.position -= delta
	if explorer != null:
		explorer.global_position -= delta
		explorer.reset_physics_interpolation()


# ---------------------------------------------------------------------------------------------
# Actions (keyboard + UI)
# ---------------------------------------------------------------------------------------------

func handle_action(action: StringName) -> void:
	match action:
		&"toggle_deploy":
			toggle_deploy()
		&"toggle_scoreboard":
			toggle_scoreboard()
		&"toggle_commander":
			toggle_commander()
		&"build_turret", &"build_shield", &"build_supply":
			request_buildable(String(action).trim_prefix("build_"))
		&"close_combat_panel":
			combat_hud.close_panels()
		&"interact_vehicle":
			if can_mutate_world():
				vehicle_manager.interact()
			elif get_active_vehicle() != null:
				network_authority.request_vehicle_board("")
			else:
				var parked := vehicle_manager.find_nearest_parked(explorer.get_planet_position())
				if parked != null:
					network_authority.request_vehicle_board(parked.vehicle_id)
		&"toggle_map":
			toggle_map()
		&"toggle_settings":
			toggle_settings()
		&"toggle_diagnostics":
			debug_ui.toggle_diagnostics()
		&"toggle_wireframe":
			toggle_wireframe()
		&"toggle_collision_debug":
			toggle_collision_debug()
		&"toggle_lod_heatmap":
			toggle_lod_heatmap()
		&"regenerate":
			if can_mutate_world():
				regenerate_world(world_config.world_seed)
		&"next_landmark":
			cycle_landmark()
		&"toggle_orbit_surface":
			toggle_orbit_surface_view()
		&"toggle_hangar_doors":
			toggle_hangar_doors()
		&"cycle_destruction":
			cycle_destruction()
		&"mouse_capture_changed":
			_sync_vehicle_controls()


func toggle_map() -> void:
	combat_hud.close_panels()
	debug_ui.toggle_map()


func toggle_settings() -> void:
	combat_hud.close_panels()
	debug_ui.toggle_settings()


func toggle_hangar_doors() -> void:
	if mothership_manager != null and can_mutate_world():
		mothership_manager.toggle_hangar_doors()


func cycle_destruction() -> void:
	if can_mutate_world():
		destruction.cycle_all_states()


func toggle_walk_fly() -> void:
	explorer.toggle_move_mode()


func toggle_gravity_alignment() -> void:
	explorer.toggle_gravity_alignment()


func set_camera_mode(mode: int) -> void:
	explorer.set_camera_mode(mode)


func cycle_camera_mode() -> void:
	explorer.cycle_camera_mode()


func toggle_wireframe() -> void:
	wireframe_enabled = not wireframe_enabled
	planet.set_wireframe(wireframe_enabled)


func toggle_collision_debug() -> void:
	collision_debug_enabled = not collision_debug_enabled
	get_tree().debug_collisions_hint = collision_debug_enabled
	# Collision shapes created before the flag flipped carry no debug mesh: rebuild them.
	for p in planet.collision_manager.active:
		if is_instance_valid(p):
			p.remove_collision()
	planet.collision_manager.active.clear()
	if not collision_debug_enabled:
		_clear_collision_highlight()
	planet.collision_manager.update_collision(_get_focus_position())


func toggle_lod_heatmap() -> void:
	lod_heatmap_enabled = not lod_heatmap_enabled
	planet.set_lod_debug(lod_heatmap_enabled)


func _update_collision_highlight() -> void:
	if _highlight_material == null:
		_highlight_material = StandardMaterial3D.new()
		_highlight_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_highlight_material.albedo_color = Color(0.1, 0.9, 1.0, 0.16)
		_highlight_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_highlight_material.no_depth_test = false
	var now: Array[PlanetPatch] = []
	for p in planet.collision_manager.active:
		if is_instance_valid(p) and p.has_collision and p.mesh_instance != null:
			now.append(p)
			p.mesh_instance.material_overlay = _highlight_material
	for old in _highlighted:
		if is_instance_valid(old) and not now.has(old) and old.mesh_instance != null:
			old.mesh_instance.material_overlay = null
	_highlighted = now


func _clear_collision_highlight() -> void:
	for p in _highlighted:
		if is_instance_valid(p) and p.mesh_instance != null:
			p.mesh_instance.material_overlay = null
	_highlighted.clear()


func _sync_mouse_capture() -> void:
	var frontend_modal := get_frontend_state() != "GAMEPLAY"
	explorer.modal_open = frontend_modal or debug_ui.is_any_panel_open()
	if DisplayServer.get_name() != "headless" or (frontend_ui != null and frontend_ui.managed):
		explorer.set_mouse_captured(not explorer.modal_open)
	debug_ui.update_panel_layer()
	_sync_vehicle_controls()


func _sync_vehicle_controls() -> void:
	var vehicle := get_active_vehicle()
	if vehicle != null:
		vehicle.controls_enabled = (explorer.mouse_captured or DisplayServer.get_name() == "headless") and not explorer.modal_open
		vehicle.look_delta = Vector2.ZERO


func _on_frontend_vehicle_damage(_amount: float, _point: Vector3, vehicle: Vehicle) -> void:
	if frontend_ui != null and frontend_ui.managed and vehicle == get_active_vehicle() and vehicle.health <= 0.0:
		_frontend_lose_vehicle.call_deferred(vehicle)


func _frontend_lose_vehicle(vehicle: Vehicle) -> void:
	if get_active_vehicle() == vehicle and is_instance_valid(vehicle) and vehicle.health <= 0.0:
		vehicle_manager.release_for_world_travel()
		player_combat.health = 0.0
		frontend_ui.on_player_eliminated()


func _on_active_vehicle_changed(vehicle: Vehicle) -> void:
	if vehicle != null:
		var damage_callback := _on_frontend_vehicle_damage.bind(vehicle)
		if not vehicle.damaged.is_connected(damage_callback):
			vehicle.damaged.connect(damage_callback)
	_last_ex_pos = _get_focus_position()
	_fx_timer = 0.0
	if frontend_ui != null and frontend_ui.uses_menu_camera():
		frontend_ui.menu_camera.make_current()
	apply_frontend_presentation(false)
	_update_environment(0.0)


func get_active_vehicle() -> Vehicle:
	return vehicle_manager.active_vehicle if vehicle_manager != null else null


func quick_board_vehicle(vehicle_key: String) -> bool:
	if not can_mutate_world():
		return false
	var boarded := vehicle_manager.quick_board_vehicle(vehicle_key)
	if boarded and debug_ui.settings_panel.visible:
		debug_ui.toggle_settings()
	return boarded


func exit_vehicle() -> bool:
	if not can_mutate_world():
		return network_authority.request_vehicle_board("")
	return vehicle_manager.exit_active_vehicle()


func request_board_from_settings(vehicle_key: String) -> bool:
	if can_mutate_world():
		return quick_board_vehicle(vehicle_key)
	return network_authority.request_vehicle_board(vehicle_key)


func request_buildable(kind: String) -> bool:
	return engineering_build_manager.request_local(kind)


func toggle_commander() -> void:
	_close_debug_panels()
	combat_hud.toggle_commander()


func _get_view_camera() -> Camera3D:
	if frontend_ui != null and frontend_ui.uses_menu_camera():
		return frontend_ui.menu_camera
	var vehicle := get_active_vehicle()
	return vehicle.get_active_camera() if vehicle != null else explorer.get_camera()


func _get_focus_position() -> Vector3:
	if frontend_ui != null and frontend_ui.uses_menu_camera():
		return floating_origin.render_to_planet(frontend_ui.menu_camera.global_position)
	var vehicle := get_active_vehicle()
	return vehicle.get_planet_position() if vehicle != null else explorer.get_planet_position()


func _get_focus_altitude() -> float:
	if frontend_ui != null and frontend_ui.uses_menu_camera():
		return _get_focus_position().length() - world_config.planet_radius
	var vehicle := get_active_vehicle()
	return vehicle.get_altitude() if vehicle != null else explorer.altitude


func _get_focus_height() -> float:
	if frontend_ui != null and frontend_ui.uses_menu_camera():
		return _get_focus_altitude()
	var vehicle := get_active_vehicle()
	return vehicle.get_height_above_ground() if vehicle != null else explorer.height_above_ground


func _is_focus_inside_ship() -> bool:
	if frontend_ui != null and frontend_ui.uses_menu_camera():
		return false
	var vehicle := get_active_vehicle()
	return vehicle.get_ship() != null if vehicle != null else explorer.in_ship_interior


# ---------------------------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------------------------

func regenerate_world(new_seed: int) -> void:
	network_authority.reset_live_state()
	commander_system.rebuild()
	engineering_build_manager.rebuild()
	vehicle_manager.release_for_world_travel()
	world_config.world_seed = new_seed
	network_authority.world_seed = new_seed
	planet.regenerate(new_seed)
	prop_scatterer.rebuild()
	landmark_manager.rebuild()
	surface_facilities.rebuild()
	mothership_manager.refresh_placement()
	orbital_environment.rebuild()
	streaming.bind_debris_field(orbital_environment.debris_field)
	weather.rebuild()
	destruction.rebuild()
	world_audio.rebuild()
	vehicle_manager.rebuild()
	_set_fleet_authority(can_mutate_world())
	_clear_combat_effects()
	_place_objectives()
	match_manager.reset_match()
	ai_manager.reset_pool()
	floating_origin.check_and_shift(_get_focus_position())
	regeneration_count += 1
	_clear_collision_highlight()
	if _get_focus_height() < 3000.0:
		planet.ensure_area_ready(_get_focus_position())
	explorer.snap_above_ground()
	debug_ui.refresh_map_pins()
	network_authority.reset_remote_spawns()
	world_regenerated.emit(new_seed)


func set_quality_preset(preset: String) -> void:
	var key: String = preset.to_upper()
	if not PlanetLODManager.PRESETS.has(key):
		push_warning("WorldRoot: unknown quality preset '%s'" % preset)
		return
	world_config.quality_preset = key
	planet.set_quality_preset(key)
	atmosphere.set_quality(key)
	world_lighting.set_quality(key)
	space_environment.set_quality(key)
	prop_scatterer.set_quality_preset(key)
	surface_effects.set_quality(key)
	orbital_environment.set_quality(key)
	streaming.set_quality(key)
	weather.set_quality(key)
	world_audio.set_quality(key)
	_clear_collision_highlight()
	if _get_focus_height() < 3000.0:
		planet.ensure_area_ready(_get_focus_position())
	quality_changed.emit(key)


func teleport_to_landmark(index: int) -> void:
	var lm: Dictionary = landmark_manager.get_landmark(index)
	if lm.is_empty():
		return
	if vehicle_manager != null:
		vehicle_manager.release_for_world_travel()
	landmark_manager.current_index = int(lm["index"])
	var target: Vector3 = lm["planet_pos"]
	floating_origin.check_and_shift(target)
	var is_orbit: bool = lm.get("is_orbit", false)
	if not is_orbit:
		# Terrain + collision must exist before the explorer arrives.
		planet.ensure_area_ready(target)
		planet.ensure_area_ready(lm["surface_pos"])
	if explorer.camera_mode == ExplorerController.CameraMode.PLANET_ORBIT or explorer.camera_mode == ExplorerController.CameraMode.CINEMATIC:
		explorer.set_camera_mode(ExplorerController.CameraMode.FREE_FLIGHT)
	var walk_inside: bool = lm.get("walk", false)
	if is_orbit and not walk_inside:
		explorer.set_move_mode(ExplorerController.MoveMode.FLY)
	explorer.teleport_to(target, lm["look_dir"])
	if walk_inside:
		explorer.set_move_mode(ExplorerController.MoveMode.WALK)
	planet.update_for_camera(target, target)
	_update_environment(0.0)
	teleported.emit(int(lm["index"]))


func cycle_landmark() -> void:
	teleport_to_landmark(landmark_manager.next_index())


func is_orbit_view() -> bool:
	return explorer != null and _get_focus_height() > ORBIT_ALTITUDE_THRESHOLD


## F7: Terminus Basin surface <-> orbital overview.
func toggle_orbit_surface_view() -> void:
	teleport_to_landmark(1 if is_orbit_view() else 0)


func get_diagnostics() -> Dictionary:
	var d: Dictionary = {}
	if planet == null or explorer == null:
		return d
	var stats: Dictionary = planet.get_stats()
	var pp := _get_focus_position()
	var vehicle := get_active_vehicle()
	var geo: Dictionary = Transforms.cartesian_to_geographic_deg(pp, world_config.planet_radius)
	var unit: Vector3 = pp.normalized()
	d["fps"] = Engine.get_frames_per_second()
	d["frame_ms"] = get_process_delta_time() * 1000.0
	d["memory_mb"] = OS.get_static_memory_usage() / 1048576.0
	d["total_patches"] = stats.get("total_patches", 0)
	d["visible_patches"] = stats.get("visible_patches", 0)
	d["queued_builds"] = stats.get("queued_builds", 0)
	d["lod_counts"] = stats.get("lod_counts", {})
	d["collision_patches"] = stats.get("collision_patches", 0)
	d["planet_pos"] = pp
	d["render_pos"] = floating_origin.planet_to_render(pp)
	d["lat_deg"] = geo["latitude"]
	d["lon_deg"] = geo["longitude"]
	d["altitude"] = _get_focus_altitude()
	d["height_above_ground"] = _get_focus_height()
	d["biome"] = planet.get_biome_name_at(unit)
	d["origin_shifts"] = floating_origin.shift_count
	d["move_mode"] = "Walk" if explorer.move_mode == ExplorerController.MoveMode.WALK else "Fly"
	d["camera_mode"] = explorer.get_camera_mode_name()
	d["camera_mode_index"] = explorer.camera_mode
	d["speed"] = explorer.current_speed
	d["gravity_alignment"] = explorer.gravity_alignment
	d["seed"] = world_config.world_seed
	d["quality"] = world_config.quality_preset
	d["wireframe"] = wireframe_enabled
	d["collision_debug"] = collision_debug_enabled
	d["lod_heatmap"] = lod_heatmap_enabled
	d["orbit_view"] = is_orbit_view()
	d["landmark"] = str(landmark_manager.get_landmark(landmark_manager.current_index).get("name", ""))
	d["landmark_count"] = landmark_manager.get_count()
	d["prop_instances"] = prop_scatterer.get_instance_count()
	if surface_facilities != null:
		d["surface_facilities"] = surface_facilities.get_diagnostics()
	if mothership_manager != null:
		d["motherships"] = mothership_manager.get_diagnostics()
		d["hangar_doors_open"] = mothership_manager.is_hangar_doors_open()
		d["in_ship"] = _is_focus_inside_ship()
	d["match"] = match_manager.get_match_summary()
	d["ai"] = {"troopers": ai_manager.troopers.size(), "fighters": ai_manager.fighters.size(), "roster_counts": ai_manager.get_roster_counts()}
	d["network"] = {"mode": network_authority.get_network_mode(), "peer_counts": network_authority.get_peer_counts()}
	d["streaming"] = streaming.get_streaming_stats()
	d["destruction"] = destruction.get_summary()
	d["destruction_states"] = destruction.get_states()
	d["audio"] = world_audio.get_diagnostics()
	d["orbital"] = orbital_environment.get_diagnostics()
	d["weather"] = weather.get_diagnostics()
	d["cloud_formations"] = atmosphere.get_cloud_formations()
	if vehicle != null:
		d["move_mode"] = vehicle.get_flight_regime()
		d["camera_mode"] = "Cockpit" if vehicle.camera_first_person else "Chase"
		d["speed"] = vehicle.get_speed()
		d["vehicle"] = {
			"name": vehicle.display_name,
			"regime": vehicle.get_flight_regime(),
			"health": vehicle.health,
			"shield": vehicle.shield,
			"boost": vehicle.get_boost_ratio(),
			"weapons": vehicle.weapon_system.get_weapon_status(),
		}
	return d


func can_mutate_world() -> bool:
	return network_authority == null or network_authority.is_server_authority()


func can_simulate_combat() -> bool:
	if not can_mutate_world() or match_manager.match_state != "ACTIVE":
		return false
	if frontend_ui == null:
		return true
	return frontend_ui.active_match and (get_frontend_state() != "PAUSED" or network_authority.get_network_mode() == "HOST")


func infantry_spawn(choice: String, faction: String) -> Dictionary:
	if choice == "bridge":
		var ship: Node3D = mothership_manager.get_ship(faction)
		return {"position": ship.local_to_planet(Vector3(110, 9, 205)), "facing": ship.planet_basis.x, "up": ship.planet_basis.y}
	if choice == "hangar":
		var frame: Basis = mothership_manager.ship_basis(faction)
		return {"position": mothership_manager.get_room_planet_point(faction, "Main Hangar"), "facing": frame.z, "up": frame.y}
	var objective := ai_manager.objective_by_id(choice)
	if objective == null:
		return {}
	return {
		"position": objective.planet_position + objective.global_basis * Vector3(0, 1.0, -7.0),
		"facing": objective.global_basis.z, "up": objective.global_basis.y,
	}


func place_infantry(choice: String, target: Vector3, facing: Vector3) -> void:
	vehicle_manager.release_for_world_travel()
	floating_origin.check_and_shift(target)
	if choice not in ["hangar", "bridge"]:
		planet.ensure_area_ready(target)
	explorer.set_move_mode(ExplorerController.MoveMode.WALK)
	explorer.teleport_to(target, facing)
	explorer.reset_physics_interpolation()
	_update_environment(0.0)


func deploy_player(choice: String) -> bool:
	if choice not in ["hangar", "bridge", "alpha", "bravo", "charlie", "fighter"]:
		return false
	if not can_mutate_world():
		return choice not in ["fighter", "bridge"] and network_authority.request_player_deploy(choice)
	var faction := match_manager.player_faction
	if choice == "fighter":
		if not quick_board_vehicle(faction + "_fighter_hangar"):
			return false
	else:
		var placement := infantry_spawn(choice, faction)
		place_infantry(choice, placement.position, placement.facing)
	player_combat.spawn_choice = "hangar" if choice == "fighter" else choice
	player_combat.reset_for_spawn()
	combat_hud.close_panels()
	return true


func switch_faction(faction: String) -> bool:
	if not network_authority.set_host_faction(faction) or not match_manager.switch_faction(faction):
		return false
	return deploy_player("hangar")


func switch_to_other_faction() -> void:
	switch_faction("cinder" if match_manager.player_faction == "helion" else "helion")


func reset_combat_match(deploy_local: bool = true) -> void:
	if can_mutate_world():
		commander_system.rebuild()
		engineering_build_manager.rebuild()
		match_manager.reset_match()
		_clear_combat_effects()
		ai_manager.reset_pool()
		for vehicle in vehicle_manager.vehicles.values():
			vehicle.heal_full()
		if deploy_local:
			deploy_player("hangar")


func get_frontend_state() -> String:
	return frontend_ui.state if frontend_ui != null else "GAMEPLAY"


func open_main_menu() -> void:
	frontend_ui.open_main_menu()


func open_lobby() -> void:
	frontend_ui.open_lobby()


func open_spawn_screen() -> void:
	frontend_ui.open_spawn_screen()


func open_pause_menu() -> void:
	frontend_ui.open_pause_menu()


func resume_gameplay() -> void:
	frontend_ui.resume_gameplay()


func deploy_from_frontend(spawn_id: String, faction: String, role: String) -> bool:
	return frontend_ui.deploy_from_frontend(spawn_id, faction, role)


func enter_sandbox_mode() -> void:
	frontend_ui.enter_sandbox_mode()


func close_frontend_modals() -> void:
	_close_debug_panels()
	combat_hud.close_panels()


func apply_frontend_presentation(close_modals: bool = true) -> void:
	var gameplay := get_frontend_state() == "GAMEPLAY"
	var sandbox_mode: bool = frontend_ui != null and frontend_ui.sandbox
	if close_modals:
		close_frontend_modals()
	combat_hud.visible = gameplay and not sandbox_mode
	# On foot this layer only draws the contextual boarding prompt.
	vehicle_hud.visible = gameplay
	debug_ui.set_dev_bar_visible((gameplay or get_frontend_state() == "PAUSED") and frontend_ui != null and frontend_ui.dev_bar_enabled)
	if not gameplay:
		player_combat.viewmodel.hide()
	_sync_mouse_capture()


func frontend_fighter_available(faction: String) -> bool:
	var craft: Vehicle = vehicle_manager.vehicles.get(faction + "_fighter_hangar")
	return craft != null and craft.health > 0.0 and (craft == get_active_vehicle() or (not craft.is_piloted and craft.get_speed() <= 1.0)) and craft.get_ship() == mothership_manager.get_ship(faction)


func toggle_deploy() -> void:
	if frontend_ui != null and frontend_ui.managed:
		frontend_ui.handle_key(KEY_B)
	else:
		_close_debug_panels()
		combat_hud.toggle_deploy()


func toggle_scoreboard() -> void:
	_close_debug_panels()
	combat_hud.toggle_scoreboard()


func _close_debug_panels() -> void:
	if debug_ui.settings_panel.visible:
		debug_ui.toggle_settings()
	if debug_ui.map_panel.visible:
		debug_ui.toggle_map()


func toggle_network_host() -> void:
	if network_authority.get_network_mode() == "OFFLINE":
		var error := network_authority.host_server(Network.DEFAULT_PORT, world_config.world_seed)
		if error != OK:
			debug_ui.status_label.text = "Host failed · " + error_string(error)
	else:
		network_authority.disconnect_session()


func _on_network_mode_changed(mode: String) -> void:
	var authority := mode != "CLIENT"
	if not authority or mode == "OFFLINE":
		vehicle_manager.release_for_world_travel()
		for effect in vehicle_manager.projectile_root.get_children():
			effect.queue_free()
	_set_fleet_authority(authority)


func _set_fleet_authority(enabled: bool) -> void:
	vehicle_manager.set_physics_process(enabled)
	for vehicle in vehicle_manager.vehicles.values():
		vehicle.set_process(enabled)
		vehicle.weapon_system.set_physics_process(enabled)
		if not enabled:
			vehicle.set_physics_process(false)


func _clear_combat_effects() -> void:
	for effect in combat_effects.get_children():
		combat_effects.remove_child(effect)
		effect.queue_free()
