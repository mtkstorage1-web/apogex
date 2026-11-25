extends RefCounted
## Shared projection rules for labels that have to read over 3D geometry.

const NAME_RANGE := 40.0
const STATION_RANGE := 6.0
const NAME_MAX_PIXELS := 22.0


static func pixels_per_meter(camera: Camera3D, at: Vector3) -> float:
	if camera.is_position_behind(at):
		return 0.0
	var center := camera.unproject_position(at)
	var up := camera.unproject_position(at + camera.global_basis.y)
	return center.distance_to(up)


static func clamp_billboard(label: Label3D, camera: Camera3D, max_pixels: float, world_pixel_size: float) -> void:
	var pixels := pixels_per_meter(camera, label.global_position)
	var height := label.font.get_height(label.font_size) + label.outline_size
	var native_scale := maxf(1.0, label.get_viewport().get_stretch_transform().get_scale().y)
	var world_scale := absf(label.global_basis.get_scale().y)
	label.pixel_size = minf(world_pixel_size, max_pixels / maxf(0.01, pixels * height * native_scale * world_scale))


static func select_station(labels: Array[Label3D], camera: Camera3D, player: Vector3) -> void:
	var best: Label3D
	var nearest := STATION_RANGE
	var view := camera.get_viewport().get_visible_rect()
	for label in labels:
		if not is_instance_valid(label):
			continue
		label.hide()
		var at := label.global_position
		var distance := player.distance_to(at)
		if distance >= nearest or label.text.is_empty() or camera.is_position_behind(at):
			continue
		if not (label.get_parent() as Node3D).is_visible_in_tree():
			continue
		if not view.has_point(camera.unproject_position(at)):
			continue
		best = label
		nearest = distance
	if best != null:
		clamp_billboard(best, camera, 20.0, 0.006)
		best.show()


static func screen_bounds(label: Label3D, camera: Camera3D) -> Rect2:
	var font := label.font
	var text_size := Vector2.ZERO
	var lines := label.text.split("\n")
	for line in lines:
		text_size.x = maxf(text_size.x, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, label.font_size).x)
	text_size.y = lines.size() * font.get_height(label.font_size)
	text_size += Vector2.ONE * label.outline_size
	var factor := label.pixel_size * pixels_per_meter(camera, label.global_position)
	text_size *= Vector2(label.global_basis.x.length(), label.global_basis.y.length()) * factor
	return Rect2(camera.unproject_position(label.global_position) - text_size * 0.5, text_size)


static func declutter_nameplates(camera: Camera3D) -> void:
	var occupied: Array[Rect2] = []
	var scene := camera.get_tree()
	for station: Label3D in scene.get_nodes_in_group("station_labels"):
		if station.is_visible_in_tree() and not camera.is_position_behind(station.global_position):
			occupied.append(screen_bounds(station, camera).grow(3.0))
	var nearby: Array[Label3D] = []
	for tag: Label3D in scene.get_nodes_in_group("crew_nameplates"):
		if tag.is_visible_in_tree() and not camera.is_position_behind(tag.global_position) and camera.global_position.distance_squared_to(tag.global_position) < NAME_RANGE * NAME_RANGE:
			nearby.append(tag)
	nearby.sort_custom(func(a: Label3D, b: Label3D) -> bool:
		return camera.global_position.distance_squared_to(a.global_position) < camera.global_position.distance_squared_to(b.global_position))
	for tag in nearby:
		clamp_billboard(tag, camera, NAME_MAX_PIXELS, 0.010)
		var bounds := screen_bounds(tag, camera).grow(2.0)
		var overlaps := occupied.any(func(rect: Rect2) -> bool: return rect.intersects(bounds))
		tag.set_meta("overlaps_label", overlaps)
		if not overlaps:
			occupied.append(bounds)
