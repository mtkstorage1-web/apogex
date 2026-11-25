class_name AtmosphereController
extends Node3D
## Planet-centred atmosphere shell + animated cloud shell. Both follow planet_center = -current_origin.

const ATMOSPHERE_SHADER := "res://shaders/atmosphere.gdshader"
const CLOUD_SHADER := "res://shaders/cloud.gdshader"
const CLOUD_ALTITUDE := 900.0

const Transforms = preload("res://scripts/coordinates/CoordinateTransformUtils.gd")

## "high" / "storm" / "plume" scale the three cloud formations smoothly with the preset.
const QUALITY := {
	"LOW": {"steps": 5, "segments": 48, "cloud": true, "high": 0.45, "storm": 0.0, "plume": 0.55},
	"MEDIUM": {"steps": 8, "segments": 72, "cloud": true, "high": 0.7, "storm": 0.6, "plume": 0.75},
	"HIGH": {"steps": 12, "segments": 96, "cloud": true, "high": 1.0, "storm": 0.9, "plume": 1.0},
	"ULTRA": {"steps": 18, "segments": 128, "cloud": true, "high": 1.2, "storm": 1.1, "plume": 1.2},
}
## Plume anchors: Obsidian Fields (0, -20) and Terminus Basin (0, 0).
const PLUME_SITES: Array = [Vector2(0.0, -20.0), Vector2(0.0, 0.0)]

var world_cfg: WorldConfig
var shell: MeshInstance3D
var clouds: MeshInstance3D
var shell_material: ShaderMaterial
var cloud_material: ShaderMaterial
var current_origin: Vector3 = Vector3.ZERO
var quality_preset: String = "HIGH"


func setup(p_world_cfg: WorldConfig) -> void:
	world_cfg = p_world_cfg
	quality_preset = world_cfg.quality_preset.to_upper()
	shell = get_node_or_null("AtmosphereShell") as MeshInstance3D
	clouds = get_node_or_null("CloudShell") as MeshInstance3D
	if shell == null:
		shell = MeshInstance3D.new()
		shell.name = "AtmosphereShell"
		add_child(shell)
	if clouds == null:
		clouds = MeshInstance3D.new()
		clouds.name = "CloudShell"
		add_child(clouds)
	shell_material = ShaderMaterial.new()
	shell_material.shader = load(ATMOSPHERE_SHADER) as Shader
	cloud_material = ShaderMaterial.new()
	cloud_material.shader = load(CLOUD_SHADER) as Shader
	shell.material_override = shell_material
	clouds.material_override = cloud_material
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	clouds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Shells are huge; never frustum-cull them away while the camera is inside.
	shell.extra_cull_margin = 16384.0
	clouds.extra_cull_margin = 16384.0
	set_star_direction(world_cfg.star_direction)
	set_quality(quality_preset)
	apply_origin(current_origin)


func set_quality(preset: String) -> void:
	quality_preset = preset.to_upper()
	var q: Dictionary = QUALITY.get(quality_preset, QUALITY["HIGH"])
	var seg: int = q["segments"]
	var sphere := SphereMesh.new()
	sphere.radius = world_cfg.atmosphere_radius
	sphere.height = world_cfg.atmosphere_radius * 2.0
	sphere.radial_segments = seg
	sphere.rings = seg / 2
	shell.mesh = sphere
	var cs := SphereMesh.new()
	cs.radius = world_cfg.planet_radius + CLOUD_ALTITUDE
	cs.height = cs.radius * 2.0
	cs.radial_segments = seg
	cs.rings = seg / 2
	clouds.mesh = cs
	clouds.visible = q["cloud"]
	cloud_material.set_shader_parameter("high_amount", q["high"])
	cloud_material.set_shader_parameter("storm_amount", q["storm"])
	cloud_material.set_shader_parameter("plume_amount", q["plume"])
	cloud_material.set_shader_parameter("plume_dir_a", _site_dir(0))
	cloud_material.set_shader_parameter("plume_dir_b", _site_dir(1))
	shell_material.set_shader_parameter("scattering_quality", q["steps"])
	shell_material.set_shader_parameter("planet_radius", world_cfg.planet_radius)
	shell_material.set_shader_parameter("atmosphere_radius", world_cfg.atmosphere_radius)


func set_star_direction(dir: Vector3) -> void:
	var d: Vector3 = dir.normalized()
	shell_material.set_shader_parameter("star_direction", d)
	cloud_material.set_shader_parameter("star_direction", d)


## Moves both shells so they stay centred on the planet in render space.
func apply_origin(new_origin: Vector3) -> void:
	current_origin = new_origin
	var center: Vector3 = -new_origin
	position = center
	if shell_material != null:
		shell_material.set_shader_parameter("planet_center", center)


## 0 = deep space (full glow), 1 = on the surface.
func get_density_at_altitude(altitude: float) -> float:
	return clampf(1.0 - altitude / (world_cfg.atmosphere_radius - world_cfg.planet_radius), 0.0, 1.0)


func _site_dir(i: int) -> Vector3:
	var s: Vector2 = PLUME_SITES[i]
	return Transforms.lat_lon_to_unit_dir(deg_to_rad(s.x), deg_to_rad(s.y))


## Current strength of the three formations (0 when a formation is disabled by the preset).
func get_cloud_formations() -> Dictionary:
	var q: Dictionary = QUALITY.get(quality_preset, QUALITY["HIGH"])
	return {"high_wisps": q["high"], "storm_bands": q["storm"], "volcanic_plumes": q["plume"], "shell_visible": clouds != null and clouds.visible}
