extends Control

const UI = preload("res://scripts/ui/UIThemeUtils.gd")

var _frontend: CanvasLayer
var _factions := {}
var _roster := {}
var _team_titles := {}
var _roles := {}
var _role_detail: Label
var _mode: OptionButton
var _address_row: HBoxContainer
var _address: LineEdit
var _port: LineEdit
var _network_action: Button
var _session_status: Label
var _seed: LineEdit
var _target: OptionButton
var _launch: Button
var _notice: Label


func setup(frontend: CanvasLayer) -> void:
	_frontend = frontend
	UI.shade(self, [Color("#060d17ef"), Color("#08121eac")], false)
	var margin := MarginContainer.new()
	UI.full(self, margin, 30)
	var layout := UI.column(margin, 14)
	var mast := UI.row(layout)
	var title := UI.column(mast, 2)
	UI.label(title, "APOGEX  /  VESPER-9", 14, UI.CYAN, 750)
	UI.label(title, "Match Lobby", 44, UI.INK, 780)
	UI.space(mast)
	UI.label(mast, "16 vs 16  /  PLANETARY & ORBITAL WARFARE", 15, UI.MUTED, 650)
	var body := UI.row(layout, 14)
	body.size_flags_vertical = SIZE_EXPAND_FILL

	var loadout := UI.card(body, UI.STEEL, 17)
	loadout.custom_minimum_size.x = 275
	var left := UI.column(loadout, 7)
	UI.label(left, "FACTION", 15, UI.MUTED, 750)
	for faction in UI.FACTIONS:
		var item := UI.button(left, faction.to_upper(), func() -> void: frontend.select_faction(faction), UI.faction_color(faction), 46)
		item.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_factions[faction] = item
		var lore := "Ceramic fleets of the Helion Accord defend orbital trade." if faction == "helion" else "Cinder foundry crews fight for control of Vesper-9’s iron belt."
		var detail := UI.label(left, lore, 15, UI.MUTED)
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UI.line(left)
	UI.label(left, "STARTING ROLE", 15, UI.MUTED, 750)
	var role_list := UI.column(left, 4)
	for id in UI.ROLES:
		var choice := UI.button(role_list, UI.ROLES[id][0], frontend.select_role.bind(id), Color.TRANSPARENT, 31)
		choice.alignment = HORIZONTAL_ALIGNMENT_LEFT
		choice.add_theme_font_size_override("font_size", 15)
		_roles[id] = choice
	_role_detail = UI.label(left, "", 15)
	_role_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var roster_panel := UI.card(body, UI.STEEL.lightened(0.14), 17)
	roster_panel.size_flags_horizontal = SIZE_EXPAND_FILL
	var middle := UI.column(roster_panel, 9)
	UI.label(middle, "TEAM ROSTER", 15, UI.MUTED, 750)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	middle.add_child(scroll)
	var teams := UI.row(scroll, 12)
	teams.size_flags_horizontal = SIZE_EXPAND_FILL
	for faction in UI.FACTIONS:
		var team := UI.column(teams, 2)
		team.size_flags_horizontal = SIZE_EXPAND_FILL
		var tint := UI.faction_color(faction)
		_team_titles[faction] = UI.label(team, "", 16, tint, 800)
		UI.line(team, tint.darkened(0.43))
		var entries: Array[Label] = []
		for index in 16:
			var cell := PanelContainer.new()
			cell.add_theme_stylebox_override("panel", UI.style(Color("#14283a") if index % 2 == 0 else Color("#0d1c2a"), Color.TRANSPARENT, 1, 2))
			team.add_child(cell)
			var entry := UI.label(cell, "", 14)
			entry.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			entries.append(entry)
		_roster[faction] = entries

	var config := UI.card(body, UI.STEEL, 17)
	config.custom_minimum_size.x = 313
	var right := UI.column(config, 9)
	UI.label(right, "SESSION MODE", 15, UI.MUTED, 750)
	_mode = UI.option(right, ["Offline 16v16 Bots", "Host 32P ENet Server", "Join ENet Server"], _select_mode)
	_address_row = UI.row(right, 6)
	_address = UI.field(_address_row, "127.0.0.1", "IP address or hostname", 255)
	_port = UI.field(_address_row, "24567", "Port", 5)
	_port.custom_minimum_size.x = 74
	_network_action = UI.button(right, "", _session_action)
	_session_status = UI.label(right, "", 15, UI.CYAN)
	_session_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UI.line(right)
	UI.label(right, "MATCH SETUP", 15, UI.MUTED, 750)
	UI.label(right, "World seed", 15)
	_seed = UI.field(right, "", "Integer seed", 20)
	_seed.text_changed.connect(func(value: String) -> void: frontend.seed_text = value)
	UI.label(right, "Target score", 15)
	_target = UI.option(right, [500, 1000, 1500], func(index: int) -> void: frontend.target_score = [500, 1000, 1500][index])

	var footer := UI.row(layout, 16)
	UI.button(footer, "← MAIN MENU", frontend.open_main_menu, Color.TRANSPARENT, 49)
	_notice = UI.label(footer, "", 15, UI.ORANGE)
	UI.space(footer)
	_launch = UI.button(footer, "LAUNCH & DEPLOY →", frontend.launch_lobby, UI.CYAN, 49)


func _select_mode(index: int) -> void:
	_frontend.stop_session()
	_mode.select(index)
	refresh()


func _session_action() -> void:
	var network: Node = _frontend.world.network_authority
	if network.get_network_mode() != "OFFLINE":
		_frontend.stop_session()
	elif not _port.text.is_valid_int() or int(_port.text) not in range(1, 65536):
		_frontend.session_message = "Enter a port from 1 to 65535."
	elif _mode.selected == 1:
		_frontend.start_host(int(_port.text))
	else:
		_frontend.join_session(_address.text.strip_edges(), int(_port.text))
	refresh()


func refresh() -> void:
	var front := _frontend
	var world: Node = front.world
	var network: Node = world.network_authority
	var mode: String = network.get_network_mode()
	var client := mode == "CLIENT"
	var active := mode != "OFFLINE"
	if active:
		_mode.select(1 if mode == "HOST" else 2)
	_mode.disabled = active
	_address_row.visible = _mode.selected != 0
	_address.visible = _mode.selected == 2
	_address.editable = not active
	_port.editable = not active
	_network_action.visible = _mode.selected != 0
	_network_action.text = "Stop host" if mode == "HOST" else ("Disconnect" if client else ("Start host" if _mode.selected == 1 else "Connect"))
	_session_status.text = "●  " + front.session_status()
	_seed.editable = not client
	_target.disabled = client
	if not _seed.has_focus():
		_seed.text = str(world.world_config.world_seed) if client else front.seed_text
	var score_choices := [500, 1000, 1500]
	_target.select(score_choices.find(int(world.match_manager.target_score) if client else front.target_score))
	_launch.disabled = (client and not front.client_ready()) or (not active and _mode.selected != 0)
	_notice.text = front.notice
	for id in _roles:
		var choice: Button = _roles[id]
		var selected: bool = front.role == id
		var tint: Color = UI.faction_color(front.faction)
		choice.text = ("◆  " if selected else "◇  ") + UI.ROLES[id][0]
		choice.add_theme_stylebox_override("normal", UI.style(Color(tint, 0.14) if selected else Color("#101e2c"), tint if selected else UI.STEEL, 4))
		choice.add_theme_stylebox_override("hover", UI.style(Color(tint, 0.22), tint, 4))
		choice.add_theme_stylebox_override("pressed", UI.style(Color(tint, 0.30), tint, 4))
		choice.add_theme_color_override("font_color", tint.lightened(0.46) if selected else UI.INK)
	_role_detail.text = UI.ROLES[front.role][1]
	_role_detail.add_theme_color_override("font_color", UI.faction_color(front.faction))
	var peers: Dictionary = network.peer_factions
	var own_id: int = world.multiplayer.get_unique_id()
	for faction in UI.FACTIONS:
		var tint := UI.faction_color(faction)
		var item: Button = _factions[faction]
		item.text = ("◆  " if front.faction == faction else "◇  ") + faction.to_upper()
		item.disabled = (client and not front.client_ready()) or (active and faction != peers.get(own_id) and network.get_peer_counts()[faction] >= 16)
		var occupants: Array[String] = []
		if front.faction == faction and (not client or front.client_ready()):
			occupants.append("[YOU]  " + UI.ROLES[front.role][0])
		var peer_ids := peers.keys()
		peer_ids.sort()
		for id in peer_ids:
			if id != own_id and peers[id] == faction:
				occupants.append("PEER  %d" % id)
		var human_count := occupants.size()
		_team_titles[faction].text = "%s  /  16" % faction.to_upper()
		var bots: Array = world.ai_manager.roster[faction]
		for index in 16:
			var entry: Label = _roster[faction][index]
			var is_you := index == 0 and human_count > 0 and occupants[0].begins_with("[YOU]")
			if index < human_count:
				entry.text = "  " + occupants[index]
			else:
				var bot: Dictionary = bots[index - human_count]
				entry.text = "  %s  ·  %s" % [bot.callsign, bot.role]
			var color := tint.lightened(0.35) if is_you else (UI.INK if index < human_count else UI.MUTED)
			entry.add_theme_color_override("font_color", color)
			entry.get_parent().add_theme_stylebox_override("panel", UI.style(Color(tint, 0.16) if is_you else (Color("#14283a") if index % 2 == 0 else Color("#0d1c2a")), tint.darkened(0.45) if is_you else Color.TRANSPARENT, 1, 2))
