class_name PlanetMaterialController
extends Node

const TERRAIN_SHADER_PATH: String = "res://shaders/terrain.gdshader"

var material: ShaderMaterial
var lod_debug_enabled: bool = false
var wireframe_enabled: bool = false


func _init() -> void:
	material = ShaderMaterial.new()
	var shader: Shader = load(TERRAIN_SHADER_PATH) as Shader
	if shader == null:
		push_error("PlanetMaterialController: failed to load %s" % TERRAIN_SHADER_PATH)
		return
	material.shader = shader
	material.set_shader_parameter("lod_debug_enabled", false)


func set_star_direction(dir: Vector3) -> void:
	if dir.length_squared() > 0.0001:
		material.set_shader_parameter("star_direction", dir.normalized())


func set_planet_center(world_center: Vector3) -> void:
	material.set_shader_parameter("planet_center", world_center)


func set_lod_debug(enabled: bool) -> void:
	lod_debug_enabled = enabled
	material.set_shader_parameter("lod_debug_enabled", enabled)


func apply_quality(preset: String) -> void:
	var q: float = 0.75
	var bump: float = 0.7
	match preset.to_upper():
		"LOW":
			q = 0.0
			bump = 0.3
		"MEDIUM":
			q = 0.5
			bump = 0.55
		"HIGH":
			q = 0.75
			bump = 0.7
		"ULTRA":
			q = 1.0
			bump = 0.9
	material.set_shader_parameter("quality", q)
	material.set_shader_parameter("bump_strength", bump)


func set_wireframe(enabled: bool) -> void:
	wireframe_enabled = enabled
	if enabled:
		RenderingServer.set_debug_generate_wireframes(true)
	var vp: Viewport = get_viewport()
	if vp != null:
		vp.debug_draw = Viewport.DEBUG_DRAW_WIREFRAME if enabled else Viewport.DEBUG_DRAW_DISABLED
