extends SceneTree

var failures := 0
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func bounds(ship: Node3D) -> AABB:
	var result := [null]
	Actor._aabb(ship, Transform3D.IDENTITY, result)
	return result[0]

func count_gear(node: Node, prefix: String) -> int:
	var result := 1 if String(node.name).begins_with(prefix) else 0
	for child in node.get_children(): result += count_gear(child, prefix)
	return result

func run() -> void:
	var reference := ShipModel.full(Color.ORANGE)
	var ref_bounds := bounds(reference)
	var cases: Array[Dictionary] = []
	for family in ShipCatalog.FAMILIES:
		var choice := {}
		for slot in ShipCatalog.VARIANTS: choice[slot] = family
		cases.append(choice)
	var mixed := {}
	var index := 0
	for slot in ShipCatalog.VARIANTS:
		mixed[slot] = ShipCatalog.FAMILIES.keys()[index % 5]
		index += 1
	cases.append(mixed)
	for choice in cases:
		var ship := ShipModel.full(Color.ORANGE, choice)
		check(ship.name == "Kestrel", "retains Kestrel root")
		for slot in ShipCatalog.VARIANTS:
			var part := ship.get_node_or_null(NodePath(slot)) as Node3D
			check(part != null, "missing " + slot)
			if part == null: continue
			check(part.get_meta("ship_family", "") == choice[slot], "wrong family " + slot)
			var donor: Node3D = ShipModel.prefab(choice[slot]).instantiate()
			var expected := donor.get_node(NodePath(slot)) as Node3D
			check(part.transform == expected.transform, "transform changed " + slot)
			var greeble := 1 if part.has_node("GreebleHardware") else 0
			check(part.get_child_count() - greeble == expected.get_child_count(), "module geometry differs " + slot)
			for child in expected.get_children(): check(part.has_node(NodePath(child.name)), "missing geometry " + str(child.name))
			donor.free()
		check(count_gear(ship, "LandingLeg") == 4, "exactly four landing legs")
		check(count_gear(ship, "LandingFoot") == 4, "exactly four landing feet")
		var box := bounds(ship)
		for axis in 3:
			check(box.size[axis] / ref_bounds.size[axis] >= 0.80 and box.size[axis] / ref_bounds.size[axis] <= 1.20, "ship bounds outside limits")
		var fx := ShipModel.flame(8, ship)
		check(fx.get_child_count() == 2, "two engine flames")
		for i in 2:
			var id: String = ["port", "thruster"][i]
			var engine := ship.get_node(id) as Node3D
			var nozzle := engine.get_node_or_null("NozzleGlow") as Node3D
			check(nozzle != null, "nozzle exists " + id)
			check(fx.get_child(i).position.is_equal_approx(engine.transform * nozzle.position + Vector3(0, 0, .12)), "flame follows selected nozzle")
		fx.free()
		ship.free()
	reference.free()
	print("SHIP_ASSEMBLY_RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
