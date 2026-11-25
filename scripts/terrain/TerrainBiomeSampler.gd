class_name TerrainBiomeSampler
extends RefCounted

const Transforms = preload("res://scripts/coordinates/CoordinateTransformUtils.gd")

enum BiomeId {
	ASHEN_WASTES = 0,
	CRIMSON_CANYONS = 1,
	OBSIDIAN_FIELDS = 2,
	IRON_DESERT = 3,
	FRACTURED_HIGHLANDS = 4,
	TERMINUS_BASIN = 5,
}

const BIOME_NAMES: PackedStringArray = [
	"Ashen Wastes", "Crimson Canyons", "Obsidian Fields", "Iron Desert",
	"Fractured Highlands", "Terminus Basin",
]
const REGION_KEYS = [
	&"ashen_wastes", &"crimson_canyons", &"obsidian_fields", &"iron_desert",
	&"fractured_highlands", &"terminus_basin",
]

# Latitude, longitude, outer angular radius, and finished elevation for each site.
const INDUSTRIAL_SITES = [
	Vector4(0.0, 0.0, 1.35, -220.0),     # Extraction complex
	Vector4(18.0, 0.0, 1.05, 225.0),    # Landing platform
	Vector4(0.0, 20.0, 1.0, 28.0),      # Refinery yard
	Vector4(0.0, -20.0, 0.95, 45.0),    # Power station
	Vector4(-18.0, 0.0, 1.1, -20.0),    # Launch site
]

var _north: Vector3 = _direction(18.0, 0.0)
var _east: Vector3 = _direction(0.0, 20.0)
var _west: Vector3 = _direction(0.0, -20.0)
var _south: Vector3 = _direction(-18.0, 0.0)
var _site_centers: PackedVector3Array = []
var _climate := FastNoiseLite.new()


func _init(seed_val: int = 4209) -> void:
	for site: Vector4 in INDUSTRIAL_SITES:
		_site_centers.append(_direction(site.x, site.y))
	configure(seed_val)


func configure(seed_val: int) -> void:
	_climate.seed = seed_val
	_climate.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_climate.frequency = 4.5
	_climate.fractal_octaves = 3


func sample_biome_weights(unit_dir: Vector3) -> PackedFloat32Array:
	var weights := _region_masks(_normalized_direction(unit_dir))
	var sum := 0.0
	for weight in weights:
		sum += weight
	for i in weights.size():
		weights[i] /= sum
	return weights


func get_dominant_biome(unit_dir: Vector3) -> int:
	var masks := _region_masks(_normalized_direction(unit_dir))
	var dominant := BiomeId.ASHEN_WASTES
	for i in range(1, masks.size()):
		if masks[i] > masks[dominant]:
			dominant = i
	return dominant


func get_biome_name(biome_id: int) -> String:
	if biome_id < 0 or biome_id >= BIOME_NAMES.size():
		return ""
	return BIOME_NAMES[biome_id]


## Each mask is a region's unnormalized influence.
func get_region_mask(unit_dir: Vector3) -> Dictionary:
	var masks := _region_masks(_normalized_direction(unit_dir))
	var regions := {}
	for i in masks.size():
		regions[REGION_KEYS[i]] = masks[i]
	return regions


func get_exclusion_factor(unit_dir: Vector3) -> float:
	return get_exclusion_data(unit_dir).x


## x is natural terrain influence, y is finished site elevation in meters.
func get_exclusion_data(unit_dir: Vector3) -> Vector2:
	var direction := _normalized_direction(unit_dir)
	for i in INDUSTRIAL_SITES.size():
		var site: Vector4 = INDUSTRIAL_SITES[i]
		var outer_radius := deg_to_rad(site.z)
		var dot := direction.dot(_site_centers[i])
		if dot > cos(outer_radius):
			var angle := direction.angle_to(_site_centers[i])
			return Vector2(smoothstep(outer_radius * 0.48, outer_radius, angle), site.w)
	return Vector2(1.0, 0.0)


func get_biome_climate(unit_dir: Vector3) -> Dictionary:
	var direction := _normalized_direction(unit_dir)
	var weights := sample_biome_weights(direction)
	var variation := _climate.get_noise_3dv(direction)
	var moisture := clampf(
		0.24 + variation * 0.24 + weights[BiomeId.FRACTURED_HIGHLANDS] * 0.26
		- weights[BiomeId.IRON_DESERT] * 0.15, 0.0, 1.0
	)
	var temperature := clampf(
		0.8 - absf(direction.y) * 0.55 + weights[BiomeId.OBSIDIAN_FIELDS] * 0.17
		+ variation * 0.15, 0.0, 1.0
	)
	return {"moisture": moisture, "temperature": temperature}


func _region_masks(direction: Vector3) -> PackedFloat32Array:
	var basin := _angular_mask(direction, Vector3.BACK, 7.5, 12.0)
	var north := _angular_mask(direction, _north, 6.0, 15.0)
	var east := _angular_mask(direction, _east, 7.0, 17.0)
	var west := _angular_mask(direction, _west, 7.0, 17.0)
	var south := _angular_mask(direction, _south, 8.0, 17.0)
	var canyon := 0.0
	if direction.z > 0.0:
		var radians := Transforms.unit_dir_to_lat_lon(direction)
		var lat := rad_to_deg(radians.x)
		var lon := rad_to_deg(radians.y)
		canyon = maxf(_canyon_mask(lat, lon, 1.0), _canyon_mask(lat, lon, -1.0))

	var regional := maxf(maxf(north, east), maxf(west, basin))
	return PackedFloat32Array([
		maxf(south, lerpf(1.0, 0.06, maxf(regional, canyon))),
		canyon * (1.0 - basin),
		west * (1.0 - basin),
		east * (1.0 - basin),
		north * (1.0 - basin),
		basin,
	])


static func _canyon_mask(latitude: float, longitude: float, side: float) -> float:
	var along := -side * longitude - 13.0
	var center_lat := side * (10.0 + 2.0 * sin(along * 0.32))
	var across := absf(latitude - center_lat)
	return (1.0 - smoothstep(1.5, 4.5, across)) * (1.0 - smoothstep(4.0, 10.0, absf(along)))


static func _angular_mask(direction: Vector3, center: Vector3, inner: float, outer: float) -> float:
	# The cosine thresholds avoid taking an inverse trigonometric function for each region.
	return smoothstep(cos(deg_to_rad(outer)), cos(deg_to_rad(inner)), direction.dot(center))


static func _direction(latitude_deg: float, longitude_deg: float) -> Vector3:
	return Transforms.lat_lon_to_unit_dir(deg_to_rad(latitude_deg), deg_to_rad(longitude_deg))


static func _normalized_direction(direction: Vector3) -> Vector3:
	return Vector3.BACK if direction == Vector3.ZERO else direction.normalized()
