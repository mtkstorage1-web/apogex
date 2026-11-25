class_name CoordinateTransformUtils
extends RefCounted


## Geographic angles are radians unless the method name specifies degrees.
static func geographic_to_cartesian(
	latitude: float, longitude: float, altitude: float, planet_radius: float = 12000.0
) -> Vector3:
	return lat_lon_to_unit_dir(latitude, longitude) * (planet_radius + altitude)


static func cartesian_to_geographic(pos: Vector3, planet_radius: float = 12000.0) -> Dictionary:
	var angles := unit_dir_to_lat_lon(pos)
	return {"latitude": angles.x, "longitude": angles.y, "altitude": pos.length() - planet_radius}


static func geographic_deg_to_cartesian(
	lat_deg: float, lon_deg: float, altitude: float, planet_radius: float = 12000.0
) -> Vector3:
	return geographic_to_cartesian(deg_to_rad(lat_deg), deg_to_rad(lon_deg), altitude, planet_radius)


static func cartesian_to_geographic_deg(pos: Vector3, planet_radius: float = 12000.0) -> Dictionary:
	var geographic := cartesian_to_geographic(pos, planet_radius)
	geographic["latitude"] = rad_to_deg(geographic["latitude"])
	geographic["longitude"] = rad_to_deg(geographic["longitude"])
	return geographic


static func unit_dir_to_lat_lon(unit_dir: Vector3) -> Vector2:
	var horizontal := Vector2(unit_dir.x, unit_dir.z).length()
	if horizontal <= unit_dir.length() * 1.0e-8:
		# Longitude is undefined on the polar axis.
		return Vector2(atan2(unit_dir.y, horizontal), 0.0)
	return Vector2(atan2(unit_dir.y, horizontal), atan2(unit_dir.x, unit_dir.z))


static func lat_lon_to_unit_dir(lat_rad: float, lon_rad: float) -> Vector3:
	var horizontal := cos(lat_rad)
	return Vector3(horizontal * sin(lon_rad), sin(lat_rad), horizontal * cos(lon_rad))


static func surface_tangent_basis(
	position: Vector3, planet_center: Vector3 = Vector3.ZERO
) -> Basis:
	var up := (position - planet_center).normalized()
	if up == Vector3.ZERO:
		up = Vector3.UP
	var east := Vector3.UP.cross(up)
	if east.length_squared() < 1.0e-10:
		east = Vector3.RIGHT - up * up.x
	east = east.normalized()
	return Basis(east, up, east.cross(up).normalized())
