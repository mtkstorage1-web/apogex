class_name BotTrooper
extends CharacterBody3D

signal eliminated(bot: Node, killer_faction: String)

const Combat = preload("res://scripts/combat/PlayerCombatComponent.gd")
const RESPAWN_TIME := 8.0
const ENGAGE_RANGE := 90.0

@export var faction := "helion"
@export var callsign := "HELION-04"
var health := 100.0
var shield := 40.0
var objective: Node3D
var squad_slot := 0
var state := "ADVANCE"
var model_source := "procedural"
var respawn_remaining := 0.0
var manager: Node3D
var _cooldown := 0.0
var _scan_wait := 0.0
var _target: Node3D


func _ready() -> void:
	add_to_group("bot_troopers")
	var model := Combat.instantiate_model(Combat.COMBAT_MODELS + faction + "_trooper.glb")
	if model != null:
		add_child(model)
		model_source = "glb"
	else:
		_build_fallback()


func _build_fallback() -> void:
	var armor := Combat.hull_material()
	var accent := Combat.glow_material(Combat.faction_color(faction), 1.4)
	for side in [-1.0, 1.0]:
		var leg := BoxMesh.new()
		leg.size = Vector3(0.22, 0.76, 0.28)
		Combat.add_mesh(self, leg, Vector3(side * 0.19, 0.38, 0), armor)
		var arm := BoxMesh.new()
		arm.size = Vector3(0.17, 0.44, 0.23)
		Combat.add_mesh(self, arm, Vector3(side * 0.33, 1.12, -0.03), accent)
	var torso := BoxMesh.new()
	torso.size = Vector3(0.52, 0.64, 0.35)
	Combat.add_mesh(self, torso, Vector3.UP * 1.07, armor)
	var helmet := SphereMesh.new()
	helmet.radius = 0.19
	helmet.height = 0.4
	Combat.add_mesh(self, helmet, Vector3.UP * 1.58, armor)
	var visor := BoxMesh.new()
	visor.size = Vector3(0.26, 0.075, 0.1)
	Combat.add_mesh(self, visor, Vector3(0, 1.61, -0.15), accent)


func respawn() -> void:
	health = 100.0
	shield = 40.0
	respawn_remaining = 0.0
	collision_layer = 8
	state = "ADVANCE"
	velocity = Vector3.ZERO
	_target = null
	_cooldown = 0.28 + squad_slot * 0.17
	_scan_wait = squad_slot * 0.04
	global_basis = objective.global_basis
	var side := -1.0 if faction == "helion" else 1.0
	var offset := Vector3((7.0 + squad_slot * 3.0) * side, 0, squad_slot * 4.0 + 0.5)
	global_position = objective.to_global(offset)
	_snap_to_surface()
	reset_physics_interpolation()
	show()


func _physics_process(delta: float) -> void:
	if manager == null or manager.origin_is_resyncing() or not manager.world.can_simulate_combat():
		return
	if health <= 0.0:
		respawn_remaining -= delta
		if respawn_remaining <= 0.0:
			respawn()
		return
	_cooldown -= delta
	_scan_wait -= delta
	if _scan_wait <= 0.0:
		_target = manager.find_trooper_target(self, ENGAGE_RANGE)
		_scan_wait = 0.28 + squad_slot * 0.03
	var up: Vector3 = (global_position + manager.current_origin).normalized()
	up_direction = up
	var side := -1.0 if faction == "helion" else 1.0
	var patrol := objective.to_global(Vector3(side * (3.5 + squad_slot * 4.0), 0, squad_slot * 4.0 + 0.5))
	var goal := patrol - global_position
	state = "ADVANCE" if goal.length_squared() > 4.0 else "DEFEND"
	var movement := goal.slide(up)
	var facing := movement
	if is_instance_valid(_target):
		var rival: Vector3 = _target.global_position - global_position
		if rival.length_squared() <= ENGAGE_RANGE * ENGAGE_RANGE:
			facing = rival.slide(up)
			state = "ENGAGE"
			if _cooldown <= 0.0:
				_fire(up)
			if rival.length_squared() < 22.0 * 22.0 and movement.length_squared() < 4.0:
				movement = facing.cross(up) * side
	if facing.length_squared() > 0.015:
		global_basis = global_basis.slerp(Basis.looking_at(facing.normalized(), up), 1.0 - exp(-10.0 * delta)).orthonormalized()
	var lateral := movement.normalized() * minf(movement.length() * 2.5, 5.5)
	velocity = lateral + up * maxf(velocity.dot(up) - 12.0 * delta, -14.0)
	move_and_slide()
	_snap_to_surface()


func _snap_to_surface() -> void:
	var dir: Vector3 = (global_position + manager.current_origin).normalized()
	var terrain: float = manager.world.planet.get_surface_radius(dir)
	var deck: float = (objective.planet_position - (global_position + manager.current_origin)).dot(objective.global_basis.y)
	# Facility slabs stay resident even when the high resolution terrain collision is distant.
	var support := maxf(terrain - (global_position + manager.current_origin).length(), deck)
	if support > 0.005:
		global_position += dir * support
		velocity -= dir * minf(0.0, velocity.dot(dir))


func _fire(up: Vector3) -> void:
	_cooldown = 0.48 + squad_slot * 0.12
	var start := global_position + up * 1.37
	var end: Vector3 = _target.global_position + (_target.global_basis.y * 1.1 if _target is BotTrooper else Vector3.ZERO)
	var hit := Combat.cast_ray(self, start, end, 1 | 2 | 4 | 8)
	Combat.spawn_tracer(manager.world.combat_effects, start, hit.get("position", end), Combat.faction_color(faction), 0.028, 0.085)
	if hit.get("collider") != _target:
		return
	if _target == manager.world.explorer:
		manager.world.player_combat.take_damage(9.0, faction)
	elif _target.has_method("take_faction_damage"):
		if _target.take_faction_damage(16.0, faction):
			manager.note_bot_kill(self, _target)


func take_damage(amount: float, source_faction: String = "") -> bool:
	return take_faction_damage(amount, source_faction)


func take_faction_damage(amount: float, source_faction: String, player_kill: bool = false) -> bool:
	if health <= 0.0 or amount <= 0.0 or source_faction == faction or not manager.world.can_simulate_combat():
		return false
	var absorbed := minf(shield, amount)
	shield -= absorbed
	health = maxf(0.0, health - (amount - absorbed))
	if health == 0.0:
		state = "RESPAWNING"
		respawn_remaining = RESPAWN_TIME + squad_slot * 0.8
		collision_layer = 0
		hide()
		if player_kill:
			manager.note_player_kill(self)
		eliminated.emit(self, source_faction)
	return true
