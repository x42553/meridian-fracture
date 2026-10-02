// Test-arena terrain: procedural dirt/grass/dry patches and a road, lit. Not part of the VFX system.
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
varying vec3 v_wp;

void vertex() {
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 n1 = texture(noise_tex, v_wp.xz * 0.018);
	vec4 n2 = texture(noise_tex, v_wp.xz * 0.09);
	vec4 n3 = texture(noise_tex, v_wp.xz * 0.45);
	vec4 n4 = texture(noise_tex, v_wp.xz * 1.7);
	vec3 dirt = vec3(0.17, 0.125, 0.075);
	vec3 grass = vec3(0.075, 0.13, 0.04);
	vec3 dry = vec3(0.27, 0.22, 0.13);
	float g = smoothstep(0.42, 0.6, n1.r + (n2.g - 0.5) * 0.35);
	vec3 c = mix(dirt, grass, g);
	c = mix(c, dry, smoothstep(0.55, 0.72, n1.b));
	c *= 0.7 + 0.55 * n3.a + 0.3 * (n2.r - 0.5) + 0.25 * (n4.a - 0.5);
	float road = 1.0 - smoothstep(2.6, 3.6, abs(v_wp.x + 26.0 + 4.0 * sin(v_wp.z * 0.06)));
	c = mix(c, vec3(0.09, 0.09, 0.10) * (0.8 + 0.5 * n3.r), road);
	ALBEDO = c;
	ROUGHNESS = 1.0;
}
