## Mission Design & Science Simulator UI and telemetry chart extracted from main.gd.
class_name MissionControlUI
extends RefCounted


class SimChart extends Control:
	var history: Array = []
	var days := 60
	var events: Array = []

	func _draw() -> void:
		var r := Rect2(Vector2(40, 10), size - Vector2(50, 36))
		draw_rect(r, Color(1, 1, 1, 0.04))
		for i in 5:
			var y := r.position.y + r.size.y * i / 4.0
			draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), Color(1, 1, 1, 0.07))
		for ev in events:
			var x: float = r.position.x + r.size.x * float(ev["day"]) / maxf(1.0, days)
			draw_rect(Rect2(x, r.position.y, r.size.x * float(ev["duration"]) / maxf(1.0, days), r.size.y), Color(0.93, 0.49, 0.55, 0.12))
		var series := [["energy", Color("#f7ce59")], ["buffer", Color("#b7a0f3")], ["health", Color("#9cdeb1")], ["science", Color("#eaa665")]]
		var max_sci := 1.0
		for h in history:
			max_sci = maxf(max_sci, h["science"])
		for s in series:
			var pts := PackedVector2Array()
			for h in history:
				var v: float = h[s[0]]
				if s[0] == "health": v /= 100.0
				if s[0] == "science": v /= max_sci
				pts.append(Vector2(r.position.x + r.size.x * float(h["day"]) / maxf(1.0, days), r.end.y - r.size.y * clampf(v, 0.0, 1.0)))
			if pts.size() > 1:
				draw_polyline(pts, s[1], 2.0, true)
		var font := UI.font(true)
		var lx := r.position.x
		for s in series:
			draw_string(font, Vector2(lx, size.y - 6), String(s[0]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, s[1])
			lx += 90
		draw_string(font, Vector2(r.end.x - 80, size.y - 6), "DAY %d/%d" % [history.size(), days], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.6))


static func show(g) -> void:
	if g.mc_plan.is_empty():
		g.mc_plan = MissionControl.default_plan("climate")
	render(g)


static func set_param(g, key: String, value) -> void:
	if key == "scenario":
		g.mc_plan = MissionControl.default_plan(value)
	elif key == "payload":
		var p: Array = g.mc_plan["payload"]
		if p.has(value): p.erase(value)
		else: p.append(value)
	else:
		g.mc_plan[key] = value
	g.mc_state = {}
	render(g)


static func add_param(g, key: String, delta: float, lo: float, hi: float) -> void:
	g.mc_plan[key] = clampf(float(g.mc_plan[key]) + delta, lo, hi)
	if key == "days": g.mc_plan[key] = int(g.mc_plan[key])
	g.mc_state = {}
	render(g)


static func set_policy(g, p: String) -> void:
	g.mc_policy = p
	render(g)


static func run_sim(g, days: int) -> void:
	if g.mc_state.is_empty():
		g.mc_state = MissionControl.create_simulation(g.mc_plan)
	var n := 0
	while not g.mc_state["done"] and (days <= 0 or n < days):
		MissionControl.step(g.mc_state, g.mc_policy)
		n += 1
	render(g)


static func reset_sim(g) -> void:
	g.mc_state = {}
	render(g)


static func _row(g, v: VBoxContainer, title: String, key: String, list: Array) -> void:
	v.add_child(UI.label(title, 11, UI.ACCENT))
	var h := HFlowContainer.new()
	h.add_theme_constant_override("h_separation", 6)
	h.add_theme_constant_override("v_separation", 6)
	for x in list:
		var on: bool = g.mc_plan["payload"].has(x["id"]) if key == "payload" else g.mc_plan[key] == x["id"]
		h.add_child(UI.toggle(x["name"], on, g._mc_set.bind(key, x["id"]), 150))
	v.add_child(h)


static func render(g) -> void:
	var e := MissionControl.evaluate(g.mc_plan)
	var v: VBoxContainer = g._sp_screen("MISSION CONTROL / SCIENCE SIMULATOR")
	v.add_child(UI.label("MISSION DESIGN & SCIENCE SIMULATOR", 12, UI.ACCENT))
	v.add_child(g._mint_heading("DESIGN, SIMULATE, ", "COMPARE.", 46))
	var sc: Dictionary = e["scenario"]
	var d := UI.label("%s — %s. %s" % [sc["name"], sc["subtitle"], sc["description"]], 13, UI.MUTED)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(1300, 0)
	v.add_child(d)
	var row := UI.hbox(24)
	v.add_child(row)
	var form := UI.vbox(6)
	form.custom_minimum_size = Vector2(760, 0)
	row.add_child(form)
	var scen := []
	for s in MissionControl.SCENARIOS:
		scen.append({"id": s["id"], "name": s["subtitle"]})
	_row(g, form, "MISSION OBJECTIVE", "scenario", scen)
	var diffs := []
	for k in MissionControl.DIFFICULTIES:
		diffs.append({"id": k, "name": MissionControl.DIFFICULTIES[k]["name"]})
	_row(g, form, "DIFFICULTY", "difficulty", diffs)
	_row(g, form, "SPACECRAFT BUS", "bus", MissionControl.BUSES)
	_row(g, form, "SOLAR ARRAY", "array", MissionControl.ARRAYS)
	_row(g, form, "BATTERY", "battery", MissionControl.BATTERIES)
	_row(g, form, "RADIO", "radio", MissionControl.RADIOS)
	_row(g, form, "PAYLOAD (MULTI-SELECT)", "payload", MissionControl.INSTRUMENTS)
	_row(g, form, "ORBIT", "orbit", MissionControl.ORBITS)
	_row(g, form, "LAUNCHER", "launcher", MissionControl.LAUNCHERS)
	var nums := UI.hbox(16)
	for f in [["PROPELLANT", "fuel", 5.0, 10.0, 250.0, "%d kg"], ["DAYS", "days", 5.0, 15.0, 180.0, "%d"], ["OBSERVATION HOURS/DAY", "hours", 1.0, 1.0, 16.0, "%d h"]]:
		var nv := UI.vbox(2)
		nv.add_child(UI.label(f[0], 11, UI.ACCENT))
		var nh := UI.hbox(4)
		nh.add_child(UI.toggle("−", false, g._mc_add.bind(f[1], -f[2], f[3], f[4]), 34))
		nh.add_child(UI.label(f[5] % int(g.mc_plan[f[1]]), 16, UI.TEXT))
		nh.add_child(UI.toggle("+", false, g._mc_add.bind(f[1], f[2], f[3], f[4]), 34))
		nv.add_child(nh)
		nums.add_child(nv)
	form.add_child(nums)
	var side := UI.vbox(8)
	side.custom_minimum_size = Vector2(520, 0)
	row.add_child(side)
	var rp := UI.panel(Vector2(520, 0), Color("#12202a"))
	side.add_child(rp)
	var rv := UI.vbox(4)
	rp.add_child(rv)
	rv.add_child(UI.label("GO FOR SIMULATION" if e["valid"] else "NO-GO", 22, UI.GOOD if e["valid"] else UI.BAD))
	for line in [["Launch mass / capacity", "%d / %d kg" % [roundi(e["mass"]), roundi(e["capacity"])]], ["Cost / budget", "%.1f / %.1f M" % [e["cost"], e["budget"]]],
			["Generation / load", "%d / %d W" % [roundi(e["generated"]), roundi(e["load"])]], ["Eclipse need / battery", "%d / %d Wh" % [roundi(e["eclipse_required"]), roundi(e["battery"]["capacity"])]],
			["Data / downlink per day", "%.2f / %.2f GB" % [e["data_daily"], e["downlink_daily"]]], ["Propellant need / loaded", "%.1f / %.1f kg" % [e["fuel_required"], g.mc_plan["fuel"]]],
			["Ideal science / target", "%d / %d" % [roundi(e["science_daily"] * g.mc_plan["days"]), roundi(e["target"])]]]:
		var h := UI.hbox(6)
		var a := UI.label(line[0], 12, UI.MUTED)
		a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(a)
		h.add_child(UI.label(line[1], 12, UI.TEXT))
		rv.add_child(h)
	for c in e["checks"]:
		var col: Color = UI.BAD if c["level"] == "error" else (UI.WARN if c["level"] == "warn" else UI.MUTED)
		var l := UI.label(("✕ " if c["level"] == "error" else "! ") + c["title"] + " — " + c["why"] + " " + c["fix"], 11, col)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(480, 0)
		rv.add_child(l)
	v.add_child(UI.label("OPERATIONS POLICY (APPLIES TO THE NEXT DAYS YOU RUN)", 11, UI.ACCENT))
	var ph := UI.hbox(8)
	for k in MissionControl.POLICIES:
		ph.add_child(UI.toggle(MissionControl.POLICIES[k], g.mc_policy == k, g._mc_policy.bind(k), 140))
	ph.add_child(UI.spacer(0, 20))
	var run := UI.button("RUN TO END   ▸▸", g._mc_run.bind(0), true, 200, 40)
	run.disabled = not e["valid"]
	ph.add_child(run)
	var step := UI.button("STEP 10 DAYS", g._mc_run.bind(10), false, 160, 40)
	step.disabled = not e["valid"]
	ph.add_child(step)
	ph.add_child(UI.button("RESET", g._mc_reset, false, 100, 40))
	v.add_child(ph)
	if not g.mc_state.is_empty():
		var chart := SimChart.new()
		chart.custom_minimum_size = Vector2(1300, 220)
		chart.history = g.mc_state["history"]
		chart.days = g.mc_plan["days"]
		chart.events = g.mc_state["events"]
		v.add_child(chart)
		var last = g.mc_state["history"][-1] if g.mc_state["history"].size() > 0 else null
		if last != null:
			v.add_child(UI.label("DAY %d · energy %d%% · buffer %d%% · health %d%% · fuel %.1f kg · science %d / %d%s" % [last["day"], roundi(last["energy"] * 100), roundi(last["buffer"] * 100), roundi(last["health"]), last["fuel"], roundi(last["science"]), roundi(e["target"]), ("  · " + ", ".join(last["events"])) if last["events"].size() > 0 else ""], 13, UI.TEXT))
		if g.mc_state["done"]:
			var rep := MissionControl.report(g.mc_state)
			v.add_child(g._mint_heading("MISSION %s · " % ("SUCCESS" if rep["success"] else "REVIEW"), "%d POINTS" % rep["score"], 34))
			var cats := UI.hbox(30)
			for k in rep["categories"]:
				var cv := UI.vbox(0)
				cv.add_child(UI.label(str(rep["categories"][k]), 24, UI.ACCENT))
				cv.add_child(UI.label(String(k).to_upper(), 10, UI.MUTED))
				cats.add_child(cv)
			v.add_child(cats)
			for r in rep["reasons"]:
				var l := UI.label("%s — %s %s" % [r["title"], r["detail"], r["tip"]], 13, UI.TEXT)
				l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				l.custom_minimum_size = Vector2(1300, 0)
				v.add_child(l)
			for ev in rep["events"]:
				v.add_child(UI.label("Day %d · %s — %s" % [ev["day"], ev["title"], ev["detail"]], 12, UI.MUTED))
	v.add_child(UI.spacer(30))
