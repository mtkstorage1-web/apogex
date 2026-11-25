extends SceneTree
## Run with Godot --headless --path . --script tests/run_empire_suite.gd.

const TESTS := [
	"tminus_net", "empire_sim", "arena_clash_sim", "empire_integration", "sim", "crew_match",
	"crew_match_runtime", "arena_clash_runtime", "pad_sequence_runtime", "hud_style", "shop_picker_runtime", "ship_builder_runtime",
]

# Run the standalone suites against this SceneTree. All test bodies, assertions,
# deferred calls and frame waits stay the same. Capture each suite's quit code.
const HARNESS := """
var tree: SceneTree
var result := -1
var root: Window:
	get: return tree.root
var process_frame: Signal:
	get: return tree.process_frame
var multiplayer_poll: bool:
	get: return tree.multiplayer_poll
	set(value): tree.multiplayer_poll = value

func quit(code := 0) -> void:
	result = code

func create_timer(seconds: float) -> SceneTreeTimer:
	return tree.create_timer(seconds)

func set_multiplayer(api: MultiplayerAPI, at: NodePath) -> void:
	tree.set_multiplayer(api, at)
"""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var failures := 0
	var original_children := root.get_children()
	var original_size := root.size
	var original_content_scale := root.content_scale_size
	var original_poll := multiplayer_poll
	for test: String in TESTS:
		print("\nSUITE START %s_test.gd" % test)
		var path := "res://tests/%s_test.gd" % test
		var file := FileAccess.get_file_as_string(path)
		var code := GDScript.new()
		code.resource_path = path + ".batched"
		code.source_code = file.replace("extends SceneTree", "extends RefCounted").replace(
			"func _init() -> void:", "func start() -> void:").replace(
			"func _initialize() -> void:", "func start() -> void:") + HARNESS
		var load_error := code.reload()
		var result := -1
		if load_error == OK:
			var suite: RefCounted = code.new()
			suite.tree = self
			suite.start.call_deferred()
			var deadline := Time.get_ticks_msec() + 180000
			while suite.result == -1 and Time.get_ticks_msec() < deadline:
				await process_frame
			result = suite.result
		else:
			printerr("Suite load error %s" % error_string(load_error))
		for child in root.get_children():
			if child not in original_children:
				var branch_path: NodePath = child.get_path()
				child.free()
				set_multiplayer(null, branch_path)
		await process_frame
		root.content_scale_size = original_content_scale
		root.size = original_size
		multiplayer_poll = original_poll
		Engine.time_scale = 1.0
		print("SUITE %s %s_test.gd (exit %d)" % ["PASS" if result == 0 else "FAIL", test, result])
		failures += int(result != 0)
	print("\nSUITE SUMMARY %d/%d passed" % [TESTS.size() - failures, TESTS.size()])
	quit(int(failures > 0))
