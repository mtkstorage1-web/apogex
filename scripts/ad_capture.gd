## Deterministic Movie Maker driver: --write-movie artifacts/ad/raw.avi --fixed-fps 30 -- --ad
## Captures the pad-to-Moon flight and entry into Arena Clash.
extends RefCounted
var g
var frame := 0

func frames(n: int, step: Callable = Callable()) -> void:
	for i in n:
		if step.is_valid(): step.call()
		await g.get_tree().process_frame
		frame += 1

func mark(label: String) -> void:
	print("AD ", label, " frame=", frame, " time=", frame / 30.0)

func tap(k: int) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = true
	Input.parse_input_event(e)
	await frames(2)
	e = e.duplicate()
	e.pressed = false
	Input.parse_input_event(e)
	await frames(2)

func title(text: String, subtitle: String) -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.layer = 30
	layer.transform = Transform2D(0.0, Vector2.ZERO).scaled(Vector2(1.2, 1.2))
	g.add_child(layer)
	var panel := ColorRect.new()
	panel.color = Color(0.025, 0.04, 0.06, 0.86)
	panel.position = Vector2(430, 280)
	panel.size = Vector2(740, 330)
	layer.add_child(panel)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 94)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(430, 325)
	label.size = Vector2(740, 120)
	layer.add_child(label)
	var sub := Label.new()
	sub.text = subtitle
	sub.add_theme_font_size_override("font_size", 24)
	sub.modulate = Color("eaa665")
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.position = Vector2(430, 475)
	sub.size = Vector2(740, 50)
	layer.add_child(sub)
	return layer

func run(main) -> void:
	g = main
	var intro := title("T-MINUS", "BUILD. BOARD. FLY. FIGHT.")
	await frames(30)
	intro.queue_free()
	LobbyPages.play_mode = "arena_clash"
	g.quick_deploy()
	mark("pad")
	var demo := Autotest.new()
	demo.g = g
	demo.dir = ProjectSettings.globalize_path("res://shots")
	if not await demo.fly_to("planet_c"):
		g.get_tree().quit(1)
		return
	await tap(KEY_E)
	mark("arena")
	await frames(120)
	title("PLAY NOW", "T-MINUS / ARENA CLASH")
	await frames(100)
	g.get_tree().quit()
