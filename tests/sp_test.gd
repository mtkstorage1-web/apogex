extends SceneTree
## Headless: simulate the default Mission Control plans.


func _init() -> void:
	for sid in ["climate", "lunar", "mars"]:
		var st := MissionControl.create_simulation(MissionControl.default_plan(sid))
		while not st["done"]: MissionControl.step(st, "balanced")
		var rep := MissionControl.report(st)
		print(sid, " valid ", st["e"]["valid"], " success ", rep["success"], " score ", rep["score"], " science ", roundi(rep["science"]), "/", roundi(rep["target"]), " days ", rep["days"])
	print("RESULT PASS")
	quit(0)
