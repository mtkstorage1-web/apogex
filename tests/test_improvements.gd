@tool
extends McpTestSuite

## Editor-side McpTestSuite smoke test validating all modified scripts,
## bundled audio resources, and SceneTree test script loading.

func suite_name() -> String:
	return "improvements"


func test_modified_scripts_load_without_errors() -> void:
	var script_paths := [
		"res://scripts/sfx_gen.gd",
		"res://scripts/mission_control_ui.gd",
		"res://scripts/main.gd",
		"res://scripts/flight.gd",
		"res://scripts/planet_b.gd",
		"res://scripts/combat_fx.gd",
		"res://scripts/actor.gd",
		"res://scripts/ui.gd",
		"res://scripts/hud.gd",
		"res://scripts/ship_builder.gd",
		"res://scripts/ship_picker.gd",
		"res://tests/improvements_test.gd",
	]
	for path in script_paths:
		var res := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		assert_true(res is GDScript, "Script failed to load cleanly: " + path)


func test_bundled_audio_assets_load() -> void:
	var clips := [
		"shot_carbine", "shot_scatter", "shot_sidearm", "hitmarker", "capture_tick",
		"explosion", "hurt", "shield_recharge", "shield_hit", "shield_break",
		"reload_click", "reload_ratchet", "step_0", "step_1", "step_2", "step_3",
	]
	for clip in clips:
		var found := false
		for ext in ["ogg", "wav"]:
			var path := "res://assets/audio/%s.%s" % [clip, ext]
			if ResourceLoader.exists(path):
				var stream := ResourceLoader.load(path)
				assert_true(stream is AudioStream, "Audio asset invalid: " + path)
				found = true
				break
		assert_true(found, "Missing audio asset: " + clip)


func test_main_scene_instantiates() -> void:
	var packed := ResourceLoader.load("res://main.tscn") as PackedScene
	assert_true(packed != null, "main.tscn failed to load")
	var inst := packed.instantiate()
	assert_true(inst != null, "main.tscn failed to instantiate")
	track(inst)
