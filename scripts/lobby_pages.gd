class_name LobbyPages
extends RefCounted
## Multiplayer-lobby tabs (PLAY / SHOP / LEADERBOARD / GUIDE / PROFILE) and the persisted player profile.
## main.gd owns navigation; this helper builds the page content and stores [profile] in settings.cfg.

const EMPIRE_HOME_LABEL := "16 VS 16 · PLANET A ALLIANCE VS PLANET B ALLIANCE"
const EMPIRE_LENGTH_LABELS := {"standard": "40M EMPIRE", "short": "15M QUICK", "classic": "14M CLASSIC"}

static func build_alliance_roster(local_squad: String) -> VBoxContainer:
	var stack := UI.vbox(4)
	for alliance: String in Sim.EmpireRules.ALLIANCE_SQUADS:
		var title := alliance.to_upper().replace("_", " ")
		var accent := UI.CYAN if alliance == "planet_a" else Color("#ff896e")
		stack.add_child(UI.label("%s ALLIANCE (16 PLAYERS · 4 SQUADS)" % title, 10, accent))
		var row := UI.hbox(6)
		for id: String in Sim.EmpireRules.ALLIANCE_SQUADS[alliance]:
			var caption := id.to_upper() + (" (YOU)" if id == local_squad else "")
			row.add_child(UI.label(caption, 10, Color.html(Sim.EMPIRE_COLORS[id])))
		stack.add_child(row)
	return stack


const TABS := ["PLAY", "SHOP", "LEADERBOARD", "GUIDE", "PROFILE"]
const PRACTICE_DIFFICULTY := "cadet"
const LOBBY_ACCENT := UI.HUD_CYAN
const LOBBY_ACTIVE := UI.HUD_YELLOW
const LOBBY_SURFACE := UI.HUD_GLASS
const LOBBY_EDGE := UI.HUD_EDGE
const CARD_SLIDE := Vector2(0, 8)
const RARITY_COLORS := {
	"COMMON": Color("#9ca3af"), "RARE": LOBBY_ACCENT,
	"EPIC": UI.VIOLET, "LEGENDARY": LOBBY_ACTIVE,
}
const TIERS := [
	["APEX", 3000], ["DIAMOND", 2400], ["PLATINUM", 1900], ["GOLD", 1300], ["SILVER", 700], ["BRONZE", 0],
]
const SKINS := [
	{"id": "crew_obsidian", "kind": "crew", "name": "Obsidian Recon", "rarity": "COMMON", "price": 0, "a": "#111827", "b": "#6b7280", "icon": "◆"},
	{"id": "crew_solar", "kind": "crew", "name": "Solar Vanguard", "rarity": "RARE", "price": 800, "a": "#f59e0b", "b": "#fde68a", "icon": "☀"},
	{"id": "crew_lunar", "kind": "crew", "name": "Lunar Ghost", "rarity": "RARE", "price": 800, "a": "#e5e7eb", "b": "#94a3b8", "icon": "☾"},
	{"id": "crew_hacker", "kind": "crew", "name": "Cyber Hacker", "rarity": "EPIC", "price": 1200, "a": "#22c55e", "b": "#052e16", "icon": "⌘"},
	{"id": "crew_apex", "kind": "crew", "name": "Apex Commander", "rarity": "LEGENDARY", "price": 2000, "a": "#facc15", "b": "#7c2d12", "icon": "★"},
	{"id": "crew_neon", "kind": "crew", "name": "Neon Striker", "rarity": "EPIC", "price": 1500, "a": "#ec4899", "b": "#06b6d4", "icon": "⚡"},
	{"id": "ship_stealth", "kind": "ship", "name": "Stealth Matte", "rarity": "COMMON", "price": 0, "a": "#1f2937", "b": "#374151", "icon": "▲"},
	{"id": "ship_chrome", "kind": "ship", "name": "Orbital Chrome", "rarity": "RARE", "price": 900, "a": "#e5e7eb", "b": "#60a5fa", "icon": "◈"},
	{"id": "ship_corsair", "kind": "ship", "name": "Crimson Corsair", "rarity": "EPIC", "price": 1400, "a": "#b91c1c", "b": "#111827", "icon": "✦"},
	{"id": "ship_void", "kind": "ship", "name": "Deep Void", "rarity": "LEGENDARY", "price": 2200, "a": "#312e81", "b": "#000000", "icon": "●"},
]
const RIVALS := [
	["NovaKnight", "Vanguard", 3412, 212], ["Kestrel-9", "Helios", 3188, 190], ["OrbitWitch", "Nebula", 2950, 171],
	["Zero.G", "Vanguard", 2610, 155], ["IronMoth", "Helios", 2395, 140], ["Halcyon", "Nebula", 2102, 126],
	["Rift Squad", "Squad", 1960, 118], ["Comet Crew", "Squad", 1744, 99], ["Mara_V", "Helios", 1512, 84],
]
const GUIDE := [
	["1 · MISSION LOOP", ["BUILD in the Workshop", "LAUNCH to orbit", "SPACE DOGFIGHT rival squads", "PLANET C · MOON: capture the flag", "RETURN home with the cargo"]],
	["2 · CREW ROLES & SPACE SPECIALS", [
		"PILOT — Ramming Overdrive: shielded boost that bursts through enemy hulls",
		"GUNNER — Lock-On Salvo: tags targets, then fires a homing volley",
		"ENGINEER — System Hack / EMP: disables enemy systems and shields",
		"SCIENCE — Gravity Pulse: pulls enemies together and slows them"]],
	["3 · PLANET C · MOON & SHIP DEFENSE", [
		"4-player enemy squads contest every flag zone",
		"Protect your ship: it is your respawn and your ride home",
		"PUBG-style controls: move, aim, fire, ability; CUSTOMIZE HUD in Settings"]],
]

static var apx := 2500
static var rp := 1450
static var owned: Array = ["crew_obsidian", "ship_stealth"]
static var equipped := {"crew": "crew_obsidian", "ship": "ship_stealth"}
static var play_mode := "arena_clash"
static var arena_preset := "standard"
static var arena_home := "planet_a"
const MAX_HISTORY := 15
static var stats := _default_stats()
static var history: Array = []


static func _default_stats() -> Dictionary:
	return {"matches_played": 0, "wins": 0, "losses": 0, "total_kos": 0, "total_flags": 0, "total_score": 0,
		"best_score": 0, "total_play_seconds": 0, "win_streak": 0, "best_streak": 0,
		"role_picks": {"PILOT": 0, "GUNNER": 0, "ENGINEER": 0, "SCIENCE": 0}}


static func favorite_role() -> String:
	var best := "—"
	var n := 0
	var rp_d: Dictionary = stats.get("role_picks", {})
	for k in rp_d.keys():
		if int(rp_d[k]) > n:
			n = int(rp_d[k])
			best = str(k)
	return best


## Records a finished match. entry: {mode, result, score, flags, kos, ship_hull, duration_s, role?, date?}
## Updates career stats, RP/APX, history (newest first, max 15) and saves when path is non-empty.
static func record_match(entry: Dictionary, path := "") -> Dictionary:
	var e := entry.duplicate()
	var mode_id := str(e.get("mode", "RANKED")).to_upper()
	var win := str(e.get("result", "DEFEAT")).to_upper() == "VICTORY"
	e["mode"] = mode_id
	e["result"] = "VICTORY" if win else "DEFEAT"
	var delta := 0
	if mode_id == "RANKED":
		delta = 35 if win else -15
	elif mode_id == "CASUAL" and win:
		delta = 15
	var new_rp := maxi(0, rp + delta)
	e["rp_delta"] = new_rp - rp
	rp = new_rp
	apx += 150 if win else 50
	e["score"] = int(e.get("score", 0))
	e["flags"] = int(e.get("flags", 0))
	e["kos"] = int(e.get("kos", 0))
	e["ship_hull"] = int(e.get("ship_hull", 0))
	e["duration_s"] = int(e.get("duration_s", 0))
	if not e.has("date"):
		e["date"] = Time.get_datetime_string_from_system(false, true)
	stats["matches_played"] = int(stats["matches_played"]) + 1
	stats["wins" if win else "losses"] = int(stats["wins" if win else "losses"]) + 1
	stats["total_kos"] = int(stats["total_kos"]) + e["kos"]
	stats["total_flags"] = int(stats["total_flags"]) + e["flags"]
	stats["total_score"] = int(stats["total_score"]) + e["score"]
	stats["best_score"] = maxi(int(stats["best_score"]), e["score"])
	stats["total_play_seconds"] = int(stats["total_play_seconds"]) + e["duration_s"]
	stats["win_streak"] = int(stats["win_streak"]) + 1 if win else 0
	stats["best_streak"] = maxi(int(stats["best_streak"]), int(stats["win_streak"]))
	var role := str(e.get("role", "")).to_upper()
	if role != "":
		var rd: Dictionary = stats["role_picks"]
		rd[role] = int(rd.get(role, 0)) + 1
	history.push_front(e)
	while history.size() > MAX_HISTORY:
		history.pop_back()
	if path != "":
		save_profile(path)
	return e


static func _fmt_time(sec: int) -> String:
	if sec >= 3600:
		return "%dh %02dm" % [sec / 3600, (sec % 3600) / 60]
	return "%dm %02ds" % [sec / 60, sec % 60]


static func tier_for(points: int) -> String:
	for t in TIERS:
		if points >= int(t[1]):
			return str(t[0])
	return "BRONZE"


static func rank_label() -> String:
	var t := tier_for(rp)
	var base := 0
	for e in TIERS:
		if e[0] == t:
			base = int(e[1])
	var div: String = ["I", "II", "III"][clampi((rp - base) / 150, 0, 2)] if t != "APEX" else ""
	return ("%s %s" % [t, div]).strip_edges()


static func _comma(n: int) -> String:
	var s := str(n)
	var out := ""
	for i in s.length():
		if i > 0 and (s.length() - i) % 3 == 0:
			out += ","
		out += s[i]
	return out


static func load_profile(path: String) -> void:
	var c := ConfigFile.new()
	c.load(path)
	apx = maxi(0, int(c.get_value("profile", "apx", 2500)))
	rp = maxi(0, int(c.get_value("profile", "rp", 1450)))
	var o: Variant = c.get_value("profile", "owned", owned)
	owned = (o as Array).duplicate() if o is Array else ["crew_obsidian", "ship_stealth"]
	for d in ["crew_obsidian", "ship_stealth"]:
		if not owned.has(d):
			owned.append(d)
	equipped = {"crew": str(c.get_value("profile", "equipped_crew", "crew_obsidian")), "ship": str(c.get_value("profile", "equipped_ship", "ship_stealth"))}
	for k in equipped.keys():
		if not owned.has(equipped[k]):
			equipped[k] = "crew_obsidian" if k == "crew" else "ship_stealth"
	var m := str(c.get_value("profile", "play_mode", "arena_clash"))
	play_mode = m if m in ["ranked", "practice", "arena_clash"] else "arena_clash"
	arena_preset = str(c.get_value("profile", "arena_preset", "standard"))
	if arena_preset not in ["standard", "short"]:
		arena_preset = "standard"
	arena_home = "planet_b" if c.get_value("profile", "arena_home", "planet_a") == "planet_b" else "planet_a"
	stats = _default_stats()
	var sv: Variant = c.get_value("profile", "stats", {})
	if sv is Dictionary:
		for k in (sv as Dictionary).keys():
			if k == "role_picks" and sv[k] is Dictionary:
				stats["role_picks"] = (sv[k] as Dictionary).duplicate()
			elif stats.has(k) and k != "role_picks":
				stats[k] = int(sv[k])
	var hv: Variant = c.get_value("profile", "history", [])
	history = []
	if hv is Array:
		for h in hv:
			if h is Dictionary:
				history.append(h)
		history = history.slice(0, MAX_HISTORY)


static func save_profile(path: String) -> void:
	var c := ConfigFile.new()
	c.load(path)
	c.set_value("profile", "apx", apx)
	c.set_value("profile", "rp", rp)
	c.set_value("profile", "owned", owned)
	c.set_value("profile", "equipped_crew", equipped["crew"])
	c.set_value("profile", "equipped_ship", equipped["ship"])
	c.set_value("profile", "play_mode", play_mode)
	c.set_value("profile", "arena_preset", arena_preset)
	c.set_value("profile", "arena_home", arena_home)
	c.set_value("profile", "stats", stats)
	c.set_value("profile", "history", history)
	c.save(path)


static func _polish_button(button: Button, accent: Color, selected := false) -> void:
	var ink := UI.BG_DEEP
	var normal := LOBBY_ACTIVE if selected else LOBBY_SURFACE
	var hover := LOBBY_ACTIVE.lightened(0.18) if selected else LOBBY_SURFACE.lerp(accent, 0.17)
	var pressed := LOBBY_ACTIVE.darkened(0.13) if selected else LOBBY_SURFACE.lerp(accent, 0.24)
	var edge := LOBBY_ACTIVE if selected else Color(accent, 0.55)
	button.add_theme_stylebox_override("normal", UI.chamfered_style(normal, edge, 8, 12, 1, 5 if selected else 0))
	button.add_theme_stylebox_override("hover", UI.chamfered_style(hover, LOBBY_ACTIVE if selected else accent, 8, 12, 1, 5))
	button.add_theme_stylebox_override("pressed", UI.chamfered_style(pressed, LOBBY_ACTIVE if selected else accent, 8))
	button.add_theme_stylebox_override("hover_pressed", button.get_theme_stylebox("pressed"))
	button.add_theme_stylebox_override("focus", UI.chamfered_style(Color.TRANSPARENT, LOBBY_ACCENT, 8, 12, 2))
	button.add_theme_stylebox_override("disabled", UI.chamfered_style(Color(LOBBY_SURFACE, 0.7), Color(accent, 0.28), 8))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, ink if selected else UI.TEXT)
	button.add_theme_color_override("font_disabled_color", UI.MUTED)
	button.add_theme_font_override("font", UI.font())
	UI.add_juice(button, accent)


static func _page_content(scroll: ScrollContainer, spacing: int) -> VBoxContainer:
	scroll.add_theme_stylebox_override("panel", UI.chamfered_style(Color(LOBBY_SURFACE, 0.58), LOBBY_EDGE, 14, 0))
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for edge in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(edge, 12)
	scroll.add_child(margin)
	var v := UI.vbox(spacing)
	margin.add_child(v)
	UI.animate_panel_in(scroll, CARD_SLIDE)
	return v


static func _page_header(title: String, metric := "") -> PanelContainer:
	var panel := UI.chamfered_panel(Vector2.ZERO, LOBBY_SURFACE, Color(LOBBY_ACCENT, 0.72), 14, 12, 4)
	var row := UI.hbox(10)
	panel.add_child(row)
	var icon := TextureRect.new()
	icon.texture = preload("res://icon.png")
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	icon.custom_minimum_size = Vector2(30, 30)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	var label := UI.label(title, 22)
	label.add_theme_constant_override("outline_size", 0)
	row.add_child(label)
	if not metric.is_empty():
		row.add_child(UI.spacer(0, 0, true))
		row.add_child(UI.mono_label(metric, 16, LOBBY_ACTIVE))
	return panel


static func _reveal_card(card: Control, index: int) -> void:
	UI.animate_panel_in(card, CARD_SLIDE, 0.22, 0.06 + mini(index, 8) * 0.028)


static func _showcase_panel(page: ScrollContainer) -> VBoxContainer:
	# main.gd sizes the page to the lobby area. Only the right-hand panel receives input.
	page.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var layout := Control.new()
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(layout)
	var glass := UI.chamfered_panel(Vector2.ZERO, Color(LOBBY_SURFACE, 0.79), Color(LOBBY_ACCENT, 0.78), 14, 18, 10)
	glass.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glass.anchor_left = 0.33
	layout.add_child(glass)
	var content := UI.vbox(10)
	glass.add_child(content)
	return content


static func _showcase_scroll(parent: VBoxContainer, spacing: int) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_RESERVE
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	parent.add_child(scroll)
	var content := UI.vbox(spacing)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	return content


## on_tab(name) is called with the tab title.
static func build_tab_bar(active: String, on_tab: Callable) -> HBoxContainer:
	var bar := UI.hbox(8)
	for t in TABS:
		var name: String = t
		var b := UI.toggle(name, name == active, on_tab.bind(name), 130)
		b.custom_minimum_size.y = maxf(b.custom_minimum_size.y, 40.0)
		_polish_button(b, LOBBY_ACCENT, name == active)
		bar.add_child(b)
	var wallet := UI.chamfered_panel(Vector2.ZERO, LOBBY_SURFACE, Color(LOBBY_ACTIVE, 0.74), 14, 10, 4)
	wallet.add_child(UI.mono_label("APX  %s" % _comma(apx), 14, LOBBY_ACTIVE))
	bar.add_child(wallet)
	UI.animate_panel_in(bar, Vector2(0, 6), 0.18)
	return bar


## PLAY tab: mode selector card. on_mode(mode_id) switches ranked/practice.
static func build_mode_selector(on_mode: Callable, online := false) -> VBoxContainer:
	var root := UI.vbox()
	var panel := UI.chamfered_panel(Vector2.ZERO, LOBBY_SURFACE, LOBBY_EDGE)
	root.add_child(panel)
	var v := UI.vbox(6)
	panel.add_child(v)
	v.add_child(UI.label("MATCH MODE", 12, LOBBY_ACCENT))
	var h := UI.hbox(5)
	for mode in ["ranked", "practice"]:
		var selected: bool = play_mode == mode
		var b := UI.toggle(str(mode).to_upper(), selected, on_mode.bind(mode), 136)
		_polish_button(b, LOBBY_ACCENT, selected)
		h.add_child(b)
	v.add_child(h)
	var arena := UI.toggle("ARENA CLASH", play_mode == "arena_clash", on_mode.bind("arena_clash"), 277)
	_polish_button(arena, LOBBY_ACCENT, play_mode == "arena_clash")
	arena.disabled = online
	v.add_child(arena)
	if play_mode == "arena_clash":
		var description := UI.label("Build a ship, fly to the Moon, fight in a 16v16 arena", 11, UI.MUTED)
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(description)
	elif play_mode == "ranked":
		v.add_child(UI.mono_label("%s · %s RP" % [rank_label(), _comma(rp)], 13, LOBBY_ACTIVE))
	else:
		v.add_child(UI.label("Solo training · no RP at stake · Cadet bots", 11, UI.MUTED))
	UI.animate_panel_in(panel, CARD_SLIDE)
	return root


static func _swatch(s: Dictionary, accent: Color) -> PanelContainer:
	var ink := Color(s["b"]).lerp(accent, 0.55).lightened(0.22)
	var p := UI.chamfered_panel(Vector2(0, 86), Color("#07111e").lerp(Color(s["a"]), 0.36), Color(accent, 0.46), 6, 9)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var orbit := Control.new()
	orbit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(orbit)
	orbit.draw.connect(func() -> void:
		var center := orbit.size * 0.5
		orbit.draw_arc(center, 29.0, 0.0, TAU, 48, Color(ink, 0.16), 1.0, true)
		orbit.draw_arc(center, 33.0, 0.0, 1.55, 18, Color(ink, 0.17), 5.0, true)
		orbit.draw_arc(center, 33.0, 0.0, 1.55, 18, ink, 1.5, true)
		orbit.draw_arc(center, 33.0, PI, PI + 0.85, 12, Color(ink, 0.65), 1.0, true)
	)
	orbit.resized.connect(func() -> void:
		orbit.pivot_offset = orbit.size * 0.5
		orbit.queue_redraw()
	)
	orbit.ready.connect(func() -> void:
		if not UI.reduced_motion:
			orbit.create_tween().set_loops().tween_property(orbit, "rotation", TAU, 5.0).from(0.0)
	)
	var emblem := UI.label(s["icon"], 32, ink, HORIZONTAL_ALIGNMENT_CENTER)
	emblem.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(emblem)
	return p


static func _skin_card(s: Dictionary, tag: String, on_action: Callable) -> PanelContainer:
	var id: String = s["id"]
	var rc: Color = RARITY_COLORS[s["rarity"]]
	var card := UI.chamfered_panel(Vector2(166, 0), LOBBY_SURFACE.lerp(rc, 0.08), Color(rc, 0.72), 10, 12, 8)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	UI.add_juice(card, rc, 1.025)
	var v := UI.vbox(4)
	card.add_child(v)
	v.add_child(_swatch(s, rc))
	v.add_child(UI.label(s["name"], 13, Color.WHITE))
	var top := UI.hbox(6)
	top.add_child(UI.label(s["rarity"], 10, rc))
	top.add_child(UI.spacer(0, 0, true))
	top.add_child(UI.label(tag, 9, UI.DIM))
	v.add_child(top)
	var kind: String = s["kind"]
	var is_owned := owned.has(id)
	var is_eq: bool = equipped[kind] == id
	var price := "%s APX" % _comma(int(s["price"]))
	v.add_child(UI.mono_label("OWNED" if is_owned else price, 13, LOBBY_ACTIVE))
	var btn: Button
	if is_eq:
		btn = UI.button("EQUIPPED ✓", func() -> void: pass, false, 0, 30)
		btn.disabled = true
	elif is_owned:
		btn = UI.button("EQUIP", on_action.bind("equip", id), false, 0, 30)
	else:
		btn = UI.button("BUY", on_action.bind("buy", id), false, 0, 30)
		btn.disabled = apx < int(s["price"])
	_polish_button(btn, LOBBY_ACCENT, not is_eq and not btn.disabled)
	btn.add_theme_font_override("font", UI.font(true))
	if is_eq:
		btn.add_theme_color_override("font_disabled_color", LOBBY_ACTIVE)
	v.add_child(btn)
	return card


## SHOP tab. on_action(op, id) is invoked for "buy"/"equip"; use apply_shop_action to handle it.
static func build_shop(on_action: Callable) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	var panel := _showcase_panel(scroll)
	panel.add_child(_page_header("ITEM SHOP", "BALANCE  %s APX" % _comma(apx)))
	var v := _showcase_scroll(panel, 12)
	var card_index := 0
	var sections := [
		["FEATURED · ASTRONAUT / CREW SKINS", "crew", "FEATURED"],
		["DAILY · SPACECRAFT LIVERIES", "ship", "DAILY"],
	]
	for sec in sections:
		v.add_child(UI.label(sec[0], 12, LOBBY_ACCENT))
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 14)
		row.add_theme_constant_override("v_separation", 14)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(row)
		for s in SKINS:
			if s["kind"] == sec[1]:
				var card := _skin_card(s, sec[2], on_action)
				row.add_child(card)
				_reveal_card(card, card_index)
				card_index += 1
	return scroll


## Returns true if state changed (and was saved).
static func apply_shop_action(op: String, id: String, path: String) -> bool:
	for s in SKINS:
		if s["id"] != id:
			continue
		if op == "buy":
			if owned.has(id) or apx < int(s["price"]):
				return false
			apx -= int(s["price"])
			owned.append(id)
		elif op != "equip" or not owned.has(id):
			return false
		equipped[s["kind"]] = id
		save_profile(path)
		return true
	return false


static func _row(cells: Array, widths: Array, color: Color, bg := LOBBY_SURFACE, edge := LOBBY_EDGE) -> PanelContainer:
	var p := UI.chamfered_panel(Vector2.ZERO, bg, edge, 8, 7)
	var h := UI.hbox(6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	for i in cells.size():
		var l := UI.mono_label(str(cells[i]), 13, color)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.custom_minimum_size.x = widths[i]
		h.add_child(l)
	return p


static func _ranking_row(cells: Array, tint: Color, bg: Color, edge: Color, pinned := false) -> PanelContainer:
	var row := UI.chamfered_panel(Vector2(0, 46 if pinned else 35), bg, edge, 10, 8, 12 if pinned else 0)
	var columns := UI.hbox(8)
	row.add_child(columns)
	var weights := [0.55, 1.9, 1.3, 1.3, 0.7, 0.9]
	for i in cells.size():
		var align := HORIZONTAL_ALIGNMENT_RIGHT if i >= 4 else HORIZONTAL_ALIGNMENT_LEFT
		var cell := UI.mono_label(str(cells[i]), 14 if pinned else 13, tint, align)
		cell.clip_text = true
		cell.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.size_flags_stretch_ratio = weights[i]
		columns.add_child(cell)
	return row


static func build_leaderboard() -> ScrollContainer:
	var page := ScrollContainer.new()
	var panel := _showcase_panel(page)
	panel.add_child(_page_header("RANKED LEADERBOARD"))
	var header := _ranking_row(["#", "CALLSIGN", "FACTION", "TIER", "WINS", "RP"], LOBBY_ACCENT,
		Color("#102839"), Color(LOBBY_ACCENT, 0.45))
	panel.add_child(header)
	var rivals := _showcase_scroll(panel, 5)
	var sorted := RIVALS.duplicate()
	sorted.sort_custom(func(a, b): return a[2] > b[2])
	var player_rank := 1
	for i in sorted.size():
		var rival: Array = sorted[i]
		var points := int(rival[2])
		if points >= rp:
			player_rank += 1
		var rank := i + 1 if points >= rp else i + 2
		var row := _ranking_row(["#%d" % rank, rival[0], rival[1], tier_for(points), rival[3], _comma(points)],
			UI.TEXT, Color(LOBBY_SURFACE, 0.84 if i % 2 == 0 else 0.55), Color(LOBBY_ACCENT, 0.20))
		rivals.add_child(row)
		_reveal_card(row, i)
	var player := _ranking_row(["#%d" % player_rank, "YOU", "Player", tier_for(rp), stats["wins"], _comma(rp)],
		LOBBY_ACTIVE, Color("#3a2e16"), LOBBY_ACTIVE, true)
	panel.add_child(player)
	# Match the fixed rows to the scrollbar gutter reserved by the scrolling rows.
	var body := rivals.get_parent() as ScrollContainer
	var sync_columns := func() -> void:
		var gutter := int(body.get_v_scroll_bar().get_combined_minimum_size().x)
		for fixed in [header, player]:
			var frame := fixed.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
			frame.content_margin_right = 10 + gutter
			fixed.add_theme_stylebox_override("panel", frame)
	body.ready.connect(sync_columns)
	body.get_v_scroll_bar().minimum_size_changed.connect(sync_columns)
	return page


static func build_guide() -> ScrollContainer:
	var scroll := ScrollContainer.new()
	var v := _page_content(scroll, 10)
	v.add_child(_page_header("MISSION & COMBAT GUIDE"))
	for section_index in GUIDE.size():
		var sec: Array = GUIDE[section_index]
		var p := UI.chamfered_panel(Vector2.ZERO, LOBBY_SURFACE, LOBBY_EDGE)
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var pv := UI.vbox(4)
		p.add_child(pv)
		pv.add_child(UI.label(sec[0], 15, LOBBY_ACTIVE))
		var steps: Array = sec[1]
		var is_loop: bool = str(sec[0]).begins_with("1")
		if is_loop:
			var line := HFlowContainer.new()
			line.add_theme_constant_override("h_separation", 8)
			for i in steps.size():
				line.add_child(UI.chip("%d. %s" % [i + 1, steps[i]], LOBBY_ACCENT))
			pv.add_child(line)
		else:
			for st in steps:
				var l := UI.label("•  " + str(st), 14, UI.TEXT)
				l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				pv.add_child(l)
		v.add_child(p)
		_reveal_card(p, section_index)
	return scroll



static func _skin_name(id: String) -> String:
	for s in SKINS:
		if s["id"] == id:
			return str(s["name"])
	return id


static func _stat_tile(value: String, caption: String) -> PanelContainer:
	var p := UI.chamfered_panel(Vector2(190, 0), LOBBY_SURFACE, LOBBY_EDGE, 10)
	var v := UI.vbox(2)
	p.add_child(v)
	var stat := UI.mono_label(value, 24, LOBBY_ACCENT)
	stat.add_theme_constant_override("outline_size", 0)
	v.add_child(stat)
	v.add_child(UI.label(caption, 10, UI.MUTED))
	return p


static func _tier_floor_ceiling() -> Vector2i:
	var lo := 0
	var hi := -1
	for i in TIERS.size():
		if rp >= int(TIERS[i][1]):
			lo = int(TIERS[i][1])
			hi = int(TIERS[i - 1][1]) if i > 0 else -1
			break
	return Vector2i(lo, hi)


static func build_profile() -> ScrollContainer:
	var scroll := ScrollContainer.new()
	var v := _page_content(scroll, 12)
	# --- Commander header card ---
	var card := UI.chamfered_panel(Vector2.ZERO, LOBBY_SURFACE, Color(LOBBY_ACCENT, 0.65), 14, 12, 5)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cv := UI.vbox(6)
	card.add_child(cv)
	var top := UI.hbox(14)
	var title := UI.label("COMMANDER", 22)
	title.add_theme_constant_override("outline_size", 0)
	top.add_child(title)
	top.add_child(UI.chip(rank_label(), LOBBY_ACCENT))
	top.add_child(UI.spacer(0, 0, true))
	top.add_child(UI.mono_label("APX  %s" % _comma(apx), 16, LOBBY_ACTIVE))
	cv.add_child(top)
	var fl := _tier_floor_ceiling()
	var prog := UI.hbox(10)
	prog.add_child(UI.mono_label("%s RP" % _comma(rp), 13, LOBBY_ACCENT))
	var ratio := 1.0
	if fl.y > 0:
		ratio = clampf(float(rp - fl.x) / float(fl.y - fl.x), 0.0, 1.0)
	var pb := UI.bar(LOBBY_ACCENT, ratio, 8.0)
	pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pb.custom_minimum_size = Vector2(300, 8)
	prog.add_child(pb)
	var nxt := "MAX TIER" if fl.y < 0 else "%s RP to next tier" % _comma(fl.y - rp)
	prog.add_child(UI.mono_label(nxt, 11, UI.MUTED))
	cv.add_child(prog)
	var badges := HFlowContainer.new()
	badges.add_theme_constant_override("h_separation", 8)
	badges.add_child(UI.chip("CREW · " + _skin_name(equipped["crew"]).to_upper(), UI.TEXT))
	badges.add_child(UI.chip("LIVERY · " + _skin_name(equipped["ship"]).to_upper(), UI.TEXT))
	badges.add_child(UI.chip("STREAK %d · BEST %d" % [int(stats["win_streak"]), int(stats["best_streak"])], LOBBY_ACTIVE))
	badges.add_child(UI.chip("FAVORITE ROLE · " + favorite_role(), UI.MUTED))
	cv.add_child(badges)
	v.add_child(card)
	# --- Career statistics ---
	v.add_child(UI.label("CAREER STATISTICS", 12, LOBBY_ACCENT))
	var mp := int(stats["matches_played"])
	var wins := int(stats["wins"])
	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var tiles := [
		[str(mp), "MATCHES PLAYED"], [str(wins), "WINS"],
		["%d%%" % (roundi(100.0 * wins / mp) if mp > 0 else 0), "WIN RATE"],
		[_comma(int(stats["total_kos"])), "TOTAL KOs"], [_comma(int(stats["total_flags"])), "FLAGS CAPTURED"],
		[_comma(int(stats["best_score"])), "BEST SCORE"],
		[_comma(int(stats["total_score"]) / mp if mp > 0 else 0), "AVG SCORE"],
		[_fmt_time(int(stats["total_play_seconds"])), "TOTAL MISSION TIME"],
	]
	for i in tiles.size():
		var tile := _stat_tile(tiles[i][0], tiles[i][1])
		grid.add_child(tile)
		_reveal_card(tile, i)
	v.add_child(grid)
	# --- Match history ---
	v.add_child(UI.label("MATCH HISTORY · LAST %d" % MAX_HISTORY, 12, LOBBY_ACCENT))
	if history.is_empty():
		var empty := UI.chamfered_panel(Vector2(0, 90), LOBBY_SURFACE, LOBBY_EDGE)
		empty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		empty.add_child(UI.label("NO MATCHES YET — launch a mission and your results will appear here.", 13, UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
		v.add_child(empty)
		_reveal_card(empty, 3)
		return scroll
	var w := [100, 110, 80, 70, 70, 80, 80, 170]
	v.add_child(_row(["MODE", "RESULT", "SCORE", "FLAGS", "KOs", "HULL", "RP", "DATE"], w, LOBBY_ACCENT))
	var detail := UI.label("Select a match for details.", 12, UI.MUTED)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for i in history.size():
		var h: Dictionary = history[i]
		var win := str(h.get("result", "")) == "VICTORY"
		var d := int(h.get("rp_delta", 0))
		var cells := [h.get("mode", "—"), ("● " if win else "○ ") + str(h.get("result", "—")), _comma(int(h.get("score", 0))),
			int(h.get("flags", 0)), int(h.get("kos", 0)), "%d%%" % int(h.get("ship_hull", 0)),
			("%+d" % d) if d != 0 else "±0", str(h.get("date", "—")).replace("T", " ").substr(0, 16)]
		var row := _row(cells, w, LOBBY_ACTIVE if win else UI.TEXT, Color(LOBBY_SURFACE, 0.86 if i % 2 == 0 else 0.70))
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		UI.add_juice(row, LOBBY_ACCENT, 1.005)
		var text := "%s · %s  |  score %s · %d flags · %d KOs · hull %d%% · RP %+d · duration %s · role %s" % [
			h.get("mode", "—"), h.get("result", "—"), _comma(int(h.get("score", 0))), int(h.get("flags", 0)),
			int(h.get("kos", 0)), int(h.get("ship_hull", 0)), d, _fmt_time(int(h.get("duration_s", 0))), str(h.get("role", "—"))]
		row.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				detail.text = text
				detail.add_theme_color_override("font_color", Color.WHITE))
		v.add_child(row)
		_reveal_card(row, i + 3)
	var dp := UI.chamfered_panel(Vector2.ZERO, LOBBY_SURFACE, LOBBY_EDGE)
	dp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dp.add_child(detail)
	v.add_child(dp)
	return scroll
