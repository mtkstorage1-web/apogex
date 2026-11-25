class_name Projectile
extends Node3D

const PlasmaShader = preload("res://shaders/projectile.gdshader")
const ThrusterShader = preload("res://shaders/thruster.gdshader")
const HIT_MASK := 1 | 4
const FACILITY_HIT_RADIUS := 8.0

var direction := Vector3.FORWARD
var speed := 600.0
var damage := 18.0
var splash_radius := 0.0
var flight_time := 2.2
var energy_color := Color.CYAN
var shooter: CharacterBody3D
var destruction: DestructionStateController
var origin_mgr: FloatingOriginManager
var _origin_shift_frame := -2

signal hit_registered


func _ready() -> void:
	var missile := splash_radius > 0.0
	var sphere := SphereMesh.new()
	sphere.radius = 0.29 if missile else 0.15
	sphere.height = sphere.radius * 2.0
	sphere.radial_segments = 12
	sphere.rings = 6
	var core := MeshInstance3D.new()
	core.mesh = sphere
	core.material_override = plasma_material(energy_color, 3.3)
	core.scale.z = 3.4 if missile else 7.0
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(core)
	if missile:
		var cone := CylinderMesh.new()
		cone.top_radius = 0.29
		cone.bottom_radius = 0.02
		cone.height = 2.6
		cone.cap_top = false
		cone.cap_bottom = false
		var plume := MeshInstance3D.new()
		plume.mesh = cone
		var material := ShaderMaterial.new()
		material.shader = ThrusterShader
		material.set_shader_parameter("plasma_color", energy_color)
		material.set_shader_parameter("throttle", 1.8)
		material.set_shader_parameter("plume_length", cone.height)
		plume.material_override = material
		plume.rotation.x = -PI * 0.5
		plume.position.z = 1.85
		plume.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(plume)


func apply_origin_delta(delta: Vector3) -> void:
	global_position -= delta
	_origin_shift_frame = Engine.get_physics_frames()
	reset_physics_interpolation()


func _physics_process(delta: float) -> void:
	if Engine.get_physics_frames() <= _origin_shift_frame + 1:
		return
	var step := minf(delta, flight_time)
	var target := global_position + direction * speed * step
	var excluded: Array[RID] = []
	if is_instance_valid(shooter):
		excluded.append(shooter.get_rid())
	var query := PhysicsRayQueryParameters3D.create(global_position, target, HIT_MASK, excluded)
	query.hit_from_inside = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		_impact(hit, excluded)
		return
	global_position = target
	flight_time -= delta
	if flight_time <= 0.0:
		queue_free()


func _impact(hit: Dictionary, excluded: Array[RID]) -> void:
	var point: Vector3 = hit.position
	var collider: Object = hit.collider
	if is_instance_valid(collider) and collider.has_method("take_damage"):
		collider.take_damage(damage, point)
	if splash_radius > 0.0:
		var normal: Vector3 = hit.normal
		_apply_splash(point, normal if not normal.is_zero_approx() else -direction, collider, excluded)
	_apply_facility_damage(point)
	hit_registered.emit()
	spawn_flash(get_parent(), point, energy_color, 1.8 if splash_radius > 0.0 else 0.52,
		0.34 if splash_radius > 0.0 else 0.16)
	queue_free()


func _apply_splash(point: Vector3, normal: Vector3, direct_hit: Object, excluded: Array[RID]) -> void:
	var shape := SphereShape3D.new()
	shape.radius = splash_radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform.origin = point
	query.collision_mask = 4
	query.exclude = excluded
	var space := get_world_3d().direct_space_state
	var damaged: Dictionary = {}
	for result in space.intersect_shape(query, 64):
		var target := result.collider as Node3D
		if target == direct_hit or damaged.has(target) or not target.has_method("take_damage"):
			continue
		damaged[target] = true
		var center: Vector3 = target.global_position + target.global_basis.y * target.dimensions.y * 0.5
		var los := PhysicsRayQueryParameters3D.create(point + normal * 0.065, center, HIT_MASK, excluded)
		var obstruction := space.intersect_ray(los)
		if obstruction.is_empty() or obstruction.collider == target:
			var distance := point.distance_to(obstruction.get("position", center))
			target.take_damage(damage * 0.7 * (1.0 - clampf(distance / splash_radius, 0.0, 1.0)), point)


func _apply_facility_damage(point: Vector3) -> void:
	if not is_instance_valid(destruction):
		return
	var planet_point := origin_mgr.render_to_planet(point) if origin_mgr != null else point
	var radius := maxf(FACILITY_HIT_RADIUS, splash_radius)
	for id in destruction.get_section_ids():
		if destruction.get_section_position(id).distance_squared_to(planet_point) <= radius * radius:
			var state := destruction.get_state(id)
			if state < DestructionStateController.DestructionState.DESTROYED:
				destruction.set_section_state(id, state + 1)


static func plasma_material(color: Color, intensity: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = PlasmaShader
	material.set_shader_parameter("energy_color", color)
	material.set_shader_parameter("intensity", intensity)
	return material


static func spawn_flash(parent: Node, point: Vector3, color: Color, radius: float, duration: float) -> void:
	var burst := MeshInstance3D.new()
	burst.name = "EnergyFlash"
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 10
	mesh.rings = 6
	burst.mesh = mesh
	var material := plasma_material(color, 3.8)
	burst.material_override = material
	burst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	burst.scale = Vector3.ONE * 0.28
	parent.add_child(burst)
	burst.global_position = point
	var tween := burst.create_tween().set_parallel()
	tween.tween_property(burst, "scale", Vector3.ONE * 1.8, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(material, "shader_parameter/intensity", 0.0, duration)
	tween.chain().tween_callback(burst.queue_free)
