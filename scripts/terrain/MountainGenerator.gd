class_name MountainGenerator
extends RefCounted

var _ridges := FastNoiseLite.new()
var _uplift := FastNoiseLite.new()


func _init(world_seed: int = 4209) -> void:
	configure(world_seed)


func configure(world_seed: int) -> void:
	_ridges.seed = world_seed ^ 0x264d1
	_ridges.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_ridges.frequency = 25.0
	_ridges.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_ridges.fractal_octaves = 5
	_ridges.fractal_lacunarity = 2.2
	_ridges.fractal_gain = 0.51
	_ridges.fractal_weighted_strength = 0.75

	_uplift.seed = world_seed ^ 0x37bc3
	_uplift.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_uplift.frequency = 9.5
	_uplift.fractal_octaves = 3


## Samples unit directions. Apply the highland biome weight to the result.
func sample_height(unit_dir: Vector3) -> float:
	var plateau := smoothstep(-0.42, 0.38, _uplift.get_noise_3dv(unit_dir))
	var ridge := smoothstep(-0.30, 0.86, _ridges.get_noise_3dv(unit_dir))
	return 105.0 + 205.0 * plateau + 245.0 * ridge
