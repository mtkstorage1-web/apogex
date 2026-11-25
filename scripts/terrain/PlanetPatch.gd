class_name PlanetPatch
extends Node3D

## One quadtree node of a cube-sphere face. Children patches are siblings in the
## scene tree (parented to the PlanetFace) so transforms never compound.

var face_index: int = 0
var depth: int = 0
var uv_min: Vector2 = Vector2(-1, -1)
var uv_max: Vector2 = Vector2(1, 1)
var center_planet_pos: Vector3 = Vector3.ZERO
var patch_extent: float = 1.0
var mesh_instance: MeshInstance3D
var children_patches: Array[PlanetPatch] = []
var is_split: bool = false
var mesh_built: bool = false
var collision_faces: PackedVector3Array = PackedVector3Array()
var has_collision: bool = false
var bounding_radius: float = 1.0
var avg_biome: int = 0
var want_visible: bool = false
var build_queued: bool = false
var discarded: bool = false
var collision_body: StaticBody3D

var _noise: TerrainNoiseStack
var _planet_radius: float = 12000.0
var _origin: Vector3 = Vector3.ZERO
var _material: Material
var _parent_patch: PlanetPatch


func setup(p_face: int, p_depth: int, p_uv_min: Vector2, p_uv_max: Vector2, p_noise: TerrainNoiseStack, p_radius: float, p_origin: Vector3, p_material: Material, p_parent: PlanetPatch = null) -> void:
	face_index = p_face
	depth = p_depth
	uv_min = p_uv_min
	uv_max = p_uv_max
	_noise = p_noise
	_planet_radius = p_radius
	_origin = p_origin
	_material = p_material
	_parent_patch = p_parent
	var dir: Vector3 = CubeSphereBuilder.patch_center_direction(face_index, uv_min, uv_max)
	center_planet_pos = _noise.sample_surface_position(dir)
	patch_extent = _planet_radius * PI * 0.25 * (uv_max.x - uv_min.x)
	bounding_radius = patch_extent * 0.75
	position = center_planet_pos - _origin
	_ensure_mesh_instance()
	_refresh_visibility()


func _ensure_mesh_instance() -> void:
	if mesh_instance != null:
		return
	var existing: Node = get_node_or_null("MeshInstance3D")
	if existing is MeshInstance3D:
		mesh_instance = existing as MeshInstance3D
	else:
		mesh_instance = MeshInstance3D.new()
		mesh_instance.name = "MeshInstance3D"
		add_child(mesh_instance)
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func build_mesh(noise_stack: TerrainNoiseStack, resolution: int, skirt_ratio: float) -> void:
	if mesh_built or discarded:
		return
	_ensure_mesh_instance()
	var skirt_depth: float = patch_extent * skirt_ratio
	var result: Dictionary = CubeSphereBuilder.build_patch_mesh(
		face_index, uv_min, uv_max, resolution, noise_stack, skirt_depth, center_planet_pos)
	mesh_instance.mesh = result["mesh"] as ArrayMesh
	collision_faces = result["collision_faces"] as PackedVector3Array
	bounding_radius = result["patch_radius"] as float
	avg_biome = result["avg_biome"] as int
	if _material != null:
		mesh_instance.material_override = _material
	if mesh_instance.material_override != null:
		mesh_instance.set_instance_shader_parameter("patch_lod_norm", float(depth) / 5.0)
	mesh_built = true
	build_queued = false
	_refresh_visibility()


func _refresh_visibility() -> void:
	if mesh_instance != null:
		mesh_instance.visible = mesh_built and want_visible and not is_split


func create_children() -> void:
	if not children_patches.is_empty():
		return
	var host: Node = get_parent()
	if host == null:
		return
	var mid: Vector2 = (uv_min + uv_max) * 0.5
	var boxes: Array[Array] = [
		[Vector2(uv_min.x, uv_min.y), Vector2(mid.x, mid.y)],
		[Vector2(mid.x, uv_min.y), Vector2(uv_max.x, mid.y)],
		[Vector2(uv_min.x, mid.y), Vector2(mid.x, uv_max.y)],
		[Vector2(mid.x, mid.y), Vector2(uv_max.x, uv_max.y)],
	]
	for box in boxes:
		var child := PlanetPatch.new()
		host.add_child(child)
		child.setup(face_index, depth + 1, box[0] as Vector2, box[1] as Vector2, _noise, _planet_radius, _origin, _material, self)
		children_patches.append(child)


func children_ready() -> bool:
	if children_patches.is_empty():
		return false
	for c in children_patches:
		if not c.mesh_built:
			return false
	return true


func split() -> void:
	if is_split or not children_ready():
		return
	is_split = true
	for c in children_patches:
		c.want_visible = true
		c._refresh_visibility()
	remove_collision()
	_refresh_visibility()


func merge() -> void:
	for c in children_patches:
		c.free_subtree()
	children_patches.clear()
	is_split = false
	_refresh_visibility()


func free_subtree() -> void:
	discarded = true
	for c in children_patches:
		c.free_subtree()
	children_patches.clear()
	remove_collision()
	if is_inside_tree():
		queue_free()
	else:
		free()


func apply_origin(new_origin: Vector3) -> void:
	_origin = new_origin
	position = center_planet_pos - _origin


func build_collision() -> void:
	if has_collision or collision_faces.is_empty():
		return
	collision_body = StaticBody3D.new()
	collision_body.name = "CollisionBody"
	collision_body.collision_layer = 1
	collision_body.collision_mask = 0
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(collision_faces)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	collision_body.add_child(cs)
	add_child(collision_body)
	has_collision = true


func remove_collision() -> void:
	if collision_body != null and is_instance_valid(collision_body):
		collision_body.queue_free()
	collision_body = null
	has_collision = false
