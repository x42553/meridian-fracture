// Ground-plane rings: shockwave, EMP ring, superweapon warning marker, water ripple, heat-haze disc.
// Mesh: horizontal quad spanning [-1,1]^2 in XZ. Instance transform = translate * scale(R, 1, R).
// INSTANCE_CUSTOM: x spawn, y lifetime, z palette+seed.  Variant DISTORT (defined by FxAssets) samples the
// screen texture and refracts it (blend_mix) instead of adding light (blend_premul_alpha).
shader_type spatial;
#ifdef DISTORT
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled;
#else
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, fog_disabled;
#endif

#include "res://assets/shaders/fx_common.gdshaderinc"

// 0 SHOCK, 1 EMP, 2 MARKER, 3 RIPPLE, 4 HAZE (distort variant only), 5 WAKE (foam streak; basis scale = length, 1, width)
uniform int mode = 0;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D palette_tex : filter_nearest, repeat_disable;
#ifdef DISTORT
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear_mipmap;
#endif
uniform float strength = 1.0;

varying flat vec4 v_inst;
varying vec2 v_q;
varying float v_age;
varying vec3 v_wpos;
varying flat vec3 v_center;

void vertex() {
	vec4 ic = INSTANCE_CUSTOM;
	float age = (fx_time - ic.x) / max(ic.y, 0.001);
	bool dead = (age < 0.0 || age >= 1.0);
	age = clamp(age, 0.0, 0.999);
	v_inst = ic;
	v_age = age;
	v_q = VERTEX.xz;
	VERTEX.y += 0.12;
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_center = MODEL_MATRIX[3].xyz;
	if (dead) {
		VERTEX = vec3(0.0);
	}
}

void fragment() {
	float age = v_age;
	float d = length(v_q);
	float pidx = floor(v_inst.z);
	float rnd = fract(v_inst.z);
	vec3 pal = texture(palette_tex, vec2((pidx + 0.5) / 8.0, 0.5)).rgb;
#ifdef DISTORT
	float mask = 0.0;
	vec2 off = vec2(0.0);
	if (mode == 0) {
		float rr = 1.0 - pow(1.0 - age, 2.6);
		float w = rr * mix(0.16, 0.05, age) + 0.008;
		float x = d - rr;
		float band = ((x < 0.0) ? exp(x / (w * 2.0)) : exp(-x / (w * 0.2))) * pow(1.0 - age, 1.4);
		vec3 rad = normalize(v_wpos - v_center + vec3(0.0001));
		vec2 dv = (VIEW_MATRIX * vec4(rad, 0.0)).xy;
		dv.y = -dv.y;
		off = normalize(dv + vec2(0.0001)) * band * 0.06 * strength;
		mask = clamp(band * 2.0, 0.0, 1.0);
	} else {
		float m = 1.0 - smoothstep(0.55, 1.0, d);
		float env = smoothstep(0.0, 0.1, age) * (1.0 - smoothstep(0.85, 1.0, age));
		vec2 n = texture(noise_tex, v_wpos.xz * 0.12 + vec2(0.0, -fx_time * 0.35)).rg - 0.5;
		off = n * 0.05 * m * env * strength;
		mask = clamp(m * env * 1.5, 0.0, 1.0);
	}
	ALBEDO = texture(screen_tex, SCREEN_UV + off).rgb;
	ALPHA = mask;
#else
	vec3 col = vec3(0.0);
	float a = 0.0;
	if (mode == 0) { // SHOCK: hot leading edge with a soft dusty trailing gradient
		float rr = 1.0 - pow(1.0 - age, 2.6);
		float w = rr * mix(0.16, 0.05, age) + 0.008;
		float x = d - rr;
		float band = (x < 0.0) ? exp(x / (w * 0.7)) : exp(-x / (w * 0.15));
		float fade = pow(1.0 - age, 1.8);
		col = pal * band * band * fade * 0.5;
	} else if (mode == 1) { // EMP: crackling energy ring
		float rr = 1.0 - pow(1.0 - age, 2.2);
		float w = rr * mix(0.3, 0.1, age) + 0.012;
		float ang = atan(v_q.y, v_q.x);
		float n = texture(noise_tex, vec2(ang * 0.9 + rnd * 4.0, d * 2.5 - fx_time * 1.2)).r;
		float band = smoothstep(rr - w * 2.5, rr, d) * (1.0 - smoothstep(rr, rr + w * 0.5, d));
		float fade = pow(1.0 - age, 1.2);
		float disc = (1.0 - smoothstep(0.0, rr, d)) * 0.05 * (1.0 - age);
		col = pal * (band * (0.8 + 1.6 * n) * 1.3 + disc) * fade;
	} else if (mode == 2) { // MARKER: dashed rings, rotating spokes, clock sweep, pulse rate rises with age
		float ang = atan(v_q.y, v_q.x);
		float freq = 2.5 + 9.0 * age * age;
		float pulse = 0.6 + 0.4 * sin(fx_time * freq * 2.0);
		float ring = smoothstep(0.925, 0.96, d) * (1.0 - smoothstep(0.985, 1.0, d));
		float dashes = step(0.45, fract(ang / TAU * 36.0 + fx_time * 0.12));
		float ring2 = smoothstep(0.585, 0.6, d) * (1.0 - smoothstep(0.62, 0.635, d)) * step(0.5, fract(ang / TAU * 18.0 - fx_time * 0.25));
		float ring3 = smoothstep(0.28, 0.295, d) * (1.0 - smoothstep(0.305, 0.32, d));
		float sweep = fract(ang / TAU + 1.25);
		float filled = step(sweep, age) * (1.0 - smoothstep(0.92, 1.0, d)) * smoothstep(0.0, 0.05, d);
		float env = smoothstep(0.0, 0.03, age) * (1.0 - smoothstep(0.97, 1.0, age));
		vec3 red = vec3(1.0, 0.22, 0.08);
		col = red * (ring * mix(0.5, 1.0, dashes) * 2.6 + ring2 * 1.6 + ring3 * 1.2 + filled * 0.22) * pulse * env;
	} else if (mode == 3) { // RIPPLE: concentric water rings
		float rr = age * 0.95 + 0.05;
		float wave = pow(max(sin((d - rr) * 38.0), 0.0), 3.0);
		float m = smoothstep(rr + 0.04, rr - 0.02, d) * smoothstep(rr - 0.4, rr - 0.05, d);
		float k = wave * m * (1.0 - age);
		col = vec3(0.85, 0.93, 1.0) * k * 0.8;
		a = k * 0.6;
	} else if (mode == 5) { // WAKE: foam streak along the heading (+x = bow), world-anchored noise so it stays put
		float x01 = (v_q.x + 1.0) * 0.5;
		float hw = mix(1.0, 0.3, x01);
		float shape = 1.0 - abs(v_q.y) / hw;
		float n = texture(noise_tex, v_wpos.xz * 0.3 + vec2(rnd * 5.0)).r;
		float streak = smoothstep(0.0, 0.5, shape + (n - 0.5) * 0.9 - age * 0.9);
		float ends = smoothstep(0.0, 0.25, x01) * (1.0 - smoothstep(0.85, 1.0, x01));
		float fade = pow(1.0 - age, 1.5) * smoothstep(0.0, 0.05, age);
		a = streak * ends * fade * 0.8;
		col = vec3(0.92, 0.96, 1.0) * a;
	}
	ALBEDO = col;
	ALPHA = a;
#endif
}
