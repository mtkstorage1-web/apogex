extends SceneTree

const Coordinate = preload("res://scripts/coordinates/PlanetCoordinate.gd")
const Transforms = preload("res://scripts/coordinates/CoordinateTransformUtils.gd")
const ReferenceFrame = preload("res://scripts/coordinates/LocalReferenceFrame.gd")
const FloatingOrigin = preload("res://scripts/coordinates/FloatingOriginManager.gd")
const WorldCoordinates = preload("res://scripts/coordinates/WorldCoordinateSystem.gd")
const WORLD = preload("res://resources/world_configs/vesper9_world_config.tres")

var _failures := 0


func _init() -> void:
	_test_geographic_coordinates()
	_test_tangent_frames()
	_test_gravity_and_origin()
	print("Coordinates %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(0 if _failures == 0 else 1)


func _test_geographic_coordinates() -> void:
	_check(Transforms.geographic_to_cartesian(0, 0, 0) == Vector3(0, 0, 12000), "Prime meridian is +Z")
	_check(
		Transforms.geographic_deg_to_cartesian(0, 90, 0).distance_to(Vector3.RIGHT * 12000) < 0.001,
		"East longitude is +X"
	)
	for angles: Vector2 in [Vector2(32, -74), Vector2(-61, 159), Vector2(0, 180)]:
		var position := Transforms.geographic_deg_to_cartesian(angles.x, angles.y, -310, 13200)
		var geographic := Transforms.cartesian_to_geographic(position, 13200)
		_check(absf(geographic.latitude - deg_to_rad(angles.x)) < 0.000001, "Latitude round trip")
		_check(absf(angle_difference(geographic.longitude, deg_to_rad(angles.y))) < 0.000001, "Longitude round trip")
		_check(absf(geographic.altitude + 310) < 0.003, "Altitude round trip")
		var degrees := Transforms.cartesian_to_geographic_deg(position, 13200)
		_check(absf(degrees.latitude - angles.x) < 0.0001, "Inverse degree helper")

	var pole := Transforms.unit_dir_to_lat_lon(Vector3.UP)
	_check(absf(pole.x - PI * 0.5) < 0.000001 and pole.y == 0.0, "Polar angles")
	var coordinate := Coordinate.new(Vector3(1, 2, 3), Vector3(4, 5, 6))
	var copy := coordinate.duplicate_coord()
	_check(copy != coordinate and copy.position == coordinate.position and copy.velocity == coordinate.velocity, "Coordinate duplication")
	copy.position = Vector3.ZERO
	_check(coordinate.position == Vector3(1, 2, 3), "Copy has independent state")


func _test_tangent_frames() -> void:
	var center := Vector3(30, -60, 220)
	var frame := ReferenceFrame.new()
	for direction: Vector3 in [Vector3.BACK, Vector3.UP, Vector3.DOWN, Vector3(0.000001, 1, 0), Vector3(-1, 2, 3)]:
		var anchor := center + direction.normalized() * 12000.0
		frame.set_from_planet_position(anchor, center)
		_check(frame.basis.y.distance_to(direction.normalized()) < 0.000001, "Tangent basis local up")
		_check(frame.basis.is_equal_approx(frame.basis.orthonormalized()), "Tangent basis is orthonormal")
		_check(absf(frame.basis.determinant() - 1.0) < 0.000001, "Tangent basis is right-handed")
		_check(frame.planet_to_local(anchor) == Vector3.ZERO, "Anchor maps to local zero")
		var point := Vector3(122.0, -40.5, 80.25)
		_check(frame.planet_to_local(frame.local_to_planet(point)).distance_to(point) < 0.002, "Local frame round trip")


func _test_gravity_and_origin() -> void:
	var world := WorldCoordinates.new()
	world.planet_center = Vector3(20, -70, 140)
	_check(WORLD.world_seed == 4209 and WORLD.planet_name == "VESPER-9", "World resource identity")
	_check(WORLD.planet_radius == world.planet_radius and WORLD.surface_gravity == world.surface_gravity, "World defaults")
	var surface := world.geographic_to_cartesian(0.0, 0.0, 0.0)
	_check(surface == world.planet_center + Vector3.BACK * 12000.0, "Offset planet center")
	_check(world.cartesian_to_geographic(surface).altitude == 0.0, "Offset geographic inverse")
	_check(world.get_surface_tangent_basis(surface).y == Vector3.BACK, "Offset tangent basis")
	_check(world.get_gravity_vector(surface).distance_to(Vector3.FORWARD * 9.81) < 0.00001, "Surface gravity")
	var high_orbit := world.planet_center + Vector3.RIGHT * world.planet_radius * 2.0
	_check(is_equal_approx(world.get_gravity_magnitude(high_orbit), 9.81 / 4.0), "Inverse square gravity")
	_check(is_equal_approx(world.get_gravity_magnitude(world.planet_center + Vector3.UP), 19.62), "Gravity cap")
	_check(world.get_gravity_vector(world.planet_center) == Vector3.ZERO, "Gravity at the center")
	world.gravity_falloff_enabled = false
	_check(is_equal_approx(world.get_gravity_magnitude(high_orbit), 9.81), "Constant gravity")
	_check(world.planet_to_render(surface) == surface, "Identity without floating origin")

	var origin := FloatingOrigin.new()
	world.floating_origin = origin
	var shifts: Array[Vector3] = []
	origin.origin_shifted.connect(func(delta: Vector3, new_origin: Vector3) -> void:
		shifts.append(delta)
		_check(origin.current_origin == new_origin, "Origin is updated before emitting")
	)
	_check(not origin.check_and_shift(Vector3(2000, 0, 0)), "At threshold")
	_check(origin.check_and_shift(surface), "Beyond threshold")
	_check(world.planet_to_render(surface) == Vector3.ZERO, "Focus moves to render origin")
	_check(world.render_to_planet(Vector3.ONE) == surface + Vector3.ONE, "Render inverse")
	_check(not origin.check_and_shift(surface + Vector3.ONE), "Nearby focus stays put")
	var next_focus := surface + Vector3(3000, 0, 0)
	_check(origin.check_and_shift(next_focus) and origin.shift_count == 2, "Multiple origin shifts")
	_check(shifts == [surface, Vector3(3000, 0, 0)], "Signal deltas")
	origin.reset_origin()
	_check(origin.current_origin == Vector3.ZERO and origin.shift_count == 0, "Reset clears origin and count")
	_check(shifts.size() == 3 and shifts.back() == -next_focus, "Reset emits the inverse translation")
	origin.free()
	world.free()


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL %s" % label)
