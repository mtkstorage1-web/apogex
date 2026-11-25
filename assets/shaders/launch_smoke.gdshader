shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

// Billowy launch exhaust: sunlit cool-white top, engine-lit orange underside,
// soft cauliflower lobes at the rim.
uniform vec3 sun_tint = vec3(1.0, 0.93, 0.80);
uniform vec3 engine_tint = vec3(1.0, 0.52, 0.18);
uniform float billow = 1.0;

void vertex(){
 float sx=length(MODEL_MATRIX[0].xyz);
 MODELVIEW_MATRIX=VIEW_MATRIX*mat4(INV_VIEW_MATRIX[0],INV_VIEW_MATRIX[1],INV_VIEW_MATRIX[2],MODEL_MATRIX[3]);
 MODELVIEW_MATRIX[0]*=sx; MODELVIEW_MATRIX[1]*=sx;
}
void fragment(){
 vec2 p=UV*2.0-1.0;
 float ang=atan(p.y,p.x);
 float lobes=(sin(ang*5.0+p.x*3.0)*.5+sin(ang*9.0-p.y*4.0)*.3+sin(p.x*15.0+p.y*9.0)*sin(p.y*17.0-p.x*7.0)*.4)*.085*billow;
 float edge=1.0-dot(p,p)+lobes;
 float body=smoothstep(0.0,.7,edge);
 // Light from above (sun) vs. from below (engine fire); UV.y grows downward on the quad.
 float top=clamp(1.0-UV.y,0.0,1.0);
 float bottom=clamp(UV.y,0.0,1.0);
 vec3 lit=mix(vec3(0.62,0.66,0.74),sun_tint,smoothstep(0.1,1.0,top));
 lit=mix(lit,engine_tint*1.35,pow(bottom,2.2)*0.55*(0.4+0.6*body));
 // Thin self-shadow in the dense core for volume.
 lit*=0.78+0.22*smoothstep(0.0,.5,edge);
 ALBEDO=COLOR.rgb*lit;
 ALPHA=body*COLOR.a;
}
