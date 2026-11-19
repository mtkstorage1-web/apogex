## Shared 512px textures. NoiseTexture2D builds asynchronously; never call get_image at startup.
class_name ProcTex
extends RefCounted

static var _cache: Dictionary = {}

static func noise(key: String, normal := false) -> NoiseTexture2D:
	var id := key + str(normal)
	if _cache.has(id): return _cache[id]
	var n := FastNoiseLite.new()
	n.seed = 719 if key == "rock" else 317
	n.frequency = 0.035 if key == "rock" else 0.018
	n.fractal_octaves = 4
	if key == "metal":
		n.noise_type = FastNoiseLite.TYPE_CELLULAR
		n.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
		n.frequency = 0.025
	var t := NoiseTexture2D.new()
	t.width = 512
	t.height = 512
	t.seamless = true
	t.generate_mipmaps = true
	t.as_normal_map = normal
	t.bump_strength = 2.0 if key == "metal" else 5.0
	if not normal and key in ["ground", "rock"]:
		var gradient := Gradient.new()
		gradient.colors = PackedColorArray([Color(0.68, 0.68, 0.68), Color.WHITE])
		t.color_ramp = gradient
	t.noise = n
	_cache[id] = t
	return t

# Tint stays on the material, so every palette shares the same neutral texture.
static func ground_albedo(_tint := Color.WHITE) -> NoiseTexture2D:
	return noise("ground")

static func ground_normal() -> NoiseTexture2D:
	return noise("ground", true)

static func rock_albedo(_tint := Color.WHITE) -> NoiseTexture2D:
	return noise("rock")

static func rock_normal() -> NoiseTexture2D:
	return noise("rock", true)

static func metal_panel_normal() -> NoiseTexture2D:
	return noise("metal", true)
