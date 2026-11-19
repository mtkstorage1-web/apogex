## Run: godot --headless --path . -s tools/check_ship_families.gd
## AABB dimensions are checked per axis, not just volume. Kestrel's root-level
## landing gear is attributed to its keel for the equivalent assembled-keel check.
extends SceneTree
const IDS := ["keel", "port", "bridge", "reactor", "battery", "coolant", "cargo", "scrubber", "stores", "engine", "antenna", "thruster"]
const FAMILIES := ["lancer", "hauler", "halo", "bulwark"]
var failures := 0
var checks := 0

func require(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	var reference: Node3D = load("res://scenes/prefabs/Kestrel.tscn").instantiate()
	for id in IDS: require(reference.get_node_or_null(id) is Node3D, "Kestrel missing " + id)
	for family in FAMILIES:
		var path := "res://scenes/prefabs/ships/%s.tscn" % family
		var resource := load(path) as PackedScene
		require(resource != null, "Cannot load " + path)
		if not resource: continue
		var ship: Node3D = resource.instantiate()
		require(ship.get_child_count() == 12, family + " must have exactly 12 root modules")
		var meshes := 0
		for id in IDS:
			var n := ship.get_node_or_null(id) as Node3D
			require(n != null, family + " missing " + id)
			if not n: continue
			require(n.transform == reference.get_node(id).transform, family + "/" + id + " transform differs")
			meshes += validate(n, ship)
			require(mesh_count(n) >= 8, family + "/" + id + " needs 8 meshes")
			require(n.get_node_or_null("MountFlange") is MeshInstance3D, family + "/" + id + " needs mount flange")
			var ref_box := bounds(reference.get_node(id), true)
			var box := bounds(n, true)
			limits(box, ref_box, .25, family + "/" + id + " exterior")
			if id == "keel":
				var ref_gear := ref_box
				for c in reference.get_children():
					if String(c.name).begins_with("Landing") and c is MeshInstance3D:
						ref_gear = ref_gear.merge(reference.get_node(id).transform.affine_inverse() * c.transform * c.get_aabb())
				limits(bounds(n), ref_gear, .25, family + "/keel including landing gear")
				for suffix in ["00", "01", "10", "11"]:
					require(n.has_node("LandingLeg" + suffix) and n.has_node("LandingFoot" + suffix), family + " missing keel gear " + suffix)
		for id in ["port", "thruster"]:
			var glow := ship.get_node_or_null(id + "/NozzleGlow") as Node3D
			require(glow != null, family + "/" + id + " NozzleGlow missing")
			if glow:
				require(glow.position.z > bounds(ship.get_node(id)).end.z - 1.0, family + " nozzle marker must be at aft tip")
		limits(bounds(ship), bounds(reference), .15, family + " overall")
		print("%s: %d meshes; overall %s; reference %s" % [family, meshes, bounds(ship).size, bounds(reference).size])
		ship.free()
	reference.free()
	print("Ship families: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func limits(actual: AABB, expected: AABB, tolerance: float, label: String) -> void:
	for axis in 3:
		var ratio := actual.size[axis] / expected.size[axis]
		require(ratio >= 1.0 - tolerance - .001 and ratio <= 1.0 + tolerance + .001, "%s axis %d ratio %.4f outside +/-%.0f%%" % [label, axis, ratio, tolerance * 100])

func mesh_count(n: Node) -> int:
	var count := 1 if n is MeshInstance3D else 0
	for c in n.get_children(): count += mesh_count(c)
	return count

func validate(n: Node, ship: Node) -> int:
	var count := 0
	for c in n.get_children():
		require(c is Node3D, "Non-editable node type " + str(c.name))
		require(c.owner == ship, "Unsaved owner " + str(c.name))
		if c is MeshInstance3D:
			count += 1
			require(c.mesh is BoxMesh or c.mesh is CylinderMesh or c.mesh is SphereMesh or c.mesh is PrismMesh or c.mesh is TorusMesh or c.mesh is CapsuleMesh, "Non-native mesh " + str(c.name))
			require(c.material_override is StandardMaterial3D, "Unexpected material " + str(c.name))
		count += validate(c, ship)
	return count

func bounds(n: Node3D, skip_gear := false) -> AABB:
	var boxes: Array[AABB] = []
	collect(n, Transform3D.IDENTITY, boxes, skip_gear)
	var result := boxes[0]
	for b in boxes: result = result.merge(b)
	return result

func collect(n: Node3D, t: Transform3D, boxes: Array[AABB], skip_gear: bool) -> void:
	if skip_gear and String(n.name).begins_with("Landing"): return
	if n is MeshInstance3D and n.mesh: boxes.append(t * n.get_aabb())
	for c in n.get_children():
		if c is Node3D: collect(c, t * c.transform, boxes, skip_gear)
