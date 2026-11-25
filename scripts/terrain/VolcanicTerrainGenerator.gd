class_name VolcanicTerrainGenerator
extends RefCounted

var _fractures := FastNoiseLite.new()
var _spires := FastNoiseLite.new()


func _init(world_seed: int = 4209) -> void:
	configure(world_seed)


func configure(world_seed: int) -> void:
	_fractures.seed = world_seed ^ 0x61bd9
	_fractures.noise_type = FastNoiseLite.TYPE_CELLULAR
	_fractures.frequency = 39.0
	_fractures.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	_fractures.fractal_type = FastNoiseLite.FRACTAL_NONE

	_spires.seed = world_seed ^ 0x7f23d
	_spires.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_spires.frequency = 84.0
	_spires.fractal_octaves = 3


func sample(unit_dir: Vector3) -> Dictionary:
	var border_distance := absf(_fractures.get_noise_3dv(unit_dir) + 1.0)
	var fissure := 1.0 - smoothstep(0.012, 0.13, border_distance)
	var core := 1.0 - smoothstep(0.008, 0.064, border_distance)
	var rock := _spires.get_noise_3dv(unit_dir)
	var spire := smoothstep(0.19, 0.64, rock)
	var height := rock * 25.0 + pow(spire, 1.7) * 160.0 - fissure * 52.0
	return {"height": height, "volcanic_heat": core, "fissure_mask": fissure}
