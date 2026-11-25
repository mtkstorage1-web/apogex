class_name CraterGenerator
extends RefCounted

const Transforms = preload("res://scripts/coordinates/CoordinateTransformUtils.gd")
const EJECTA_EXTENT := 1.65

const REGION_CENTERS = [
	Vector2(0.0, 0.0), Vector2(18.0, 0.0), Vector2(0.0, 20.0),
	Vector2(0.0, -20.0), Vector2(-18.0, 0.0), Vector2(10.0, -13.0),
	Vector2(-10.0, 13.0),
]


class Crater:
	var name: String
	var direction: Vector3
	var angular_radius: float
	var cutoff_chord_squared: float
	var depth: float
	var rim_height: float
	var peak_height: float


var _catalog: Array[Crater] = []
var _planet_radius: float


func _init(world_seed: int = 4209, planet_radius: float = 12000.0) -> void:
	configure(world_seed, planet_radius)


func configure(world_seed: int, planet_radius: float = 12000.0) -> void:
	_planet_radius = planet_radius
	_catalog.clear()
	_add_crater("Terminus Basin", Vector2.ZERO, 2100.0, 252.0, 96.0, 0.0)
	_add_crater("Cinderfall Crater", Vector2(-19.6, 5.6), 535.0, 112.0, 34.0, 22.0)

	var random := RandomNumberGenerator.new()
	random.seed = world_seed ^ 0x3c970
	# Place impacts around the playable regions. Bias the size distribution toward small impacts.
	for center: Vector2 in REGION_CENTERS:
		for i in 12:
			var offset := Vector2.from_angle(random.randf() * TAU) * sqrt(random.randf()) * 8.0
			var radius := lerpf(10.0, 600.0, pow(random.randf(), 2.4))
			var depth := radius * random.randf_range(0.13, 0.24)
			var rim := radius * random.randf_range(0.035, 0.095)
			var peak := depth * random.randf_range(0.10, 0.28) if radius >= 280.0 else 0.0
			_add_crater("", center + offset, radius, depth, rim, peak)


## The exclusion factor fades both geometry and visible impact deposits at industrial sites.
func sample(unit_dir: Vector3, exclusion_factor: float = 1.0) -> Dictionary:
	var influence := clampf(exclusion_factor, 0.0, 1.0)
	var height := 0.0
	var ejecta := 0.0
	var rim := 0.0
	if influence > 0.0:
		for crater in _catalog:
			var chord_squared := unit_dir.distance_squared_to(crater.direction)
			if chord_squared >= crater.cutoff_chord_squared:
				continue
			var distance := 2.0 * asin(minf(1.0, sqrt(chord_squared) * 0.5))
			var radial := distance / crater.angular_radius
			var bowl := 1.0 - smoothstep(0.16, 1.0, radial)
			var lip := smoothstep(0.72, 1.0, radial) * (1.0 - smoothstep(1.0, 1.28, radial))
			var apron := smoothstep(0.68, 0.95, radial) * (1.0 - smoothstep(1.0, EJECTA_EXTENT, radial))
			var peak := (1.0 - smoothstep(0.0, 0.25, radial)) * crater.peak_height
			height += -bowl * crater.depth + lip * crater.rim_height + apron * crater.rim_height * 0.13 + peak
			ejecta = maxf(ejecta, apron)
			rim = maxf(rim, lip)
	return {"height": height * influence, "ejecta": ejecta * influence, "rim": rim * influence}


func _add_crater(
	crater_name: String, lat_lon: Vector2, radius: float, depth: float, rim: float, peak: float
) -> void:
	var crater := Crater.new()
	crater.name = crater_name
	crater.direction = Transforms.lat_lon_to_unit_dir(deg_to_rad(lat_lon.x), deg_to_rad(lat_lon.y))
	crater.angular_radius = radius / maxf(_planet_radius, 1.0)
	var cutoff_angle := minf(PI, crater.angular_radius * EJECTA_EXTENT)
	var cutoff_chord := 2.0 * sin(cutoff_angle * 0.5)
	crater.cutoff_chord_squared = cutoff_chord * cutoff_chord
	crater.depth = depth
	crater.rim_height = rim
	crater.peak_height = peak
	_catalog.append(crater)
