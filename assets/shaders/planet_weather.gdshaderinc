uniform sampler2D weather_tex : filter_linear_mipmap, repeat_enable;
uniform int cloud_detail = 1;
uniform float weather_time = 0.0;
uniform vec3 sun_direction = vec3(0.45, 0.7, 0.55);

float planet_noise(vec3 p) {
	vec3 w = abs(p);
	w *= w;
	w /= max(dot(w, vec3(1.0)), 0.001);
	return dot(w, vec3(texture(weather_tex, p.yz).r,
		texture(weather_tex, p.xz).r, texture(weather_tex, p.xy).r));
}

float cloud_cover(vec3 p) {
	p.xz += vec2(0.35 * sin(p.y * 13.0), weather_time * 0.004);
	float n = planet_noise(p * 1.9);
	if (cloud_detail >= 1) {
		n = 0.74 * n + 0.26 * planet_noise(p * 6.4 + vec3(0.2, 0.1, 0.7));
	}
	if (cloud_detail >= 2) {
		n += (planet_noise(p * 16.0) - 0.5) * 0.11;
	}
	return smoothstep(0.50, 0.67, n);
}
