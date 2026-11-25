extends StaticBody3D

const Combat = preload("res://scripts/combat/PlayerCombatComponent.gd")
const Vehicle = preload("res://scripts/vehicles/VehicleBase.gd")
const MODELS := "res://assets/models/apogex/deployables/"
const MAX_HEALTH := 180.0

var world: Node
var faction := "helion"
var planet_position := Vector3.ZERO
var health := MAX_HEALTH
var capital_battery := false
var ship_hull: CollisionObject3D
var target: Node3D
var shots_fired := 0
var yaw: Node3D
var pitch: Node3D
var model_source := "procedural"
var _cooldown := 0.0


func _ready() -> void:
	var filename := "mothership_turret_battery" if capital_battery else faction + "_defense_turret"
	var prefix := "Battery" if capital_battery else "Turret"
	var model := Combat.instantiate_model(MODELS + filename + ".glb")
	if model != null:
		yaw = model.find_child(prefix + "Yaw", true, false) as Node3D
		pitch = model.find_child(prefix + "Pitch", true, false) as Node3D
		if yaw == null or pitch == null:
			model.free()
			model = null
	if model == null:
		model = _fallback(prefix)
	else:
		model_source = "glb"
	add_child(model)
	collision_layer = 0 if capital_battery else 8
	collision_mask = 0
	if not capital_battery:
		add_hit_box(self, Vector3(2.6, 2.7, 2.6))


func _fallback(prefix: String) -> Node3D:
	var model := Node3D.new()
	var size := 3.5 if capital_battery else 1.0
	var skirt := 0.0 if capital_battery else 0.25
	var metal := Combat.hull_material()
	var glow := Combat.glow_material(Combat.faction_color(faction), 2.0)
	box(model, Vector3(2.8, 0.55, 2.8) * size + Vector3.UP * skirt, Vector3.UP * (0.275 * size - skirt * 0.5), metal)
	box(model, Vector3(1.55, 1.1, 1.55) * size, Vector3.UP * 0.85 * size, metal)
	yaw = Node3D.new()
	yaw.name = prefix + "Yaw"
	yaw.position.y = 1.35 * size
	model.add_child(yaw)
	pitch = Node3D.new()
	pitch.name = prefix + "Pitch"
	yaw.add_child(pitch)
	box(pitch, Vector3(1.6, 0.55, 1.2) * size, Vector3.ZERO, metal)
	for side in [-0.42, 0.42]:
		box(pitch, Vector3(0.24, 0.27, 1.85) * size, Vector3(side, 0, -0.95) * size, metal)
		box(pitch, Vector3(0.18, 0.15, 0.24) * size, Vector3(side, 0, -1.9) * size, glow)
	return model


func tick(delta: float) -> void:
	if health <= 0.0 or world == null or not world.can_simulate_combat():
		return
	_cooldown = maxf(0.0, _cooldown - delta)
	target = null
	var nearest := pow(650.0 if capital_battery else 115.0, 2)
	var aim := Vector3.ZERO
	var start := pitch.global_position
	for candidate in world.engineering_build_manager.combat_targets():
		if candidate == self or not hostile(world, candidate, faction):
			continue
		if capital_battery:
			if candidate is Vehicle:
				if candidate.vehicle_type == "rover" or (not candidate.is_piloted and candidate.get_speed() < 1.0):
					continue
			elif not candidate is CharacterBody3D or candidate not in world.ai_manager.fighters:
				continue
		var point := aim_point(world, candidate)
		var distance := start.distance_squared_to(point)
		if distance >= nearest:
			continue
		var excluded: Array[RID] = [get_rid()]
		if ship_hull != null:
			excluded.append(ship_hull.get_rid())
		var ray := PhysicsRayQueryParameters3D.create(start, point, Combat.HIT_MASK | 2, excluded)
		ray.hit_from_inside = true
		var hit := get_world_3d().direct_space_state.intersect_ray(ray)
		if hit.is_empty() or hit.collider == candidate:
			nearest = distance
			target = candidate
			aim = point
	if target == null:
		return
	var local := yaw.get_parent_node_3d().to_local(aim) - yaw.position
	yaw.rotation.y = lerp_angle(yaw.rotation.y, atan2(-local.x, -local.z), 1.0 - exp(-10.0 * delta))
	local = yaw.to_local(aim) - pitch.position
	pitch.rotation.x = lerp_angle(pitch.rotation.x, atan2(local.y, Vector2(local.x, local.z).length()), 1.0 - exp(-10.0 * delta))
	if _cooldown > 0.0 or (-pitch.global_basis.z).normalized().dot((aim - start).normalized()) < 0.975:
		return
	_cooldown = 0.31 if capital_battery else (0.37 if faction == "helion" else 0.46)
	shots_fired += 1
	var amount := 43.0 if capital_battery else (19.0 if faction == "helion" else 24.0)
	var shield_hit: Dictionary = world.engineering_build_manager.intercept_shot(start, aim, faction, amount)
	var end: Vector3 = shield_hit.get("position", aim)
	if shield_hit.is_empty():
		damage_target(world, target, amount, faction, start if target == world.explorer else aim)
	world.network_authority.publish_tracer(start, end, Combat.faction_color(faction), 0.25 if capital_battery else 0.10)


func take_damage(amount: float, source: Variant = "") -> bool:
	return take_faction_damage(amount, source if source is String else "")


func take_faction_damage(amount: float, source: String, _player_kill: bool = false) -> bool:
	if health <= 0.0 or amount <= 0.0 or source == faction:
		return false
	health = maxf(0.0, health - amount)
	if health == 0.0:
		hide()
		set_deferred("collision_layer", 0)
		world.match_manager.record_elimination(source, name, false)
	return true


func repair(amount: float) -> float:
	var before := health
	if health > 0.0:
		health = minf(MAX_HEALTH, health + amount)
	return health - before


static func add_hit_box(body: CollisionObject3D, size: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var hit_box := CollisionShape3D.new()
	hit_box.shape = shape
	hit_box.position.y = size.y * 0.5
	body.add_child(hit_box)


static func box(parent: Node3D, size: Vector3, at: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	Combat.add_mesh(parent, mesh, at, material)


static func hostile(context: Node, candidate: Node3D, team: String) -> bool:
	if candidate == context.explorer:
		return not candidate.is_piloting and context.player_combat.health > 0.0 and context.player_combat.faction != team
	return candidate.health > 0.0 and candidate.faction != team and not candidate.get_meta("boarded", false)


static func aim_point(context: Node, candidate: Node3D) -> Vector3:
	if candidate == context.explorer or candidate.get("peer_id") != null:
		return candidate.global_position
	if candidate is Vehicle:
		return candidate.global_position + candidate.global_basis.y * candidate.dimensions.y * 0.5
	return candidate.global_position + candidate.global_basis.y * 1.15


static func damage_target(context: Node, candidate: Node3D, amount: float, team: String, hit: Vector3, player_kill := false) -> bool:
	if not hostile(context, candidate, team):
		return false
	if candidate == context.explorer:
		context.game_feel.damage_from(hit)
		return context.player_combat.take_damage(amount, team)
	if candidate is Vehicle:
		candidate.take_damage(amount, hit)
		if candidate.health <= 0.0:
			context.match_manager.record_elimination(team, candidate.display_name, player_kill)
		return true
	return candidate.take_faction_damage(amount, team, player_kill)
