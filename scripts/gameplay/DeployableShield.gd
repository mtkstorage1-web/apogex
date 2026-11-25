extends StaticBody3D

const Turret = preload("res://scripts/gameplay/DefenseTurret.gd")
const Combat = preload("res://scripts/combat/PlayerCombatComponent.gd")
const FieldShader = preload("res://shaders/forcefield.gdshader")
const RADIUS := 6.5
const MAX_SHIELD := 350.0

var faction := "helion"
var planet_position := Vector3.ZERO
var shield_hp := MAX_SHIELD
var dome: MeshInstance3D


func _ready() -> void:
	collision_layer = 8
	collision_mask = 0
	Turret.add_hit_box(self, Vector3(2.4, 3.3, 2.4))
	var model := Combat.instantiate_model(Turret.MODELS + "deployable_shield_gen.glb")
	if model != null:
		add_child(model)
	else:
		Turret.box(self, Vector3(2.4, 0.65, 2.4), Vector3.UP * 0.075, Combat.hull_material())
		Turret.box(self, Vector3(1.4, 3.35, 1.4), Vector3.UP * 1.68, Combat.hull_material())
		Turret.box(self, Vector3(0.95, 0.35, 0.95), Vector3.UP * 3.4, Combat.glow_material(Combat.faction_color(faction), 2.8))
	var mesh := SphereMesh.new()
	mesh.radius = RADIUS
	mesh.height = RADIUS * 2.0
	mesh.is_hemisphere = true
	var material := ShaderMaterial.new()
	material.shader = FieldShader
	material.set_shader_parameter("field_color", Combat.faction_color(faction))
	material.set_shader_parameter("base_alpha", 0.035)
	material.set_shader_parameter("intensity", 0.85)
	dome = Combat.add_mesh(self, mesh, Vector3.UP * RADIUS * 0.5, material)
	dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func entry_fraction(start: Vector3, end: Vector3, source: String) -> float:
	if shield_hp <= 0.0 or source == faction:
		return INF
	var offset := start - global_position
	var line := end - start
	var a := line.length_squared()
	var b := offset.dot(line)
	var c := offset.length_squared() - RADIUS * RADIUS
	var discriminant := b * b - a * c
	if a < 0.00001 or c <= 0.0 or discriminant < 0.0:
		return INF
	var t := (-b - sqrt(discriminant)) / a
	if t < 0.0 or t > 1.0 or (offset + line * t).dot(global_basis.y) < 0.0:
		return INF
	return t


func take_damage(amount: float, source: Variant = "") -> bool:
	return take_faction_damage(amount, source if source is String else "")


func take_faction_damage(amount: float, source: String, _player_kill: bool = false) -> bool:
	if amount <= 0.0 or shield_hp <= 0.0 or source == faction:
		return false
	set_shield_hp(shield_hp - amount)
	return true


func repair(amount: float) -> float:
	var before := shield_hp
	set_shield_hp(shield_hp + amount)
	return shield_hp - before


func set_shield_hp(value: float) -> void:
	shield_hp = clampf(value, 0.0, MAX_SHIELD)
	dome.visible = shield_hp > 0.0
	(dome.material_override as ShaderMaterial).set_shader_parameter("intensity", lerpf(0.3, 0.85, shield_hp / MAX_SHIELD))
