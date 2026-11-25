## Runs once when an authored environment enters the tree; cached resources are shared.
extends Node3D

const INDUSTRIAL := preload("res://assets/shaders/industrial.gdshader")

static func surface_arena(arena: Node3D) -> void:
	var finishes := {}
	for child in arena.get_children():
		var piece := child as MeshInstance3D
		if piece == null:
			continue
		var source := piece.material_override as StandardMaterial3D
		if source == null:
			continue
		var label := String(piece.name)
		var concrete := label == "ArenaFoundation" or label.begins_with("LaneFloor")
		var status := label.begins_with("GateLight") or label.begins_with("ReactorCoolingBand")
		var hazard := not status and (label.ends_with("Band") or label.begins_with("TowerBand"))
		var key := [source, concrete, status, hazard]
		if not finishes.has(key):
			var material := ShaderMaterial.new()
			material.shader = INDUSTRIAL
			var paint := source.albedo_color
			if hazard:
				paint = Color("#eea73a")
			elif status:
				paint = Color("#56cddd")
			elif not concrete:
				paint = paint.lerp(Color("#687681"), 0.28)
			material.set_shader_parameter("paint", paint)
			material.set_shader_parameter("arena_surface", true)
			material.set_shader_parameter("concrete", concrete)
			material.set_shader_parameter("hazard", hazard)
			material.set_shader_parameter("status_emission", 1.75 if status else 0.0)
			material.set_shader_parameter("metal", 0.0 if concrete else 0.68)
			material.set_shader_parameter("finish", 0.79 if concrete else 0.38)
			material.set_shader_parameter("panel_detail", 0.36 if status or hazard else 1.0)
			material.set_shader_parameter("panel_scale", 0.23 if concrete else 0.52)
			material.set_shader_parameter("wear_amount", 0.69)
			finishes[key] = material
		piece.material_override = finishes[key]

func _ready() -> void:
	var we := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we and we.environment.sky and we.environment.sky.sky_material is ProceduralSkyMaterial:
		Gfx.textured_sky(we.environment.sky, name == "FlightEnvironment")
	apply_surfaces(self)
	preload("res://scripts/model_detail.gd").environment(self)


static func apply_surfaces(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var old := mi.material_override as StandardMaterial3D
		if old:
			if node.name in ["BodyA", "BodyB", "Core"]:
				mi.material_override = Gfx.planet_mat(old.albedo_color, old.albedo_color.lightened(0.18))
			elif "Terrain" in str(node.get_path()) or node.name == "Ground":
				mi.material_override = Gfx.terrain_mat(old.albedo_color, not mi.mesh is PlaneMesh)
	# Old cylinder stripes are replaced by the sphere shader.
	if str(node.name).begins_with("Band") and node is MeshInstance3D:
		node.hide()
	for child in node.get_children(): apply_surfaces(child)
