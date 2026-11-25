## Bakes every Planet A launchpad structure into scenes/levels/PlanetAEnvironment.tscn so it can be
## selected and dragged in the Godot editor. scripts/planet_a.gd then binds to those nodes at runtime.
##
##   Godot --headless --path . -s tools/bake_planet_a_scene.gd            # first bake (refuses to overwrite)
##   Godot --headless --path . -s tools/bake_planet_a_scene.gd -- --force  # discard the generated groups and rebake
##
## The generated groups are rebuilt by the SAME _build_* functions planet_a.gd uses as a runtime
## fallback, so there is a single source of truth for the geometry.
extends SceneTree

const SCENE_PATH := "res://scenes/levels/PlanetAEnvironment.tscn"
# Top-level groups created by the bake. Hand-made groups (Terrain, LaunchPad, PartRacks,
# SystemCheckConsoles, ScienceDelivery, RivalLandingPads, CollisionFootprints) are left untouched.
const GENERATED := ["Buildings", "Cranes", "BoardingRig", "Stations", "Infrastructure", "Environment", "SpaceportCampus", "EmpireDistricts"]


func _initialize() -> void:
	call_deferred("_bake")


func _bake() -> void:
	var force := OS.get_cmdline_user_args().has("--force")
	var packed := load(SCENE_PATH) as PackedScene
	var root := packed.instantiate() as Node3D
	var existing: Array[String] = []
	for group_name in GENERATED:
		if root.has_node(group_name):
			existing.append(group_name)
	if not existing.is_empty():
		if not force:
			push_error("Already baked (%s). Re-baking discards your editor changes; pass `-- --force` to do it anyway." % ", ".join(existing))
			root.free()
			quit(1)
			return
		for group_name in existing:
			var old := root.get_node(group_name)
			root.remove_child(old)
			old.free()
	var builder := PlanetA.new()
	builder.bake_structures(root)
	builder.bake_campus(root)
	EmpireWorldLayer.bake_home_districts(root)
	var count := 0
	for group_name in GENERATED:
		var group := root.get_node_or_null(group_name)
		if group != null:
			group.owner = root
			count += 1 + _own(group, root)
	var out := PackedScene.new()
	var err := out.pack(root)
	if err != OK:
		push_error("pack failed: %d" % err)
		quit(1)
		return
	err = ResourceSaver.save(out, SCENE_PATH)
	if err != OK:
		push_error("save failed: %d" % err)
		quit(1)
		return
	print("Baked %d editable nodes into %s" % [count, SCENE_PATH])
	_print_tree(root, 0, 3)
	builder.free()
	root.free()
	quit(0)


# Gives auto-generated names a readable form and makes every node an editor-visible
# part of the scene (owner = root). Returns the number of nodes owned.
func _own(node: Node, root: Node) -> int:
	var total := 0
	for child in node.get_children():
		if String(child.name).contains("@"):
			var base := String(child.get_class()).replace("3D", "").replace("Instance", "")
			child.name = base
		child.owner = root
		total += 1
		# Instanced .glb/.tscn sub-scenes stay clean references: never claim their internal nodes.
		if child.scene_file_path == "":
			total += _own(child, root)
	return total


func _print_tree(node: Node, depth: int, max_depth: int) -> void:
	if depth > max_depth:
		return
	var generated := depth == 0
	for child in node.get_children():
		if depth == 0 and not GENERATED.has(String(child.name)):
			continue
		print("  ".repeat(depth) + "%s (%s, %d children)" % [child.name, child.get_class(), child.get_child_count()])
		_print_tree(child, depth + 1, max_depth)
	if generated:
		return
