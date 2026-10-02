// Vertical light columns: superweapon beacon (thin pulsing pillar) and orbital strike (descending
// penetrator that lands into a lingering pillar). Mesh: open cylinder radius 1, height 1 (y from -0.5..0.5).
// Instance transform = translate * scale(radius, height, radius). INSTANCE_CUSTOM: x spawn, y lifetime.
shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, fog_disabled;

#include "res://assets/shaders/fx_common.gdshaderinc"

// 0 BEACON, 1 STRIKE
uniform int mode = 0;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

varying flat vec4 v_inst;
varying vec4 v_data; // age, height 0..1
varying vec2 v_uv;

void vertex() {
	vec4 ic = INSTANCE_CUSTOM;
	float age = (fx_time - ic.x) / max(ic.y, 0.001);
	bool dead = (age < 0.0 || age >= 1.0);
	age = clamp(age, 0.0, 0.999);
	float rs = 1.0;
	if (mode == 1) {
		rs = mix(0.07, 1.0, smoothstep(0.15, 0.2, age)) * (1.0 + 0.35 * age);
	}
	v_data = vec4(age, VERTEX.y + 0.5, 0.0, 0.0);
	v_inst = ic;
	v_uv = UV;
	VERTEX = vec3(VERTEX.x * rs, VERTEX.y + 0.5, VERTEX.z * rs);
	if (dead) {
		VERTEX = vec3(0.0);
	}
}

void fragment() {
	float age = v_data.x;
	float h = v_data.y;
	float soft = pow(abs(dot(normalize(NORMAL), normalize(VIEW))), 1.4);
	vec3 col = vec3(0.0);
	if (mode == 0) {
		float pulse = 0.55 + 0.45 * sin(fx_time * (3.0 + 9.0 * age * age) * 2.0);
		float f = fract(h * 12.0 - fx_time * 2.0);
		float band = smoothstep(0.0, 0.25, f) * (1.0 - smoothstep(0.25, 0.5, f));
		float env = smoothstep(0.0, 0.03, age) * (1.0 - smoothstep(0.97, 1.0, age));
		col = vec3(1.0, 0.25, 0.1) * soft * (0.5 + 1.6 * band) * pulse * (1.0 - h * 0.6) * 2.5 * env;
	} else {
		float land = 0.15;
		if (age < land) {
			float head_y = 1.0 - age / land;
			float rel = (h - head_y) / 0.28;
			float inside = step(0.0, rel) * step(rel, 1.0);
			float st = inside * pow(1.0 - rel, 1.5);
			float tip = inside * pow(max(1.0 - rel * 6.0, 0.0), 2.0);
			col = vec3(0.6, 0.85, 1.0) * st * 5.0 * soft + vec3(1.0) * tip * 8.0 * soft;
		} else {
			float k = (age - land) / (1.0 - land);
			float n = texture(noise_tex, vec2(v_uv.x * 3.0 + fx_time * 0.2, h * 1.5 - fx_time * 1.2)).r;
			float pillar = pow(soft, 1.2) * (0.6 + 0.8 * n) * (1.0 - h * 0.35);
			float fade = pow(1.0 - k, 1.8) * smoothstep(0.0, 0.03, k);
			col = mix(vec3(1.0, 0.6, 0.3), vec3(0.7, 0.85, 1.0), 1.0 - h) * pillar * fade * 4.0;
		}
	}
	ALBEDO = col;
	ALPHA = 0.0;
}
