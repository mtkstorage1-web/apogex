class_name PlanetCoordinate
extends RefCounted

var position: Vector3 = Vector3.ZERO
var velocity: Vector3 = Vector3.ZERO


func _init(pos: Vector3 = Vector3.ZERO, vel: Vector3 = Vector3.ZERO) -> void:
	position = pos
	velocity = vel


func duplicate_coord() -> PlanetCoordinate:
	return get_script().new(position, velocity)
