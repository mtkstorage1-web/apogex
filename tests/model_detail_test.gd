extends SceneTree
const Detail = preload("res://scripts/model_detail.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func count(node: Node, multi := false) -> int:
	var total := int(node is MultiMeshInstance3D) if multi else int(node is MeshInstance3D)
	for child in node.get_children(): total += count(child,multi)
	return total
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var baseline: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/phase-3-baseline.json"))
	var report := {}
	var text := FileAccess.get_file_as_string("res://scenes/prefabs/Kestrel.tscn")
	var material_count := text.count('[sub_resource type="StandardMaterial3D"')
	check(material_count < int(baseline["scenes/prefabs/Kestrel.tscn"]["materials_before"])/2, "Kestrel materials must be deduplicated")
	print("Kestrel StandardMaterial3D: ",baseline["scenes/prefabs/Kestrel.tscn"]["materials_before"]," -> ",material_count)
	for family in ShipCatalog.FAMILIES:
		var loadout := {}
		for slot in ShipCatalog.VARIANTS: loadout[slot] = family
		var ship := ShipModel.full(Color.ORANGE,loadout)
		var path: String = ShipCatalog.FAMILIES[family]["prefab_path"].trim_prefix("res://")
		var before := int(baseline[path]["meshes_before"])
		var after := count(ship)
		check(after <= before*1.25, family+" mesh budget")
		for slot in ShipCatalog.VARIANTS:
			check(ship.get_node(NodePath(slot)).has_node("ServiceDetail"),family+" slot detail "+slot)
		report[family] = {"before":before,"after":after}
		ship.free()
	for level in ["PlanetA","PlanetB","Workshop","Universe","Flight","OrbitShipInterior","FrontierArena"]:
		var file: String = level+"Environment" if level in ["PlanetA","PlanetB","Workshop","Universe","Flight"] else level
		var path: String = "scenes/levels/"+file+".tscn"
		var scene: Node3D = load("res://"+path).instantiate()
		var before := count(scene)
		root.add_child(scene)
		if level == "PlanetB": Detail.batch(scene.get_node("Terrain/TerrainRocks"),[],900)
		var batches := count(scene,true)
		if level in ["PlanetA","PlanetB","Workshop"]: check(batches > 0,level+" rock/prop MultiMesh")
		report[level] = {"before":before,"after":count(scene),"multimeshes":batches}
		scene.free()
	var props := Node3D.new()
	Detail.surroundings(props,Vector3.ZERO)
	check(count(props,true)>0,"prop instancing")
	props.free()
	var footprints := Node3D.new()
	for i in 3:
		var rock := Gfx.sphere(1,Color.GRAY,Vector3(i*2,0,0))
		rock.name = "Cover"+str(i)
		rock.set_meta("gameplay_radius",1.0)
		footprints.add_child(rock)
	Detail.batch(footprints)
	check(count(footprints,true)==1,"repeated rock instances share a batch")
	for i in 3:
		var marker := footprints.get_node("Cover"+str(i))
		check(marker is Marker3D and marker.get_meta("gameplay_radius")==1.0,"retain collision/state marker")
	footprints.free()
	var preview := ShipModel.full(Color.WHITE)
	preload("res://scripts/shop_preview.gd")._preview_detail(preview)
	check(preview.get_node("keel/ServiceDetail").visibility_range_end==0,"preview detail has no distance cutoff")
	preview.free()
	var output := FileAccess.open("res://docs/phase-3-counts.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"  ")+"\n")
	output.close()
	print(JSON.stringify(report))
	print("model_detail_test: %d failures" % failures)
	quit(1 if failures else 0)
