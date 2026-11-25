class_name TerrainNoiseStack
extends RefCounted

const Transforms = preload("res://scripts/coordinates/CoordinateTransformUtils.gd")
const BiomeSampler = preload("res://scripts/terrain/TerrainBiomeSampler.gd")
const Mountains = preload("res://scripts/terrain/MountainGenerator.gd")
const Canyons = preload("res://scripts/terrain/CanyonGenerator.gd")
const Craters = preload("res://scripts/terrain/CraterGenerator.gd")
const Volcanoes = preload("res://scripts/terrain/VolcanicTerrainGenerator.gd")

static var _biome_parameters: PackedVector2Array
static var _height_limits: Vector2

var _planet_radius: float
var _biomes: BiomeSampler
var _mountains: Mountains
var _canyons: Canyons
var _craters: Craters
var _volcanoes: Volcanoes
var _continental := FastNoiseLite.new()
var _roughness := FastNoiseLite.new()


static func _static_init() -> void:
	# Sample the shipped defaults independently of resources held by scenes or tools.
	var terrain := ResourceLoader.load(
		"res://resources/terrain_configs/vesper9_terrain_config.tres", "", ResourceLoader.CACHE_MODE_IGNORE
	)
	_height_limits = Vector2(-terrain.max_depth, terrain.max_elevation)
	for biome_key: StringName in BiomeSampler.REGION_KEYS:
		var biome := ResourceLoader.load(
			"res://resources/biome_configs/%s.tres" % biome_key, "", ResourceLoader.CACHE_MODE_IGNORE
		)
		_biome_parameters.append(Vector2(biome.elevation_bias, biome.volcanic_activity))


func _init(seed_val: int = 4209, radius: float = 12000.0) -> void:
	_biomes = BiomeSampler.new(seed_val)
	_mountains = Mountains.new(seed_val)
	_canyons = Canyons.new(seed_val)
	_craters = Craters.new(seed_val, radius)
	_volcanoes = Volcanoes.new(seed_val)
	_configure_base(seed_val, radius)


func configure(seed_val: int, radius: float = 12000.0) -> void:
	_biomes.configure(seed_val)
	_mountains.configure(seed_val)
	_canyons.configure(seed_val)
	_craters.configure(seed_val, radius)
	_volcanoes.configure(seed_val)
	_configure_base(seed_val, radius)


func sample_height(unit_dir: Vector3) -> float:
	var direction := _normalized_direction(unit_dir)
	var weights := _biomes.sample_biome_weights(direction)
	return _sample_layers(direction, weights, _biomes.get_exclusion_data(direction)).x


func sample_surface_radius(unit_dir: Vector3) -> float:
	return _planet_radius + sample_height(unit_dir)


func sample_surface_position(unit_dir: Vector3) -> Vector3:
	return _normalized_direction(unit_dir) * sample_surface_radius(unit_dir)


func sample_surface_normal(unit_dir: Vector3, eps: float = 0.00025) -> Vector3:
	var direction := _normalized_direction(unit_dir)
	var tangent := Transforms.surface_tangent_basis(direction)
	var step := maxf(absf(eps), 0.00001)
	var along_x := (
		sample_surface_position(direction + tangent.x * step)
		- sample_surface_position(direction - tangent.x * step)
	)
	var along_z := (
		sample_surface_position(direction + tangent.z * step)
		- sample_surface_position(direction - tangent.z * step)
	)
	var normal := along_z.cross(along_x).normalized()
	return direction if normal == Vector3.ZERO else normal


func sample_vertex_data(unit_dir: Vector3) -> Dictionary:
	var direction := _normalized_direction(unit_dir)
	var weights := _biomes.sample_biome_weights(direction)
	var exclusion := _biomes.get_exclusion_data(direction)
	var layers := _sample_layers(direction, weights, exclusion)
	var biome_id := 0
	for i in range(1, weights.size()):
		if weights[i] > weights[biome_id]:
			biome_id = i

	var radius := _planet_radius + layers.x
	var biome_index := float(biome_id) / (weights.size() - 1)
	var mineral := weights[BiomeSampler.BiomeId.OBSIDIAN_FIELDS] * exclusion.x
	var industrial := 1.0 - exclusion.x
	var moisture: float = _biomes.get_biome_climate(direction)["moisture"]
	return {
		"height": layers.x,
		"radius": radius,
		"position": direction * radius,
		"biome_id": biome_id,
		"biome_weights": weights,
		"volcanic": layers.y,
		"crater_ejecta": layers.z,
		"canyon_strata": layers.w,
		"mineral": mineral,
		"industrial": industrial,
		"color_weights": Color(biome_index, layers.y, mineral, layers.z),
		"extra_weights": Color(biome_index, layers.w, industrial, moisture),
	}


## Vector components hold height, volcanic heat, crater ejecta, and canyon strata.
func _sample_layers(direction: Vector3, weights: PackedFloat32Array, exclusion: Vector2) -> Vector4:
	var natural := exclusion.x
	if natural == 0.0:
		return Vector4(exclusion.y, 0.0, 0.0, 0.0)

	var obsidian := weights[BiomeSampler.BiomeId.OBSIDIAN_FIELDS]
	var highlands := weights[BiomeSampler.BiomeId.FRACTURED_HIGHLANDS]
	var canyons := weights[BiomeSampler.BiomeId.CRIMSON_CANYONS]
	var basin := weights[BiomeSampler.BiomeId.TERMINUS_BASIN]
	var biome_parameters := Vector2.ZERO
	for i in weights.size():
		biome_parameters += _biome_parameters[i] * weights[i]

	var base := _continental.get_noise_3dv(direction) * 105.0 + biome_parameters.x
	var mountain_height := _mountains.sample_height(direction) * highlands
	var canyon := _canyons.sample(direction, canyons)
	var crater := _craters.sample(direction, natural)
	var volcanic := _volcanoes.sample(direction)
	var detail_strength := lerpf(16.0, 5.0, maxf(canyons, basin))
	var detail := _roughness.get_noise_3dv(direction) * detail_strength
	var terrain := base + mountain_height + canyon.x + float(volcanic["height"]) * obsidian + detail
	var height := lerpf(exclusion.y, terrain, natural) + float(crater["height"])
	return Vector4(
		clampf(height, _height_limits.x, _height_limits.y),
		float(volcanic["volcanic_heat"]) * biome_parameters.y * obsidian * natural,
		crater["ejecta"], canyon.y * natural,
	)


func _configure_base(seed_val: int, radius: float) -> void:
	_planet_radius = radius
	_continental.seed = seed_val ^ 0x15395
	_continental.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_continental.frequency = 3.2
	_continental.fractal_octaves = 4

	_roughness.seed = seed_val ^ 0x89a4b
	_roughness.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_roughness.frequency = 159.0
	_roughness.fractal_octaves = 4


static func _normalized_direction(direction: Vector3) -> Vector3:
	return Vector3.BACK if direction == Vector3.ZERO else direction.normalized()
