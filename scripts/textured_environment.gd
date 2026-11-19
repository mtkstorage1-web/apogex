## Runs once when an authored environment enters the tree; cached resources are shared.
extends Node3D

func _ready() -> void:
	var we := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we and we.environment.sky and we.environment.sky.sky_material is ProceduralSkyMaterial:
		Gfx.textured_sky(we.environment.sky, name == "FlightEnvironment")
	_apply(self)
	preload("res://scripts/model_detail.gd").environment(self)

func _apply(node: Node) -> void:
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
	for child in node.get_children(): _apply(child)
