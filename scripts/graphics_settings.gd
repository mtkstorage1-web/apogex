extends RefCounted

const QUALITY_NAMES := ["LOW", "MEDIUM", "HIGH", "ULTRA", "CUSTOM"]
const HIGH := 2
const CUSTOM := 4
const RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080),
	Vector2i(2560, 1440), Vector2i(3840, 2160)]
const WINDOW_MODES := [DisplayServer.WINDOW_MODE_WINDOWED, DisplayServer.WINDOW_MODE_FULLSCREEN,
	DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
const TOGGLE := [false, true]
const LEVELS := [0, 1, 2]
const LEVEL_NAMES := ["LOW", "MEDIUM", "HIGH"]
const SHADOW_SIZES := [0, 1024, 2048, 4096, 8192]
# Index 0 (shadows OFF) keeps a valid positive range: a 0.0 max distance builds a
# degenerate directional shadow frustum if anything re-enables the light's shadow.
const SHADOW_DISTANCES := [100.0, 110.0, 220.0, 420.0, 700.0]
const DISPLAY_KEYS := ["window_mode", "resolution", "vsync"]
const ANISOTROPY := [Viewport.ANISOTROPY_DISABLED, Viewport.ANISOTROPY_4X, Viewport.ANISOTROPY_16X]
const SHADOW_FILTERS := [RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_HARD,
	RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM,
	RenderingServer.SHADOW_QUALITY_SOFT_HIGH]
const FORWARD_EFFECTS := ["ssil", "ssr", "volumetric_fog"]

# Each row contains the menu label, cycle values, and defaults for Low through Ultra.
const OPTIONS := {
	"window_mode": ["WINDOW MODE", WINDOW_MODES, [0, 0, 0, 0]],
	"resolution": ["RESOLUTION", RESOLUTIONS, [Vector2i(1600, 900), Vector2i(1600, 900), Vector2i(1600, 900), Vector2i(1600, 900)]],
	"render_scale": ["RENDER SCALE", [50, 67, 75, 85, 100], [67, 85, 100, 100]],
	"upscaler": ["UPSCALER", [0, 1, 2], [0, 1, 0, 0]],
	"vsync": ["VSYNC", [0, 1, 2, 3], [1, 1, 1, 1]],
	"aa": ["ANTI-ALIASING", [0, 1, 2, 3, 4, 5], [0, 1, 3, 5]],
	"shadows": ["SHADOW QUALITY", [0, 1, 2, 3, 4], [0, 1, 3, 4]],
	"lod": ["TEXTURE / MESH LOD", LEVELS, [0, 1, 2, 2]],
	"ssao": ["SSAO", TOGGLE, [false, false, true, true]],
	"ssil": ["SSIL", TOGGLE, [false, false, false, true]],
	"ssr": ["SSR", TOGGLE, [false, false, false, true]],
	"glow": ["GLOW / BLOOM", TOGGLE, [false, true, true, true]],
	"volumetric_fog": ["VOLUMETRIC FOG", TOGGLE, [false, false, false, true]],
	"motion_effects": ["MOTION EFFECTS", TOGGLE, [false, true, true, true]],
	"particles": ["PARTICLE DENSITY", [25, 50, 75, 100], [25, 50, 75, 100]],
	"terrain": ["TERRAIN DETAIL", LEVELS, [0, 1, 2, 2]],
	"clouds": ["CLOUD DETAIL", LEVELS, [0, 1, 2, 2]],
	"atmosphere": ["ATMOSPHERE DETAIL", [0, 1, 2, 3], [0, 1, 2, 3]],
	"brightness": ["BRIGHTNESS", [80, 90, 100, 110, 120], [100, 100, 100, 100]],
	"fps_limit": ["FPS LIMIT", [30, 60, 120, 144, 0], [60, 60, 60, 60]],
	"fps_counter": ["FPS COUNTER", TOGGLE, [false, false, false, false]],
}

var quality := HIGH
var values := {}
var _fullscreen_transition := false
# Spawned effects use these values even if created after the settings were applied.
static var particle_density := 1.0
static var motion_effects := true
# The directional shadow atlas and soft filter are global RenderingServer state.
# Remember what was last pushed so repeated applies do not reallocate them.
static var _directional_atlas_size := -1
static var _soft_shadow_filter := -1


func _init() -> void:
	set_preset(HIGH)


func set_preset(preset: int) -> bool:
	if preset < 0 or preset >= CUSTOM:
		return false
	quality = preset
	for key in OPTIONS:
		values[key] = OPTIONS[key][2][preset]
	return true


## Snapshot of the settings that touch the native window, so callers can skip
## window work when only rendering options changed.
func display_state() -> Array:
	return DISPLAY_KEYS.map(func(key: String): return values.get(key))


func load_config(config: ConfigFile) -> void:
	var saved_quality := clampi(int(config.get_value("graphics", "quality", HIGH)), 0, CUSTOM)
	set_preset(HIGH if saved_quality == CUSTOM else saved_quality)
	quality = saved_quality
	for key in OPTIONS:
		var saved: Variant = config.get_value("graphics", key, values[key])
		if OPTIONS[key][1].has(saved):
			values[key] = saved


func save_config(config: ConfigFile) -> void:
	config.set_value("graphics", "quality", quality)
	for key in OPTIONS:
		config.set_value("graphics", key, values[key])


## True on iOS/iPadOS or any mobile feature build (Apple A-series / M-series Metal tiled GPUs).
static func is_mobile_gpu() -> bool:
	return OS.has_feature("ios") or OS.has_feature("mobile")


func renderer() -> StringName:
	return RenderingServer.get_current_rendering_method()


func window_resolutions() -> Array:
	if DisplayServer.get_name() == "headless":
		return RESOLUTIONS
	var screen := DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())
	return RESOLUTIONS.filter(func(size: Vector2i): return size.x <= screen.x and size.y <= screen.y)


func available(key: String) -> Array:
	var method := renderer()
	match key:
		"resolution":
			return window_resolutions()
		"upscaler":
			if method != &"forward_plus":
				return [0]
			return [0, 1] if OS.get_name() == "macOS" else OPTIONS[key][1]
		"aa":
			var choices := [0]
			if method != &"gl_compatibility":
				choices.append(1)
			choices.append_array([2, 3, 4])
			if method == &"forward_plus" and OS.get_name() != "macOS":
				choices.append(5)
			return choices
		"ssao":
			return [false] if method == &"mobile" or is_mobile_gpu() else TOGGLE
		"vsync":
			# Metal and MoltenVK on macOS expose only the display sync toggle.
			if method == &"gl_compatibility" or OS.get_name() == "macOS":
				return [0, 1]
	if key in FORWARD_EFFECTS and method != &"forward_plus":
		return [false]
	return OPTIONS[key][1]


func effective(key: String) -> Variant:
	var choices := available(key)
	var value: Variant = values[key]
	if choices.has(value):
		return value
	if key == "resolution":
		return choices.back() if not choices.is_empty() else Vector2i.ZERO
	if key == "vsync":
		return DisplayServer.VSYNC_ENABLED
	if key == "aa" and value == 5 and choices.has(1):
		return 1
	return choices.front()


func can_cycle(key: String) -> bool:
	if not OPTIONS.has(key):
		return false
	if key == "resolution" and values["window_mode"] != DisplayServer.WINDOW_MODE_WINDOWED:
		return false
	return available(key).size() > 1


func cycle(key: String) -> void:
	if not can_cycle(key):
		return
	var choices := available(key)
	values[key] = choices[(choices.find(effective(key)) + 1) % choices.size()]
	# FSR2 includes its own temporal AA. Selecting a different AA returns to bilinear.
	if key == "upscaler" and values[key] == Viewport.SCALING_3D_MODE_FSR2:
		values["aa"] = 0
	elif key == "aa" and values[key] != 0 and effective("upscaler") == Viewport.SCALING_3D_MODE_FSR2:
		values["upscaler"] = Viewport.SCALING_3D_MODE_BILINEAR
	quality = CUSTOM


func option_text(key: String, reduced_motion: bool) -> String:
	var value: Variant = effective(key)
	var label: String
	match key:
		"window_mode": label = ["WINDOWED", "BORDERLESS FULLSCREEN", "EXCLUSIVE FULLSCREEN"][WINDOW_MODES.find(value)]
		"resolution":
			if values["window_mode"] != DisplayServer.WINDOW_MODE_WINDOWED:
				label = "DISPLAY SIZE"
			else:
				label = "%d × %d" % [value.x, value.y] if value != Vector2i.ZERO else "DISPLAY SIZE"
		"upscaler": label = ["BILINEAR", "FSR1", "FSR2"][value]
		"vsync": label = ["OFF", "ON", "ADAPTIVE", "MAILBOX"][value]
		"aa":
			label = "FSR2" if effective("upscaler") == Viewport.SCALING_3D_MODE_FSR2 else ["OFF", "FXAA", "MSAA 2×", "MSAA 4×", "MSAA 8×", "TAA"][value]
		"shadows": label = ["OFF", "LOW", "MEDIUM", "HIGH", "ULTRA"][value]
		"lod", "terrain", "clouds": label = LEVEL_NAMES[value]
		"atmosphere": label = QUALITY_NAMES[value]
		"render_scale", "particles", "brightness": label = "%d%%" % value
		"fps_limit": label = "UNLIMITED" if value == 0 else str(value)
		"motion_effects": label = "OFF (REDUCED MOTION)" if reduced_motion else ("ON" if value else "OFF")
		_: label = "ON" if value else "OFF"
	return "%s: %s" % [OPTIONS[key][0], label]


# Untyped targets let these entry points reject previously freed Godot objects.
func _has_native_window(window) -> bool:
	return DisplayServer.get_name() != "headless" and is_instance_valid(window) and window.is_inside_tree() \
		and not window.is_queued_for_deletion() and not Engine.is_embedded_in_editor() \
		and not window.is_embedded() and window.get_window_id() != DisplayServer.INVALID_WINDOW_ID


func apply_display(window) -> void:
	if not _has_native_window(window) or _fullscreen_transition:
		return
	var window_id: int = window.get_window_id()
	for attempt in 3:
		var target_mode: int = values["window_mode"]
		var current_mode := DisplayServer.window_get_mode(window_id)
		if current_mode == target_mode:
			break
		DisplayServer.window_set_mode(target_mode as DisplayServer.WindowMode, window_id)
		if OS.get_name() != "macOS" or (current_mode >= DisplayServer.WINDOW_MODE_FULLSCREEN
				and target_mode >= DisplayServer.WINDOW_MODE_FULLSCREEN):
			break
		# Cocoa animates transitions asynchronously and may defer a mode change.
		# Wait before resizing the window or applying another fullscreen request.
		_fullscreen_transition = true
		await window.get_tree().create_timer(1.0, true, false, true).timeout
		if not _has_native_window(window) or window.get_window_id() != window_id:
			_fullscreen_transition = false
			return
	_fullscreen_transition = false
	_apply_window_options(window_id)


func _apply_window_options(window_id: int) -> void:
	if values["window_mode"] == DisplayServer.WINDOW_MODE_WINDOWED and DisplayServer.window_get_mode(window_id) == DisplayServer.WINDOW_MODE_WINDOWED:
		if DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, window_id):
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false, window_id)
		var size: Vector2i = effective("resolution")
		if size != Vector2i.ZERO and DisplayServer.window_get_size(window_id) != size:
			DisplayServer.window_set_size(size, window_id)
	_apply_vsync(window_id)


func _apply_vsync(window_id: int) -> void:
	var vsync: int = effective("vsync")
	if DisplayServer.window_get_vsync_mode(window_id) != vsync:
		DisplayServer.window_set_vsync_mode(vsync as DisplayServer.VSyncMode, window_id)


func apply_viewport(viewport) -> void:
	if not is_instance_valid(viewport) or not viewport.is_inside_tree() or viewport.is_queued_for_deletion():
		return
	apply_viewport_buffers(viewport)
	apply_shadow_atlases(viewport)


func apply_viewport_buffers(viewport: Viewport) -> void:
	var upscaler: int = effective("upscaler")
	var aa: int = effective("aa") if upscaler != Viewport.SCALING_3D_MODE_FSR2 else 0
	var lod: int = values["lod"]
	var msaa: int = [0, 0, 1, 2, 3, 0][aa]
	# Tiled mobile GPUs resolve MSAA cheaply on-chip at 2x; 4x/8x burn bandwidth and heat.
	if is_mobile_gpu():
		msaa = mini(msaa, Viewport.MSAA_2X)
	var screen_aa: int = Viewport.SCREEN_SPACE_AA_FXAA if aa == 1 else Viewport.SCREEN_SPACE_AA_DISABLED
	var scale: float = values["render_scale"] / 100.0
	# Remove old AA before switching to FSR2 and leave FSR2 before enabling new AA.
	if viewport.use_taa and aa != 5:
		viewport.use_taa = false
	if msaa == Viewport.MSAA_DISABLED and viewport.msaa_3d != msaa:
		viewport.msaa_3d = Viewport.MSAA_DISABLED
	if viewport.screen_space_aa != screen_aa and viewport.screen_space_aa != Viewport.SCREEN_SPACE_AA_DISABLED:
		viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	if viewport.scaling_3d_mode != upscaler:
		viewport.scaling_3d_mode = upscaler as Viewport.Scaling3DMode
	if not is_equal_approx(viewport.scaling_3d_scale, scale):
		viewport.scaling_3d_scale = scale
	if viewport.msaa_3d != msaa:
		viewport.msaa_3d = msaa as Viewport.MSAA
	if viewport.screen_space_aa != screen_aa:
		viewport.screen_space_aa = screen_aa as Viewport.ScreenSpaceAA
	if viewport.use_taa != (aa == 5):
		viewport.use_taa = aa == 5
	if not is_equal_approx(viewport.mesh_lod_threshold, [4.0, 2.0, 1.0][lod]):
		viewport.mesh_lod_threshold = [4.0, 2.0, 1.0][lod]
	if viewport.anisotropic_filtering_level != ANISOTROPY[lod]:
		viewport.anisotropic_filtering_level = ANISOTROPY[lod]


func apply_shadow_atlases(viewport: Viewport) -> void:
	var shadows: int = values["shadows"]
	var positional_size := mini(4096, SHADOW_SIZES[shadows])
	if viewport.positional_shadow_atlas_size != positional_size:
		viewport.positional_shadow_atlas_size = positional_size
	# Keep a valid directional atlas when shadows are disabled on the lights.
	var atlas_size := maxi(1024, SHADOW_SIZES[shadows])
	var filter: int = SHADOW_FILTERS[shadows]
	if is_mobile_gpu():
		atlas_size = mini(atlas_size, 2048)
		filter = mini(filter, RenderingServer.SHADOW_QUALITY_SOFT_LOW)
	var device := RenderingServer.get_rendering_device()
	if device != null:
		atlas_size = mini(atlas_size, device.limit_get(RenderingDevice.LIMIT_MAX_TEXTURE_SIZE_2D))
	if atlas_size != _directional_atlas_size:
		_directional_atlas_size = atlas_size
		RenderingServer.directional_shadow_atlas_set_size(atlas_size, true)
	if filter != _soft_shadow_filter:
		_soft_shadow_filter = filter
		RenderingServer.directional_soft_shadow_filter_set_quality(filter)


func apply_scene(root) -> void:
	if not is_instance_valid(root) or root.is_queued_for_deletion():
		return
	apply_shadows(root)
	for node in root.find_children("*", "WorldEnvironment", true, false):
		var env: Environment = node.environment
		if env == null:
			continue
		_set_if_changed(env, &"ssao_enabled", effective("ssao"))
		_set_if_changed(env, &"ssil_enabled", effective("ssil"))
		_set_if_changed(env, &"ssr_enabled", effective("ssr"))
		_set_if_changed(env, &"glow_enabled", values["glow"])
		_set_if_changed(env, &"volumetric_fog_enabled", effective("volumetric_fog"))
		var tier := clampi(values["atmosphere"], 0, 3)
		_set_if_changed(env, &"volumetric_fog_density", env.fog_density * [0.0, 0.3, 0.5, 0.9][tier] if env.fog_enabled else 0.0)
		_set_if_changed(env, &"volumetric_fog_emission_energy", [0.0, 0.0, 0.0, 0.25][tier])
		_set_if_changed(env, &"ssil_intensity", [0.0, 0.6, 1.0, 1.6][tier])
		_set_if_changed(env, &"ssr_max_steps", [8, 32, 64, 128][tier])
		_set_if_changed(env, &"fog_sun_scatter", [0.0, 0.35, 0.65, 0.95][tier])
		_set_if_changed(env, &"fog_aerial_perspective", [0.0, 0.40, 0.72, 0.95][tier])
		_set_if_changed(env, &"glow_intensity", [0.0, 0.22, 0.38, 0.62][tier])
		_set_if_changed(env, &"glow_bloom", [0.0, 0.05, 0.10, 0.18][tier])
		_set_if_changed(env, &"ssao_intensity", [0.0, 0.7, 1.1, 1.6][tier])
		_set_if_changed(env, &"adjustment_contrast", [1.0, 1.05, 1.09, 1.14][tier])
		_set_if_changed(env, &"adjustment_saturation", [1.0, 1.06, 1.12, 1.18][tier])
		_set_if_changed(env, &"adjustment_brightness", values["brightness"] / 100.0)
		_set_if_changed(env, &"adjustment_enabled", true)
	for node in root.find_children("*", "CPUParticles3D", true, false):
		set_particle_count(node, node.get_meta("base_particle_count", node.amount))
	if root.name == &"PlanetA" and root.has_method("apply_quality"):
		root.apply_quality(self)
	for node in root.find_children("PlanetA", "", true, false):
		if node.has_method("apply_quality"):
			node.apply_quality(self)


func apply_shadows(root) -> void:
	if not is_instance_valid(root) or root.is_queued_for_deletion():
		return
	var shadows: int = values["shadows"]
	for node in root.find_children("*", "Light3D", true, false):
		if node.is_queued_for_deletion():
			continue
		if not node.has_meta("authored_shadows"):
			node.set_meta("authored_shadows", node.shadow_enabled)
		var cast: bool = shadows > 0 and node.get_meta("authored_shadows")
		if not cast:
			_set_if_changed(node, &"shadow_enabled", false)
		if node is DirectionalLight3D:
			_set_if_changed(node, &"directional_shadow_max_distance", SHADOW_DISTANCES[shadows])
			_set_if_changed(node, &"shadow_blur", [1.0, 1.4, 1.2, 1.0, 0.8][shadows])
		if cast:
			_set_if_changed(node, &"shadow_enabled", true)


static func _set_if_changed(object: Object, property: StringName, value: Variant) -> void:
	var current: Variant = object.get(property)
	if typeof(current) == TYPE_FLOAT and typeof(value) in [TYPE_FLOAT, TYPE_INT]:
		if is_equal_approx(current, float(value)):
			return
	elif typeof(current) == typeof(value) and current == value:
		return
	object.set(property, value)


static func set_particle_count(particles, count: int) -> void:
	if not is_instance_valid(particles) or particles.is_queued_for_deletion():
		return
	particles.set_meta("base_particle_count", count)
	var target := maxi(1, roundi(count * particle_density))
	if particles.amount != target:
		particles.amount = target
