extends SceneTree

const ENVIRONMENT_PATH := "res://scenes/levels/PlanetAEnvironment.tscn"
const EmpireLayer = preload("res://scripts/empire_world_layer.gd")
const Rules = preload("res://scripts/empire_sim.gd")
const CAMPUS_NODES := [
	"AlliedTower_NW", "AlliedTower_NE", "AlliedTower_N", "TankFarm", "FleetMotorPool",
	"FleetMotorPool/ParkedDropship", "FleetMotorPool/ParkedRover",
	"WestAvenue", "WestTrunkRoad", "EastAvenue", "EastTrunkRoad",
]
const SLOT_IDS := ["defense_turrets", "shield_gen", "refinery", "radar", "hangar", "vault"]
const DISTRICTS := "EmpireDistricts"
const REFINERY := DISTRICTS + "/refinery"
const RAID_ZONES := DISTRICTS + "/RaidLandingZones"
const POSITION_TOLERANCE := 0.05

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene := load(ENVIRONMENT_PATH) as PackedScene
	if _check(scene != null, "Planet A environment loads as a PackedScene"):
		var editable_env := scene.instantiate() as Node3D
		if _check(editable_env != null, "Planet A environment has a Node3D root"):
			_check_scene_ownership(editable_env)
			editable_env.free()
			if failures == 0:
				_check_main_binding()
				await _check_repositioning(scene)
	print("PLANET_A_EDITABLE_SCENE_BINDING_RESULT: %d failures" % failures)
	quit(int(failures > 0))


func _check_scene_ownership(editable_env: Node3D) -> void:
	_check_owned(editable_env, "SpaceportCampus")
	for path: String in CAMPUS_NODES:
		_check_owned(editable_env, "SpaceportCampus/" + path)
	_check_owned(editable_env, DISTRICTS)
	for id: String in SLOT_IDS:
		var slot_path := DISTRICTS + "/" + id
		_check_owned(editable_env, slot_path)
		_check_owned(editable_env, slot_path + "/FoundationPad")
		_check_owned(editable_env, slot_path + "/Terminal")
	_check_owned(editable_env, RAID_ZONES)
	for index in 4:
		_check_owned(editable_env, RAID_ZONES + "/RaidZone%d" % index)


func _check_owned(editable_env: Node3D, path: String) -> void:
	var node := editable_env.get_node_or_null(path) as Node3D
	_check(node != null and node.owner == editable_env, "%s is owned by PlanetAEnvironment" % path)


func _check_main_binding() -> void:
	var previous_mode := LobbyPages.play_mode
	var settings := "user://planet-a-editable-binding-%d.cfg" % OS.get_process_id()
	var game: Node = preload("res://main.tscn").instantiate()
	game.settings_path = settings
	root.add_child(game)
	game.set_process(false)
	LobbyPages.play_mode = "ranked"
	game.opts["length"] = "standard"
	game.opts["seed"] = 6184
	game.start_match()
	var home: PlanetA = game.world_a
	if _check(home != null and home.empire_layer != null, "Main starts Planet A with an Empire layer"):
		var campus := home.editable_root.get_node_or_null("SpaceportCampus") as Node3D
		_check(campus != null and home.spaceport_perimeter == campus,
			"Planet A uses the baked SpaceportCampus instance")
		_check(game.find_children("SpaceportCampus*", "Node3D", true, false).size() == 1
			and game.find_children("SpaceportPerimeter*", "Node3D", true, false).is_empty(),
			"Main has one campus and no procedural SpaceportPerimeter")
		var refinery := home.editable_root.get_node_or_null(REFINERY)
		var slot: Dictionary = home.empire_layer.slots.get("refinery", {})
		_check(refinery != null and slot.get("anchor") == refinery,
			"Main passes the editable environment to the Empire layer")
	game.free()
	LobbyPages.play_mode = previous_mode
	if FileAccess.file_exists(settings):
		DirAccess.remove_absolute(settings)


func _check_repositioning(scene: PackedScene) -> void:
	var fixture := Node3D.new()
	root.add_child(fixture)
	var editable_env := scene.instantiate() as Node3D
	fixture.add_child(editable_env)
	var refinery := editable_env.get_node(REFINERY) as Node3D
	var terminal := refinery.get_node("Terminal") as Node3D
	var raid_zone := editable_env.get_node(RAID_ZONES + "/RaidZone0") as Node3D
	var original_terminal := terminal.global_position
	refinery.position += Vector3(-12, 0, 8)
	raid_zone.position += Vector3(-5, 0, 6)
	var moved_refinery := refinery.global_position
	var moved_terminal := terminal.global_position
	var moved_landing := raid_zone.global_position

	var empire := Rules.new()
	empire.setup(6184)
	var cb := func(type: String, payload: Dictionary) -> Dictionary:
		if type != "build_or_upgrade":
			return {"ok": false, "reason": "unexpected_action"}
		return empire.build_or_upgrade(payload["alliance"], payload["slot_id"], "orange")
	var layer := EmpireLayer.new()
	layer.setup(empire, "planet_a", true, "orange", cb, editable_env)
	fixture.add_child(layer)
	var slot: Dictionary = layer.slots.get("refinery", {})
	var anchor := slot.get("anchor") as Node3D
	_check(anchor == refinery and anchor.global_position.distance_to(moved_refinery) <= POSITION_TOLERANCE,
		"Empire layer binds to the repositioned refinery anchor")
	var nearest := layer.nearest_interactable(moved_terminal, POSITION_TOLERANCE)
	var reported_position: Vector3 = nearest.get("position", Vector3.INF)
	_check(slot.get("terminal") == terminal and nearest.get("slot_id") == "refinery"
		and reported_position.distance_to(moved_terminal) <= POSITION_TOLERANCE
		and layer.nearest_interactable(original_terminal, POSITION_TOLERANCE).is_empty(),
		"The refinery interaction follows the moved editor terminal")
	var districts := editable_env.get_node(DISTRICTS)
	_check(districts.find_children("FoundationPad*", "Node3D", true, false).size() == SLOT_IDS.size()
		and districts.find_children("Terminal*", "Node3D", true, false).size() == SLOT_IDS.size()
		and layer.find_children("FoundationPad*", "Node3D", true, false).is_empty()
		and layer.find_children("Terminal*", "Node3D", true, false).is_empty()
		and layer.find_children("*_foundation*", "Node3D", true, false).is_empty(),
		"Setup reuses the six scene foundations and terminals without procedural duplicates")

	var result := layer.interact(moved_terminal, false)
	if _check(result.get("ok", false) and empire.structures["planet_a"]["refinery"]["tier"] == 1,
			"Interacting at the edited terminal builds refinery Tier 1"):
		# The build animation raises the model to its final position over 0.55 seconds.
		await create_timer(0.65).timeout
		var model := slot.get("model") as Node3D
		_check(model != null and model.name == &"RefineryTowerCluster"
			and not model.find_children("*", "MeshInstance3D", true, false).is_empty()
			and model.global_position.distance_to(moved_refinery) <= POSITION_TOLERANCE,
			"The Tier 1 Blender refinery model settles on the edited foundation")

	var invader: String = Rules.ALLIANCE_SQUADS["planet_b"][0]
	empire.act_number = 2
	empire._set_phase(empire.squads[invader], "raid", "planet_a", 75.0)
	layer.tick_raid(0.05, false)
	var raid: Dictionary = layer.raid_groups.get(invader, {})
	var dropship := raid.get("dropship") as Node3D
	_check(dropship != null and dropship.global_position.distance_to(moved_landing) <= POSITION_TOLERANCE,
		"The first live raid dropship spawns at the moved RaidZone0 marker")
	fixture.free()


func _check(condition: bool, message: String) -> bool:
	if not condition:
		failures += 1
		printerr("FAIL " + message)
	return condition
