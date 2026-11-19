## Shared lighting, viewport and camera fitting for both shop modals.
extends RefCounted

const STAGE_TILT := 0.32
const STAGE_FLOOR_NAME := "StageCubesFloor"
const STAGE_FLOOR_Y := -1.15
const STAGE_FLOOR_WIDTH := 8.0
const STAGE_FLOOR_CLEARANCE := 0.08
const FOCUS_TWEEN := &"shop_preview_focus_tween"

static func create(parent: Control, with_stage: bool = false) -> Dictionary:
	var view := SubViewportContainer.new()
	view.custom_minimum_size = Vector2(400, 300)
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view.stretch = true
	var frame := PanelContainer.new()
	var fs := UI.style(Color(0, 0, 0, 0), Color(1, 1, 1, 0.14), 12, 12, 1)
	fs.shadow_color = Color(0, 0, 0, 0.6)
	fs.shadow_size = 18
	frame.add_theme_stylebox_override("panel", fs)
	frame.clip_contents = true
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_child(view)
	parent.add_child(frame)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(800, 220)
	viewport.own_world_3d = true
	viewport.transparent_bg = false
	view.add_child(viewport)
	var preview_root := Node3D.new()
	preview_root.rotation.y = 0.9
	viewport.add_child(preview_root)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.06, 0.045, 0.1)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.85, 0.9, 1.0)
	environment.environment.ambient_light_energy = 0.75
	viewport.add_child(environment)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = 5.0
	camera.position = Vector3(0, 1, 7)
	camera.rotation.x = -0.14
	viewport.add_child(camera)
	if with_stage:
		environment.environment.background_color = Color("#f3f5f8")
		environment.environment.ambient_light_color = Color(0.96, 0.97, 1.0)
		environment.environment.ambient_light_energy = 0.72
		environment.environment.tonemap_mode = Environment.TONE_MAPPER_ACES
		environment.environment.glow_enabled = false
		camera.position.y = tan(STAGE_TILT) * camera.position.z - 0.25
		camera.rotation.x = -STAGE_TILT
		_add_stage_lights(viewport)
		_add_stage_floor(viewport)
	else:
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-40, -30, 0)
		light.light_energy = 1.6
		viewport.add_child(light)
		var fill := OmniLight3D.new()
		fill.position = Vector3(-3, 2, 3)
		fill.omni_range = 20
		fill.light_energy = 3
		viewport.add_child(fill)
	return {"root": preview_root, "view": view, "camera": camera}

static func _add_stage_lights(viewport: SubViewport) -> void:
	var key := DirectionalLight3D.new()
	key.name = "StageKey"
	key.rotation_degrees = Vector3(-45, -35, 0)
	key.light_color = Color(1.0, 0.97, 0.92)
	key.light_energy = 1.1
	key.light_specular = 0.0
	viewport.add_child(key)

	var fill := DirectionalLight3D.new()
	fill.name = "StageFill"
	fill.rotation_degrees = Vector3(-12, 42, 0)
	fill.light_color = Color(0.88, 0.93, 1.0)
	fill.light_energy = 0.7
	fill.light_specular = 0.0
	viewport.add_child(fill)

	var rim := DirectionalLight3D.new()
	rim.name = "StageRim"
	rim.rotation_degrees = Vector3(-25, 165, 0)
	rim.light_color = Color(0.94, 0.97, 1.0)
	rim.light_energy = 0.65
	rim.light_specular = 0.0
	viewport.add_child(rim)

static func _add_stage_floor(viewport: SubViewport) -> void:
	var cubes_floor := MultiMeshInstance3D.new()
	cubes_floor.name = STAGE_FLOOR_NAME
	cubes_floor.position.y = STAGE_FLOOR_Y
	cubes_floor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var tiles_per_side := 16
	var pitch := STAGE_FLOOR_WIDTH / tiles_per_side
	var cube := BoxMesh.new()
	cube.size = Vector3(pitch * 0.94, 1.0, pitch * 0.94)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.85
	material.metallic = 0.05
	cube.material = material

	var tiles := MultiMesh.new()
	tiles.transform_format = MultiMesh.TRANSFORM_3D
	tiles.use_colors = true
	tiles.mesh = cube
	tiles.instance_count = tiles_per_side * tiles_per_side
	var random := RandomNumberGenerator.new()
	random.seed = 37
	var light_tile := Color("#eef2f6")
	var grey_tile := Color("#dde3ec")
	for z in range(tiles_per_side):
		for x in range(tiles_per_side):
			var index := z * tiles_per_side + x
			var height := random.randf_range(0.39, 0.49)
			var top := random.randf_range(-0.045, 0.0)
			var origin := Vector3(
				(x + 0.5) * pitch - STAGE_FLOOR_WIDTH * 0.5,
				top - height * 0.5,
				(z + 0.5) * pitch - STAGE_FLOOR_WIDTH * 0.5
			)
			var basis := Basis.from_scale(Vector3(1.0, height, 1.0))
			tiles.set_instance_transform(index, Transform3D(basis, origin))
			tiles.set_instance_color(index, light_tile.lerp(grey_tile, random.randf()))
	cubes_floor.multimesh = tiles
	viewport.add_child(cubes_floor)

static func spawn_install_sparkle(parent_node: Node3D, local_pos: Vector3) -> void:
	if not is_instance_valid(parent_node) or not parent_node.is_inside_tree():
		return
	var sparks := CPUParticles3D.new()
	sparks.name = "InstallSparkle"
	sparks.position = local_pos
	sparks.emitting = false
	sparks.one_shot = true
	sparks.amount = 28
	sparks.lifetime = 0.65
	sparks.explosiveness = 0.92
	sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	sparks.emission_sphere_radius = 0.12
	sparks.spread = 180.0
	sparks.gravity = Vector3(0, 0.8, 0)
	sparks.initial_velocity_min = 0.85
	sparks.initial_velocity_max = 2.1
	sparks.scale_amount_min = 0.45
	sparks.scale_amount_max = 1.25

	var colors := Gradient.new()
	colors.colors = PackedColorArray([Color("#00879a"), Color("#42bdc9")])
	sparks.color_initial_ramp = colors
	var fade := Gradient.new()
	fade.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0)])
	sparks.color_ramp = fade

	var spark_mesh := SphereMesh.new()
	spark_mesh.radius = 0.035
	spark_mesh.height = 0.07
	spark_mesh.radial_segments = 6
	spark_mesh.rings = 3
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sparks.mesh = spark_mesh
	sparks.material_override = material
	sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent_node.add_child(sparks)
	sparks.emitting = true
	parent_node.get_tree().create_timer(1.0).timeout.connect(sparks.queue_free)

static func focus_camera(camera: Camera3D, preview_root: Node3D, preview_view: SubViewportContainer, target_local_pos: Vector3 = Vector3.ZERO) -> void:
	if not is_instance_valid(camera):
		return
	var frame := _stage_frame(preview_root, preview_view, camera)
	_cancel_focus(camera)
	if frame.is_empty():
		return
	var position: Vector3 = frame.position
	var size: float = frame.size
	if UI.reduced_motion or not camera.is_inside_tree():
		camera.position = position
		camera.size = size
		return

	var tween := camera.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	camera.set_meta(FOCUS_TWEEN, tween)
	if target_local_pos != Vector3.ZERO and preview_root.get_child_count() > 0:
		var target := preview_root.transform * target_local_pos
		var offset := target - position
		offset -= camera.basis.z * offset.dot(camera.basis.z)
		var pan := (offset * 0.20).limit_length(size * 0.04)
		tween.tween_property(camera, "position", position + pan, 0.28)
		tween.parallel().tween_property(camera, "size", size * 0.96, 0.28)
		tween.tween_property(camera, "position", position, 0.17)
		tween.parallel().tween_property(camera, "size", size, 0.17)
	else:
		tween.tween_property(camera, "position", position, 0.45)
		tween.parallel().tween_property(camera, "size", size, 0.45)

static func fit(preview_root: Node3D, preview_view: SubViewportContainer, preview_camera: Camera3D) -> void:
	if not is_instance_valid(preview_camera):
		return
	var frame := _stage_frame(preview_root, preview_view, preview_camera)
	if not frame.is_empty():
		_cancel_focus(preview_camera)
		preview_camera.position = frame.position
		preview_camera.size = frame.size
		return
	if preview_root.get_child_count() == 0:
		return
	_preview_detail(preview_root)
	var boxes := [null]
	Actor._aabb(preview_root.get_child(0), Transform3D.IDENTITY, boxes)
	if boxes[0] == null:
		return
	var box: AABB = boxes[0]
	var diameter := Vector2(box.size.x, box.size.z).length()
	var height := box.size.y * cos(0.14) + diameter * sin(0.14)
	var aspect := preview_view.size.x / maxf(1.0, preview_view.size.y)
	preview_camera.size = maxf(height, diameter / maxf(aspect, 0.1)) * 1.18

static func _stage_frame(preview_root: Node3D, preview_view: SubViewportContainer, camera: Camera3D) -> Dictionary:
	var cubes_floor := preview_root.get_node_or_null("../" + STAGE_FLOOR_NAME) as MultiMeshInstance3D
	if cubes_floor == null:
		return {}
	var resting_position := Vector3(0, tan(STAGE_TILT) * 7.0 - 0.25, 7.0)
	var boxes := [null]
	_preview_detail(preview_root)
	for child in preview_root.get_children():
		Actor._aabb(child, Transform3D.IDENTITY, boxes)
	if boxes[0] == null:
		cubes_floor.position = Vector3(0, STAGE_FLOOR_Y, 0)
		cubes_floor.scale = Vector3.ONE
		return {"position": resting_position, "size": 5.0}

	var box: AABB = boxes[0]
	var stage_box := preview_root.transform * box
	var center := stage_box.get_center()
	cubes_floor.position = Vector3(center.x, stage_box.position.y - STAGE_FLOOR_CLEARANCE, center.z)
	var diameter := Vector2(box.size.x, box.size.z).length()
	var floor_scale := maxf(diameter * 1.75, 2.0) / STAGE_FLOOR_WIDTH
	cubes_floor.scale = Vector3(floor_scale, 1.0, floor_scale)
	var camera_space := Transform3D(camera.basis.inverse(), Vector3.ZERO) * preview_root.transform
	var projected := camera_space * box
	var aspect := maxf(preview_view.size.x / maxf(1.0, preview_view.size.y), 0.1)
	var size := maxf(projected.size.y, projected.size.x / aspect) * 1.24
	var position := center + camera.basis.z * resting_position.dot(camera.basis.z)
	return {"position": position, "size": maxf(size, 0.1)}

static func _cancel_focus(camera: Camera3D) -> void:
	if camera.has_meta(FOCUS_TWEEN):
		var tween := camera.get_meta(FOCUS_TWEEN) as Tween
		tween.kill()
		camera.remove_meta(FOCUS_TWEEN)

# Orthographic thumbnails always show detail without distance fading.
static func _preview_detail(node: Node) -> void:
	if node is GeometryInstance3D:
		node.visibility_range_end = 0
		node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	for child in node.get_children(): _preview_detail(child)
