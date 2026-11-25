extends Node3D

const Turret = preload("res://scripts/gameplay/DefenseTurret.gd")
const Shield = preload("res://scripts/gameplay/DeployableShield.gd")
const Pod = preload("res://scripts/gameplay/SupplyPod.gd")
const Combat = preload("res://scripts/combat/PlayerCombatComponent.gd")
const ProjectileScript = preload("res://scripts/vehicles/Projectile.gd")
const COSTS := {"turret": 60.0, "shield": 50.0, "supply": 40.0}
const MAX_STRUCTURES := 96

var world: Node
var structures := {}
var current_origin := Vector3.ZERO
var _sequence := 0
var _origin_frame := -2


func setup(context: Node) -> void:
	world = context
	current_origin = world.floating_origin.current_origin
	process_physics_priority = -10


func rebuild() -> void:
	for structure in structures.values():
		remove_child(structure)
		structure.queue_free()
	structures.clear()
	_sequence = 0


func request_local(kind: String) -> bool:
	if world.explorer.is_piloting or world.player_combat.health <= 0.0 or world.explorer.in_ship_interior:
		return false
	var player: Node3D = world.explorer
	var here: Vector3 = player.get_planet_position()
	if ground_at(here, 4.5).is_empty():
		return false
	var destination: Vector3 = here - player.global_basis.z * 5.0
	if world.can_mutate_world():
		return deploy(kind, world.player_combat.faction, destination) != null
	return world.network_authority.request_deploy_buildable(kind, destination)


func ground_at(planet_point: Vector3, distance: float = 18.0, footprint: bool = false) -> Dictionary:
	if not planet_point.is_finite() or planet_point.length_squared() < 1.0:
		return {}
	var up := planet_point.normalized()
	var from := planet_point - current_origin
	var query := PhysicsRayQueryParameters3D.create(from + up * 2.5, from - up * distance, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or hit.normal.dot(up) < 0.75 or world.mothership_manager.find_ship_containing(hit.position + current_origin) != null:
		return {}
	var frame := Basis.looking_at(Vector3.FORWARD.slide(up).normalized() if absf(up.z) < 0.98 else Vector3.RIGHT.slide(up).normalized(), up)
	var center: Vector3 = hit.position
	if footprint:
		for side in [frame.x, -frame.x, frame.z, -frame.z]:
			var edge: Vector3 = center + side * 1.2
			var support := PhysicsRayQueryParameters3D.create(edge + up * 0.35, edge - up * 0.28, 1)
			if get_world_3d().direct_space_state.intersect_ray(support).is_empty():
				return {}
	return {"planet_position": center + current_origin, "basis": frame}


func deploy(kind: String, faction: String, planet_point: Vector3) -> Node3D:
	if not world.can_simulate_combat() or not COSTS.has(kind):
		return null
	var site := ground_at(planet_point, 18.0, true)
	if not can_place(site) or not world.match_manager.spend_resources(faction, COSTS[kind]):
		return null
	return spawn_buildable(kind, faction, site)


func can_place(site: Dictionary) -> bool:
	if site.is_empty() or structures.size() >= MAX_STRUCTURES:
		return false
	for structure in structures.values():
		if structure.planet_position.distance_squared_to(site.planet_position) < 9.0 and structure.visible:
			return false
	return true


func spawn_buildable(kind: String, faction: String, site: Dictionary, launch: Vector3 = Vector3.ZERO) -> Node3D:
	_sequence += 1
	var id := "%s-%04d" % [kind, _sequence]
	return _spawn(id, kind, faction, site.planet_position, site.basis, launch, Pod.DROP_TIME if launch != Vector3.ZERO else 0.0)


func _spawn(id: String, kind: String, faction: String, planet_point: Vector3, frame: Basis, launch: Vector3, drop_time: float) -> Node3D:
	var structure: StaticBody3D
	match kind:
		"turret":
			structure = Turret.new()
			structure.world = world
		"shield":
			structure = Shield.new()
		"supply":
			structure = Pod.new()
			structure.world = world
			structure.launch_position = launch
			structure.drop_remaining = drop_time
	structure.name = id
	structure.set_meta("kind", kind)
	structure.faction = faction
	structure.planet_position = planet_point
	structure.transform = Transform3D(frame, planet_point - current_origin)
	add_child(structure)
	structures[id] = structure
	if structure is Pod:
		structure.pose(current_origin)
	return structure


func apply_origin(new_origin: Vector3) -> void:
	current_origin = new_origin
	_origin_frame = Engine.get_physics_frames()
	for structure in structures.values():
		if structure is Pod:
			structure.pose(current_origin)
		else:
			structure.global_position = structure.planet_position - current_origin
		structure.reset_physics_interpolation()


func _physics_process(delta: float) -> void:
	if not world.ready_complete:
		return
	var authority: bool = world.can_simulate_combat()
	if authority and Engine.get_physics_frames() > _origin_frame + 1:
		_screen_vehicle_projectiles(delta)
	for id in structures.keys():
		var structure: StaticBody3D = structures[id]
		if structure is Pod:
			structure.tick(delta, authority)
		elif authority and structure is Turret:
			if structure.health <= 0.0:
				structures.erase(id)
				remove_child(structure)
				structure.queue_free()
			elif Engine.get_physics_frames() > _origin_frame + 1:
				structure.tick(delta)


func combat_targets() -> Array:
	return world.ai_manager.troopers + world.ai_manager.fighters + world.vehicle_manager.vehicles.values() + [world.explorer] + world.network_authority.replication.avatars.values()


func intercept_shot(start: Vector3, end: Vector3, faction: String, damage: float) -> Dictionary:
	var best := INF
	var absorber: StaticBody3D
	for structure in structures.values():
		if structure is Shield:
			var at: float = structure.entry_fraction(start, end, faction)
			if at < best:
				best = at
				absorber = structure
	if absorber == null:
		return {}
	var point := start.lerp(end, best)
	absorber.take_faction_damage(damage, faction)
	ProjectileScript.spawn_flash(world.combat_effects, point, Combat.faction_color(absorber.faction), 0.45, 0.14)
	return {"position": point, "collider": absorber}


func _screen_vehicle_projectiles(delta: float) -> void:
	for shot in world.vehicle_manager.projectile_root.get_children():
		if not shot is ProjectileScript or shot.is_queued_for_deletion() or not is_instance_valid(shot.shooter):
			continue
		if not shot.has_meta("replicated_visual"):
			shot.set_meta("replicated_visual", true)
			world.network_authority.relay_vehicle_projectile(shot)
		var start: Vector3 = shot.global_position
		var end: Vector3 = start + shot.direction * shot.speed * minf(delta, shot.flight_time)
		var hit := Combat.cast_ray(shot.shooter, start, end)
		var point: Vector3 = hit.get("position", end)
		var faction: String = shot.shooter.faction
		if not intercept_shot(start, point, faction, shot.damage).is_empty():
			shot.queue_free()
		elif hit.get("collider") is Turret or hit.get("collider") is Shield or hit.get("collider") == world.explorer or hit.get("collider") in world.network_authority.replication.avatars.values() or (hit.get("collider") is CharacterBody3D and hit.collider in world.ai_manager.troopers):
			var target: Node3D = hit.collider
			if target is Shield:
				target.take_faction_damage(shot.damage, faction)
			else:
				Turret.damage_target(world, target, shot.damage, faction, point)
			ProjectileScript.spawn_flash(world.combat_effects, point, shot.energy_color, 0.52, 0.16)
			shot.hit_registered.emit()
			shot.queue_free()
		# Queued projectiles must also stop their own sweep for this frame.
		if shot.is_queued_for_deletion():
			shot.set_physics_process(false)


func snapshot() -> Dictionary:
	var state := {}
	for id in structures:
		var structure: StaticBody3D = structures[id]
		var entry := {"kind": structure.get_meta("kind"), "faction": structure.faction, "position": structure.planet_position, "basis": structure.basis}
		if structure is Turret:
			entry.merge({"health": structure.health, "yaw": structure.yaw.rotation.y, "pitch": structure.pitch.rotation.x})
		elif structure is Shield:
			entry.health = structure.shield_hp
		else:
			entry.merge({"launch": structure.launch_position, "drop": structure.drop_remaining})
		state[id] = entry
	return state


func apply_snapshot(state: Dictionary) -> void:
	for id in structures.keys():
		if not state.has(id) or structures[id].planet_position != state[id].position:
			remove_child(structures[id])
			structures[id].queue_free()
			structures.erase(id)
	for id in state:
		var entry: Dictionary = state[id]
		_sequence = maxi(_sequence, id.get_slice("-", 1).to_int())
		var structure: StaticBody3D = structures.get(id)
		if structure == null:
			structure = _spawn(id, entry.kind, entry.faction, entry.position, entry.basis, entry.get("launch", Vector3.ZERO), entry.get("drop", 0.0))
		if structure is Turret:
			structure.health = entry.health
			structure.visible = structure.health > 0.0
			structure.collision_layer = 8 if structure.visible else 0
			structure.yaw.rotation.y = entry.yaw
			structure.pitch.rotation.x = entry.pitch
		elif structure is Shield:
			structure.set_shield_hp(entry.health)
		elif absf(structure.drop_remaining - entry.drop) > 0.15:
			structure.drop_remaining = entry.drop
			structure.pose(current_origin)


class FieldCombat extends Combat:
	func fire_weapon() -> bool:
		if not world.can_mutate_world():
			return false
		if not _can_act() or selected_tool != 0 or ammo <= 0 or _cooldown > 0.0:
			return false
		var camera: Camera3D = explorer.get_camera()
		var start := camera.global_position
		var end := start - camera.global_basis.z * RIFLE_RANGE
		var hit := cast_ray(explorer, start, end)
		var point: Vector3 = hit.get("position", end)
		var blocked: Dictionary = world.engineering_build_manager.intercept_shot(start, point, faction, 24.0)
		var terminal: Vector3 = blocked.get("position", point)
		var muzzle := _muzzle()
		if blocked.is_empty():
			if not super.fire_weapon():
				return false
			world.network_authority.relay_tracer(muzzle, terminal, faction_color(faction), 0.035)
		else:
			ammo -= 1
			shots_fired += 1
			_cooldown = FIRE_INTERVAL
			hitmarker_time = 0.17
			world.network_authority.publish_tracer(muzzle, terminal, faction_color(faction), 0.035)
			viewmodel.position.z += 0.052
		return true

	func use_engineering_beam(delta: float) -> bool:
		if not _can_act() or selected_tool != 1 or delta <= 0.0:
			return false
		var camera: Camera3D = explorer.get_camera()
		var hit := cast_ray(explorer, camera.global_position, camera.global_position - camera.global_basis.z * BEAM_RANGE)
		var target: Object = hit.get("collider")
		if target is Turret or target is Shield:
			_draw_engineering_arc(_muzzle(), hit.position, camera.global_basis)
			if target.faction != faction:
				return false
			var amount: float = target.repair(36.0 * delta)
			world.match_manager.record_repair(amount)
			return amount > 0.0
		return super.use_engineering_beam(delta)

	func reload() -> void:
		if world.can_mutate_world():
			super.reload()
		else:
			world.network_authority.request_reload()
