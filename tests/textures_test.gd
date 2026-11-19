extends SceneTree
var failures := 0
func _initialize() -> void:
	call_deferred("_run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func _run() -> void:
	var start := Time.get_ticks_usec()
	var textures := [ProcTex.ground_albedo(), ProcTex.ground_normal(), ProcTex.rock_albedo(), ProcTex.rock_normal(), ProcTex.metal_panel_normal(), ProcTex.noise("sky")]
	var setup_ms := (Time.get_ticks_usec() - start) / 1000.0
	check(setup_ms < 50.0, "Texture request setup must stay below 50 ms")
	check(ProcTex.ground_albedo(Color.RED) == ProcTex.ground_albedo(Color.BLUE), "Tint must share neutral texture")
	for t in textures:
		check(t.width == 512 and t.height == 512 and t.seamless and t.generate_mipmaps, "Texture dimensions/seamless/mips")
	check(ProcTex.ground_normal().as_normal_map and ProcTex.rock_normal().as_normal_map and ProcTex.metal_panel_normal().as_normal_map, "Normal generation")
	var mat := Gfx.terrain_mat(Color.RED)
	check(mat == Gfx.terrain_mat(Color.RED), "Ground material cached")
	check(mat.uv1_triplanar and mat.normal_enabled and is_equal_approx(mat.normal_scale, 0.6), "Ground triplanar normal setup")
	check(mat.texture_filter == BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC, "Anisotropic ground")
	check(Gfx.planet_mat(Color.RED, Color.BLUE) == Gfx.planet_mat(Color.RED, Color.BLUE), "Planet material cached")
	for level in ["Workshop", "PlanetA", "PlanetB", "Flight", "Universe"]:
		var scene: Node = load("res://scenes/levels/%sEnvironment.tscn" % level).instantiate()
		root.add_child(scene)
		var we := scene.get_node_or_null("WorldEnvironment") as WorldEnvironment
		if we:
			check(we.environment.sky.sky_material is ShaderMaterial, level + " textured sky")
			check(we.environment.sky.process_mode == Sky.PROCESS_MODE_AUTOMATIC and we.environment.sky.radiance_size == Sky.RADIANCE_SIZE_64, level + " cheap sky")
			check(we.environment.ssao_radius == 0.5 and is_equal_approx(we.environment.ssao_detail, 0.1), level + " SSAO preserved")
		if level == "Universe":
			check(scene.get_node("PlanetA/BodyA").material_override is ShaderMaterial, "BodyA shader")
			check(scene.get_node("PlanetB/BodyB").material_override is ShaderMaterial, "BodyB shader")
		scene.free()
	# Let background generators finish and inspect their output without blocking the main thread.
	for t in textures:
		while t.get_image() == null: await process_frame
		check(t.get_image() != null and t.get_image().has_mipmaps(), "Generated mipmapped image")
	print("textures_test: %d failures; texture request setup %.2f ms; six RGBA8 mip chains <= 8 MiB" % [failures, setup_ms])
	quit(1 if failures else 0)
