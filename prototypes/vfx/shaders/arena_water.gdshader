// Test-arena water pool (for the splash effect). Not part of the VFX system.
shader_type spatial;
render_mode specular_schlick_ggx;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

void fragment() {
	vec2 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	vec2 n = texture(noise_tex, w * 0.05 + vec2(TIME * 0.01, 0.0)).rg - 0.5;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = mix(vec3(0.015, 0.06, 0.085), vec3(0.06, 0.16, 0.22), fres + n.x * 0.3);
	ROUGHNESS = 0.1;
	METALLIC = 0.0;
	SPECULAR = 0.6;
	ALPHA = 0.92;
}
