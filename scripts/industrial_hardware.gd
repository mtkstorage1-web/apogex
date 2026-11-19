## Shared, dimensioned aerospace hardware. +Y is the engine / tank axis.
extends RefCounted

static var _materials: Dictionary = {}

static func material(color: Color, metal := 0.55, rough := 0.38) -> ShaderMaterial:
	var key := "%s|%s|%s" % [color.to_html(), metal, rough]
	if _materials.has(key): return _materials[key]
	var m := preload("res://assets/materials/metal.tres").duplicate() as ShaderMaterial
	m.set_shader_parameter("panel_normal", ProcTex.metal_panel_normal())
	_materials[key] = m
	m.shader = preload("res://assets/shaders/industrial.gdshader")
	m.set_shader_parameter("paint", color)
	m.set_shader_parameter("metal", metal)
	m.set_shader_parameter("finish", rough)
	return m

static func part(parent: Node3D, mesh: Mesh, pos: Vector3, color: Color, metal := 0.55) -> MeshInstance3D:
	var mi := Gfx.mesh(mesh, material(color, metal), pos)
	parent.add_child(mi)
	return mi

static func cylinder(parent: Node3D, radius: float, height: float, pos: Vector3, color: Color) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = height
	m.radial_segments = 64
	return part(parent, m, pos, color)

## Revolved profile supports rounded ogives and a genuinely open engine bell.
static func lathe(parent: Node3D, profile: Array, color: Color) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in range(profile.size() - 1):
		for i in 64:
			var a := float(i) * TAU / 64.0
			var b := float(i + 1) * TAU / 64.0
			var p: Vector2 = profile[j]
			var q: Vector2 = profile[j + 1]
			var vertices := [Vector3(p.x*cos(a),p.y,p.x*sin(a)), Vector3(q.x*cos(a),q.y,q.x*sin(a)), Vector3(q.x*cos(b),q.y,q.x*sin(b)), Vector3(p.x*cos(b),p.y,p.x*sin(b))]
			for k in [0,1,2,0,2,3]:
				st.add_vertex(vertices[k])
	st.generate_normals()
	return part(parent, st.commit(), Vector3.ZERO, color)

static func booster(radius: float, height: float, serial := "01") -> Node3D:
	var root := Node3D.new()
	root.name = "FlightBooster" + serial
	var shell := Color("#dadbd4")
	var steel := Color("#6d777c")
	var dark := Color("#242b30")
	cylinder(root, radius, height, Vector3(0,height*0.5,0), shell)
	var nose: Array = []
	var nose_length := radius*2.7
	var ogive_radius := (radius*radius+nose_length*nose_length)/(2.0*radius)
	for i in 33:
		var y := float(i)/32.0*nose_length
		nose.append(Vector2(maxf(.005,sqrt(ogive_radius*ogive_radius-y*y)+radius-ogive_radius),height+y))
	lathe(root,nose,shell)
	for y in [0.15, height*.18, height*.5, height*.82, height-.12]:
		cylinder(root,radius*1.012,.065,Vector3(0,y,0),steel)
	for y in [height*.12,height*.86]:
		cylinder(root,radius*1.016,.22,Vector3(0,y,0),dark)
		for i in 16:
			var a := i*TAU/16.0
			var bolt := Gfx.sphere(radius*.025,steel,Vector3(cos(a)*radius*1.025,y,sin(a)*radius*1.025),0,8)
			root.add_child(bolt)
	# Sealed service hatches and exposed attachment hardpoints.
	for y in [height*.28,height*.73]:
		var seal := Gfx.box(Vector3(radius*.55,.78,.055),dark,Vector3(0,y,radius*.994))
		root.add_child(seal)
		var panel := Gfx.box(Vector3(radius*.48,.68,.065),shell,Vector3(0,y,radius*1.006))
		panel.material_override = material(shell,.3,.48)
		root.add_child(panel)
		for x in [-1,1]:
			for dy in [-.26,.26]:
				root.add_child(Gfx.sphere(.025,steel,Vector3(x*radius*.19,y+dy,radius*1.04),0,8))
	for y in [height*.22,height*.76]:
		for x in [-1,1]:
			root.add_child(Gfx.box(Vector3(.18,.35,.28),steel,Vector3(x*radius,y,0)))
	# External feedline with stand-off clamps.
	cylinder(root,radius*.055,height*.77,Vector3(radius*1.035,height*.48,0),steel)
	for y in [height*.16,height*.35,height*.55,height*.75]:
		root.add_child(Gfx.box(Vector3(radius*.22,.09,.21),dark,Vector3(radius*1.03,y,0)))
	cylinder(root,radius*1.025,.65,Vector3(0,.32,0),dark)
	# Bell: throat, expanding outer wall, lip, inner wall, recessed throat.
	lathe(root,[Vector2(radius*.28,.1),Vector2(radius*.30,-.25),Vector2(radius*.42,-.65),Vector2(radius*.64,-1.16),Vector2(radius*.79,-1.65),Vector2(radius*.73,-1.65),Vector2(radius*.58,-1.12),Vector2(radius*.37,-.61),Vector2(radius*.24,-.22)],Color("#424b53"))
	for j in 10:
		var k := float(j)/9.0
		var rib := TorusMesh.new()
		rib.inner_radius = radius*lerpf(.31,.77,k)
		rib.outer_radius = rib.inner_radius + .025
		rib.rings = 48
		rib.ring_segments = 6
		part(root,rib,Vector3(0,lerpf(-.3,-1.58,k),0),steel)
	for side in [-1,1]:
		var housing := Gfx.box(Vector3(radius*.28,height*.22,radius*.22),dark,Vector3(side*radius*.96,height*.18,0))
		root.add_child(housing)
	var text := Label3D.new()
	text.text = "T− / " + serial + "\nFLIGHT SYSTEMS"
	text.font_size = 48
	text.pixel_size = radius*.003
	text.position = Vector3(0,height*.66,radius*1.005)
	text.modulate = dark
	text.outline_size = 0
	root.add_child(text)
	preload("res://scripts/model_detail.gd").batch(root, [], 60.0, 1.5)
	return root

static func link(color: Color, radius: float, length := 15.0) -> Node3D:
	var root := Node3D.new()
	root.name = "ServoLink"
	for side in [-1,1]:
		var beam := Gfx.box(Vector3(radius*.5,radius*.95,length*.88),color,Vector3(side*radius*.65,0,-length*.5))
		beam.material_override = material(color,.42,.44)
		root.add_child(beam)
		var rail := cylinder(root,radius*.13,length*.70,Vector3(side*radius*.66,radius*.65,-length*.48),Color("#929da3"))
		rail.rotation.x = PI/2
		var sleeve := cylinder(root,radius*.24,length*.34,Vector3(side*radius*.66,radius*.65,-length*.68),Color("#424c54"))
		sleeve.rotation.x = PI/2
	for z in [-length*.12,-length*.88]:
		root.add_child(Gfx.box(Vector3(radius*1.9,radius*1.2,radius*.6),Color("#30383e"),Vector3(0,0,z)))
	# Repeated protective hose clamps and service studs move with the link.
	for z in [-length*.2,-length*.4,-length*.6,-length*.8]:
		root.add_child(Gfx.box(Vector3(radius*1.7,.07,.10),Color("#727f86"),Vector3(0,-radius*.65,z)))
		for side in [-1,1]:
			root.add_child(Gfx.sphere(.045,Color("#d3b367"),Vector3(side*radius*.65,radius*.5,z),0,6))
	# Protected hydraulic hoses follow the link; never stretch across its joints.
	for x in [-.22,.22]:
		var hose := cylinder(root,radius*.12,length*.78,Vector3(x,-radius*.6,-length*.5),Color("#171e23"))
		hose.rotation.x = PI/2
	preload("res://scripts/model_detail.gd").batch(root, [], 60.0, 1.5)
	return root

static func joint(radius: float) -> Node3D:
	var root := Node3D.new()
	for side in [-1,1]:
		var hub := cylinder(root,radius,radius*.35,Vector3(side*radius*.65,0,0),Color("#343e46"))
		hub.rotation.z = PI/2
		var cap := cylinder(root,radius*.7,radius*.08,Vector3(side*radius*.86,0,0),Color("#abb5b9"))
		cap.rotation.z = PI/2
		for i in 8:
			var a := i*TAU/8.0
			var bolt := cylinder(root,radius*.055,radius*.1,Vector3(side*radius*.92,cos(a)*radius*.51,sin(a)*radius*.51),Color("#414a51"))
			bolt.rotation.z = PI/2
	preload("res://scripts/model_detail.gd").batch(root, [], 60.0, 1.5)
	return root

static func tool() -> Node3D:
	var root := joint(.52)
	root.name = "TorqueAndWeldHead"
	cylinder(root,.23,.9,Vector3(0,-.38,0),Color("#5c656d"))
	cylinder(root,.10,.35,Vector3(0,-.95,0),Color("#c4a17b"))
	for side in [-1,1]:
		root.add_child(Gfx.box(Vector3(.12,.65,.18),Color("#313c43"),Vector3(side*.38,-.5,0)))
	preload("res://scripts/model_detail.gd").batch(root, [], 60.0, 1.5)
	return root
