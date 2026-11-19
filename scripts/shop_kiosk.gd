## White-room parts terminal. Faces +Z and sits on the ground.
extends RefCounted

const WHITE := Color("#f1f5f9")
const SLATE := Color("#cbd5e1")
const DARK := Color("#1e293b")
const CYAN := Color("#00a8b5")
const HOLOGRAM := Color("#66fcf1")
const HOLOGRAM_HEIGHT := 3.7


static func _panel(size: Vector3, color: Color, pos: Vector3, emission := 0.0) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = size
	return Gfx.mesh(box, Gfx.mat(color, 0.4, emission), pos)


static func build(loadout: Dictionary = {}) -> Node3D:
	var kiosk := Node3D.new()
	kiosk.name = "ShopKiosk"

	kiosk.add_child(_panel(Vector3(6.4, 0.19, 3.0), SLATE, Vector3(0, 0.095, 0)))
	kiosk.add_child(_panel(Vector3(5.9, 0.14, 2.65), WHITE, Vector3(0, 0.26, 0)))
	kiosk.add_child(_panel(Vector3(5.55, 1.58, 2.06), WHITE, Vector3(0, 1.12, -0.12)))
	kiosk.add_child(_panel(Vector3(5.85, 0.16, 2.47), SLATE, Vector3(0, 1.94, -0.12)))
	kiosk.add_child(_panel(Vector3(6.05, 0.22, 2.56), WHITE, Vector3(0, 2.12, -0.12)))
	for side in [-1, 1]:
		kiosk.add_child(_panel(Vector3(0.32, 1.42, 0.12), SLATE, Vector3(side * 2.56, 1.13, 0.94)))
		kiosk.add_child(_panel(Vector3(0.055, 0.97, 0.04), CYAN, Vector3(side * 2.56, 1.2, 1.01), 0.7))

	var display := Node3D.new()
	display.position = Vector3(0, 1.84, 1.07)
	display.rotation.x = deg_to_rad(-24)
	kiosk.add_child(display)
	display.add_child(_panel(Vector3(4.67, 1.05, 0.26), SLATE, Vector3.ZERO))
	display.add_child(_panel(Vector3(4.41, 0.85, 0.06), DARK, Vector3(0, 0, 0.15)))
	display.add_child(_panel(Vector3(3.96, 0.025, 0.02), CYAN, Vector3(0, -0.25, 0.19), 1.0))
	var label := Gfx.label("PARTS SHOP", WHITE, 48, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.pixel_size = 0.009
	label.position = Vector3(0, 0.045, 0.19)
	display.add_child(label)
	var prompt := Gfx.label("PRESS  E  TO BUILD", HOLOGRAM, 26, 0)
	prompt.name = "InteractPrompt"
	prompt.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	prompt.pixel_size = 0.006
	prompt.position = Vector3(0, -0.33, 0.19)
	display.add_child(prompt)
	for i in range(3):
		display.add_child(_panel(Vector3(0.075, 0.045, 0.02), HOLOGRAM, Vector3(1.57 + i * 0.16, 0.13, 0.19), 1.2))

	var emitter := Gfx.cyl(0.93, 0.09, DARK, Vector3(0, 2.28, 0), 48)
	kiosk.add_child(emitter)
	var lens := Gfx.cyl(0.72, 0.026, CYAN, Vector3(0, 2.33, 0), 48)
	lens.material_override = Gfx.mat(CYAN, 0.25, 1.1)
	kiosk.add_child(lens)
	var rim := Gfx.ring(0.83, 0.07, HOLOGRAM, 1.0)
	rim.position.y = 2.335
	rim.material_override = Gfx.mat(HOLOGRAM, 0.25, 1.4).duplicate()
	kiosk.add_child(rim)
	var light := OmniLight3D.new()
	light.position.y = 2.63
	light.light_color = CYAN
	light.light_energy = 0.65
	light.omni_range = 2.5
	kiosk.add_child(light)
	# Gentle wayfinding pulse: rim glow, beacon light and prompt breathe together.
	var rim_mat := rim.material_override as StandardMaterial3D
	light.ready.connect(func() -> void:
		var pulse := light.create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		pulse.tween_property(light, "light_energy", 1.05, 1.4)
		pulse.parallel().tween_property(prompt, "modulate:a", 1.0, 1.4)
		if rim_mat:
			pulse.parallel().tween_property(rim_mat, "emission_energy_multiplier", 2.0, 1.4)
		pulse.tween_property(light, "light_energy", 0.65, 1.4)
		pulse.parallel().tween_property(prompt, "modulate:a", 0.55, 1.4)
		if rim_mat:
			pulse.parallel().tween_property(rim_mat, "emission_energy_multiplier", 1.4, 1.4))

	var hologram := Node3D.new()
	hologram.name = "Hologram"
	hologram.position.y = HOLOGRAM_HEIGHT
	kiosk.add_child(hologram)
	hologram.ready.connect(func() -> void:
		var spin := hologram.create_tween().set_loops()
		spin.tween_property(hologram, "rotation:y", TAU, 14.0).from(0.0)
		var bob := hologram.create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		bob.tween_property(hologram, "position:y", HOLOGRAM_HEIGHT + 0.14, 2.2)
		bob.tween_property(hologram, "position:y", HOLOGRAM_HEIGHT, 2.2))
	update_hologram(kiosk, loadout)
	return kiosk


## Replace the ship while keeping the emitter and its animation running.
static func update_hologram(kiosk: Node3D, loadout: Dictionary) -> void:
	var hologram := kiosk.get_node_or_null("Hologram") as Node3D
	if hologram == null:
		return

	var ship := ShipModel.full(HOLOGRAM, loadout)
	ship.name = "Spacecraft"
	var bounds := [null]
	Actor._aabb(ship, Transform3D.IDENTITY, bounds)
	if bounds[0] != null:
		var box: AABB = bounds[0]
		# Fit the swept footprint as the ship rotates, including mixed-family loadouts.
		var horizontal_diameter := Vector2(box.size.x, box.size.z).length()
		var display_scale := minf(0.28, minf(3.16 / horizontal_diameter, 2.32 / box.size.y))
		ship.scale *= display_scale
		ship.position = (ship.position - box.get_center()) * display_scale

	var material := Gfx.mat(HOLOGRAM, 0.35, 0.7, 0.48)
	for node in ship.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		mesh.material_overlay = null
		mesh.material_override = material
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var previous := hologram.get_node_or_null("Spacecraft")
	if previous != null:
		hologram.remove_child(previous)
		previous.queue_free()
	hologram.add_child(ship)
