## Offline authoring tool: detail is saved once, never rebuilt per frame.
extends SceneTree
const Hardware = preload("res://scripts/industrial_hardware.gd")
func _initialize() -> void:
	var service_material := Hardware.material(Color("#687780"),.65,.45).duplicate() as ShaderMaterial
	service_material.set_shader_parameter("panel_normal",null)
	for family in ShipCatalog.FAMILIES:
		var path: String = ShipCatalog.FAMILIES[family]["prefab_path"]
		var ship: Node3D = load(path).instantiate()
		for slot in ShipCatalog.VARIANTS:
			var part: Node3D = ship.get_node(NodePath(slot))
			for id in ["ServiceDetail","SlotAccent"]:
				var old := part.get_node_or_null(NodePath(id))
				if old:
					part.remove_child(old)
					old.free()
			var boxes := [null]
			Actor._aabb(part, part.transform.affine_inverse(), boxes)
			var b: AABB = boxes[0]
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			# Raised service rails follow the part envelope; all strips merge into one mesh.
			for side in [-1, 1]:
				append_box(st, Vector3(.045,.045,b.size.z*.65), b.get_center()+Vector3(side*b.size.x*.32,b.size.y*.5+.025,0))
			if slot == "coolant":
				for i in 8:
					append_box(st,Vector3(b.size.x*.85,.12,.035),Vector3(b.get_center().x,b.end.y+.06,b.position.z+b.size.z*(.15+i*.1)))
			if slot in ["cargo","stores","scrubber"]:
				for z in [-1,1]: append_box(st,Vector3(b.size.x*.7,.07,.06),b.get_center()+Vector3(0,b.size.y*.5+.04,z*b.size.z*.3))
			if slot in ["bridge","antenna"]:
				append_box(st,Vector3(.06,.45,.06),b.get_center()+Vector3(0,b.size.y*.5+.225,0))
			if slot == "bridge":
				var dish := CylinderMesh.new()
				dish.bottom_radius = .2
				dish.top_radius = .08
				dish.height = .08
				dish.radial_segments = 12
				st.append_from(dish,0,Transform3D(Basis(Vector3.RIGHT,-.45),b.get_center()+Vector3(0,b.size.y*.5+.48,0)))
			if slot == "keel":
				var gear_parent: Node3D = ship if family == "kestrel" else part
				for foot in gear_parent.get_children():
					if str(foot.name).begins_with("LandingFoot") and foot is MeshInstance3D:
						var xf: Transform3D = part.transform.affine_inverse()*foot.transform if family == "kestrel" else foot.transform
						for offset in [-.35,0,.35]: append_box(st,Vector3(.05,.025,.8),xf*Vector3(offset,.12,0))
				for side in [-1,1]: append_box(st,Vector3(.16,.08,b.size.z*.38),b.get_center()+Vector3(side*b.size.x*.48,0,0))
			var mi := Gfx.mesh(st.commit(),service_material,Vector3.ZERO,false)
			mi.name = "ServiceDetail"
			mi.visibility_range_end = 60
			mi.visibility_range_end_margin = 8
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			part.add_child(mi)
			mi.owner = ship
			# One merged emissive mesh per slot, including a recessed engine core.
			var glow := SurfaceTool.new()
			glow.begin(Mesh.PRIMITIVE_TRIANGLES)
			append_box(glow,Vector3(b.size.x*.42,.025,.045),b.get_center()+Vector3(0,b.size.y*.5+.055,-b.size.z*.2))
			if slot in ["port","thruster"]:
				var nozzle: Node3D = part.get_node("NozzleGlow")
				var ring := TorusMesh.new()
				ring.inner_radius = .30
				ring.outer_radius = .38
				ring.rings = 16
				ring.ring_segments = 4
				glow.append_from(ring,0,Transform3D(Basis(Vector3.RIGHT,PI/2),nozzle.position))
			var accent := Gfx.mesh(glow.commit(),Gfx.mat(Color.from_hsv(float(ShipCatalog.VARIANTS.keys().find(slot))/12.0,.5,1.0),.5,1.2),Vector3.ZERO,false)
			accent.name = "SlotAccent"
			accent.visibility_range_end = 60
			part.add_child(accent)
			accent.owner = ship
		var packed := PackedScene.new()
		packed.pack(ship)
		ResourceSaver.save(packed,path)
		ship.free()
	quit()
func append_box(st: SurfaceTool, size: Vector3, pos: Vector3) -> void:
	var box := BoxMesh.new()
	box.size = size
	st.append_from(box,0,Transform3D(Basis.IDENTITY,pos))
