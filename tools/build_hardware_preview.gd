extends SceneTree
const Hardware = preload("res://scripts/industrial_hardware.gd")

func _initialize() -> void:
	call_deferred("build")

func own(node: Node, root: Node) -> void:
	for child in node.get_children():
		child.owner = root
		own(child,root)

func save(root: Node, path: String) -> void:
	own(root,root)
	var packed := PackedScene.new()
	assert(packed.pack(root) == OK)
	assert(ResourceSaver.save(packed,path) == OK)

func build() -> void:
	var stage := Node3D.new()
	stage.name = "AerospaceHardwarePreview"
	root.add_child(stage)
	var booster := Hardware.booster(1.5,16.0,"B01")
	booster.position = Vector3(5,2,0)
	stage.add_child(booster)
	save(booster,"res://scenes/prefabs/FlightBooster.tscn")
	var machine := Node3D.new()
	machine.name = "IndustrialAssemblyRobot"
	stage.add_child(machine)
	Hardware.cylinder(machine,2.0,.4,Vector3(-5,.2,0),Color("#313b42"))
	Hardware.cylinder(machine,1.1,3.0,Vector3(-5,1.9,0),Color("#63727c"))
	var a := Vector3(-5,3.5,0)
	var b := Vector3(-7,9,-1)
	var c := Vector3(-1,7,0)
	for pair in [[a,b,Color("#ba7c40")],[b,c,Color("#c4c8c2")]]:
		var start: Vector3 = pair[0]
		var end: Vector3 = pair[1]
		var link := Hardware.link(pair[2],.65)
		machine.add_child(link)
		link.look_at_from_position(start,end)
		link.scale.z = start.distance_to(end)/15.0
	for point in [a,b]:
		var joint := Hardware.joint(.8)
		joint.position = point
		machine.add_child(joint)
	var tool := Hardware.tool()
	tool.position = c
	machine.add_child(tool)
	save(machine,"res://scenes/prefabs/IndustrialAssemblyRobot.tscn")
	stage.add_child(Gfx.box(Vector3(100,.25,100),Color("#303942"),Vector3(0,-.2,0)))
	stage.add_child(Gfx.environment(Color("#263e55"),Color("#a5b4be"),Color("#343d45"),.55))
	stage.add_child(Gfx.sun(Vector3(-40,-35,0),Color(1,.91,.78),2.0))
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-25,140,0)
	fill.light_color = Color(.65,.8,1)
	fill.light_energy = .7
	stage.add_child(fill)
	var camera := Camera3D.new()
	camera.position = Vector3(27,16,34)
	camera.fov = 42
	stage.add_child(camera)
	camera.look_at(Vector3(0,10,0))
	camera.current = true
	save(stage,"res://scenes/AerospaceHardwarePreview.tscn")
	print("Hardware scenes packed successfully")
	quit()
