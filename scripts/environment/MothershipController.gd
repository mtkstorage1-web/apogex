class_name MothershipController
extends Node3D
## One 850 x 320 x 190 m APOGEX mothership (HELION or CINDER): exterior hull (Blender GLB when imported,
## detailed procedural fallback otherwise), hull collision with the recessed Main Hangar mouth left open,
## budgeted exterior lighting, and the embedded 7-room MothershipInterior.
## Ship-local axes: +Z = bow (hangar mouth + bridge windows face Vesper-9), +Y = deck up, X = width.

const Battery = preload("res://scripts/gameplay/DefenseTurret.gd")
const K = preload("res://scripts/environment/ModularKitBuilder.gd")
const InteriorScript = preload("res://scripts/environment/MothershipInterior.gd")

const HULL_DIR := "res://assets/models/apogex/mothership/"
const EXTERIOR := Vector3(320.0, 190.0, 850.0)   # X width, Y height, Z length
const LIGHT_DISTANCE := 900.0

@export var faction: String = "helion"

var interior: Node3D
var hull_visual: Node3D
var exterior_lights: Node3D
var hull_collision: StaticBody3D
var hull_source: String = "procedural"
var planet_origin: Vector3 = Vector3.ZERO
var planet_basis: Basis = Basis.IDENTITY
var camera_inside: bool = false
var built: bool = false

var defense_batteries: Array[StaticBody3D] = []

var _p: Dictionary = {}
var _strobes: Array = []
var _glows: Array = []
var _time: float = 0.0


func _ready() -> void:
	if not built:
		build()


# ---------------------------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------------------------

func get_exterior_dimensions() -> Vector3:
	return EXTERIOR


func get_interior() -> Node3D:
	return interior


func get_local_up_direction() -> Vector3:
	return planet_basis.y.normalized()


func planet_to_local(planet_pos: Vector3) -> Vector3:
	return planet_basis.inverse() * (planet_pos - planet_origin)


func local_to_planet(local_pos: Vector3) -> Vector3:
	return planet_origin + planet_basis * local_pos


func contains_planet_point_in_interior(planet_pos: Vector3) -> bool:
	if interior == null:
		return false
	return (interior as Node).call("get_interior_aabb").has_point(planet_to_local(planet_pos))


func contains_render_point(render_pos: Vector3) -> bool:
	if interior == null:
		return false
	return (interior as Node).call("get_interior_aabb").has_point(to_local(render_pos))


func place(origin: Vector3, basis_in: Basis, render_origin: Vector3) -> void:
	planet_origin = origin
	planet_basis = basis_in.orthonormalized()
	transform = Transform3D(planet_basis, planet_origin - render_origin)


func apply_origin(render_origin: Vector3) -> void:
	position = planet_origin - render_origin


func set_hull_visible(v: bool) -> void:
	if hull_visual != null:
		hull_visual.visible = v


## Merged mesh bounds of the exterior hull in ship-local space.
func get_hull_visual_aabb() -> AABB:
	var box := AABB()
	var first: bool = true
	var stack: Array = [[hull_visual, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var item: Array = stack.pop_back()
		var n: Node = item[0]
		var xf: Transform3D = item[1]
		if n is Node3D and n != hull_visual:
			xf = xf * (n as Node3D).transform
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var a: AABB = xf * (n as MeshInstance3D).mesh.get_aabb()
			box = a if first else box.merge(a)
			first = false
		for c in n.get_children():
			stack.append([c, xf])
	return box


func get_diagnostics() -> Dictionary:
	var d: Dictionary = {"faction": faction, "hull_source": hull_source, "camera_inside": camera_inside, "exterior": EXTERIOR}
	if interior != null:
		d.merge((interior as Node).call("get_diagnostics"))
	return d


func setup_defense(context: Node) -> void:
	if not defense_batteries.is_empty():
		return
	for side in [-1.0, 1.0]:
		var battery := Battery.new()
		battery.name = "DefenseBatteryPort" if side < 0.0 else "DefenseBatteryStarboard"
		battery.faction = faction
		battery.world = context
		battery.capital_battery = true
		battery.ship_hull = hull_collision
		battery.position = Vector3(side * 118.0, 72.1, -118.0)
		hull_visual.add_child(battery)
		defense_batteries.append(battery)


func tick_defense(delta: float) -> void:
	for battery in defense_batteries:
		battery.tick(delta)


func tick(delta: float) -> void:
	_time += delta
	if interior != null:
		(interior as Node).call("tick", delta)
	for s in _strobes:
		var m: StandardMaterial3D = s["mat"]
		var ph: float = fmod(_time * float(s["rate"]) + float(s["phase"]), 1.0)
		m.emission_energy_multiplier = 6.0 if ph < float(s["duty"]) else 0.25
	for g in _glows:
		var gm: StandardMaterial3D = g["mat"]
		gm.emission_energy_multiplier = float(g["base"]) * (0.85 + 0.15 * sin(_time * 2.0 + float(g["phase"])))
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null:
		var lp: Vector3 = to_local(cam.global_position)
		var inside: bool = interior != null and (interior as Node).call("get_interior_aabb").has_point(lp)
		camera_inside = inside
		set_hull_visible(not inside)
		if interior != null:
			(interior as Node).call("set_lights_active", inside or lp.length() < LIGHT_DISTANCE)


# ---------------------------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------------------------

func build() -> void:
	if built:
		return
	built = true
	_p = K.palette(faction)
	name = "%sMothership" % faction.capitalize()
	hull_visual = Node3D.new()
	hull_visual.name = "HullVisual"
	add_child(hull_visual)
	var glb_path: String = HULL_DIR + "%s_mothership_hull.glb" % faction
	var glb_ok: bool = false
	if ResourceLoader.exists(glb_path):
		var ps: PackedScene = load(glb_path) as PackedScene
		if ps != null:
			var inst: Node = ps.instantiate()
			if inst is Node3D:
				inst.name = "HullGLB"
				hull_visual.add_child(inst)
				hull_source = "glb"
				glb_ok = true
			else:
				inst.free()
	if not glb_ok:
		_build_fallback_hull()
	exterior_lights = Node3D.new()
	exterior_lights.name = "ExteriorLighting"
	add_child(exterior_lights)
	_build_exterior_lighting()
	_build_hull_collision()
	interior = InteriorScript.new()
	interior.set("faction", faction)
	interior.name = "Interior"
	add_child(interior)


func _hm(key: String, metallic: float = 0.5, rough: float = 0.5, emis: float = 0.0) -> StandardMaterial3D:
	return K.material(_p[key], metallic, rough, emis)


func _vis(size: Vector3, pos: Vector3, key: String, metallic: float = 0.5, rough: float = 0.5, emis: float = 0.0) -> Node3D:
	return K.box(hull_visual, size, pos, _hm(key, metallic, rough, emis), false)


func _build_fallback_hull() -> void:
	var helion: bool = faction == "helion"
	var body_key: String = "hull"
	var panel_key: String = "metal" if helion else "trim"
	var band_key: String = "trim" if helion else "warn"
	var fin_key: String = "trim" if helion else "alt"
	# Main body (z -395 .. 265), dorsal fin, keel, sponsons, engine block.
	_vis(Vector3(200, 140, 660), Vector3(0, 0, -65), body_key, 0.45, 0.5)
	_vis(Vector3(60, 31, 420), Vector3(0, 75.5, -80), fin_key, 0.5, 0.45)
	_vis(Vector3(50, 30, 380), Vector3(0, -80, -60), panel_key, 0.6, 0.45)
	for sx in [-1.0, 1.0]:
		_vis(Vector3(60, 110, 330), Vector3(sx * 130.0, 0, -245), panel_key, 0.6, 0.45)
		_vis(Vector3(2, 112, 334), Vector3(sx * 160.0 - sx * 1.0, 0, -245), band_key, 0.4, 0.5, 0.0)
		# Bow tube around the hangar (open mouth: x +-45, y 0..40 at z = 425).
		_vis(Vector3(48.9, 110, 159.6), Vector3(sx * 70.55, 5, 345.05), body_key, 0.45, 0.5)
		# Hull stripes + armour plating.
		_vis(Vector3(0.6, 8, 640), Vector3(sx * 100.2, 45, -65), band_key, 0.5, 0.45, 0.8 if not helion else 0.0)
		_vis(Vector3(0.6, 8, 640), Vector3(sx * 100.2, -45, -65), band_key, 0.5, 0.45, 0.8 if not helion else 0.0)
		for i in 10:
			_vis(Vector3(0.7, 3, 24), Vector3(sx * 100.3, 15.0 if i % 2 == 0 else -15.0, -360.0 + float(i) * 60.0), "accent", 0.0, 0.4, 3.0)
		for i in 6:
			_vis(Vector3(0.7, 3, 20), Vector3(sx * 159.75, 20.0, -380.0 + float(i) * 50.0), "accent", 0.0, 0.4, 3.0)
	_vis(Vector3(190, 18.9, 159.6), Vector3(0, 50.55, 345.05), body_key, 0.45, 0.5)
	_vis(Vector3(190, 48.9, 159.6), Vector3(0, -25.55, 345.05), panel_key, 0.55, 0.5)
	# Bow armour wedges + faction nose bands.
	_vis(Vector3(190, 6, 20), Vector3(0, 56, 414), band_key, 0.5, 0.45, 0.6 if not helion else 0.0)
	_vis(Vector3(190, 6, 20), Vector3(0, -46, 414), band_key, 0.5, 0.45, 0.6 if not helion else 0.0)
	_vis(Vector3(300, 3, 500), Vector3(0, 70.6, -140), panel_key, 0.6, 0.4)
	_vis(Vector3(56, 2, 300), Vector3(0, 91.0, -80), "accent", 0.0, 0.4, 0.6)
	_vis(Vector3(180, 110, 30), Vector3(0, 0, -410), "dark", 0.6, 0.5)
	# Bridge blister + sensor mast (visual only, inside the 190 m height).
	_vis(Vector3(70, 14, 60), Vector3(108, 76.0, 205), panel_key, 0.6, 0.4)
	_vis(Vector3(3, 10, 3), Vector3(108, 88.0, 205), "metal", 0.8, 0.3)
	# Engine nozzles (emissive cones) + exhaust discs.
	for ex in [-45.0, 45.0]:
		for ey in [-25.0, 25.0]:
			var cone := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 8.0
			cm.bottom_radius = 16.0
			cm.height = 40.0
			cm.radial_segments = 20
			cone.mesh = cm
			cone.material_override = _hm("dark", 0.8, 0.35)
			cone.position = Vector3(ex, ey, -405.0)
			cone.rotation_degrees.x = 90.0
			hull_visual.add_child(cone)
			var disc := MeshInstance3D.new()
			var dm := CylinderMesh.new()
			dm.top_radius = 12.0
			dm.bottom_radius = 12.0
			dm.height = 0.4
			disc.mesh = dm
			var gm := StandardMaterial3D.new()
			gm.albedo_color = _p["accent"]
			gm.emission_enabled = true
			gm.emission = _p["accent"]
			gm.emission_energy_multiplier = 6.0
			disc.material_override = gm
			disc.position = Vector3(ex, ey, -424.7)
			disc.rotation_degrees.x = 90.0
			hull_visual.add_child(disc)
			_glows.append({"mat": gm, "base": 6.0, "phase": ex + ey})


func _build_exterior_lighting() -> void:
	# Animated navigation strobes (emissive spheres).
	var defs: Array = [
		[Vector3(-158, 0, -100), Color(1.0, 0.1, 0.1), 0.9, 0.0, 0.14],
		[Vector3(158, 0, -100), Color(0.1, 1.0, 0.2), 0.9, 0.0, 0.14],
		[Vector3(0, 92.5, -120), Color(1, 1, 1), 1.1, 0.3, 0.08],
		[Vector3(0, -93.5, -60), Color(1.0, 0.7, 0.2), 1.1, 0.6, 0.1],
		[Vector3(0, 0, -423.5), Color(1, 1, 1), 1.3, 0.1, 0.07],
		[Vector3(-93, 56, 420), Color(1.0, 0.1, 0.1), 0.9, 0.5, 0.14],
		[Vector3(93, 56, 420), Color(0.1, 1.0, 0.2), 0.9, 0.5, 0.14],
	]
	for d in defs:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 1.2
		sm.height = 2.4
		sm.radial_segments = 8
		sm.rings = 4
		mi.mesh = sm
		var m := StandardMaterial3D.new()
		m.albedo_color = d[1]
		m.emission_enabled = true
		m.emission = d[1]
		m.emission_energy_multiplier = 0.25
		mi.material_override = m
		mi.position = d[0]
		exterior_lights.add_child(mi)
		_strobes.append({"mat": m, "rate": d[2], "phase": d[3], "duty": d[4]})
	# Hangar floodlights (2 shadowless spots) + lamp housings at the mouth.
	for sx in [-1.0, 1.0]:
		var lamp: Node3D = K.box(exterior_lights, Vector3(2.0, 2.0, 3.0), Vector3(sx * 47.0, 36.0, 424.0), _hm("metal", 0.7, 0.4), false)
		K.box(lamp, Vector3(1.4, 1.4, 0.2), Vector3(0, 0, 1.55), _hm("hull", 0.0, 0.3, 6.0), false)
		var spot := SpotLight3D.new()
		spot.light_color = Color(1.0, 0.97, 0.9)
		spot.light_energy = 5.0
		spot.spot_range = 160.0
		spot.spot_angle = 38.0
		spot.shadow_enabled = false
		spot.position = Vector3(sx * 47.0, 36.0, 425.5)
		spot.rotation_degrees = Vector3(0, 180.0 - sx * 8.0, 0)   # SpotLight3D shines along -Z; flip to +Z
		exterior_lights.add_child(spot)
	# Window strips are part of the hull visual group (emissive meshes), no lights needed.


func _build_hull_collision() -> void:
	hull_collision = StaticBody3D.new()
	hull_collision.name = "HullCollision"
	hull_collision.collision_layer = 1
	hull_collision.collision_mask = 0
	add_child(hull_collision)
	# Outer shell around the whole main body (z -425 .. 265): 10 m plates, hollow inside.
	var shell: Array = [
		[Vector3(320, 10, 690), Vector3(0, -90, -80)],
		[Vector3(320, 10, 690), Vector3(0, 90, -80)],
		[Vector3(10, 190, 690), Vector3(-155, 0, -80)],
		[Vector3(10, 190, 690), Vector3(155, 0, -80)],
		[Vector3(320, 190, 10), Vector3(0, 0, -420)],
		# Bow face (z 265..275) EXCEPT the tube cross-section the hangar sits in.
		[Vector3(65, 190, 10), Vector3(-127.5, 0, 270)],
		[Vector3(65, 190, 10), Vector3(127.5, 0, 270)],
		[Vector3(190, 35, 10), Vector3(0, 77.5, 270)],
		[Vector3(190, 45, 10), Vector3(0, -72.5, 270)],
		# Bow tube around the hangar: walls, roof, floor. The mouth (x +-45, y 0..40, z = 425) stays open.
		[Vector3(48.9, 110, 159.6), Vector3(-70.55, 5, 345.05)],
		[Vector3(48.9, 110, 159.6), Vector3(70.55, 5, 345.05)],
		[Vector3(190, 18.9, 159.6), Vector3(0, 50.55, 345.05)],
		[Vector3(190, 48.9, 159.6), Vector3(0, -25.55, 345.05)],
	]
	for s in shell:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = s[0]
		cs.shape = bs
		cs.position = s[1]
		hull_collision.add_child(cs)
