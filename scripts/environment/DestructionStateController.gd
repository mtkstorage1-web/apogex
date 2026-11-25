class_name DestructionStateController
extends Node
## Destruction framework. Each designated section has a stable network-safe StringName id and an authoritative
## state held in `_states` (never inside a visual node), so streaming a section out and back in restores the
## same INTACT / DAMAGED / CRITICAL / DESTROYED look: mesh strip colour, scorch decal, smoke + sparks,
## emissive shift, rubble collision and an audio event.

enum DestructionState { INTACT, DAMAGED, CRITICAL, DESTROYED }

signal state_changed(section_id: StringName, old_state: int, new_state: int)
## Emitted so WorldAudioController can play the matching hook ("crackle", "alarm", "collapse").
signal audio_event(section_id: StringName, event: StringName, planet_pos: Vector3)

const FacilityMgr = preload("res://scripts/environment/SurfaceFacilityManager.gd")

const SECTIONS: Array = [
	{"id": &"terminus_outer_perimeter", "label": "Terminus Outer Perimeter", "lat": 0.0, "lon": 0.0, "local": Vector3(46.0, 0, 46.0)},
	{"id": &"refinery_conduit_array", "label": "Refinery Conduit Array", "lat": 0.0, "lon": 20.0, "local": Vector3(-34.0, 0, 30.0)},
	{"id": &"mining_derrick_rig", "label": "Mining Derrick Rig", "lat": 18.0, "lon": 0.0, "local": Vector3(30.0, 0, 34.0)},
	{"id": &"settlement_power_grid", "label": "Settlement Power Grid", "lat": 0.0, "lon": -20.0, "local": Vector3(-30.0, 0, -26.0)},
	{"id": &"launch_pad_blast_shield", "label": "Launch Pad Blast Shield", "lat": -18.0, "lon": 0.0, "local": Vector3(36.0, 0, 28.0)},
]
const STATE_COLORS: Array[Color] = [Color(0.2, 0.9, 0.35), Color(1.0, 0.8, 0.15), Color(1.0, 0.35, 0.08), Color(0.12, 0.04, 0.04)]
const STATE_NAMES: Array[String] = ["INTACT", "DAMAGED", "CRITICAL", "DESTROYED"]
const EVENTS: Array[StringName] = [&"repair", &"crackle", &"alarm", &"collapse"]

var noise: TerrainNoiseStack
var current_origin: Vector3 = Vector3.ZERO
var quality_preset: String = "HIGH"
var _states: Dictionary = {}    # StringName -> int (authoritative)
var _visuals: Dictionary = {}   # StringName -> {node, strip_mat, decal, smoke, sparks, rubble, base_pos}
var _base_pos: Dictionary = {}  # StringName -> planet-space position
var _basis: Dictionary = {}
var transition_count: int = 0


func setup(p_noise: TerrainNoiseStack, p_quality: String = "HIGH") -> void:
	noise = p_noise
	quality_preset = p_quality.to_upper()
	for s in SECTIONS:
		if not _states.has(s["id"]):
			_states[s["id"]] = DestructionState.INTACT
	rebuild()


func rebuild() -> void:
	for id in _visuals.keys():
		unload_section_visual(id)
	_base_pos.clear()
	if noise == null:
		return
	for s in SECTIONS:
		var pt: Dictionary = FacilityMgr.pad_transform(noise, s["lat"], s["lon"])
		var p: Vector3 = (pt["origin"] as Vector3) + (pt["basis"] as Basis) * (s["local"] as Vector3)
		var surf: Vector3 = noise.sample_surface_position(p.normalized())
		_base_pos[s["id"]] = surf
		_basis[s["id"]] = pt["basis"]
		load_section_visual(s["id"])


func get_section_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for s in SECTIONS:
		out.append(s["id"])
	return out


func get_state(id: StringName) -> int:
	return _states.get(id, DestructionState.INTACT)


func get_state_name(id: StringName) -> String:
	return STATE_NAMES[get_state(id)]


func get_states() -> Dictionary:
	return _states.duplicate()


func get_section_position(id: StringName) -> Vector3:
	return _base_pos.get(id, Vector3.ZERO)


## Returns false for an unknown id / out-of-range state.
func set_section_state(id: StringName, state: int) -> bool:
	if not _states.has(id) or state < 0 or state > DestructionState.DESTROYED:
		return false
	var old: int = _states[id]
	_states[id] = state
	if _visuals.has(id):
		_apply_visual(id)
	if old != state:
		transition_count += 1
		state_changed.emit(id, old, state)
		audio_event.emit(id, EVENTS[state], _base_pos.get(id, Vector3.ZERO))
	return true


## Advances every section by one state (DESTROYED wraps back to INTACT).
func cycle_all_states() -> void:
	for id in get_section_ids():
		set_section_state(id, (get_state(id) + 1) % 4)


func get_summary() -> String:
	var counts: Array[int] = [0, 0, 0, 0]
	for id in _states:
		counts[_states[id]] += 1
	return "I:%d D:%d C:%d X:%d" % counts


## Visual streaming hooks: free / rebuild nodes only; `_states` is untouched.
func unload_section_visual(id: StringName) -> void:
	if _visuals.has(id):
		var n: Node3D = _visuals[id]["node"]
		if is_instance_valid(n):
			n.get_parent().remove_child(n)
			n.queue_free()
		_visuals.erase(id)


func load_section_visual(id: StringName) -> void:
	if _visuals.has(id) or not _base_pos.has(id):
		return
	var root := Node3D.new()
	root.name = "Section_%s" % String(id)
	root.basis = _basis[id]
	add_child(root)
	root.position = (_base_pos[id] as Vector3) - current_origin
	# Indicator pylon: its emissive strip shows the state colour.
	var pylon := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.9, 5.0, 0.9)
	pylon.mesh = pm
	pylon.position = Vector3(0, 2.5, 0)
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.2, 0.2, 0.22)
	pmat.metallic = 0.6
	pmat.roughness = 0.6
	pylon.material_override = pmat
	root.add_child(pylon)
	var strip := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.96, 1.6, 0.96)
	strip.mesh = sm
	strip.position = Vector3(0, 3.6, 0)
	var smat := StandardMaterial3D.new()
	smat.emission_enabled = true
	strip.material_override = smat
	root.add_child(strip)
	# Scorch decal on the ground.
	var decal := Decal.new()
	decal.name = "ScorchDecal"
	decal.size = Vector3(10, 4, 10)
	decal.texture_albedo = _scorch_texture()
	decal.modulate = Color(0, 0, 0, 0.9)
	root.add_child(decal)
	var smoke := _particles("Smoke", Color(0.1, 0.1, 0.1, 0.5), 1.6, Vector3(0, 1, 0), 3.0, 4.0)
	root.add_child(smoke)
	var sparks := _particles("Sparks", Color(1.0, 0.7, 0.3, 1.0), 0.1, Vector3(0, 1, 0), 5.0, 0.7)
	root.add_child(sparks)
	# Rubble blocker: collision only exists once destroyed.
	var rubble := StaticBody3D.new()
	rubble.name = "Rubble"
	rubble.collision_layer = 0
	rubble.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(5, 1.5, 5)
	cs.shape = box
	cs.position = Vector3(0, 0.6, 0)
	rubble.add_child(cs)
	var rm := MeshInstance3D.new()
	var rmesh := BoxMesh.new()
	rmesh.size = Vector3(5, 1.5, 5)
	rm.mesh = rmesh
	rm.position = Vector3(0, 0.6, 0)
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color(0.07, 0.06, 0.06)
	rmat.roughness = 1.0
	rm.material_override = rmat
	rubble.add_child(rm)
	root.add_child(rubble)
	_visuals[id] = {"node": root, "strip_mat": smat, "pylon_mat": pmat, "decal": decal, "smoke": smoke, "sparks": sparks, "rubble": rubble, "pylon": pylon}
	_apply_visual(id)


func _apply_visual(id: StringName) -> void:
	var v: Dictionary = _visuals[id]
	var st: int = _states[id]
	var col: Color = STATE_COLORS[st]
	var smat: StandardMaterial3D = v["strip_mat"]
	smat.albedo_color = col
	smat.emission = col
	smat.emission_energy_multiplier = [1.0, 2.0, 4.0, 0.2][st]
	(v["pylon_mat"] as StandardMaterial3D).albedo_color = Color(0.2, 0.2, 0.22).lerp(Color(0.04, 0.03, 0.03), st / 3.0)   # scorching
	(v["decal"] as Decal).visible = st >= DestructionState.DAMAGED
	(v["decal"] as Decal).modulate = Color(0, 0, 0, [0.0, 0.5, 0.8, 1.0][st])
	(v["smoke"] as GPUParticles3D).emitting = st >= DestructionState.CRITICAL
	(v["sparks"] as GPUParticles3D).emitting = st == DestructionState.DAMAGED or st == DestructionState.CRITICAL
	var rubble: StaticBody3D = v["rubble"]
	rubble.visible = st == DestructionState.DESTROYED
	rubble.collision_layer = 1 if st == DestructionState.DESTROYED else 0
	var pylon: MeshInstance3D = v["pylon"]
	pylon.rotation_degrees.z = [0.0, 0.0, 6.0, 38.0][st]
	pylon.scale.y = 1.0 if st < DestructionState.DESTROYED else 0.4


func has_rubble_collision(id: StringName) -> bool:
	if not _visuals.has(id):
		return false
	return (_visuals[id]["rubble"] as StaticBody3D).collision_layer != 0


func is_visual_loaded(id: StringName) -> bool:
	return _visuals.has(id)


func _scorch_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.5), Color(1, 1, 1, 0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t


func _particles(n: String, color: Color, quad: float, dir: Vector3, speed: float, lifetime: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = n
	p.amount = 24 if quality_preset != "LOW" else 10
	p.lifetime = lifetime
	p.emitting = false
	p.position = Vector3(0, 1.0, 0)
	p.visibility_aabb = AABB(Vector3(-20, -5, -20), Vector3(40, 40, 40))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.direction = dir
	pm.spread = 30.0
	pm.initial_velocity_min = speed * 0.5
	pm.initial_velocity_max = speed
	pm.gravity = Vector3(0, 0.5, 0) if n == "Smoke" else Vector3(0, -6.0, 0)
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(quad, quad)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_color = color
	q.material = m
	p.draw_pass_1 = q
	return p


func apply_origin(new_origin: Vector3) -> void:
	current_origin = new_origin
	for id in _visuals:
		var n: Node3D = _visuals[id]["node"]
		if is_instance_valid(n):
			n.position = (_base_pos[id] as Vector3) - current_origin
