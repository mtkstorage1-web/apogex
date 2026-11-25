class_name VehicleWeaponSystem
extends Node

const Shot = preload("res://scripts/vehicles/Projectile.gd")
const RELOAD_TIME := 6.0

var heat := 0.0
var overheated := false
var missiles := 0
var max_missiles := 4
var shots_fired := 0
var hits_registered := 0

var _body: CharacterBody3D
var _cooldown := 0.0
var _missile_cooldown := 0.0
var _reload_left := 0.0
var _barrel := 0
var _helion := true


func setup(body: CharacterBody3D) -> void:
	_body = body
	_helion = _body.faction == "helion"
	match _body.vehicle_type:
		"dropship":
			max_missiles = 6
		"rover":
			max_missiles = 3
	missiles = max_missiles


func _physics_process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	_missile_cooldown = maxf(0.0, _missile_cooldown - delta)
	heat = maxf(0.0, heat - delta * (0.40 if overheated else 0.21))
	if overheated and heat <= 0.34:
		overheated = false
	if _reload_left > 0.0:
		_reload_left = maxf(0.0, _reload_left - delta)
		if _reload_left == 0.0:
			missiles = max_missiles
	if _body.is_piloted and _body.controls_enabled:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			fire_primary()
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			fire_secondary()


func fire_primary() -> bool:
	if not _can_fire() or overheated or _cooldown > 0.0:
		return false
	_cooldown = 0.105 if _helion else 0.16
	heat = minf(1.0, heat + (0.094 if _helion else 0.136))
	overheated = heat >= 1.0
	_launch(820.0 if _helion else 690.0, 21.0 if _helion else 30.0, 0.0, false)
	_barrel = 1 - _barrel
	return true


func fire_secondary() -> bool:
	if not _can_fire() or missiles <= 0 or _missile_cooldown > 0.0:
		return false
	missiles -= 1
	_missile_cooldown = 0.68
	if missiles == 0:
		_reload_left = RELOAD_TIME
	_launch(340.0 if _helion else 285.0, 110.0 if _helion else 133.0, 10.0, true)
	return true


func get_weapon_status() -> Dictionary:
	return {
		"heat": heat,
		"overheated": overheated,
		"missiles": missiles,
		"max_missiles": max_missiles,
		"reload_ratio": 1.0 - _reload_left / RELOAD_TIME if _reload_left > 0.0 else 0.0,
		"shots_fired": shots_fired,
		"hits_registered": hits_registered,
	}


func _can_fire() -> bool:
	return is_instance_valid(_body) and _body.is_inside_tree() and _body.health > 0.0 and not _body.origin_is_resyncing()


func _launch(speed: float, damage: float, splash: float, secondary: bool) -> void:
	var stage: Node = _body.projectile_root
	if stage == null:
		stage = _body.get_parent()
	var frame: Transform3D = _body.get_weapon_transform()
	var muzzle: Vector3 = frame * _body.get_muzzle_local(_barrel, secondary)
	var impulse: Vector3 = -frame.basis.z * speed + _body.velocity
	var shot := Shot.new()
	shot.name = "Missile" if secondary else "AutocannonBolt"
	shot.shooter = _body
	shot.destruction = _body.destruction_controller
	shot.origin_mgr = _body.origin_mgr
	shot.direction = impulse.normalized()
	shot.speed = impulse.length()
	shot.damage = damage
	shot.splash_radius = splash
	shot.energy_color = _body.get_energy_color()
	shot.hit_registered.connect(_on_hit)
	stage.add_child(shot)
	shot.global_transform = Transform3D(Basis.looking_at(shot.direction, frame.basis.y), muzzle)
	Shot.spawn_flash(stage, muzzle, shot.energy_color, 0.68 if secondary else 0.37, 0.085)
	shots_fired += 1


func _on_hit() -> void:
	hits_registered += 1
	_body.hit_confirmed.emit()
