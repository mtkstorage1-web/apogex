extends SceneTree

# Headless verification test for FlagsmithManager (Toggle Wars Hackathon)

func _init() -> void:
	var script := load("res://scripts/flagsmith_manager.gd")
	assert(script != null, "flagsmith_manager.gd should load")

	# 1. Deterministic fallback bucketing
	var variants := ["standard", "fast_blitz", "high_risk_double"]
	var v1: String = script.pick_deterministic_variant("apogex_judge_01", "exp_extraction_balance", variants)
	var v2: String = script.pick_deterministic_variant("apogex_judge_01", "exp_extraction_balance", variants)
	assert(v1 == v2, "Deterministic variant must be stable for the same identity")
	assert(variants.has(v1), "Variant must be one of the defined options")

	# 2. Instance lifecycle & Flagsmith Cloud JSON payload parsing
	var mgr: Node = script.new()
	mgr.identity = "apogex_test_runner"
	mgr.flags = mgr._default_flags_for_identity(mgr.identity)
	mgr.apply_flagsmith_payload({
		"flags": [
			{"feature": {"name": "exp_extraction_balance"}, "enabled": true, "feature_state_value": "high_risk_double"},
			{"feature": {"name": "exp_combat_pacing"}, "enabled": true, "feature_state_value": "turbo_clash"},
			{"feature": {"name": "feature_moon_low_gravity"}, "enabled": true, "feature_state_value": null},
		]
	})

	var mods: Dictionary = mgr.get_modifiers()
	assert(mods["extraction_variant"] == "high_risk_double", "Expected high_risk_double")
	assert(is_equal_approx(mods["score_multiplier"], 2.0), "Expected 2.0 score multiplier")
	assert(mods["combat_variant"] == "turbo_clash", "Expected turbo_clash")
	assert(mods["moon_low_gravity"] == true, "Expected moon_low_gravity enabled")

	# 3. Local overrides & conversion telemetry
	mgr.set_local_override("exp_extraction_balance", true, "fast_blitz")
	assert(is_equal_approx(mgr.get_modifiers()["capture_rate"], 1.45), "Expected 1.45 capture_rate")

	mgr.telemetry = {}
	mgr.track_event("match_started")
	mgr.track_event("flag_delivered", {"count": 3})
	mgr.track_event("match_ended", {"won": true})

	var snap: Dictionary = mgr.get_snapshot()
	assert(int(snap["traits"]["matches_played"]) >= 1, "matches_played incremented")
	assert(int(snap["traits"]["flags_delivered"]) >= 3, "flags_delivered incremented")
	assert(int(snap["traits"]["matches_won"]) >= 1, "matches_won incremented")

	var found_bucket := false
	for b in snap["telemetry"]:
		if b["experiment"] == "exp_extraction_balance" and b["variant"] == "fast_blitz":
			assert(int(b["starts"]) == 1 and int(b["deliveries"]) == 3 and int(b["wins"]) == 1)
			found_bucket = true
	assert(found_bucket, "Expected fast_blitz telemetry bucket")

	print("PASS: FlagsmithManager deterministic bucketing, Cloud payload parsing, overrides, and A/B telemetry")
	mgr.free()
	quit(0)
