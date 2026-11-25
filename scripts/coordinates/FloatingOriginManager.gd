class_name FloatingOriginManager
extends Node

## Delta is the change in planet-space origin. Subtract it from existing render positions.
signal origin_shifted(delta: Vector3, new_origin: Vector3)

@export var shift_threshold: float = 2000.0

var current_origin: Vector3 = Vector3.ZERO
var shift_count: int = 0


func planet_to_render(planet_pos: Vector3) -> Vector3:
	return planet_pos - current_origin


func render_to_planet(render_pos: Vector3) -> Vector3:
	return render_pos + current_origin


func check_and_shift(focus_planet_pos: Vector3) -> bool:
	var delta := focus_planet_pos - current_origin
	if delta.length() <= maxf(shift_threshold, 0.0):
		return false
	current_origin = focus_planet_pos
	shift_count += 1
	origin_shifted.emit(delta, current_origin)
	return true


func reset_origin() -> void:
	var delta := -current_origin
	current_origin = Vector3.ZERO
	shift_count = 0
	if delta != Vector3.ZERO:
		origin_shifted.emit(delta, current_origin)
