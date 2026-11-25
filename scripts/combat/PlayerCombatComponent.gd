class_name PlayerCombatComponent
extends Node

const Vehicle = preload("res://scripts/vehicles/VehicleBase.gd")
const Shot = preload("res://scripts/vehicles/Projectile.gd")
const COMBAT_MODELS := "res://assets/models/apogex/combat/"
const RIFLES := {"helion": "helion_pulse_rifle", "cinder": "cinder_carbine"}
const HIT_MASK := 1 | 4 | 8
const MAGAZINE_SIZE := 30
const RIFLE_RANGE := 320.0
const BEAM_RANGE := 18.0
const ARC_SEGMENTS := 6
const FIRE_INTERVAL := 0.115
const FUEL_RATE := 30.0
const VIEWMODEL_REST := Vector3(0.31, -0.24, -0.62)

var max_health := 100.0
var health := 100.0
const BASE_SHIELD := 75.0
const ASSAULT_SHIELD := 100.0

var max_shield := BASE_SHIELD
var shield := 75.0
var shield_regen_delay := 4.0
var max_jetpack := 100.0
var jetpack_fuel := 100.0
var ammo := MAGAZINE_SIZE
var selected_tool := 0
var faction := "helion"
var spawn_choice := "hangar"
var model_source := "procedural"
var shots_fired := 0
var hitmarker_time := 0.0

var world: Node
var explorer: CharacterBody3D
var viewmodel: Node3D
var _model: Node3D
var _beam: Node3D
var _arc_segments: Array[MeshInstance3D] = []
var _cooldown := 0.0
var _shield_wait := 0.0
var _jetpack_thrust := 0.0
var _repair_time: Dictionary = {}


func setup(p_world: Node, player: CharacterBody3D) -> void:
	world = p_world
	explorer = player
	viewmodel = Node3D.new()
	viewmodel.name = "InfantryViewmodel"
	explorer.get_camera().add_child(viewmodel)
	viewmodel.position = VIEWMODEL_REST
	_beam = Node3D.new()
	_beam.name = "EngineeringArc"
	add_child(_beam)
	_beam.hide()
	var core := BoxMesh.new()
	var glow := glow_material(Color("#74ffbc"), 3.0)
	for index in ARC_SEGMENTS:
		var segment := add_mesh(_beam, core, Vector3.ZERO, glow)
		segment.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_arc_segments.append(segment)
	world.match_manager.faction_changed.connect(set_faction)
	_rebuild_model()


func set_faction(value: String) -> void:
	faction = value
	_rebuild_model()


func select_tool(idx: int) -> bool:
	if idx < 0 or idx > 1:
		return false
	if idx != selected_tool:
		selected_tool = idx
		_beam.hide()
		_rebuild_model()
	return true


func reload() -> void:
	if _can_act():
		ammo = MAGAZINE_SIZE


func _can_act() -> bool:
	return health > 0.0 and not explorer.is_piloting and world.can_simulate_combat()


func _physics_process(delta: float) -> void:
	if explorer == null:
		return
	viewmodel.visible = world.get_frontend_state() == "GAMEPLAY" and not world.frontend_ui.sandbox and not explorer.is_piloting and health > 0.0 and explorer.camera_mode <= 1
	viewmodel.position = viewmodel.position.lerp(VIEWMODEL_REST, 1.0 - exp(-18.0 * delta))
	_beam.hide()
	_cooldown = maxf(_cooldown - delta, 0.0)
	hitmarker_time = maxf(hitmarker_time - delta, 0.0)
	_shield_wait = maxf(_shield_wait - delta, 0.0)
	if health > 0.0 and _shield_wait == 0.0 and world.can_simulate_combat():
		shield = minf(max_shield, shield + 20.0 * delta)
	if explorer.combat_input_allowed() and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if selected_tool == 0:
			fire_weapon()
		else:
			use_engineering_beam(delta)


func fire_weapon() -> bool:
	if not _can_act() or selected_tool != 0 or ammo == 0 or _cooldown > 0.0:
		return false
	ammo -= 1
	shots_fired += 1
	_cooldown = FIRE_INTERVAL
	var camera: Camera3D = explorer.get_camera()
	var start := camera.global_position
	var end := start - camera.global_basis.z * RIFLE_RANGE
	var hit := cast_ray(explorer, start, end)
	var point: Vector3 = hit.get("position", end)
	var target: Object = hit.get("collider")
	var section := _aimed_section(start, point)
	var damaged := false
	if is_instance_valid(target) and target.has_method("take_damage") and target.get("faction") != faction:
		if target is Vehicle:
			var was_alive: bool = target.health > 0.0
			target.take_damage(24.0, point)
			if was_alive and target.health <= 0.0:
				world.match_manager.record_elimination(faction, target.display_name, true)
			damaged = was_alive
		elif target.has_method("take_faction_damage"):
			damaged = target.take_faction_damage(24.0, faction, true)
	if section != &"" and world.destruction.get_state(section) < 3:
		world.destruction.set_section_state(section, world.destruction.get_state(section) + 1)
		_repair_time.erase(section)
		damaged = true
	if damaged:
		hitmarker_time = 0.17
	var muzzle := _muzzle()
	var energy := faction_color(faction)
	spawn_tracer(world.combat_effects, muzzle, point, energy, 0.035, 0.09)
	Shot.spawn_flash(world.combat_effects, muzzle, energy, 0.085, 0.09)
	viewmodel.position.z += 0.052
	return true


func use_engineering_beam(delta: float) -> bool:
	if not _can_act() or selected_tool != 1 or delta <= 0.0:
		return false
	var camera: Camera3D = explorer.get_camera()
	var start := camera.global_position
	var end := start - camera.global_basis.z * BEAM_RANGE
	var hit := cast_ray(explorer, start, end)
	var point: Vector3 = hit.get("position", end)
	var target: Object = hit.get("collider")
	_draw_engineering_arc(_muzzle(), point, camera.global_basis)
	if target is Vehicle:
		if target.faction != faction or target.health <= 0.0:
			return false
		var before: float = target.health + target.shield
		target.health = minf(target.max_health, target.health + 30.0 * delta)
		target.shield = minf(target.max_shield, target.shield + 24.0 * delta)
		var repaired: float = target.health + target.shield - before
		world.match_manager.record_repair(repaired)
		return repaired > 0.0
	if is_instance_valid(target) and target.has_method("support_capture"):
		target.support_capture(faction, delta * 1.1)
		world.match_manager.record_extraction(4.0 * delta)
		return true
	var section := _aimed_section(start, point)
	if section != &"" and world.destruction.get_state(section) > 0:
		var worked: float = _repair_time.get(section, 0.0) + delta
		while worked >= 0.75 and world.destruction.get_state(section) > 0:
			world.destruction.set_section_state(section, world.destruction.get_state(section) - 1)
			world.match_manager.record_repair(10.0)
			worked -= 0.75
		_repair_time[section] = worked if world.destruction.get_state(section) > 0 else 0.0
		return true
	return false


func _aimed_section(start: Vector3, end: Vector3) -> StringName:
	var closest: StringName = &""
	var nearest := INF
	var line := end - start
	var length := line.length()
	if length < 0.01:
		return closest
	var direction := line / length
	for id in world.destruction.get_section_ids():
		var base: Vector3 = world.destruction.get_section_position(id)
		var up := base.normalized()
		var foot: Vector3 = world.floating_origin.planet_to_render(base)
		# The section's visible pylon has no collider until its rubble spawns.
		var pair := Geometry3D.get_closest_points_between_segments(start, end + direction * 0.45, foot, foot + up * 5.0)
		var distance := start.distance_squared_to(pair[0])
		if pair[0].distance_squared_to(pair[1]) <= 0.77 and distance < nearest:
			closest = id
			nearest = distance
	return closest


func apply_jetpack(delta: float, held: bool = true) -> float:
	if delta <= 0.0 or explorer.is_piloting:
		return 0.0
	var boosting: bool = held and explorer.move_mode == 0 and not explorer.grounded and jetpack_fuel > 0.0 and health > 0.0
	_jetpack_thrust = move_toward(_jetpack_thrust, 24.0 if boosting else 0.0, 85.0 * delta)
	if boosting:
		var burn := minf(delta, jetpack_fuel / FUEL_RATE)
		jetpack_fuel -= FUEL_RATE * burn
		var impulse := _jetpack_thrust * burn
		var up: Vector3 = explorer.global_basis.y.normalized() if explorer.is_in_eva() else -explorer.gravity_dir
		explorer.velocity += up * impulse
		return impulse
	if explorer.grounded or not held:
		jetpack_fuel = minf(max_jetpack, jetpack_fuel + delta * (33.0 if explorer.grounded else 12.0))
	return 0.0


func take_damage(amount: float, source_faction: String = "") -> bool:
	if not _can_act() or source_faction == faction or amount <= 0.0:
		return false
	var absorbed := minf(shield, amount)
	shield -= absorbed
	health = maxf(0.0, health - (amount - absorbed))
	_shield_wait = shield_regen_delay
	if health <= 0.0:
		world.match_manager.record_elimination(source_faction, "Player", false)
		_respawn_if_eliminated.call_deferred()
	return true


func heal(amount: float) -> void:
	if _can_act() and amount > 0.0:
		health = minf(max_health, health + amount)


func _respawn_if_eliminated() -> void:
	if health > 0.0:
		return
	if world.frontend_ui != null and world.frontend_ui.managed:
		world.frontend_ui.on_player_eliminated()
	else:
		respawn_player()


func respawn_player() -> void:
	if world.can_mutate_world():
		world.deploy_player(spawn_choice)


func apply_starting_role(role: String) -> void:
	max_shield = ASSAULT_SHIELD if role == "assault" else BASE_SHIELD
	select_tool(1 if role == "engineer" else 0)
	reset_for_spawn()


func reset_for_spawn() -> void:
	health = max_health
	shield = max_shield
	jetpack_fuel = max_jetpack
	ammo = MAGAZINE_SIZE
	_cooldown = 0.0
	_shield_wait = 0.0
	_jetpack_thrust = 0.0
	hitmarker_time = 0.0
	_repair_time.clear()
	_beam.hide()


func get_combat_status() -> Dictionary:
	return {
		"health": health, "max_health": max_health, "shield": shield, "max_shield": max_shield,
		"jetpack_fuel": jetpack_fuel, "max_jetpack": max_jetpack, "tool": selected_tool,
		"ammo": ammo, "max_ammo": MAGAZINE_SIZE, "faction": faction,
		"shots_fired": shots_fired, "hitmarker": hitmarker_time > 0.0,
	}


func _draw_engineering_arc(start: Vector3, end: Vector3, frame: Basis) -> void:
	_beam.global_position = start
	var phase := Time.get_ticks_msec() * 0.045
	var previous := start
	for index in ARC_SEGMENTS:
		var fraction := float(index + 1) / ARC_SEGMENTS
		var envelope := sin(PI * fraction)
		var spark := sin(phase + index * 2.2) * 0.075
		var point := start.lerp(end, fraction) + (frame.y * 0.20 + frame.x * spark) * envelope
		set_segment(_arc_segments[index], previous, point, 0.03 + envelope * 0.009)
		previous = point
	_beam.show()


func _muzzle() -> Vector3:
	var tip := -0.395
	if model_source == "glb":
		tip = -0.428 if selected_tool == 1 else (-0.551 if faction == "helion" else -0.543)
	return viewmodel.to_global(Vector3(0, 0, tip))


func _rebuild_model() -> void:
	if _model != null:
		viewmodel.remove_child(_model)
		_model.queue_free()
	var model_name: String = RIFLES[faction] if selected_tool == 0 else "engineering_tool"
	_model = instantiate_model(COMBAT_MODELS + model_name + ".glb")
	model_source = "glb" if _model != null else "procedural"
	if _model == null:
		_model = Node3D.new()
		var housing := BoxMesh.new()
		housing.size = Vector3(0.14, 0.19, 0.52 if selected_tool == 0 else 0.44)
		add_mesh(_model, housing, Vector3.ZERO, hull_material())
		var emitter := BoxMesh.new()
		emitter.size = Vector3(0.065, 0.06, 0.23)
		var color := faction_color(faction) if selected_tool == 0 else Color("#74ffbc")
		add_mesh(_model, emitter, Vector3(0, 0.03, -0.28), glow_material(color, 2.1))
	viewmodel.add_child(_model)


static func instantiate_model(path: String) -> Node3D:
	if ResourceLoader.exists(path, "PackedScene"):
		var scene := ResourceLoader.load(path, "PackedScene") as PackedScene
		if scene != null:
			return scene.instantiate() as Node3D
	return null


static func faction_color(team: String) -> Color:
	match team:
		"helion": return Color("#22e5ff")
		"cinder": return Color("#ff6a1a")
		_: return Color("#f2c94c")


static func hull_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#263140")
	material.metallic = 0.65
	material.roughness = 0.42
	return material


static func glow_material(color: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	return material


static func add_mesh(parent: Node3D, mesh: Mesh, at: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	parent.add_child(instance)
	return instance


static func cast_ray(body: CollisionObject3D, start: Vector3, end: Vector3, mask: int = HIT_MASK) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(start, end, mask, [body.get_rid()])
	query.hit_from_inside = true
	return body.get_world_3d().direct_space_state.intersect_ray(query)


static func set_segment(segment: MeshInstance3D, start: Vector3, end: Vector3, width: float) -> void:
	var line := end - start
	if line.length_squared() < 0.000001:
		line = Vector3.FORWARD * 0.001
	var direction := line.normalized()
	var up := Vector3.UP if absf(direction.y) < 0.98 else Vector3.RIGHT
	var frame := Basis.looking_at(direction, up).scaled_local(Vector3(width, width, line.length()))
	segment.global_transform = Transform3D(frame, (start + end) * 0.5)
	segment.reset_physics_interpolation()


static func spawn_tracer(parent: Node3D, start: Vector3, end: Vector3, color: Color, width: float, duration: float) -> void:
	var tracer := add_mesh(parent, BoxMesh.new(), Vector3.ZERO, glow_material(color, 2.7))
	tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	set_segment(tracer, start, end, width)
	var tween := tracer.create_tween()
	tween.tween_interval(duration)
	tween.tween_callback(tracer.queue_free)


func on_pilot_changed(active: bool) -> void:
	viewmodel.visible = not active
	_beam.hide()


func shift_effects(delta: Vector3) -> void:
	if _beam.visible:
		_beam.global_position -= delta
		_beam.reset_physics_interpolation()
