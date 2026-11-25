extends SceneTree

const WorldScene = preload("res://scenes/world/WorldRoot.tscn")
const Fleet = preload("res://scripts/vehicles/VehicleManager.gd")
const Vehicle = preload("res://scripts/vehicles/VehicleBase.gd")
const Craft = preload("res://scripts/vehicles/SpacecraftController.gd")
const Rover = preload("res://scripts/vehicles/RoverController.gd")
const Shot = preload("res://scripts/vehicles/Projectile.gd")

var _world: WorldRoot
var _failures := 0
var _raw_models: Array[PackedScene] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, detail: String) -> void:
	if not condition:
		_failures += 1
	print("%s %s" % ["PASS" if condition else "FAIL", detail])


func _steps(count: int) -> void:
	for i in count:
		await physics_frame


func _run() -> void:
	if OS.has_environment("APOGEX_TEST_RAW_GLB"):
		_cache_raw_models()
	_world = WorldScene.instantiate() as WorldRoot
	root.add_child(_world)
	await _steps(8)
	if _world.vehicle_manager == null:
		_check(false, "world initialized its vehicle fleet")
		quit(1)
		return

	_check_scenes()
	_check_fleet()
	await _check_boarding()
	await _check_flight()
	await _check_landing()
	await _check_rover()
	await _check_weapons()
	await _check_regeneration()

	_world.queue_free()
	await process_frame
	await process_frame
	print("PASS vehicle suite" if _failures == 0 else "FAIL vehicle suite (%d)" % _failures)
	quit(0 if _failures == 0 else 1)


## Exercise the imported-model path in memory while the Blender export folder stays untouched.
func _cache_raw_models() -> void:
	for key in Fleet.SCENES:
		var path: String = Vehicle.MODEL_DIR + key + ".glb"
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		if document.append_from_file(path, state) != OK:
			_check(false, "%s can be read from the exported GLB" % key)
			continue
		var model := document.generate_scene(state)
		var packed := PackedScene.new()
		if model != null and packed.pack(model) == OK:
			packed.take_over_path(path)
			_raw_models.append(packed)
		else:
			_check(false, "%s generates a usable scene from the exported GLB" % key)
		if model != null:
			model.free()


func _check_scenes() -> void:
	for key in Fleet.SCENES:
		var vehicle := (Fleet.SCENES[key] as PackedScene).instantiate() as Vehicle
		root.add_child(vehicle)
		_check(vehicle.vehicle_id == key and vehicle.collision_layer == 4 and vehicle.collision_mask == 5
			and vehicle.visual.get_child_count() > 0 and vehicle.get_active_camera() != null,
			"%s instantiates with %s model, collision, and camera" % [key, vehicle.model_source])
		if OS.has_environment("APOGEX_TEST_RAW_GLB"):
			_check(vehicle.model_source == "glb", "%s uses the cached Blender model" % key)
		var bounds := _mesh_bounds(vehicle.visual, Transform3D.IDENTITY)
		var expected := Vector3(-vehicle.dimensions.x * 0.5, 0, -vehicle.dimensions.z * 0.5)
		_check(bounds.position.distance_to(expected) < 0.002 and bounds.size.distance_to(vehicle.dimensions) < 0.002,
			"%s %s model is grounded at Y=0 with contract dimensions %s" % [key, vehicle.model_source, bounds])
		vehicle.free()


func _mesh_bounds(node: Node3D, frame: Transform3D) -> AABB:
	var bounds := AABB()
	if node is MeshInstance3D:
		bounds = frame * node.mesh.get_aabb()
	for child in node.get_children():
		if child is Node3D:
			var child_box := _mesh_bounds(child, frame * child.transform)
			if child_box.has_volume():
				bounds = bounds.merge(child_box) if bounds.has_volume() else child_box
	return bounds


func _check_fleet() -> void:
	var fleet := _world.vehicle_manager
	_check(fleet.vehicles.size() == 10, "world spawns all 10 vehicles")
	for vehicle in fleet.vehicles.values():
		var up: Vector3 = vehicle.get_local_up(vehicle.get_ship())
		var start: Vector3 = vehicle.global_position
		var hit: Dictionary = vehicle.raycast(start + up * 0.35, start - up * 0.6)
		var distance: float = (start - Vector3(hit.get("position", Vector3.INF))).dot(up)
		_check(not hit.is_empty() and distance >= -0.015 and distance <= 0.6,
			"%s is flush with solid deck/pad (%.3f m)" % [vehicle.vehicle_id, distance])


func _check_boarding() -> void:
	var explorer := _world.explorer
	var fighter: Vehicle = _world.vehicle_manager.vehicles["helion_fighter_hangar"]
	var up := fighter.get_local_up(fighter.get_ship())
	explorer.teleport_to(fighter.get_planet_position() + fighter.global_basis.x * 9.0 + up,
		-fighter.global_basis.z)
	await _steps(2)
	_check(_world.vehicle_manager.find_nearest_parked(explorer.get_planet_position()) == fighter,
		"fighter is the nearest parked vehicle inside boarding range")
	explorer._unhandled_input(_key(KEY_E))
	_check(_world.get_active_vehicle() == fighter, "E boards nearest fighter")
	await _check_camera_and_exit(fighter)
	for key in ["cinder_dropship_hangar", "helion_rover_terminus"]:
		_check(_world.quick_board_vehicle(key), "%s quick-boards" % key)
		var vehicle := _world.get_active_vehicle()
		if vehicle != null:
			await _check_camera_and_exit(vehicle)


func _check_camera_and_exit(vehicle: Vehicle) -> void:
	var explorer := _world.explorer
	_check(vehicle.is_piloted and explorer.is_piloting and not explorer.visible
		and root.get_camera_3d() == vehicle.get_active_camera(), "%s takes over explorer view" % vehicle.vehicle_type)
	vehicle._unhandled_input(_key(KEY_V))
	_check(vehicle.camera_first_person and root.get_camera_3d() == vehicle.cockpit_camera,
		"%s V switches to cockpit" % vehicle.vehicle_type)
	vehicle._unhandled_input(_key(KEY_V))
	_check(root.get_camera_3d() == vehicle.chase_camera, "%s V restores chase camera" % vehicle.vehicle_type)
	await _steps(4)
	explorer._unhandled_input(_key(KEY_E))
	var release := _key(KEY_E)
	release.pressed = false
	explorer._unhandled_input(release)
	_check(_world.get_active_vehicle() == null, "%s has a safe disembark position" % vehicle.vehicle_type)
	await _steps(14)
	_check(explorer.visible and explorer.grounded and not explorer.is_piloting
		and root.get_camera_3d() == explorer.get_camera(), "%s restores grounded explorer and camera" % vehicle.vehicle_type)


func _key(key: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.pressed = true
	return event


func _check_flight() -> void:
	if not _world.quick_board_vehicle("helion_fighter_hangar"):
		_check(false, "fighter boards for flight test")
		return
	var fighter := _world.get_active_vehicle() as Craft
	var ship := fighter.get_ship()
	_check(fighter.get_flight_regime() == "HANGAR" and ship != null, "fighter begins inside its hangar")
	if ship == null:
		return
	var door_start := fighter.get_planet_position()
	_world.mothership_manager.set_hangar_doors_open(false)
	for i in 420:
		if ship.get_interior().get_door_progress() <= 0.005:
			break
		await _steps(1)
	fighter.set_autopilot_input({"throttle": 1.0, "hover": false})
	await _steps(105)
	var closed_local: Vector3 = ship.planet_to_local(fighter.get_planet_position())
	_check(fighter.get_flight_regime() == "HANGAR" and closed_local.z < 421.0
		and fighter.get_planet_position().distance_to(door_start) > 15.0, "fighter advances under thrust and closed doors block it (local %s)" % closed_local)
	_world.mothership_manager.set_hangar_doors_open(true)
	for i in 180:
		if fighter.get_flight_regime() == "ORBIT":
			break
		await _steps(1)
	_check(fighter.get_flight_regime() == "ORBIT", "fighter clears the open hangar mouth under its own thrust")
	_check(not _world.exit_vehicle() and fighter.is_piloted, "exit in open space leaves the pilot in control")
	fighter.set_autopilot_input({"throttle": -0.55})
	for i in 180:
		if fighter.get_flight_regime() == "HANGAR":
			break
		await _steps(1)
	_check(fighter.get_flight_regime() == "HANGAR", "fighter flies back through the open hangar mouth")
	fighter.set_autopilot_input({"throttle": 1.0, "boost": true})
	for i in 180:
		if fighter.get_flight_regime() == "ORBIT":
			break
		await _steps(1)
	var previous_altitude := fighter.get_altitude()
	for i in 360:
		if fighter.get_flight_regime() == "ATMOSPHERE":
			break
		await _steps(1)
	_check(previous_altitude > Craft.ORBIT_ALTITUDE and fighter.get_altitude() < Craft.ORBIT_ALTITUDE
		and fighter.get_flight_regime() == "ATMOSPHERE",
		"boosted dive reaches atmosphere continuously (%.1f m)" % fighter.get_altitude())
	_check(_world.get_diagnostics().planet_pos.distance_to(fighter.get_planet_position()) < 0.01
		and _world.get_diagnostics().move_mode == fighter.get_flight_regime()
		and fighter.get_boost_ratio() > 0.9, "world telemetry tracks the boosted active craft")
	fighter.set_autopilot_input({"throttle": 0.65})
	for i in 650:
		if fighter.get_height_above_ground() < 120.0:
			break
		await _steps(1)
	fighter.set_autopilot_input({"throttle": 0.0})
	fighter._unhandled_input(_key(KEY_X))
	await _steps(155)
	var up := fighter.get_local_up()
	_check(fighter.get_flight_regime() == "VTOL_HOVER" and fighter.global_basis.y.dot(up) > 0.99
		and fighter.get_speed() < 1.0, "X engages hover and levels to the spherical horizon (%s, dot %.3f, %.1f m/s)" % [fighter.get_flight_regime(), fighter.global_basis.y.dot(up), fighter.get_speed()])
	_world.teleport_to_landmark(0)


func _check_landing() -> void:
	if not _world.quick_board_vehicle("helion_fighter_terminus"):
		_check(false, "surface fighter boards for landing test")
		return
	var fighter := _world.get_active_vehicle() as Craft
	var start := fighter.get_planet_position()
	var up := fighter.get_local_up()
	await _steps(4)
	_check(fighter.get_flight_regime() == "VTOL_HOVER", "low speed near the Terminus pad engages hover automatically")
	fighter.set_autopilot_input({"lift": 1.0, "hover": true})
	for i in 100:
		if (fighter.get_planet_position() - start).dot(up) >= 11.0:
			break
		await _steps(1)
	_check((fighter.get_planet_position() - start).dot(up) >= 11.0, "VTOL lifts vertically above the Terminus pad")

	fighter.set_autopilot_input({"lift": -0.6})
	for i in 160:
		if fighter.get_slide_collision_count() > 0:
			break
		await _steps(1)
	fighter.set_autopilot_input({"throttle": 0.0})
	await _steps(12)
	_check(fighter.get_planet_position().distance_to(start) < 0.85 and _world.exit_vehicle(),
		"fighter touches down on the Terminus pad and exits safely")
	await _steps(12)
	_check(_world.explorer.grounded and _world.get_active_vehicle() == null, "explorer is grounded after surface landing")

func _check_rover() -> void:
	if not _world.quick_board_vehicle("helion_rover_terminus"):
		_check(false, "rover boards for drive test")
		return
	var rover := _world.get_active_vehicle() as Rover
	var start := rover.get_planet_position()
	var heading := -rover.global_basis.z
	rover.set_drive_input(1.0, -0.22, false, false)
	await _steps(67)
	var up := rover.get_local_up()
	_check(rover.velocity.slide(up).length() > 10.0 and start.distance_to(rover.get_planet_position()) > 10.0,
		"Helion rover drives across Terminus above 10 m/s (%.1f m/s, %.1f m displaced)" % [rover.get_speed(), start.distance_to(rover.get_planet_position())])
	_check(rover.grounded and rover.global_basis.y.dot(up) > 0.96, "rover stays grounded and aligned to spherical up")
	_check((-rover.global_basis.z).dot(heading) < 0.995, "rover steers while driving")
	rover.set_drive_input(0.0, 0.0, false, true)
	await _steps(60)
	_check(rover.get_speed() < 0.5, "rover handbrake brings it to a stop")
	_world.teleport_to_landmark(0)


func _check_weapons() -> void:
	var fleet := _world.vehicle_manager
	var shooter: Vehicle = fleet.vehicles["helion_fighter_hangar"]
	var target: Vehicle = fleet.vehicles["cinder_dropship_hangar"]
	var splash_target: Vehicle = fleet.vehicles["cinder_rover_refinery"]
	var position := Vector3(2000.0, 19000.0, 0.0)
	shooter.set_planet_position(position)
	shooter.global_basis = Basis.IDENTITY
	target.set_planet_position(position + Vector3(0, 0, -31))
	target.global_basis = Basis.IDENTITY
	splash_target.set_planet_position(position + Vector3(9.4, 0, -18))
	splash_target.global_basis = Basis.IDENTITY
	_world.floating_origin.check_and_shift(position)
	await _steps(3)

	var guns := shooter.weapon_system
	var initial_shield := target.shield
	_check(guns.fire_primary() and not guns.fire_primary(), "primary fires with rate limiting")
	var projectiles := fleet.projectile_root.get_children().filter(func(child: Node) -> bool: return child is Shot)
	_check(projectiles.size() == 1 and guns.get_weapon_status().heat > 0.0, "primary spawns a swept projectile and builds heat")
	if not projectiles.is_empty():
		var p: Vector3 = projectiles[0].global_position
		var old_origin := _world.floating_origin.current_origin
		fleet.apply_origin(old_origin + Vector3(100.0, 50.0, 0.0))
		_check(projectiles[0].global_position.distance_to(p - Vector3(100.0, 50.0, 0.0)) < 0.01,
			"live projectiles shift with the fleet")
		fleet.apply_origin(old_origin)
	await _steps(9)
	_check(target.shield < initial_shield and guns.get_weapon_status().hits_registered == 1,
		"autocannon sweep hits nearby target and damages shield")
	var shield_before_splash := splash_target.shield
	target.shield = 30.0
	var hull_before_missile := target.health
	_check(guns.fire_secondary() and guns.get_weapon_status().missiles == guns.max_missiles - 1,
		"missile launches and consumes ammunition")
	await _steps(20)
	_check(target.health < hull_before_missile and guns.get_weapon_status().hits_registered == 2,
		"missile impact applies hull damage and registers")
	_check(splash_target.shield < shield_before_splash, "missile splash damages an adjacent vehicle")

	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(16, 6, 0.12)
	collision.shape = shape
	wall.add_child(collision)
	_world.add_child(wall)
	wall.global_position = shooter.global_position + Vector3(0, 3, -13.75)
	await _steps(3)
	var shield_at_wall_test := target.shield
	_check(guns.fire_primary(), "second autocannon barrel fires at the thin-wall test")
	await _steps(8)
	_check(guns.hits_registered == 3 and is_equal_approx(target.shield, shield_at_wall_test),
		"the fast shot hits a 12 cm wall before it reaches the vehicle")
	wall.queue_free()
	await _steps(1)

	var section := &"terminus_outer_perimeter"
	var contact := _world.destruction.get_section_position(section)
	var normal := contact.normalized()
	_world.floating_origin.check_and_shift(contact)
	_world.planet.ensure_area_ready(contact)
	_world.explorer.teleport_to(contact + normal * 42.0, Vector3.FORWARD)
	shooter.global_basis = Basis.looking_at(-normal, Vector3.UP)
	var muzzle: Vector3 = shooter.global_basis * shooter.get_muzzle_local(0, false)
	shooter.set_planet_position(contact + normal * 24.0 - muzzle)
	await _steps(8)
	var initial_state := _world.destruction.get_state(section)
	_check(guns.fire_primary(), "autocannon fires at the Terminus perimeter")
	await _steps(12)
	_check(_world.destruction.get_state(section) == initial_state + 1, "nearby projectile impact advances facility damage")


func _check_regeneration() -> void:
	var fleet := _world.vehicle_manager
	var previous: Vehicle = fleet.vehicles["helion_rover_terminus"]
	_check(_world.quick_board_vehicle("helion_rover_terminus"), "rover boards before regeneration")
	_world.regenerate_world(_world.world_config.world_seed + 1)
	await _steps(6)
	_check(fleet.active_vehicle == null and not _world.explorer.is_piloting
		and root.get_camera_3d() == _world.explorer.get_camera(), "regeneration restores explorer control")
	_check(fleet.vehicles.size() == 10 and not is_instance_valid(previous)
		and fleet.projectile_root.get_child_count() == 0, "regeneration replaces fleet and clears old projectiles")
	_check_fleet()
