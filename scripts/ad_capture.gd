## Deterministic Movie Maker driver: --write-movie artifacts/ad/raw.avi --fixed-fps 30 -- --ad
## Uses existing paid construction, cinematics and flag interaction; time jumps are edit cuts.
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
	seed(47)
	var intro := title("T-MINUS", "BUILD. LAUNCH. CAPTURE. RETURN.")
	await frames(30)
	intro.queue_free()
	g.show_select()
	await frames(15)
	g.opts["seed"] = 47
	g.new_sim()
	for p in g.sim.parts: g.sim.buy_part(p["id"])
	g.start_match()
	g._end_cine("intro")
	var s: Sim = g.sim
	var a = g.world
	s.shop_open = false
	s.auto_build["enabled"] = true
	a.pad_stage = "build"
	g.begin_cine("build", 15.8)
	mark("assembly")
	await frames(90, func():
		s.auto_assemble(15.8 / 90.0)
		g.cine["t"] = minf(15.7, float(g.cine["t"]) + 15.8 / 90.0)
	)
	g._end_cine("build")
	await frames(21, func(): g.cine["t"] = minf(6.4, float(g.cine["t"]) + 6.5 / 21.0))
	g._end_cine("outfit")
	g.begin_cine("erect", 7.0)
	await frames(21, func(): g.cine["t"] = minf(6.9, float(g.cine["t"]) + 7.0 / 21.0))
	g._end_cine("erect")
	await frames(18, func(): g.cine["t"] = minf(6.9, float(g.cine["t"]) + 7.0 / 18.0))
	g._end_cine("boosters")
	g.chosen_route = "sheltered"
	g.launch()
	mark("launch")
	await frames(120, func():
		if g.mode == "cine": g.cine["t"] = float(g.cine["t"]) + PlanetA.LAUNCH_DURATION / 120.0 - 1.0 / 30.0
	)
	if not g.world is Flight: g._end_cine("launch")
	s.selected = 2
	g.lmb = true
	mark("flight")
	await frames(60)
	g.lmb = false
	s.flight_time = s.flight_duration()
	await frames(3)
	g._end_cine("landing")
	await frames(9)
	s.selected = 3
	var b = g.world
	var f = s.flags[6]
	var ra: Actor = b.actor(3)
	ra.position = f["position"] + Vector3(0, 0, 2.6)
	g.yaw = 0.0
	g.pitch = -0.3
	g.lmb = true
	mark("capture")
	await frames(90, func(): b.tick(0.04))
	g.lmb = false
	print("AD captured=", s.carried_flag(0, 3) != null)
	await frames(15)
	ra.position = PlanetB.HATCH + Vector3(0, 0, -1)
	await tap(KEY_E)
	print("AD onboard=", s.flag_counts(0)["onboard"])
	await tap(KEY_T)
	mark("return")
	await frames(45)
	s.flight_time = s.flight_duration()
	await frames(3)
	g._end_cine("docking")
	g.world.actor(s.selected).position = Sim.DELIVERY_PAD + Vector3(0, 0, -2)
	await frames(21)
	title("PLAY NOW", "T-MINUS  /  THE FIRST FRONTIER")
	mark("endcard")
	await frames(100)
	mark("complete")
	g.get_tree().quit()
