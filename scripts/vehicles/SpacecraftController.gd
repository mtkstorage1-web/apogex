class_name SpacecraftController
extends "res://scripts/vehicles/VehicleBase.gd"

const ThrusterShader = preload("res://shaders/thruster.gdshader")
const ORBIT_ALTITUDE := 1200.0

@export var cruise_speed := 160.0
@export var boost_speed := 320.0
@export var thrust_acceleration := 71.0
@export var turn_rate := 1.65

var flight_assist := true
var _hover_override := -1
var _auto_hover := false
var _boost := 0.0
var _autopilot := {}
var _right_roll_held := 0.0
var _thruster_material: ShaderMaterial
var _primary_muzzles: Array[Vector3] = []


func _ready() -> void:
	super._ready()
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	_thruster_material = ShaderMaterial.new()
	_thruster_material.shader = ThrusterShader
	_thruster_material.set_shader_parameter("plasma_color", get_energy_color())
	var length := dimensions.z * 0.38
	_thruster_material.set_shader_parameter("plume_length", length)
	for index in 2:
		var side := 1.0 if index == 0 else -1.0
		var side_name := "R" if index == 0 else "L"
		var cannon := get_model_part_bounds("Cannon_%s_Mesh" % side_name)
		if cannon.has_volume():
			var center := cannon.get_center()
			_primary_muzzles.append(Vector3(center.x, center.y, cannon.position.z - 0.12))
		else:
			_primary_muzzles.append(super.get_muzzle_local(index, false))

		var engine_name := "Engine_%s_Mesh" if vehicle_type == "fighter" else "Vector_Engine_%s_1_Mesh"
		var engine := get_model_part_bounds(engine_name % side_name)
		var nozzle := dimensions * Vector3(side * 0.34, 0.43, 0.50)
		var radius := dimensions.x * 0.074
		if engine.has_volume():
			var center := engine.get_center()
			nozzle = Vector3(center.x, center.y, engine.end.z)
			radius = engine.size.x * 0.36
		var cone := CylinderMesh.new()
		cone.top_radius = radius
		cone.bottom_radius = 0.025
		cone.height = length
		cone.cap_top = false
		cone.cap_bottom = false
		var plume := add_visual_mesh(self, "EnginePlume", cone, nozzle + Vector3.BACK * length * 0.5, _thruster_material)
		plume.rotation.x = -PI * 0.5
		plume.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func get_muzzle_local(barrel: int, secondary: bool) -> Vector3:
	return super.get_muzzle_local(barrel, true) if secondary else _primary_muzzles[barrel]

func get_flight_regime() -> String:
	if get_ship() != null:
		return "HANGAR"
	if get_altitude() >= ORBIT_ALTITUDE:
		return "ORBIT"
	if _hover_override == 1 or (_hover_override == -1 and _auto_hover):
		return "VTOL_HOVER"
	return "ATMOSPHERE"


func get_boost_ratio() -> float:
	return _boost


## Throttle/strafe/lift and pitch/yaw/roll are in [-1, 1]. An empty dictionary returns control to the pilot.
func set_autopilot_input(command: Dictionary) -> void:
	_autopilot = command.duplicate()
	if command.has("hover"):
		_hover_override = int(bool(command.hover))
	if command.has("assist"):
		flight_assist = bool(command.assist)


func _vehicle_key(key: Key) -> void:
	match key:
		KEY_X:
			_hover_override = 0 if get_flight_regime() == "VTOL_HOVER" or _hover_override == 1 else 1
		KEY_Z:
			flight_assist = not flight_assist


func _axis(positive: Key, negative: Key) -> float:
	return float(Input.is_physical_key_pressed(positive)) - float(Input.is_physical_key_pressed(negative))


func _physics_process(delta: float) -> void:
	if origin_is_resyncing():
		return
	var throttle := 0.0
	var strafe := 0.0
	var lift := 0.0
	var pitch := 0.0
	var yaw := 0.0
	var roll := 0.0
	var afterburner := false
	if is_piloted:
		if not _autopilot.is_empty():
			throttle = clampf(_autopilot.get("throttle", _autopilot.get("forward", 0.0)), -1.0, 1.0)
			strafe = clampf(_autopilot.get("strafe", 0.0), -1.0, 1.0)
			lift = clampf(_autopilot.get("lift", _autopilot.get("vertical", 0.0)), -1.0, 1.0)
			pitch = clampf(_autopilot.get("pitch", 0.0), -1.0, 1.0) * turn_rate * delta
			yaw = clampf(_autopilot.get("yaw", 0.0), -1.0, 1.0) * turn_rate * delta
			roll = clampf(_autopilot.get("roll", 0.0), -1.0, 1.0) * turn_rate * delta
			afterburner = _autopilot.get("boost", false)
		elif controls_enabled:
			throttle = _axis(KEY_W, KEY_S)
			strafe = _axis(KEY_D, KEY_A)
			lift = _axis(KEY_SPACE, KEY_CTRL)
			pitch = clampf(-look_delta.y * 0.0024, -0.20, 0.20)
			yaw = clampf(-look_delta.x * 0.0024, -0.20, 0.20)
			_right_roll_held = _right_roll_held + delta if Input.is_physical_key_pressed(KEY_E) else 0.0
			roll = (float(Input.is_physical_key_pressed(KEY_Q)) - float(_right_roll_held >= 0.18)) * turn_rate * delta
			afterburner = Input.is_physical_key_pressed(KEY_SHIFT)
	look_delta = Vector2.ZERO

	var ship := get_ship()
	var up := get_local_up(ship)
	var agl := get_height_above_ground()
	var speed := get_speed()
	# Separate engagement and disengagement thresholds keep hover stable during touchdown.
	_auto_hover = agl < (23.0 if _auto_hover else 12.0) and speed < (43.0 if _auto_hover else 24.0)
	var regime := get_flight_regime()
	var stabilized := regime == "HANGAR" or regime == "VTOL_HOVER"
	var air := regime == "ATMOSPHERE"
	_boost = move_toward(_boost, float(afterburner and not stabilized and throttle > 0.0), delta * 3.3)
	_thruster_material.set_shader_parameter("throttle",
		clampf(absf(throttle) * 0.97 + absf(lift) * 0.63 + _boost * 1.03 + float(is_piloted) * 0.09, 0.0, 2.0))

	var frame := global_basis
	if stabilized:
		frame = Basis(up, yaw) * frame
		var forward := (-frame.z).slide(up).normalized()
		if forward.is_zero_approx():
			forward = -Transforms.surface_tangent_basis(up).z
		var level := Basis.looking_at(forward, up)
		frame = frame.slerp(level, 1.0 - exp(-5.0 * delta))
	else:
		frame = frame * Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
		frame = frame * Basis(Vector3.BACK, roll + (yaw * 0.55 if air else 0.0))
		if air and flight_assist and is_zero_approx(roll) and absf(frame.z.dot(up)) < 0.97:
			var level := Basis.looking_at(-frame.z, up)
			frame = frame.slerp(level, 1.0 - exp(-0.9 * delta))
	global_basis = frame.orthonormalized()

	if stabilized:
		var forward := -global_basis.z.slide(up).normalized()
		var right := forward.cross(up)
		var v_limit := 47.0 if ship != null else 28.0
		var target := (forward * throttle + right * strafe).limit_length() * v_limit
		var climb := lift * 17.0
		if ship != null and is_zero_approx(lift) and target.length_squared() > 1.0:
			var floor_hit := raycast(global_position + up * 0.8, global_position - up * 4.0)
			if not floor_hit.is_empty():
				var clearance := (global_position - Vector3(floor_hit.position)).dot(up)
				climb = maxf(0.0, (2.0 - clearance) * 5.0)
		velocity = velocity.move_toward(target + up * climb, thrust_acceleration * delta * (1.0 if ship != null else 2.15))
	else:
		var command := Vector3(strafe, lift, -throttle).limit_length()
		var limit := lerpf(cruise_speed, boost_speed, _boost)
		var acceleration := thrust_acceleration * (1.0 + _boost * 0.67)
		if flight_assist:
			velocity = velocity.move_toward(global_basis * command * limit, acceleration * delta)
		else:
			velocity = (velocity + global_basis * command * acceleration * delta).limit_length(maxf(limit, speed - delta * 12.0))
		if air:
			if coord != null:
				velocity -= up * coord.get_gravity_magnitude(get_planet_position()) * delta * 0.36
			velocity *= exp(-0.09 * delta)
	move_and_slide()


func release_pilot() -> void:
	super.release_pilot()
	_autopilot.clear()
	_right_roll_held = 0.0
	_boost = 0.0
	_thruster_material.set_shader_parameter("throttle", 0.0)
	velocity = Vector3.ZERO
	set_physics_process(false)
