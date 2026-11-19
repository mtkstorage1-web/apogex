extends SceneTree

const BuilderScript := preload("res://scripts/ship_builder.gd")

var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
	else:
		print("ok: ", message)

func _initialize() -> void:
	call_deferred("run")

func _new_match():
	var g = load("res://main.tscn").instantiate()
	root.add_child(g)
	g.set_process(false)
	g.start_match()
	g._end_cine("intro")
	return g

func _finish(g) -> void:
	if is_instance_valid(g):
		g.queue_free()
	await process_frame
	print("ship_builder_runtime_test: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)

func run() -> void:
	var g = _new_match()
	await process_frame

	# a) Opening cleanly with a valid Sim.
	g.sim.credits = 100000
	g.open_ship_builder()
	var builder = g.picker
	check(is_instance_valid(builder) and builder.get_script() == BuilderScript, "builder opens as picker")
	if not is_instance_valid(builder):
		await _finish(g)
		return
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "builder releases mouse")
	check(builder.current_step_index == 0, "starts at first step")
	check(builder.selected_slots.is_empty(), "no slots selected on open")
	check(is_instance_valid(builder.ship_container) and is_instance_valid(builder.preview_view), "preview stage built")
	var quick: Button = builder.find_child("QuickBuildButton", true, false)
	check(quick != null and quick.visible, "quick build button visible")
	check(quick != null and quick.text == "CONFIRM ALL 12 SLOTS (QUICK BUILD)", "quick build caption for 12 slots")
	check(builder._purchase_button.disabled, "purchase disabled before all slots picked")

	# b) Selecting individual slots updates preview, cost and step.
	var first: String = BuilderScript.BUILD_ORDER[0]
	var cost_before: int = builder._draft_charge()
	var credits_before: int = g.sim.credits
	builder._select_variant(first, "bulwark")
	check(builder.draft[first] == "bulwark" and builder.selected_slots.has(first), "selection stored in draft")
	check(builder._modules.has(first) and builder._modules[first].get_parent() == builder.ship_container, "selected module added to preview")
	var expected := 0
	for slot in builder.draft:
		expected += int(g.sim.variant_charge(slot, builder.draft[slot]))
	check(builder._draft_charge() == expected, "draft charge matches sim quotes")
	check(builder._credits.text == "Draft %d CR / %d CR" % [expected, g.sim.credits], "cost label updates")
	check(builder.current_step_index == 1, "advances to next unselected step")
	check(g.sim.credits == credits_before, "selection does not spend credits")
	check(quick.text == "CONFIRM REMAINING 11 SLOTS (QUICK BUILD)", "quick build caption counts remaining")
	builder._select_variant(BuilderScript.BUILD_ORDER[5], "halo")
	check(not builder.selected_slots.has(BuilderScript.BUILD_ORDER[5]), "off-step selection ignored")
	builder.close()
	await process_frame
	check(g.picker == null, "close clears picker")

	# c1) Quick build blocked when credits are insufficient.
	g.sim.credits = 0
	g.open_ship_builder()
	builder = g.picker
	var loadout_before: Dictionary = g.sim.loadout.duplicate(true)
	builder.draft.clear()
	for slot in BuilderScript.BUILD_ORDER:
		builder.draft[slot] = "bulwark"
	builder._quick_build()
	var needs_credits: bool = builder._draft_charge() > 0
	check(needs_credits, "bulwark blueprint costs credits")
	check(is_instance_valid(builder) and not builder._closing and g.picker == builder, "builder stays open when broke")
	check(builder._purchase_status.visible and builder._purchase_status.text.begins_with("Not enough credits"), "shortfall message shown")
	check(g.sim.credits == 0 and g.sim.loadout == loadout_before, "no purchase when broke")
	check(builder.selected_slots.size() == 12, "quick build filled all slots")
	builder.close()
	await process_frame

	# c2) Quick build purchases all 12 and closes when affordable.
	g.sim.credits = 100000
	g.open_ship_builder()
	builder = g.picker
	builder.find_child("QuickBuildButton", true, false).pressed.emit()
	await process_frame
	check(g.picker == null, "builder closes after quick build")
	for slot in BuilderScript.BUILD_ORDER:
		check(g.sim.slot_confirmed(slot), "slot %s purchased" % slot)
	check(g.sim.credits < 100000, "credits spent")

	await _finish(g)
