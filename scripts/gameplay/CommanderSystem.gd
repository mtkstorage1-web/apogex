extends Node

const Combat = preload("res://scripts/combat/PlayerCombatComponent.gd")
const Turret = preload("res://scripts/gameplay/DefenseTurret.gd")
const Shot = preload("res://scripts/vehicles/Projectile.gd")
const WARNING_TIME := 2.5
const STRIKE_RADIUS := 32.0
const INFRASTRUCTURE_RADIUS := 110.0
const ABILITIES := {
	"supply": {"title": "Orbital Supply Drop", "cost": 80.0, "cooldown": 20.0},
	"strike": {"title": "Orbital Strike Barrage", "cost": 180.0, "cooldown": 35.0},
	"rally": {"title": "Squad Rally Order", "cost": 0.0, "cooldown": 12.0},
}

var world: Node
var cooldowns := {"helion": {}, "cinder": {}}
var pending_strikes: Array[Dictionary] = []


func setup(context: Node) -> void:
	world = context


func rebuild() -> void:
	for order in pending_strikes:
		if is_instance_valid(order.beacon):
			order.beacon.queue_free()
		if is_instance_valid(order.beam):
			order.beam.queue_free()
	pending_strikes.clear()
	cooldowns = {"helion": {}, "cinder": {}}
	world.ai_manager.clear_rally_orders()


func ready_in(faction: String, ability: String) -> float:
	return maxf(0.0, cooldowns.get(faction, {}).get(ability, 0.0) - world.match_manager.match_time)


func request_local(ability: String, target_id: String) -> bool:
	if not world.can_mutate_world():
		return world.network_authority.request_commander_ability(ability, target_id)
	if world.player_combat.health <= 0.0:
		return false
	return execute(world.player_combat.faction, ability, target_id, world.explorer.get_planet_position())


func execute(faction: String, ability: String, target_id: String, player_position: Vector3 = Vector3.ZERO) -> bool:
	if not world.can_simulate_combat() or not ABILITIES.has(ability) or not cooldowns.has(faction) or ready_in(faction, ability) > 0.0:
		return false
	var objective: Node3D = world.ai_manager.objective_by_id(target_id)
	if objective == null and (target_id != "beacon" or ability != "supply"):
		return false
	var site := {}
	var ship: Node3D = world.mothership_manager.get_ship(faction)
	if ability == "supply":
		var candidate: Vector3 = player_position if objective == null else objective.planet_position + objective.global_basis * Vector3(5.5, 1, -4)
		site = world.engineering_build_manager.ground_at(candidate, 18.0, true)
		if not world.engineering_build_manager.can_place(site):
			return false
	if not world.match_manager.spend_resources(faction, ABILITIES[ability].cost):
		return false
	cooldowns[faction][ability] = world.match_manager.match_time + ABILITIES[ability].cooldown
	match ability:
		"supply":
			world.engineering_build_manager.spawn_buildable("supply", faction, site, ship.local_to_planet(Vector3(0, -98, 220)))
		"strike":
			show_warning(faction, objective.planet_position, objective.global_basis)
			world.network_authority.relay_orbital("warning", faction, objective.planet_position, objective.global_basis)
		"rally":
			world.ai_manager.set_rally_order(faction, target_id)
	return true


func near_holotable() -> bool:
	if not world.explorer.in_ship_interior or world.explorer.is_piloting:
		return false
	var ship: Node3D = world.explorer.current_ship
	return ship != null and ship.faction == world.player_combat.faction and ship.planet_to_local(world.explorer.get_planet_position()).distance_to(Vector3(116, 9, 205)) < 9.0


func _physics_process(delta: float) -> void:
	for index in range(pending_strikes.size() - 1, -1, -1):
		var order := pending_strikes[index]
		order.remaining -= delta
		if order.remaining > 0.0:
			continue
		pending_strikes.remove_at(index)
		order.beacon.queue_free()
		order.beam.queue_free()
		if world.can_simulate_combat():
			_strike(order.faction, order.point, order.frame)


func show_warning(faction: String, point: Vector3, frame: Basis) -> void:
	for order in pending_strikes:
		if order.faction == faction and order.point == point:
			return
	var beacon := Combat.instantiate_model(Turret.MODELS + "orbital_strike_beacon.glb")
	var energy := _strike_color(faction)
	if beacon == null:
		beacon = Node3D.new()
		Turret.box(beacon, Vector3(1.2, 0.46, 1.2), Vector3.UP * 0.03, Combat.hull_material())
		Turret.box(beacon, Vector3(0.66, 2.0, 0.66), Vector3.UP * 1.22, Combat.hull_material())
		Turret.box(beacon, Vector3(0.45, 0.27, 0.45), Vector3.UP * 2.26, Combat.glow_material(energy, 3.2))
	beacon.name = "OrbitalStrikeBeacon"
	world.combat_effects.add_child(beacon)
	var at: Vector3 = world.floating_origin.planet_to_render(point)
	beacon.global_transform = Transform3D(frame, at + frame.x * 2.1)
	var beam := _beam(beacon.global_position + frame.y * 2.4, beacon.global_position + frame.y * 280.0, energy, 0.32)
	beam.name = "OrbitalUplink"
	pending_strikes.append({"faction": faction, "point": point, "frame": frame, "remaining": WARNING_TIME, "beacon": beacon, "beam": beam})


func _strike(faction: String, point: Vector3, frame: Basis) -> void:
	show_impact(faction, point, frame)
	world.network_authority.relay_orbital("impact", faction, point, frame)
	var at: Vector3 = world.floating_origin.planet_to_render(point)
	for target in world.engineering_build_manager.combat_targets() + world.engineering_build_manager.structures.values():
		if not target.has_method("take_faction_damage") and target != world.explorer and not target is Turret.Vehicle:
			continue
		var distance: float = target.global_position.distance_to(at)
		if distance > STRIKE_RADIUS:
			continue
		var amount := lerpf(420.0, 205.0, distance / STRIKE_RADIUS)
		if target.has_method("set_shield_hp"):
			target.take_faction_damage(amount, faction)
		else:
			Turret.damage_target(world, target, amount, faction, at)
	var nearest: StringName = &""
	var best := INFRASTRUCTURE_RADIUS * INFRASTRUCTURE_RADIUS
	for section in world.destruction.get_section_ids():
		var distance: float = point.distance_squared_to(world.destruction.get_section_position(section))
		if distance < best and world.destruction.get_state(section) < 3:
			nearest = section
			best = distance
	if nearest != &"":
		world.destruction.set_section_state(nearest, world.destruction.get_state(nearest) + 1)


func show_impact(faction: String, point: Vector3, frame: Basis) -> void:
	for index in range(pending_strikes.size() - 1, -1, -1):
		var order := pending_strikes[index]
		if order.point == point and order.faction == faction:
			order.beacon.queue_free()
			order.beam.queue_free()
			pending_strikes.remove_at(index)
	var ship: Node3D = world.mothership_manager.get_ship(faction)
	var source: Vector3 = world.floating_origin.planet_to_render(ship.local_to_planet(Vector3(0, -93, 220)))
	var at: Vector3 = world.floating_origin.planet_to_render(point)
	var beam := _beam(source, at, _strike_color(faction), 2.3)
	beam.name = "OrbitalStrikeBeam"
	var core := _beam(source, at, Color.WHITE.lerp(_strike_color(faction), 0.22), 0.7)
	var tween := beam.create_tween()
	tween.tween_interval(0.68)
	tween.tween_callback(beam.queue_free)
	tween.tween_callback(core.queue_free)
	Shot.spawn_flash(world.combat_effects, at + frame.y * 1.5, _strike_color(faction), 8.0, 0.85)
	world.game_feel.event(&"orbital", point, 0.95, 420.0)


func _beam(start: Vector3, end: Vector3, color: Color, width: float) -> MeshInstance3D:
	var beam := Combat.add_mesh(world.combat_effects, BoxMesh.new(), Vector3.ZERO, Combat.glow_material(color, 3.8))
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Combat.set_segment(beam, start, end, width)
	return beam


func _strike_color(faction: String) -> Color:
	return Color("#ff3653") if faction == "cinder" else Combat.faction_color(faction)


func warnings_snapshot() -> Array:
	var result := []
	for order in pending_strikes:
		result.append({"faction": order.faction, "point": order.point, "frame": order.frame, "remaining": order.remaining})
	return result


func apply_warnings(orders: Array) -> void:
	for entry in orders:
		var exists := pending_strikes.any(func(order: Dictionary) -> bool: return order.faction == entry.faction and order.point == entry.point)
		if not exists:
			show_warning(entry.faction, entry.point, entry.frame)
			pending_strikes.back().remaining = entry.remaining
