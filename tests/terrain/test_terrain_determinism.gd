extends SceneTree

const Transforms = preload("res://scripts/coordinates/CoordinateTransformUtils.gd")
const Biomes = preload("res://scripts/terrain/TerrainBiomeSampler.gd")
const Terrain = preload("res://scripts/terrain/TerrainNoiseStack.gd")
const Craters = preload("res://scripts/terrain/CraterGenerator.gd")
const Canyons = preload("res://scripts/terrain/CanyonGenerator.gd")
const Volcanoes = preload("res://scripts/terrain/VolcanicTerrainGenerator.gd")
const CONFIG = preload("res://resources/terrain_configs/vesper9_terrain_config.tres")

var _failures := 0


func _init() -> void:
	var terrain := Terrain.new()
	_test_layout(terrain)
	_test_seed_and_surface(terrain)
	_test_craters()
	_test_canyons_and_volcanoes()
	print("Terrain determinism %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(0 if _failures == 0 else 1)


func _test_layout(terrain: Terrain) -> void:
	var sampler := Biomes.new()
	var regions := [
		Vector3(-18.0, 0.0, Biomes.BiomeId.ASHEN_WASTES),
		Vector3(10.0, -13.0, Biomes.BiomeId.CRIMSON_CANYONS),
		Vector3(-10.0, 13.0, Biomes.BiomeId.CRIMSON_CANYONS),
		Vector3(0.0, -20.0, Biomes.BiomeId.OBSIDIAN_FIELDS),
		Vector3(0.0, 20.0, Biomes.BiomeId.IRON_DESERT),
		Vector3(18.0, 0.0, Biomes.BiomeId.FRACTURED_HIGHLANDS),
		Vector3(0.0, 0.0, Biomes.BiomeId.TERMINUS_BASIN),
		Vector3(0.0, 180.0, Biomes.BiomeId.ASHEN_WASTES),
	]
	for region: Vector3 in regions:
		var direction := _direction(region.x, region.y)
		var biome_id := int(region.z)
		_check(sampler.get_dominant_biome(direction) == biome_id, "Dominant biome at %s" % direction)
		_check(terrain.sample_vertex_data(direction).biome_id == biome_id, "Vertex biome matches layout")
		_check(sampler.get_region_mask(direction).size() == 6, "Region mask includes all six biomes")
		var config := load("res://resources/biome_configs/%s.tres" % Biomes.REGION_KEYS[biome_id])
		_check(config.id == Biomes.REGION_KEYS[biome_id], "Biome resource order and id")
		_check(config.display_name == sampler.get_biome_name(biome_id), "Biome resource display name")

	for site: Vector4 in Biomes.INDUSTRIAL_SITES:
		var center := _direction(site.x, site.y)
		_check(sampler.get_exclusion_factor(center) == 0.0, "Industrial center excluded")
		var edge := _direction(site.x + site.z * 0.75, site.y)
		var blend := sampler.get_exclusion_factor(edge)
		_check(blend > 0.0 and blend < 1.0, "Industrial site has a feathered edge")
		_check(sampler.get_exclusion_factor(_direction(site.x + site.z * 1.2, site.y)) == 1.0, "Terrain beyond the site is enabled")
		var vertex := terrain.sample_vertex_data(center)
		_check(vertex.height == site.w and vertex.industrial == 1.0, "Industrial site finished elevation")
		_check(vertex.volcanic == 0.0 and vertex.crater_ejecta == 0.0 and vertex.canyon_strata == 0.0, "Site masks exclude terrain features")
		_check(terrain.sample_height(_direction(site.x + 0.2, site.y)) == vertex.height, "Pad center is flat")


func _test_seed_and_surface(terrain: Terrain) -> void:
	var same_seed := Terrain.new(4209)
	var other_seed := Terrain.new(4210)
	var directions: Array[Vector3] = [Vector3.UP, Vector3.DOWN, Vector3.ZERO, Vector3.FORWARD]
	for latitude in range(-75, 76, 15):
		for longitude in range(-180, 180, 30):
			directions.append(_direction(latitude, longitude))
	for latitude in range(-24, 25, 4):
		for longitude in range(-24, 25, 4):
			directions.append(_direction(latitude, longitude))

	var different := 0
	for direction in directions:
		var vertex := terrain.sample_vertex_data(direction)
		_check(vertex == same_seed.sample_vertex_data(direction), "Same seed produces identical vertex data")
		_check(is_equal_approx(vertex.height, terrain.sample_height(direction * 2.0)), "Direction scale does not change height")
		_check(vertex.height == terrain.sample_height(direction), "Vertex API agrees with height API")
		_check(vertex.radius == terrain.sample_surface_radius(direction), "Vertex API agrees with radius API")
		_check(vertex.position == terrain.sample_surface_position(direction), "Vertex API agrees with position API")
		_check(vertex.height >= -CONFIG.max_depth and vertex.height <= CONFIG.max_elevation, "Configured terrain bounds")
		if not is_equal_approx(vertex.height, other_seed.sample_height(direction)):
			different += 1

		var weights: PackedFloat32Array = vertex.biome_weights
		var total := 0.0
		for weight in weights:
			total += weight
			_check(weight >= 0.0 and weight <= 1.0, "Biome weights are bounded")
		_check(weights.size() == 6 and absf(total - 1.0) < 0.000001, "Biome weights sum to one")
		var index := float(vertex.biome_id) / 5.0
		var colors: Color = vertex.color_weights
		var extra: Color = vertex.extra_weights
		_check(colors.is_equal_approx(Color(index, vertex.volcanic, vertex.mineral, vertex.crater_ejecta)), "Color channels")
		_check(extra.is_equal_approx(Color(index, vertex.canyon_strata, vertex.industrial, extra.a)), "Extra channels")
		for channel in [colors.r, colors.g, colors.b, colors.a, extra.r, extra.g, extra.b, extra.a]:
			_check(channel >= 0.0 and channel <= 1.0, "Vertex channels are bounded")
		var normal := terrain.sample_surface_normal(direction)
		_check(normal.is_finite() and is_equal_approx(normal.length(), 1.0), "Surface normal is a finite unit vector")
		_check(normal.dot(vertex.position) > 0.0, "Surface normal points outward")
	_check(different > directions.size() / 2.0, "Changing seed changes the terrain")

	other_seed.configure(4209, 13000.0)
	_check(other_seed.sample_surface_radius(Vector3.BACK) == 12780.0, "Non-default planet radius")
	other_seed.configure(4209)
	for direction in directions:
		_check(terrain.sample_vertex_data(direction) == other_seed.sample_vertex_data(direction), "Reconfigure restores determinism")


func _test_craters() -> void:
	var craters := Craters.new()
	var center := craters.sample(Vector3.BACK)
	var rim_direction := _direction(0.0, rad_to_deg(2100.0 / 12000.0))
	var rim := craters.sample(rim_direction)
	_check(center.height < -200.0 and center.rim == 0.0, "Terminus impact has a deep floor")
	_check(rim.height > 50.0 and rim.rim > 0.95 and rim.ejecta > 0.95, "Terminus impact has a raised rim and ejecta")
	_check(craters.sample(rim_direction, 0.0) == {"height": 0.0, "ejecta": 0.0, "rim": 0.0}, "Crater exclusion suppresses all channels")
	var southern := _direction(-19.6, 5.6)
	_check(craters.sample(southern).height < -50.0, "Cinderfall Crater depression")


func _test_canyons_and_volcanoes() -> void:
	var canyons := Canyons.new()
	var center := _direction(10.0, -13.0)
	var floor_sample := canyons.sample(center, 0.8)
	var wall_sample := canyons.sample(center, 0.2)
	_check(canyons.sample(center, 0.0) == Vector2.ZERO, "Canyons are confined to their corridors")
	_check(floor_sample.x >= -300.0 and floor_sample.x <= -50.0, "Canyon floor depth")
	_check(wall_sample.x > floor_sample.x and wall_sample.y > 0.0, "Canyon wall terraces and strata")

	var volcanoes := Volcanoes.new()
	var hottest := 0.0
	var coolest := 1.0
	for latitude in range(-6, 7):
		for longitude in range(-26, -13):
			var sample := volcanoes.sample(_direction(latitude, longitude))
			hottest = maxf(hottest, sample.volcanic_heat)
			coolest = minf(coolest, sample.volcanic_heat)
			_check(sample.fissure_mask >= sample.volcanic_heat, "Lava is confined to fissures")
	_check(hottest > 0.5 and coolest == 0.0, "Volcanic region contains hot fissures and cold rock")


func _direction(latitude: float, longitude: float) -> Vector3:
	return Transforms.lat_lon_to_unit_dir(deg_to_rad(latitude), deg_to_rad(longitude))


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL %s" % label)
