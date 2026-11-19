shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
void vertex(){
 float sx=length(MODEL_MATRIX[0].xyz);
 MODELVIEW_MATRIX=VIEW_MATRIX*mat4(INV_VIEW_MATRIX[0],INV_VIEW_MATRIX[1],INV_VIEW_MATRIX[2],MODEL_MATRIX[3]);
 MODELVIEW_MATRIX[0]*=sx; MODELVIEW_MATRIX[1]*=sx;
}
void fragment(){
 vec2 p=UV*2.0-1.0;
 float lobes=sin(p.x*15.0+p.y*9.0)*sin(p.y*17.0-p.x*7.0)*.075;
 float edge=1.0-dot(p,p)+lobes;
 ALBEDO=COLOR.rgb*(.83+UV.y*.17);
 ALPHA=smoothstep(0.0,.7,edge)*COLOR.a;
}
