class_name LocalReferenceFrame
extends RefCounted

const Transforms = preload("res://scripts/coordinates/CoordinateTransformUtils.gd")

var anchor_planet_pos: Vector3 = Vector3.ZERO
var basis: Basis = Basis.IDENTITY


func set_from_planet_position(planet_pos: Vector3, planet_center: Vector3 = Vector3.ZERO) -> void:
	anchor_planet_pos = planet_pos
	basis = Transforms.surface_tangent_basis(planet_pos, planet_center)


func planet_to_local(planet_pos: Vector3) -> Vector3:
	return basis.transposed() * (planet_pos - anchor_planet_pos)


func local_to_planet(local_pos: Vector3) -> Vector3:
	return anchor_planet_pos + basis * local_pos
