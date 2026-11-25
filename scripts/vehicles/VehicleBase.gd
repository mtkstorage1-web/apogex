class_name VehicleBase
extends CharacterBody3D

const Transforms = preload("res://scripts/coordinates/CoordinateTransformUtils.gd")
const Weapons = preload("res://scripts/vehicles/VehicleWeaponSystem.gd")
const MODEL_DIR := "res://assets/models/apogex/vehicles/"
const WORLD_MASK := 1
const VEHICLE_MASK := 4

signal hit_confirmed
signal exit_refused
signal damaged(amount: float, hit_pos: Vector3)

@export var vehicle_id: String
@export var vehicle_type := "fighter"
@export var faction := "helion"
@export var display_name := "Fighter"
@export var dimensions := Vector3(14.0, 4.2, 16.0)
@export var max_health := 180.0
@export var max_shield := 100.0
@export var shield_regen_rate := 14.0
@export var shield_regen_delay := 4.0
var health: float
var shield: float
var is_piloted := false
var camera_first_person := false
var controls_enabled := true
var model_source := "procedural"

var planet: PlanetGenerator
var coord: WorldCoordinateSystem
var origin_mgr: FloatingOriginManager
var mothership_manager: Node
var destruction_controller: DestructionStateController
var projectile_root: Node3D
var weapon_system: Weapons

var visual: Node3D
var cockpit_camera: Camera3D
var chase_camera: Camera3D
var look_delta := Vector2.ZERO
var _pilot: Node
var _chase_arm: SpringArm3D
var _applied_origin := Vector3.ZERO
var _origin_shift_frame := -2
var _shield_delay := 0.0
var _camera_extent: float
var _chase_extension: float


func _ready() -> void:
	collision_layer = VEHICLE_MASK
	collision_mask = WORLD_MASK | VEHICLE_MASK
	safe_margin = 0.025
	heal_full()
	visual = Node3D.new()
	visual.name = "VehicleVisual"
	add_child(visual)
	var path := MODEL_DIR + "%s_%s.glb" % [faction, vehicle_type]
	if ResourceLoader.exists(path):
		var scene := ResourceLoader.load(path) as PackedScene
		if scene != null:
			visual.add_child(scene.instantiate())
			model_source = "glb"
	if model_source == "procedural":
		_build_fallback()
	_build_collision()
	_build_cameras()
	weapon_system = Weapons.new()
	weapon_system.name = "VehicleWeaponSystem"
	weapon_system.setup(self)
	add_child(weapon_system)
	set_physics_process(false)


func _process(delta: float) -> void:
	_shield_delay = maxf(0.0, _shield_delay - delta)
	if _shield_delay == 0.0 and health > 0.0:
		shield = minf(max_shield, shield + shield_regen_rate * delta)
	if is_piloted:
		_update_cameras(delta)


func get_planet_position() -> Vector3:
	return global_position + _applied_origin


func set_planet_position(p_pos: Vector3) -> void:
	if origin_mgr != null:
		_applied_origin = origin_mgr.current_origin
	global_position = p_pos - _applied_origin
	force_update_transform()
	reset_physics_interpolation()


func apply_origin(new_origin: Vector3) -> void:
	_origin_shift_frame = Engine.get_physics_frames()
	global_position += _applied_origin - new_origin
	_applied_origin = new_origin
	force_update_transform()
	reset_physics_interpolation()


func origin_is_resyncing() -> bool:
	# Kinematic bodies enter the physics broadphase at the next sync after a rebase.
	return Engine.get_physics_frames() <= _origin_shift_frame + 1


func get_speed() -> float:
	return velocity.length()


func get_altitude() -> float:
	if coord == null:
		return 0.0
	return get_planet_position().distance_to(coord.planet_center) - coord.planet_radius


func get_height_above_ground() -> float:
	if planet == null or coord == null:
		return 0.0
	var relative := get_planet_position() - coord.planet_center
	return relative.length() - planet.get_surface_radius(relative.normalized())


func get_ship() -> Node3D:
	if mothership_manager == null:
		return null
	return mothership_manager.find_ship_containing(get_planet_position()) as Node3D


func get_local_up(ship: Node3D = null) -> Vector3:
	if ship != null:
		return ship.get_local_up_direction()
	return -coord.get_gravity_direction(get_planet_position()) if coord != null else Vector3.UP


func get_flight_regime() -> String:
	return "GROUND"


func get_boost_ratio() -> float:
	return 0.0


func board(explorer: Node) -> void:
	if is_piloted or health <= 0.0:
		return
	_pilot = explorer
	is_piloted = true
	if is_instance_valid(_pilot):
		_pilot.set_piloting_state(true)
	set_first_person(camera_first_person)
	_update_cameras(1.0)
	set_physics_process(true)


func release_pilot() -> void:
	is_piloted = false
	look_delta = Vector2.ZERO
	_pilot = null


func exit_vehicle() -> Vector3:
	if get_speed() > 4.0:
		exit_refused.emit()
		return get_planet_position()
	var up := get_local_up(get_ship())
	var forward := -global_basis.z.slide(up).normalized()
	if forward.is_zero_approx():
		forward = -Transforms.surface_tangent_basis(up).z
	var right := forward.cross(up)
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	var fit := PhysicsShapeQueryParameters3D.new()
	fit.shape = capsule
	fit.collision_mask = collision_mask
	var space := get_world_3d().direct_space_state
	for offset in [right * (dimensions.x * 0.5 + 1.35), -right * (dimensions.x * 0.5 + 1.35),
			-forward * (dimensions.z * 0.5 + 1.35), forward * (dimensions.z * 0.5 + 1.35)]:
		var side: Vector3 = global_position + offset
		var ground := raycast(side + up * 1.5, side - up * 2.5)
		if ground.is_empty() or up.dot(ground.normal) < cos(deg_to_rad(55.0)):
			continue
		var stand: Vector3 = ground.position + up * 0.97
		fit.transform = Transform3D(Transforms.surface_tangent_basis(up), stand)
		if not space.intersect_shape(fit, 1).is_empty():
			continue
		var exit_position := stand + _applied_origin
		var explorer := _pilot
		release_pilot()
		if is_instance_valid(explorer):
			explorer.set_piloting_state(false)
			explorer.gravity_alignment = true
			explorer.set_move_mode(explorer.MoveMode.WALK)
			explorer.teleport_to(exit_position, forward)
		return exit_position
	exit_refused.emit()
	return get_planet_position()


func get_active_camera() -> Camera3D:
	return cockpit_camera if camera_first_person else chase_camera


func set_first_person(enabled: bool) -> void:
	camera_first_person = enabled
	if is_piloted:
		get_active_camera().make_current()


func take_damage(amount: float, hit_pos: Vector3 = Vector3.ZERO) -> void:
	if amount <= 0.0 or health <= 0.0:
		return
	_shield_delay = shield_regen_delay
	var absorbed := minf(shield, amount)
	shield -= absorbed
	health = maxf(0.0, health - (amount - absorbed))
	damaged.emit(amount, hit_pos)


func heal_full() -> void:
	health = max_health
	shield = max_shield
	_shield_delay = 0.0


func raycast(from: Vector3, to: Vector3, mask: int = WORLD_MASK) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, mask, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query)


func get_energy_color() -> Color:
	return Color(0.12, 0.82, 1.0) if faction == "helion" else Color(1.0, 0.31, 0.065)


func get_weapon_transform() -> Transform3D:
	return global_transform


func get_muzzle_local(barrel: int, secondary: bool) -> Vector3:
	var x := 0.0 if secondary else dimensions.x * (0.30 if barrel == 0 else -0.30)
	return Vector3(x, dimensions.y * 0.48, -dimensions.z * 0.5 - 0.18)


func get_model_part_bounds(part_name: String) -> AABB:
	if model_source != "glb":
		return AABB()
	var part := visual.find_child(part_name, true, false) as MeshInstance3D
	if part == null or part.mesh == null:
		return AABB()
	var local_transform := global_transform.affine_inverse() * part.global_transform
	return local_transform * part.mesh.get_aabb()


func _unhandled_input(event: InputEvent) -> void:
	if not is_piloted or not controls_enabled:
		return
	if event is InputEventMouseMotion:
		look_delta += event.relative
	elif event is InputEventKey and event.pressed and not event.echo:
		var key: Key = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
		match key:
			KEY_V:
				set_first_person(not camera_first_person)
			_:
				_vehicle_key(key)


func _vehicle_key(_key: Key) -> void:
	pass


func _build_collision() -> void:
	add_box_collision(dimensions, Vector3.UP * dimensions.y * 0.5)


func add_box_collision(size: Vector3, offset: Vector3) -> void:
	var box := BoxShape3D.new()
	box.size = size
	var collider := CollisionShape3D.new()
	collider.shape = box
	collider.position = offset
	add_child(collider)


func _build_cameras() -> void:
	cockpit_camera = Camera3D.new()
	cockpit_camera.name = "CockpitCamera"
	cockpit_camera.position = dimensions * Vector3(0.0, 0.88, -0.25)
	if vehicle_type == "rover":
		cockpit_camera.position = dimensions * Vector3(0.0, 0.72, -0.37)
	add_child(cockpit_camera)

	_camera_extent = dimensions.z * 1.18 + 2.9
	_chase_extension = _camera_extent
	_chase_arm = SpringArm3D.new()
	_chase_arm.name = "ChaseArm"
	_chase_arm.position = Vector3(0, dimensions.y * 0.88 + 0.45, 0)
	_chase_arm.rotation.x = -0.20
	_chase_arm.collision_mask = collision_mask
	_chase_arm.spring_length = _camera_extent
	_chase_arm.margin = 0.35
	var probe := SphereShape3D.new()
	probe.radius = 0.30
	_chase_arm.shape = probe
	_chase_arm.add_excluded_object(get_rid())
	add_child(_chase_arm)
	var mount := Node3D.new()
	mount.position.z = _camera_extent
	_chase_arm.add_child(mount)
	chase_camera = Camera3D.new()
	chase_camera.name = "ChaseCamera"
	chase_camera.rotation.x = -0.04
	mount.add_child(chase_camera)


func _update_cameras(delta: float) -> void:
	var t := smoothstep(150.0, 4200.0, get_height_above_ground())
	if get_ship() != null:
		t = 0.0
	var step := 1.0 - exp(-8.0 * delta)
	for camera in [cockpit_camera, chase_camera]:
		camera.near = lerpf(0.18, 3.2, t)
		camera.far = lerpf(41000.0, 105000.0, t)
		camera.fov = lerpf(camera.fov, 72.0 + get_boost_ratio() * 12.0, step)
	var mount := chase_camera.get_parent() as Node3D
	var target_extension := mount.position.z
	# Retract immediately at obstacles and ease the view outward when clear.
	_chase_extension = minf(target_extension, lerpf(_chase_extension, target_extension, step))
	chase_camera.position.z = _chase_extension - mount.position.z


func _build_fallback() -> void:
	var helion := faction == "helion"
	var hull := hull_material(Color("d9eef0") if helion else Color("392925"), 0.61)
	var panel := hull_material(Color("275c73") if helion else Color("8d4230"), 0.58)
	var glass := hull_material(Color("13343f") if helion else Color("341b15"), 0.74)
	var accent := hull_material(get_energy_color(), 0.26, 1.8)
	var d := dimensions
	if vehicle_type == "rover":
		add_visual_box(visual, "Chassis", d * Vector3(0.64, 0.33, 1), d * Vector3(0, 0.31, 0), hull)
		add_visual_box(visual, "GlazedCab", d * Vector3(0.58, 0.32, 0.38), d * Vector3(0, 0.57, -0.23), glass)
		for side in [-1.0, 1.0]:
			add_visual_box(visual, "Headlamp", d * Vector3(0.12, 0.08, 0.03), d * Vector3(side * 0.22, 0.4, -0.485), accent)
			for axle in [-1.0, 0.0, 1.0]:
				var tire := CylinderMesh.new()
				tire.height = d.x * 0.176
				tire.top_radius = d.y * 0.21
				tire.bottom_radius = tire.top_radius
				tire.radial_segments = 20
				var wheel := add_visual_mesh(visual, "Wheel", tire,
					Vector3(side * d.x * 0.412, tire.top_radius, axle * d.z * 0.32), glass)
				wheel.rotation.z = PI / 2.0
				var hub := CylinderMesh.new()
				hub.height = 0.025
				hub.top_radius = tire.top_radius * 0.61
				hub.bottom_radius = hub.top_radius
				add_visual_mesh(wheel, "Hub", hub, Vector3(0, -side * (tire.height - hub.height) * 0.5, 0), panel)
		return

	var transport := vehicle_type == "dropship"
	var fuselage_width := 0.56 if transport else 0.34
	add_visual_box(visual, "Fuselage", d * Vector3(fuselage_width, 0.48, 0.83), d * Vector3(0, 0.44, 0.085), hull)
	var nose := PrismMesh.new()
	nose.size = d * Vector3(fuselage_width, 0.30, 0.43)
	nose.left_to_right = 0.5
	# The prism's tall apex projects toward the nose along -Z.
	nose.size = Vector3(nose.size.x, nose.size.z, nose.size.y)
	var nose_visual := add_visual_mesh(visual, "ArmoredNose", nose, d * Vector3(0, 0.42, -0.285), hull)
	nose_visual.rotation.x = -PI / 2.0
	add_visual_box(visual, "Canopy", d * Vector3(fuselage_width * 0.78, 0.25, 0.29), d * Vector3(0, 0.875, -0.13), glass)
	for side in [-1.0, 1.0]:
		add_visual_box(visual, "Wing", d * Vector3(0.36, 0.12, 0.51 if transport else 0.44), d * Vector3(side * 0.32, 0.47, 0.12), panel)
		add_visual_box(visual, "EngineNacelle", d * Vector3(0.19, 0.31, 0.50), d * Vector3(side * 0.34, 0.43, 0.25), hull)
		add_visual_box(visual, "EngineStrip", d * Vector3(0.16, 0.11, 0.025), d * Vector3(side * 0.34, 0.43, 0.4875), accent)
		for fore_aft in [-1.0, 1.0]:
			add_visual_box(visual, "LandingGear", d * Vector3(0.11, 0.26, 0.14), d * Vector3(side * 0.24, 0.13, fore_aft * 0.24), glass)


func hull_material(color: Color, metallic: float, glow: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = 0.35
	material.emission_enabled = glow > 0.0
	material.emission = color
	material.emission_energy_multiplier = glow
	return material


func add_visual_box(parent: Node3D, label: String, size: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return add_visual_mesh(parent, label, mesh, at, material)


func add_visual_mesh(parent: Node3D, label: String, mesh: Mesh, at: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = label
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	parent.add_child(instance)
	return instance
