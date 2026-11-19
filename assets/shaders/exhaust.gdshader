shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;
uniform vec4 hot_color : source_color = vec4(0.6, 0.88, 1.0, 1.0);
uniform vec4 tail_color : source_color = vec4(0.12, 0.38, 0.9, 1.0);
uniform float plume_length = 5.0;
uniform float intensity = 1.0;
uniform float phase = 0.0;
varying float axial;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
 vec2 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
 return mix(mix(hash(i),hash(i+vec2(1.0,0.0)),f.x),mix(hash(i+vec2(0.0,1.0)),hash(i+vec2(1.0,1.0)),f.x),f.y);
}
void vertex() {
 axial = clamp(VERTEX.y/plume_length+0.5,0.0,1.0);
 float pulse=sin(TIME*24.0+axial*21.0+phase)*0.07;
 VERTEX.xz *= 1.0+pulse+axial*0.12*sin(TIME*31.0+VERTEX.y*8.0);
}
void fragment() {
 float flow=TIME*6.0+phase;
 float n=noise(vec2(UV.x*13.0,axial*9.0-flow));
 float fine=noise(vec2(UV.x*27.0+flow*0.4,axial*23.0-flow*2.0));
 float fade=pow(1.0-axial,1.1)*smoothstep(0.0,0.025,axial);
 float diamonds=pow(max(0.0,cos(axial*48.0-phase)),10.0)*exp(-axial*2.8);
 float breakup=smoothstep(0.13+axial*0.32,0.72,n*0.72+fine*0.28);
 vec3 color=mix(hot_color.rgb,tail_color.rgb,smoothstep(0.0,0.8,axial));
 ALBEDO=color;
 EMISSION=color*(1.5+0.4*n+diamonds*1.8)*intensity;
 float feather = smoothstep(0.0, 0.65, abs(dot(normalize(NORMAL), normalize(VIEW))));
 ALPHA=fade*breakup*feather*(0.55+diamonds*0.3)*intensity;
}
