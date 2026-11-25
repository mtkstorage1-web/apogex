class_name WeatherEffectsController
extends Node3D
## Real-time weather + volcanic / electrical effects.
##  - Camera-centred gusting dust storms over Ashen Wastes and Iron Desert (haze shift + GPU dust drift).
##  - Volcanic ash + steam plumes near Obsidian Fields (planet-anchored, floating-origin aware).
##  - Deterministic electrical arc / spark emitters and flickering lights at the Abandoned Settlement and
##    industrial damage zones.

const Transforms = preload("res://scripts/coordinates/CoordinateTransformUtils.gd")
const FacilityMgr = preload("res://scripts/environment/SurfaceFacilityManager.gd")

const STORM_BIOMES: Array[String] = ["Ashen Wastes", "Iron Desert"]
const STORM_MAX_ALTITUDE := 700.0
const HAZE_MAX := 0.0011
const DUST_AMOUNT := {"LOW": 150, "MEDIUM": 320, "HIGH": 600, "ULTRA": 1100}
const PLUME_AMOUNT := {"LOW": 40, "MEDIUM": 90, "HIGH": 160, "ULTRA": 280}
const SPARK_AMOUNT := {"LOW": 6, "MEDIUM": 12, "HIGH": 20, "ULTRA": 32}
## Electrical zones: {id, lat, lon, local offset in pad space}.
const ARC_ZONES: Array = [
	{"id": &"settlement_grid", "lat": 0.0, "lon": -20.0, "local": Vector3(-14.0, 2.0, 10.0)},
	{"id": &"extraction_conduit", "lat": 0.0, "lon": 0.0, "local": Vector3(22.0, 2.0, -14.0)},
	{"id": &"refinery_conduit", "lat": 0.0, "lon": 20.0, "local": Vector3(-18.0, 2.0, 16.0)},
]
const PLUME_SITE := Vector2(2.0, -22.0)   # lat, lon: Obsidian Fields vent field

var noise: TerrainNoiseStack
var world_cfg: WorldConfig
var quality_preset: String = "HIGH"
var current_origin: Vector3 = Vector3.ZERO
var environment: Environment
var storm_target: float = 0.0
var storm_intensity: float = 0.0     # smoothed * gust
var storm_base: float = 0.0
var visibility_haze: float = 0.0
var flicker_time: float = 0.0
var dust: GPUParticles3D
var ash_plume: GPUParticles3D
var steam_plume: GPUParticles3D
var arc_zones: Array[Dictionary] = []   # {id, base_pos, node, sparks, light, flicker}
var _plume_base: Vector3 = Vector3.ZERO
var _time: float = 0.0


func setup(p_noise: TerrainNoiseStack, p_world_cfg: WorldConfig, p_environment: Environment = null) -> void:
	noise = p_noise
	world_cfg = p_world_cfg
	environment = p_environment
	quality_preset = world_cfg.quality_preset.to_upper()
	rebuild()


func rebuild() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	arc_zones.clear()
	dust = _make_emitter("DustStorm", Color(0.62, 0.45, 0.3, 0.28), 0.9, Vector3(60, 14, 60), Vector3(1, 0.05, 0.3), 14.0, 5.0, false)
	add_child(dust)
	if noise == null:
		return
	var pu: Vector3 = Transforms.lat_lon_to_unit_dir(deg_to_rad(PLUME_SITE.x), deg_to_rad(PLUME_SITE.y))
	_plume_base = noise.sample_surface_position(pu)
	ash_plume = _make_emitter("AshPlume", Color(0.12, 0.1, 0.1, 0.5), 5.0, Vector3(5, 1, 5), Vector3(0.15, 1, 0.05), 11.0, 9.0, true)
	steam_plume = _make_emitter("SteamPlume", Color(0.85, 0.85, 0.9, 0.3), 2.4, Vector3(3, 1, 3), Vector3(0.05, 1, 0.1), 6.0, 5.0, true)
	for e in [ash_plume, steam_plume]:
		add_child(e)
		(e as GPUParticles3D).local_coords = false
	for z in ARC_ZONES:
		var pt: Dictionary = FacilityMgr.pad_transform(noise, z["lat"], z["lon"])
		var pos: Vector3 = (pt["origin"] as Vector3) + (pt["basis"] as Basis) * (z["local"] as Vector3)
		var node := Node3D.new()
		node.name = "Arc_%s" % String(z["id"])
		var sparks: GPUParticles3D = _make_emitter("Sparks", Color(0.7, 0.85, 1.0, 1.0), 0.12, Vector3(0.6, 0.3, 0.6), Vector3(0, 1, 0), 5.0, 0.8, true)
		node.add_child(sparks)
		var light := OmniLight3D.new()
		light.name = "ArcLight"
		light.light_color = Color(0.6, 0.8, 1.0)
		light.omni_range = 18.0
		light.shadow_enabled = false
		node.add_child(light)
		add_child(node)
		node.basis = pt["basis"]
		arc_zones.append({"id": z["id"], "base_pos": pos, "node": node, "sparks": sparks, "light": light, "flicker": 0.0})
	set_quality(quality_preset)
	apply_origin(current_origin)


## Shared GPUParticles3D factory. Billboard unshaded quads, turbulence for drift.
func _make_emitter(n: String, color: Color, quad: float, extents: Vector3, dir: Vector3, speed: float, lifetime: float, one_shot_zone: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = n
	p.amount = 100
	p.lifetime = lifetime
	p.emitting = false
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-80, -30, -80), Vector3(160, 120, 160))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = extents
	pm.direction = dir.normalized()
	pm.spread = 25.0 if one_shot_zone else 8.0
	pm.initial_velocity_min = speed * 0.6
	pm.initial_velocity_max = speed
	pm.gravity = Vector3.ZERO
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.8
	pm.turbulence_noise_scale = 4.0
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(quad, quad)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_color = color
	m.disable_fog = true
	q.material = m
	p.draw_pass_1 = q
	return p


func set_quality(preset: String) -> void:
	quality_preset = preset.to_upper()
	if dust != null:
		dust.amount = DUST_AMOUNT.get(quality_preset, 600)
	if ash_plume != null:
		ash_plume.amount = PLUME_AMOUNT.get(quality_preset, 160)
		steam_plume.amount = PLUME_AMOUNT.get(quality_preset, 160) / 2
		ash_plume.emitting = true
		steam_plume.emitting = true
	for z in arc_zones:
		(z["sparks"] as GPUParticles3D).amount = SPARK_AMOUNT.get(quality_preset, 20)
		(z["sparks"] as GPUParticles3D).emitting = true


func set_environment(env: Environment) -> void:
	environment = env


func apply_origin(new_origin: Vector3) -> void:
	current_origin = new_origin
	if ash_plume != null:
		ash_plume.position = _plume_base - current_origin
		steam_plume.position = _plume_base - current_origin
	for z in arc_zones:
		(z["node"] as Node3D).position = (z["base_pos"] as Vector3) - current_origin


## Deterministic 0..1 gust factor (smooth, no randomness: pure function of time).
static func gust_factor(t: float) -> float:
	return clampf(0.62 + 0.28 * sin(t * 0.7) + 0.1 * sin(t * 2.3 + 1.7), 0.0, 1.0)


## Deterministic flicker: stepped hash of the time slice.
static func flicker(t: float, salt: float) -> float:
	var slice: float = floor(t * 14.0 + salt * 3.0)
	var h: float = fposmod(sin(slice * 12.9898 + salt * 78.233) * 43758.5453, 1.0)
	return 0.15 if h < 0.35 else 0.55 + 0.45 * h


func follow(cam_render_pos: Vector3, up: Vector3, biome_name: String, altitude: float, delta: float) -> void:
	_time += delta
	flicker_time += delta
	var in_storm_biome: bool = STORM_BIOMES.has(biome_name) and altitude < STORM_MAX_ALTITUDE
	storm_target = 1.0 if in_storm_biome else 0.0
	storm_base = move_toward(storm_base, storm_target, delta * 0.4)
	storm_intensity = storm_base * gust_factor(_time)
	visibility_haze = storm_intensity * HAZE_MAX
	if environment != null and visibility_haze > 0.0:
		environment.fog_density += visibility_haze
	if dust != null:
		dust.global_position = cam_render_pos + up * 6.0
		dust.emitting = storm_base > 0.02
		dust.amount_ratio = clampf(storm_intensity, 0.05, 1.0)
		(dust.process_material as ParticleProcessMaterial).initial_velocity_max = 10.0 + 18.0 * storm_intensity
	for i in arc_zones.size():
		var z: Dictionary = arc_zones[i]
		var f: float = flicker(flicker_time, float(i) + float(world_cfg.world_seed % 97))
		z["flicker"] = f
		(z["light"] as OmniLight3D).light_energy = f * 4.0
		(z["sparks"] as GPUParticles3D).amount_ratio = clampf(f, 0.1, 1.0)


func get_storm_intensity() -> float:
	return storm_intensity


func get_diagnostics() -> Dictionary:
	return {"storm_intensity": storm_intensity, "haze": visibility_haze, "arc_zones": arc_zones.size(),
		"plumes": 2 if ash_plume != null else 0}
