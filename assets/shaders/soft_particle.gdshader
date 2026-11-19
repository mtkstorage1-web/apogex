shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;
void vertex() {
 float sx = length(MODEL_MATRIX[0].xyz);
 float sy = length(MODEL_MATRIX[1].xyz);
 MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
 MODELVIEW_MATRIX[0] *= sx;
 MODELVIEW_MATRIX[1] *= sy;
}
void fragment() {
 vec2 point = UV * 2.0 - 1.0;
 float radius = dot(point, point);
 float falloff = pow(max(0.0, 1.0 - radius), 2.5);
 ALBEDO = COLOR.rgb;
 EMISSION = COLOR.rgb * 0.4;
 ALPHA = falloff * COLOR.a * 0.5;
}
