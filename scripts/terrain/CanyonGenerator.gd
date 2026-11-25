class_name CanyonGenerator
extends RefCounted

var _channel := FastNoiseLite.new()
var _depth := FastNoiseLite.new()


func _init(world_seed: int = 4209) -> void:
	configure(world_seed)


func configure(world_seed: int) -> void:
	_channel.seed = world_seed ^ 0x42d75
	_channel.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_channel.frequency = 18.0
	_channel.fractal_octaves = 2

	_depth.seed = world_seed ^ 0x568cb
	_depth.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_depth.frequency = 7.5
	_depth.fractal_octaves = 2


## Biome weight places the canyon walls. The inner corridor has a broad, smooth floor.
func sample(unit_dir: Vector3, canyon_weight: float) -> Vector2:
	var bend := _channel.get_noise_3dv(unit_dir) * 0.14
	var wall := smoothstep(0.035, 0.46, canyon_weight * (1.0 + bend))
	var strata_position := wall * 6.0
	var terrace := (floorf(strata_position) + smoothstep(0.15, 0.78, fposmod(strata_position, 1.0))) / 6.0
	var profile := lerpf(wall, terrace, 0.80)
	var depth := lerpf(50.0, 300.0, clampf(0.56 + _depth.get_noise_3dv(unit_dir), 0.0, 1.0))
	var bedding := 0.5 - 0.5 * cos(TAU * strata_position)
	var strata := 4.0 * wall * (1.0 - wall) * lerpf(0.4, 1.0, bedding)
	return Vector2(-depth * profile, strata)
