class_name RoverController
extends "res://scripts/vehicles/VehicleBase.gd"

@export var drive_speed := 34.0
@export var turbo_speed := 48.0

var grounded := false
var turret_yaw: Node3D
var turret_pitch: Node3D
var _drive_override := Vector4.ZERO
var _has_drive_override := false
var _boost := 0.0
var _dust: GPUParticles3D
var _turret_mount: Node3D
var _wheels: Dictionary[Node3D, float] = {}
var _primary_muzzle_depth := -1.84
var _spring := 0.0
var _spring_speed := 0.0


func _ready() -> void:
	super._ready()
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.85
	floor_constant_speed = true
	_build_turret()
	_build_dust()


func _build_collision() -> void:
	add_box_collision(dimensions * Vector3(0.68, 0.79, 0.83), dimensions * Vector3(0, 0.60, 0))
	_find_wheels(visual)
	for wheel in _wheels:
		var at := to_local(wheel.global_position)
		var radius := at.y
		var sphere := SphereShape3D.new()
		sphere.radius = radius
		var collider := CollisionShape3D.new()
		collider.shape = sphere
		at.x = signf(at.x) * (dimensions.x * 0.5 - radius)
		collider.position = at
		add_child(collider)

func _build_turret() -> void:
	_turret_mount = Node3D.new()
	_turret_mount.name = "TurretMount"
	_turret_mount.position = dimensions * Vector3(0, 0.75, 0.13)
	visual.add_child(_turret_mount)
	turret_yaw = Node3D.new()
	turret_yaw.name = "TurretYaw"
	_turret_mount.add_child(turret_yaw)
	turret_pitch = Node3D.new()
	turret_pitch.name = "TurretPitch"
	turret_pitch.position.y = dimensions.y * 0.09
	turret_yaw.add_child(turret_pitch)
	var alloy := hull_material(Color("285674") if faction == "helion" else Color("70382d"), 0.75)
	var trim := hull_material(get_energy_color(), 0.42, 1.4)
	if model_source == "glb":
		var imported_turret := visual.find_child("Roof_Turret", true, false) as Node3D
		if imported_turret != null:
			var bounds := get_model_part_bounds("Roof_Turret_Mesh")
			_primary_muzzle_depth = bounds.position.z - to_local(imported_turret.global_position).z - 0.12
			_turret_mount.global_position = imported_turret.global_position
			turret_pitch.position = Vector3.ZERO
			imported_turret.reparent(turret_pitch, true)
			return
	var housing := CylinderMesh.new()
	housing.height = dimensions.y * 0.12
	housing.top_radius = dimensions.x * 0.19
	housing.bottom_radius = dimensions.x * 0.23
	housing.radial_segments = 12
	add_visual_mesh(turret_yaw, "TraverseRing", housing, Vector3.ZERO, alloy)
	add_visual_box(turret_pitch, "TurretHousing", dimensions * Vector3(0.39, 0.22, 0.21), dimensions * Vector3(0, 0.05, 0), alloy)
	for side in [-1.0, 1.0]:
		add_visual_box(turret_pitch, "Autocannon", Vector3(0.18, 0.18, 1.75),
			Vector3(side * dimensions.x * 0.13, 0, -0.87), alloy)
		add_visual_box(turret_pitch, "MuzzleCoil", Vector3(0.23, 0.21, 0.25),
			Vector3(side * dimensions.x * 0.13, 0, -1.63), trim)
	add_visual_box(turret_pitch, "MissileTube", Vector3(0.33, 0.20, 1.0), Vector3(0, dimensions.y * 0.12, -0.48), alloy)


func _find_wheels(node: Node3D) -> void:
	for child in node.get_children():
		if not child is Node3D:
			continue
		if String(child.name).begins_with("Wheel"):
			_wheels[child as Node3D] = child.position.y
		else:
			_find_wheels(child)


func _build_dust() -> void:
	_dust = GPUParticles3D.new()
	_dust.name = "TireDust"
	_dust.position = dimensions * Vector3(0, 0.09, 0.42)
	_dust.emitting = false
	_dust.amount = 36
	_dust.lifetime = 0.8
	_dust.local_coords = false
	var particles := ParticleProcessMaterial.new()
	particles.direction = Vector3(0, 0.68, 1)
	particles.spread = 42.0
	particles.gravity = Vector3.ZERO
	particles.initial_velocity_min = 1.7
	particles.initial_velocity_max = 4.9
	particles.scale_min = 0.3
	particles.scale_max = 1.3
	var fade := Gradient.new()
	fade.colors = PackedColorArray([Color(0.70, 0.47, 0.30, 0.48), Color(0.60, 0.34, 0.2, 0.0)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	particles.color_ramp = ramp
	_dust.process_material = particles
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.85, 0.85)
	var dust_material := StandardMaterial3D.new()
	dust_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dust_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	dust_material.vertex_color_use_as_albedo = true
	mesh.material = dust_material
	_dust.draw_pass_1 = mesh
	add_child(_dust)


func get_weapon_transform() -> Transform3D:
	return turret_pitch.global_transform


func get_muzzle_local(barrel: int, secondary: bool) -> Vector3:
	if secondary:
		return Vector3(0, 0.25, -1.02)
	return Vector3(dimensions.x * (0.10 if barrel == 0 else -0.10), 0, _primary_muzzle_depth)


func get_boost_ratio() -> float:
	return _boost


func set_drive_input(throttle: float, steer: float, boost: bool, brake: bool) -> void:
	_drive_override = Vector4(clampf(throttle, -1.0, 1.0), clampf(steer, -1.0, 1.0), float(boost), float(brake))
	_has_drive_override = true


func clear_drive_input() -> void:
	_has_drive_override = false


func _physics_process(delta: float) -> void:
	if origin_is_resyncing():
		return
	var input := Vector4.ZERO
	if is_piloted:
		if _has_drive_override:
			input = _drive_override
		elif controls_enabled:
			input.x = float(Input.is_physical_key_pressed(KEY_W)) - float(Input.is_physical_key_pressed(KEY_S))
			input.y = float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A))
			input.z = float(Input.is_physical_key_pressed(KEY_SHIFT))
			input.w = float(Input.is_physical_key_pressed(KEY_SPACE))
	var ship := get_ship()
	var up := get_local_up(ship)
	up_direction = up
	var floor_up := up
	var ground := raycast(global_position + up, global_position - up * 1.15)
	if not ground.is_empty() and up.dot(ground.normal) >= cos(floor_max_angle):
		floor_up = up.lerp(ground.normal, 0.83).normalized()
	var forward := (-global_basis.z).slide(floor_up).normalized()
	if forward.is_zero_approx():
		forward = -Transforms.surface_tangent_basis(floor_up).z
	var longitudinal := velocity.dot(forward)
	var steer_ratio := smoothstep(0.0, 4.0, absf(longitudinal))
	var turn := -input.y * steer_ratio * signf(longitudinal) * delta * lerpf(1.65, 0.72, absf(longitudinal) / turbo_speed)
	forward = forward.rotated(floor_up, turn)
	var level := Basis.looking_at(forward, floor_up)
	var steered := Basis(floor_up, turn) * global_basis
	global_basis = steered.slerp(level, 1.0 - exp(-12.0 * delta)).orthonormalized()
	_boost = move_toward(_boost, float(input.z > 0.5 and input.x > 0.0 and input.w == 0.0), delta * 2.9)
	var limit := lerpf(drive_speed, turbo_speed, _boost)
	if input.x < 0.0:
		limit = drive_speed * 0.45
	var braking := input.w > 0.5
	var target_speed := 0.0 if braking else input.x * limit
	var acceleration := 36.0 if braking else (18.0 + _boost * 10.0 if not is_zero_approx(input.x) else 12.0)
	var planar_speed := move_toward(longitudinal, target_speed, acceleration * delta)
	var gravity := coord.get_gravity_magnitude(get_planet_position()) if coord != null and ship == null else 9.81
	var falling := minf(velocity.dot(up), 0.0) - gravity * delta
	var traction := (is_on_floor() or not ground.is_empty())
	if traction:
		velocity = forward * planar_speed + up * falling
	else:
		velocity -= up * gravity * delta
	move_and_slide()
	var just_landed := is_on_floor() and not grounded
	grounded = is_on_floor()

	if just_landed:
		_spring_speed -= minf(2.6, absf(falling))
	_spring_speed += (-_spring * 76.0 - _spring_speed * 11.0) * delta
	_spring = clampf(_spring + _spring_speed * delta, -0.13, 0.12)
	visual.position.y = _spring
	for wheel in _wheels:
		wheel.position.y = _wheels[wheel] - _spring
		var axle := Vector3.UP if model_source == "procedural" else Vector3.RIGHT
		wheel.rotate_object_local(axle, -planar_speed * delta / _wheels[wheel])
	turret_yaw.rotation.y -= look_delta.x * 0.0031
	turret_pitch.rotation.x = clampf(turret_pitch.rotation.x - look_delta.y * 0.0031, -0.35, 0.75)
	look_delta = Vector2.ZERO
	_dust.emitting = grounded and ship == null and absf(planar_speed) > 4.0
	if not is_piloted and grounded and get_speed() < 0.05 and absf(_spring_speed) < 0.02:
		velocity = Vector3.ZERO
		set_physics_process(false)


func release_pilot() -> void:
	super.release_pilot()
	clear_drive_input()
	_boost = 0.0
	# Keep the rover simulated while it brakes and settles on the terrain.
