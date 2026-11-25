class_name WorldCoordinateSystem
extends Node

const Transforms = preload("res://scripts/coordinates/CoordinateTransformUtils.gd")
const FloatingOrigin = preload("res://scripts/coordinates/FloatingOriginManager.gd")

@export var planet_center: Vector3 = Vector3.ZERO
@export var planet_radius: float = 12000.0
@export var surface_gravity: float = 9.81
@export var gravity_falloff_enabled: bool = true

var floating_origin: FloatingOrigin = null


func geographic_to_cartesian(latitude: float, longitude: float, altitude: float) -> Vector3:
	return planet_center + Transforms.geographic_to_cartesian(latitude, longitude, altitude, planet_radius)


func cartesian_to_geographic(position: Vector3) -> Dictionary:
	return Transforms.cartesian_to_geographic(position - planet_center, planet_radius)


func get_gravity_direction(position: Vector3) -> Vector3:
	return (planet_center - position).normalized()


func get_gravity_magnitude(position: Vector3) -> float:
	if not gravity_falloff_enabled:
		return surface_gravity
	var distance := position.distance_to(planet_center)
	if distance == 0.0:
		return surface_gravity * 2.0
	var ratio := planet_radius / distance
	return surface_gravity * clampf(ratio * ratio, 0.0, 2.0)


func get_gravity_vector(position: Vector3) -> Vector3:
	return get_gravity_direction(position) * get_gravity_magnitude(position)


func get_surface_tangent_basis(position: Vector3) -> Basis:
	return Transforms.surface_tangent_basis(position, planet_center)


func planet_to_render(planet_pos: Vector3) -> Vector3:
	return floating_origin.planet_to_render(planet_pos) if is_instance_valid(floating_origin) else planet_pos


func render_to_planet(render_pos: Vector3) -> Vector3:
	return floating_origin.render_to_planet(render_pos) if is_instance_valid(floating_origin) else render_pos
