extends RefCounted

const INK := Color("#f0f6fa")
const MUTED := Color("#9cb1c3")
const CYAN := Color("#22e5ff")
const ORANGE := Color("#ff6a1a")
const GLASS := Color("#08101ae6")
const STEEL := Color("#305064")
const FACTIONS := ["helion", "cinder"]
const ROLES := {
	"assault": ["Assault", "Rifle equipped · 100 starting shield", "hangar"],
	"engineer": ["Engineer", "Engineering tool · +100 faction resources", "hangar"],
	"pilot": ["Pilot", "Quick launch · Faction fighter cockpit", "fighter"],
	"commander": ["Commander", "Command bridge · Tactical holotable", "bridge"],
}


static func faction_color(faction: String) -> Color:
	return {"helion": CYAN, "cinder": ORANGE}.get(faction, MUTED)


static func style(fill: Color, border: Color, inset: float = 0, radius: int = 4) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(radius)
	for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
		box.set_content_margin(side, inset)
	return box


static func create_theme() -> Theme:
	var theme := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Inter", "Avenir Next", "DejaVu Sans"])
	theme.default_font = font
	theme.default_font_size = 17
	theme.set_color("font_color", "Label", INK)
	theme.set_color("font_color", "LineEdit", INK)
	theme.set_color("font_placeholder_color", "LineEdit", MUTED)
	theme.set_stylebox("normal", "LineEdit", style(Color("#101e2c"), STEEL, 9))
	theme.set_stylebox("focus", "LineEdit", style(Color.TRANSPARENT, CYAN))
	theme.set_stylebox("panel", "PopupMenu", style(GLASS, STEEL, 8))
	theme.set_stylebox("hover", "PopupMenu", style(Color("#17374a"), STEEL))
	theme.set_constant("v_separation", "PopupMenu", 8)
	for kind in ["Button", "OptionButton"]:
		theme.set_color("font_color", kind, INK)
		theme.set_color("font_hover_color", kind, Color.WHITE)
		theme.set_color("font_pressed_color", kind, Color.WHITE)
		theme.set_color("font_disabled_color", kind, MUTED.darkened(0.3))
		theme.set_stylebox("normal", kind, style(Color("#101e2c"), STEEL, 10))
		theme.set_stylebox("hover", kind, style(Color("#173447"), CYAN, 10))
		theme.set_stylebox("pressed", kind, style(Color("#144255"), CYAN, 10))
		theme.set_stylebox("disabled", kind, style(Color("#101923"), Color("#253645"), 10))
		theme.set_stylebox("focus", kind, style(Color.TRANSPARENT, CYAN.lightened(0.5)))
	theme.set_stylebox("slider", "HSlider", style(Color("#152a3b"), STEEL, 3))
	theme.set_stylebox("grabber_area", "HSlider", style(Color("#13697b"), CYAN))
	theme.set_stylebox("grabber_area_highlight", "HSlider", style(Color("#17899d"), CYAN))
	return theme


static func full(parent: Node, control: Control, inset: float = 0) -> void:
	parent.add_child(control)
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	control.offset_left = inset
	control.offset_top = inset
	control.offset_right = -inset
	control.offset_bottom = -inset


static func shade(parent: Node, colors: Array[Color], horizontal: bool = true) -> void:
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray(colors)
	var texture := GradientTexture2D.new()
	texture.gradient = ramp
	texture.fill_to = Vector2.RIGHT if horizontal else Vector2.DOWN
	var rect := TextureRect.new()
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	full(parent, rect)


static func column(parent: Node, separation: int = 12) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	parent.add_child(box)
	return box


static func row(parent: Node, separation: int = 12) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	parent.add_child(box)
	return box


static func card(parent: Node, border: Color = STEEL, inset: float = 20) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", style(GLASS, border, inset))
	parent.add_child(panel)
	return panel


static func label(parent: Node, value: String, pixels: int = 17, tint: Color = INK, weight: int = 0) -> Label:
	var item := Label.new()
	item.text = value
	item.add_theme_font_size_override("font_size", pixels)
	item.add_theme_color_override("font_color", tint)
	if weight > 0:
		var font := SystemFont.new()
		font.font_names = PackedStringArray(["Inter", "Avenir Next", "DejaVu Sans"])
		font.font_weight = weight
		item.add_theme_font_override("font", font)
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(item)
	return item


static func line(parent: Node, tint: Color = STEEL) -> void:
	var rule := ColorRect.new()
	rule.color = tint
	rule.custom_minimum_size.y = 1
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rule)


static func space(parent: Node, minimum: int = 0) -> void:
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.custom_minimum_size = Vector2(minimum, minimum)
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(spacer)


static func button(parent: Node, title: String, action: Callable, accent: Color = Color.TRANSPARENT, height: int = 43) -> Button:
	var item := Button.new()
	item.text = title
	item.custom_minimum_size.y = height
	item.pressed.connect(action)
	parent.add_child(item)
	if accent.a > 0.0:
		emphasis(item, accent)
	return item


static func emphasis(item: Button, accent: Color, glow: bool = false) -> void:
	var normal := style(Color("#10222d").lerp(accent, 0.14), accent, 10)
	if glow:
		normal.shadow_color = Color(accent, 0.34)
		normal.shadow_size = 8
	item.add_theme_stylebox_override("normal", normal)
	item.add_theme_stylebox_override("hover", style(Color("#122a37").lerp(accent, 0.30), accent.lightened(0.3), 10))
	item.add_theme_stylebox_override("pressed", style(Color("#163441").lerp(accent, 0.38), accent, 10))
	item.add_theme_color_override("font_color", accent.lightened(0.52))


static func option(parent: Node, values: Array, action: Callable) -> OptionButton:
	var item := OptionButton.new()
	for value in values:
		item.add_item(str(value))
	item.item_selected.connect(action)
	parent.add_child(item)
	return item


static func field(parent: Node, value: String, hint: String, max_length: int = 0) -> LineEdit:
	var item := LineEdit.new()
	item.text = value
	item.placeholder_text = hint
	item.max_length = max_length
	item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(item)
	return item


static func select_role(parent: Node, action: Callable) -> OptionButton:
	var names: Array = []
	for role in ROLES.values():
		names.append(role[0])
	return option(parent, names, func(index: int) -> void: action.call(ROLES.keys()[index]))
