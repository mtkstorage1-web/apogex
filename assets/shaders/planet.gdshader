shader_type spatial;
render_mode fog_disabled;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec4 palette_a : source_color = vec4(0.35,0.29,0.49,1.0);
uniform vec4 palette_b : source_color = vec4(0.52,0.43,0.62,1.0);
uniform vec4 palette_c : source_color = vec4(0.73,0.67,0.76,1.0);
uniform float clouds : hint_range(0.0,1.0) = 0.18;
uniform float atmosphere : hint_range(0.0,1.0) = 0.18;
varying vec3 sphere_position;
void vertex() { sphere_position = normalize(VERTEX); }
void fragment() {
 vec3 p = normalize(sphere_position);
 vec3 w = pow(abs(p), vec3(4.0)); w /= max(dot(w,vec3(1.0)),0.001);
 float n = dot(vec3(texture(noise_tex,p.yz*2.0).r,texture(noise_tex,p.xz*2.0).r,texture(noise_tex,p.xy*2.0).r),w);
 float band = 0.5+0.5*sin(p.y*26.0+n*7.0);
 vec3 surface = mix(palette_a.rgb,palette_b.rgb,band*0.65+n*0.25);
 float cloud = smoothstep(0.57,0.8,texture(noise_tex,p.xz*3.0+p.y*0.3).r)*clouds;
 ALBEDO = mix(surface,palette_c.rgb,cloud);
 ROUGHNESS = 0.92;
 EMISSION = palette_c.rgb*pow(1.0-max(dot(normalize(NORMAL),normalize(VIEW)),0.0),4.0)*atmosphere;
}
