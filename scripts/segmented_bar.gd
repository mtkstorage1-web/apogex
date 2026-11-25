class_name SegmentedBar
extends Control
var value := 1.0:
	set(v):
		if value != v: value = v; queue_redraw()
var nominal := UI.GOOD
var segments := 12
func _draw() -> void:
	var width := (size.x - (segments - 1) * 2) / segments
	var col := UI.ramp_color(value, nominal)
	for i in segments:
		var on := float(i) / segments < value
		var rect := Rect2(i * (width + 2), 0, width, size.y)
		if on:
			draw_rect(rect.grow(1.5), Color(col, 0.16))
			draw_style_box(UI.style(col.lerp(Color.WHITE, 0.08 * float(i) / segments), Color.TRANSPARENT, 1, 0, 0), rect)
			draw_rect(Rect2(rect.position, Vector2(width, maxf(1.0, size.y * 0.3))), Color(1, 1, 1, 0.18))
		else:
			draw_style_box(UI.style(Color(col, 0.10), Color.TRANSPARENT, 1, 0, 0), rect)
