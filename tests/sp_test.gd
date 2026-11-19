extends SceneTree
## Headless: campaign mission 01 & 02 played by rule calls; Mission Control default plans simulated.
func _play(id: String) -> Dictionary:
	var c := Campaign.new(id, Campaign.DEFAULT_DESIGN)
	var ctx := {"alignment": 50.0, "closure": 30.0, "calibration": 50.0, "at_telescope": true, "at_airlock": true}
	var guard := 0
	while not c.terminal() and guard < 200000:
		guard += 1
		if c.activity == null:
			for a in c.objectives():
				if a["id"] == "wait": break
				if a["id"] == "observe" and c.observing: continue
				if a["id"] == "optional": continue
				var r := c.start_action(a["id"], a["room"], ctx)
				if r["ok"]: break
		c.tick(0.25)
	return c.report()
func _init() -> void:
	var fails := 0
	for d in [Campaign.DEFAULT_DESIGN, {"battery": "compact", "array": "standard", "instrument": "spectrometer", "radio": "highgain"}]:
		var e := Campaign.evaluate_design(d)
		print("design ", d, " mass ", e["mass"], " cost ", e["cost"], " valid ", e["valid"], " ", e["errors"])
	for id in ["orbital", "telescope"]:
		var r := _play(id)
		print(id, " success ", r["success"], " score ", r["score"], " science ", snappedf(r["science"], 0.1), " min batt ", snappedf(r["minimum_battery"], 0.1), "% minutes ", snappedf(r["minutes"], 0.1))
		if not r["success"]: fails += 1
	for sid in ["climate", "lunar", "mars"]:
		var st := MissionControl.create_simulation(MissionControl.default_plan(sid))
		while not st["done"]: MissionControl.step(st, "balanced")
		var rep := MissionControl.report(st)
		print(sid, " valid ", st["e"]["valid"], " success ", rep["success"], " score ", rep["score"], " science ", roundi(rep["science"]), "/", roundi(rep["target"]), " days ", rep["days"])
	print("RESULT ", "PASS" if fails == 0 else "FAIL")
	quit(fails)
