## Build-time/static setup only. Gameplay nodes are deliberately selected by callers.
extends RefCounted

static func batch(parent: Node3D, prefixes: Array = [], distance := 60.0, max_dimension := INF) -> void:
	var groups := {}
	for child in parent.get_children():
		if not child is MeshInstance3D or child.get_child_count() > 0 or not child.visible: continue
		if not prefixes.is_empty():
			var selected := false
			for prefix in prefixes:
				if str(child.name).begins_with(prefix): selected = true
			if not selected: continue
		if (child.get_aabb().size * child.scale.abs()).length() > max_dimension: continue
		var source: Mesh = child.mesh
		var unit: Mesh
		var dimensions := Vector3.ONE
		var key := ""
		if source is BoxMesh:
			unit = BoxMesh.new()
			dimensions = source.size
			key = "box"
		elif source is SphereMesh:
			var sphere := SphereMesh.new()
			sphere.radius = 1
			sphere.height = 2
			sphere.radial_segments = source.radial_segments
			sphere.rings = source.rings
			unit = sphere
			dimensions = Vector3(source.radius,source.height*.5,source.radius)
			key = "sphere:%s:%s" % [sphere.radial_segments,sphere.rings]
		elif source is CylinderMesh and source.bottom_radius > 0:
			var cylinder := CylinderMesh.new()
			cylinder.bottom_radius = 1
			cylinder.top_radius = source.top_radius/source.bottom_radius
			cylinder.height = 1
			cylinder.radial_segments = source.radial_segments
			cylinder.rings = source.rings
			unit = cylinder
			dimensions = Vector3(source.bottom_radius,source.height,source.bottom_radius)
			key = "cylinder:%s:%s:%s" % [cylinder.top_radius,cylinder.radial_segments,cylinder.rings]
		else: continue
		# Spatial cells keep each batch's culling bounds local.
		var cell := Vector3i((child.position/40.0).floor())
		key += "|%s|%s" % [child.material_override.get_instance_id() if child.material_override else 0,cell]
		if not groups.has(key): groups[key] = {"mesh":unit,"material":child.material_override,"nodes":[],"transforms":[]}
		groups[key]["nodes"].append(child)
		groups[key]["transforms"].append(child.transform * Transform3D(Basis.from_scale(dimensions),Vector3.ZERO))
	for group in groups.values():
		if group["nodes"].size() < 2: continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = group["mesh"]
		mm.instance_count = group["nodes"].size()
		var center: Vector3 = group["transforms"][0].origin
		for i in mm.instance_count:
			var xf: Transform3D = group["transforms"][i]
			xf.origin -= center
			mm.set_instance_transform(i,xf)
		var instance := MultiMeshInstance3D.new()
		instance.name = "StaticDetailBatch"
		instance.position = center
		instance.multimesh = mm
		instance.material_override = group["material"]
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.visibility_range_end = distance
		instance.visibility_range_end_margin = 8
		instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		parent.add_child(instance)
		for node in group["nodes"]:
			if not node.get_meta_list().is_empty():
				var marker := Marker3D.new()
				marker.transform = node.transform
				marker.visible = node.visible
				for key in node.get_meta_list(): marker.set_meta(key,node.get_meta(key))
				var original_name: String = node.name
				parent.remove_child(node)
				marker.name = original_name
				parent.add_child(marker)
			else: parent.remove_child(node)
			node.free()

static func environment(node: Node) -> void:
	# Explicit static-only paths. TerrainRocks is batched after PlanetB reads footprints.
	for path in ["Terrain/Rocks","Terrain/Hills","LaunchPad/Gantry"]:
		var decor := node.get_node_or_null(NodePath(path)) as Node3D
		if decor: batch(decor,[],900.0 if path.begins_with("Terrain") else 160.0)
	var pad := node.get_node_or_null("LaunchPad") as Node3D
	if pad: batch(pad,["PadTick"],60.0)

static func surroundings(parent: Node3D, origin: Vector3) -> void:
	var root := Node3D.new()
	root.name = "ServiceSurroundings"
	root.position = origin
	parent.add_child(root)
	# Cable tray, guard rail and alternating warning plates share unit box batches.
	for i in 12:
		root.add_child(Gfx.box(Vector3(.7,.04,.35),Color("#dfad48") if i%2 else Color("#333c43"),Vector3(i*.75-4.5,.04,-3)))
		root.add_child(Gfx.box(Vector3(.09,1,.09),Color("#687780"),Vector3(i*.75-4.5,.5,-3.6)))
		root.add_child(Gfx.box(Vector3(.7,.07,.12),Color("#687780"),Vector3(i*.75-4.5,1,-3.6)))
		root.add_child(Gfx.box(Vector3(.7,.08,.18),Color("#333c43"),Vector3(i*.75-4.5,.1,-2.5)))
	for x in [-5,5]:
		root.add_child(Gfx.box(Vector3(.12,3,.12),Color("#687780"),Vector3(x,1.5,-3.6)))
		root.add_child(Gfx.box(Vector3(.6,.08,.3),Color("#9cdeb1"),Vector3(x,3,-3.6),1.0))
	batch(root)
