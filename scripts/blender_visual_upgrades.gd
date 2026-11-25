class_name BlenderVisualUpgrades
extends RefCounted
## Loads the APOGEX GLBs as normalized models. Scenic copies contain only meshes.
const MODEL_ROOT := "res://assets/models/apogex/"
const FORCEFIELD := preload("res://shaders/forcefield.gdshader")
const THRUSTER := preload("res://shaders/thruster.gdshader")

static var _scenes: Dictionary[String, PackedScene] = {}
static var _visual_meshes: Dictionary[String, ArrayMesh] = {}
static var _plume_mesh: CylinderMesh
static var _plume_material: ShaderMaterial


## Fits the largest dimension to size in local world units. Airborne models are centered on all axes.
static func model(asset: String, size: float, ground := true, strip_collision := true) -> Node3D:
	if not asset.ends_with(".glb") or asset.is_absolute_path() or ".." in asset.split("/") \
			or not is_finite(size) or size <= 0.0:
		return null
	var content: Node3D
	var bounds: AABB
	if strip_collision:
		if not _visual_meshes.has(asset):
			var scene := _instantiate(asset)
			if scene == null:
				return null
			var surfaces: Dictionary = {}
			_collect_surfaces(scene, Transform3D.IDENTITY, surfaces)
			scene.free()
			var mesh := ArrayMesh.new()
			for surface: SurfaceTool in surfaces.values():
				surface.commit(mesh)
			if mesh.get_surface_count() == 0:
				return null
			_visual_meshes[asset] = mesh
		var visual := MeshInstance3D.new()
		visual.mesh = _visual_meshes[asset]
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		content = visual
		bounds = visual.get_aabb()
	else:
		content = _instantiate(asset)
		if content == null:
			return null
		bounds = _mesh_bounds(content, Transform3D.IDENTITY)
	var longest := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	if not bounds.is_finite() or longest <= 0.0001:
		content.free()
		return null
	var pivot := bounds.get_center()
	if ground:
		pivot.y = bounds.position.y
	var factor := size / longest
	var uniform_scale := Vector3.ONE * factor
	var offset := -pivot * factor
	if not uniform_scale.is_finite() or not offset.is_finite() or uniform_scale.x <= 0.0:
		content.free()
		return null
	var result := Node3D.new()
	result.name = asset.get_file().get_basename().to_pascal_case()
	content.transform = Transform3D(Basis.from_scale(uniform_scale), offset) * content.transform
	result.add_child(content)
	return result


static func place(parent: Node3D, asset: String, at: Vector3, size: float, yaw := 0.0, ground := true) -> Node3D:
	var prop := model(asset, size, ground)
	if prop != null:
		prop.position = at
		prop.rotation.y = yaw
		parent.add_child(prop)
	return prop


static func _instantiate(asset: String) -> Node3D:
	if not _scenes.has(asset):
		var path := MODEL_ROOT + asset
		if not ResourceLoader.exists(path, "PackedScene"):
			_scenes[asset] = null
			return null
		_scenes[asset] = load(path) as PackedScene
	var scene := _scenes[asset]
	if scene == null:
		return null
	var instance := scene.instantiate()
	if instance is Node3D:
		return instance
	if instance != null:
		instance.free()
	return null


## Batch static GLB pieces by material and vertex format. Cache each batch across worlds and instances.
static func _collect_surfaces(node: Node, parent_xf: Transform3D, surfaces: Dictionary) -> void:
	var xf := parent_xf
	if node is Node3D:
		if not node.visible:
			return
		xf *= node.transform
	if node is MeshInstance3D and node.mesh is ArrayMesh:
		var mesh: ArrayMesh = node.mesh
		for i in mesh.get_surface_count():
			var material: Material = node.get_active_material(i)
			var key := [material, mesh.surface_get_format(i) & ((1 << Mesh.ARRAY_MAX) - 1)]
			if not surfaces.has(key):
				var surface := SurfaceTool.new()
				surface.begin(Mesh.PRIMITIVE_TRIANGLES)
				surface.set_material(material)
				surfaces[key] = surface
			(surfaces[key] as SurfaceTool).append_from(mesh, i, xf)
	for child in node.get_children():
		_collect_surfaces(child, xf, surfaces)


static func _mesh_bounds(node: Node, parent_xf: Transform3D) -> AABB:
	var xf := parent_xf
	if node is Node3D:
		xf *= node.transform
	var bounds := AABB()
	if node is MeshInstance3D and node.mesh != null:
		bounds = xf * node.get_aabb()
	for child in node.get_children():
		var child_bounds := _mesh_bounds(child, xf)
		if child_bounds.has_surface():
			bounds = bounds.merge(child_bounds) if bounds.has_surface() else child_bounds
	return bounds


static func shield(color: Color, alpha: float, diameter: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = FORCEFIELD
	material.set_shader_parameter("field_color", color)
	material.set_shader_parameter("dome_opacity", alpha)
	material.set_shader_parameter("hex_scale", 160.0 / diameter)
	material.set_shader_parameter("intensity", 1.0)
	return material


static func fighter_plume() -> MeshInstance3D:
	if _plume_mesh == null:
		_plume_mesh = CylinderMesh.new()
		_plume_mesh.top_radius = 0.23
		_plume_mesh.bottom_radius = 0.0
		_plume_mesh.height = 1.8
		_plume_mesh.radial_segments = 12
		_plume_mesh.rings = 1
		_plume_mesh.cap_top = false
		_plume_material = ShaderMaterial.new()
		_plume_material.shader = THRUSTER
		_plume_material.set_shader_parameter("plasma_color", Color("#ff7441"))
		_plume_material.set_shader_parameter("throttle", 1.25)
		_plume_material.set_shader_parameter("plume_length", _plume_mesh.height)
	var plume := MeshInstance3D.new()
	plume.mesh = _plume_mesh
	plume.material_override = _plume_material
	plume.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	plume.rotation.x = -PI / 2.0
	return plume
