## Shop modal: simulation and movement pause through main's play-mode guard.
extends Control

var g
var slot := ""
var index := 0
var cards: HBoxContainer
var heading: Label
var title_name: Label
var credits_chip: PanelContainer
var summary: Label
var confirm: Button
var preview_root: Node3D
var preview_view: SubViewportContainer
var preview_camera: Camera3D
var families := ShipCatalog.FAMILIES.keys()

func setup(main, id: String) -> void:
	g = main
	slot = id
	index = families.find(g.sim.loadout.get(slot, "kestrel"))
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UI.theme()
	var shade := ColorRect.new()
	shade.color = UI.BG_DEEP
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var glow := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0.55, 0.32, 0.18, 0.28))
	grad.set_color(1, Color(0, 0, 0, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.0)
	gt.fill_to = Vector2(0.5, 0.9)
	gt.width = 512
	gt.height = 512
	glow.texture = gt
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(glow)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + edge, 24)
	add_child(margin)
	var outer := UI.vbox(12)
	margin.add_child(outer)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(scroll)
	var column := UI.vbox(14)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	var title_row := UI.hbox(12)
	column.add_child(title_row)
	var title_col := UI.vbox(2)
	title_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title_col)
	title_col.add_child(UI.label("APOGEX · PARTS SHOP", 12, UI.ACCENT))
	title_name = UI.label("", 30)
	title_col.add_child(title_name)
	credits_chip = PanelContainer.new()
	title_row.add_child(credits_chip)
	heading = UI.label("", 18, UI.ACCENT)
	credits_chip.add_child(heading)
	var line := ColorRect.new()
	line.color = Color(UI.ACCENT.r, UI.ACCENT.g, UI.ACCENT.b, 0.35)
	line.custom_minimum_size = Vector2(0, 1)
	column.add_child(line)
	summary = UI.wrapped_label("", 12, UI.MUTED)
	column.add_child(summary)
	cards = UI.hbox(14)
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(cards)
	var preview := preload("res://scripts/shop_preview.gd").create(column)
	preview_root = preview["root"]
	preview_view = preview["view"]
	preview_camera = preview["camera"]
	preview_view.resized.connect(_fit_preview)
	confirm = UI.button("", buy, true, 0, 58)
	confirm.alignment = HORIZONTAL_ALIGNMENT_CENTER
	confirm.add_theme_font_size_override("font_size", 18)
	outer.add_child(confirm)
	var close_row := UI.hbox(12)
	close_row.add_child(UI.label("A / D  ·  browse     E / ENTER  ·  confirm     ESC  ·  close", 12, UI.DIM))
	close_row.add_child(UI.spacer(0, 0, true))
	close_row.add_child(UI.button("CLOSE", close, false, 120, 38))
	outer.add_child(close_row)
	refresh()

func refresh() -> void:
	var sim: Sim = g.sim
	var current := ShipCatalog.variant(slot, str(sim.loadout.get(slot, "kestrel")))
	var bought := sim.slot_confirmed(slot)
	summary.text = UI.loadout_summary(sim)
	title_name.text = slot.to_upper()
	heading.text = "%s CR" % _thousands(sim.credits)
	credits_chip.add_theme_stylebox_override("panel", UI.style(Color(UI.ACCENT.r, UI.ACCENT.g, UI.ACCENT.b, 0.12), Color(UI.ACCENT.r, UI.ACCENT.g, UI.ACCENT.b, 0.5), 20, 18))
	for child in cards.get_children():
		cards.remove_child(child)
		child.queue_free()
	for i in families.size():
		var family: String = families[i]
		var v := ShipCatalog.variant(slot, family)
		var charge := int(v["price"]) - (int(current["price"]) if bought else 0)
		var accent := Color(ShipCatalog.FAMILIES[family]["color"])
		var panel := UI.panel(Vector2(0, 250))
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.add_theme_stylebox_override("panel", UI.card_style(accent, i == index))
		cards.add_child(panel)
		var col := UI.vbox(8)
		panel.add_child(col)
		if i == index: col.add_child(UI.label("SELECTED", 10, accent))
		col.add_child(UI.wrapped_label(str(v["name"]).to_upper(), 16, accent if i == index else UI.TEXT))
		var price_row := UI.hbox(8)
		price_row.add_child(UI.label(_thousands(int(v["price"])), 24))
		price_row.add_child(UI.label("CR", 11, UI.DIM))
		col.add_child(price_row)
		col.add_child(UI.label("charge %+d CR" % charge, 12, UI.GOOD if charge <= 0 else (UI.MUTED if charge <= sim.credits else UI.BAD)))
		col.add_child(UI.wrapped_label("+  " + v["advantage"], 12, UI.GOOD))
		col.add_child(UI.wrapped_label("−  " + v["drawback"], 12, UI.BAD))
		var deltas := HFlowContainer.new()
		deltas.add_theme_constant_override("h_separation", 6)
		deltas.add_theme_constant_override("v_separation", 6)
		var keys := v.keys()
		for key in current:
			if not keys.has(key): keys.append(key)
		for key in keys:
			if key in ["price", "name", "advantage", "drawback"]: continue
			var delta := float(v.get(key, 0)) - float(current.get(key, 0))
			if is_zero_approx(delta): continue
			var labels := {"mass_kg": "mass kg", "fuel_kg": "fuel kg", "thrust_kn": "thrust kN", "load_kw": "draw kW", "gen_kw": "generation kW", "cargo_flags": "cargo", "battery_kwh": "battery kWh", "exhaust_mult": "exhaust", "armor": "damage taken", "turret_damage_mult": "turret", "scan_mult": "scan", "handling": "handling", "radiator": "cooling", "life": "life resilience"}
			var percent: bool = key in ["exhaust_mult", "armor", "turret_damage_mult", "scan_mult", "handling", "radiator", "life"]
			var text := ("%s %+.0f%%" % [labels.get(key, key), delta * 100.0]) if percent else ("%s %+.2f" % [labels.get(key, key), delta])
			var good: bool = delta > 0.0
			if key in ["mass_kg", "load_kw", "armor", "exhaust_mult"]: good = delta < 0.0
			deltas.add_child(UI.chip(text, UI.GOOD if good else UI.BAD))
		if deltas.get_child_count() == 0: deltas.add_child(UI.chip("unchanged", UI.MUTED))
		col.add_child(deltas)
		var button := UI.button("PREVIEWING" if i == index else ("PREVIEW" if charge <= sim.credits else "UNAFFORDABLE"), highlight.bind(i), false, 0, 34)
		button.alignment = HORIZONTAL_ALIGNMENT_CENTER
		# Unaffordable cards remain inspectable with the browse keys.
		button.tooltip_text = "Browse this variant; confirm below to purchase."
		var spacer := Control.new()
		spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
		col.add_child(spacer)
		col.add_child(button)
	var selected := ShipCatalog.variant(slot, families[index])
	var due := int(selected["price"]) - (int(current["price"]) if bought else 0)
	confirm.text = ("SWAP TO " if bought else "BUY ") + "%s  ·  %s CR" % [str(selected["name"]).to_upper(), ("%+d" % due) if bought else _thousands(due)]
	confirm.disabled = due > sim.credits
	for child in preview_root.get_children():
		preview_root.remove_child(child)
		child.queue_free()
	preview_root.add_child(ShipModel.preview(slot, families[index], Color(ShipCatalog.FAMILIES[families[index]]["color"]), 4.0))
	_fit_preview()

## Fit the centred AABB through a full yaw rotation, including narrow/tall parts.
func _fit_preview() -> void:
	preload("res://scripts/shop_preview.gd").fit(preview_root, preview_view, preview_camera)
	preview_view.custom_minimum_size.y = maxf(180, get_viewport_rect().size.y * 0.24)

func _thousands(n: int) -> String:
	var t := str(absi(n))
	var out := ""
	for k in t.length():
		if k > 0 and (t.length() - k) % 3 == 0: out += ","
		out += t[k]
	return ("-" if n < 0 else "") + out

func highlight(i: int) -> void:
	index = wrapi(i, 0, families.size())
	if g != null: g.sfx("ui_click", -10)
	refresh()

func buy() -> void:
	if g.sim.set_variant(slot, families[index]):
		g.sfx("ui_buy", -6)
		g.world.refresh_ship_loadout()
		g.hud.toast("Selected " + ShipCatalog.variant(slot, families[index])["name"])
		g._refresh_hud()
		refresh()
	else:
		g.sfx("ui_error", -6)
		g.hud.toast("Not enough credits, or assembly has started.")

func close() -> void:
	g.picker = null
	g.pressed_now.clear()
	g.capture_mouse(true)
	queue_free()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE, KEY_Q: close()
			KEY_A, KEY_LEFT: highlight(index - 1)
			KEY_D, KEY_RIGHT: highlight(index + 1)
			KEY_E, KEY_ENTER: buy()
		get_viewport().set_input_as_handled()

func _process(dt: float) -> void:
	preview_root.rotation.y += dt * 0.7
