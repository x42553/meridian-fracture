// Path ribbons: tracers, shell/missile trails, beams, rail streaks, lightning, muzzle cones, contrails.
// One MultiMesh instance = one whole ribbon; the path is encoded in the instance transform columns:
//   basis.x = arc apex offset (world vector, parabolic arc), basis.y = B - A (path), basis.z = (tail_len m,
//   flight time s, linger s), origin = A.  INSTANCE_CUSTOM: x spawn, y lifetime, z palette+seed, w width (m).
shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, fog_disabled, skip_vertex_transform;

#include "res://assets/shaders/fx_common.gdshaderinc"

const float SEGMENTS = 24.0;

// 0 TRACER, 1 SMOKE_TRAIL, 2 THERMAL_BEAM, 3 RAIL, 4 ARC, 5 FLASH_CONE, 6 CONTRAIL, 7 FIRE_TRAIL
uniform int mode = 0;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D palette_tex : filter_nearest, repeat_disable;
uniform vec4 tint = vec4(1.0, 1.0, 1.0, 1.0);
uniform float min_px = 2.6;

varying flat vec4 v_inst;
varying flat vec2 v_geo; // path length, flight time
varying vec4 v_data;     // across -1..1, s 0..1 (tail to head), point age 0..1, age
varying float v_sp;      // path fraction

void vertex() {
	vec4 ic = INSTANCE_CUSTOM;
	float t = fx_time - ic.x;
	float life = max(ic.y, 0.001);
	float age = t / life;
	bool dead = (t < 0.0 || age >= 1.0);
	t = max(t, 0.0);
	age = clamp(age, 0.0, 0.999);
	float across = VERTEX.x * 2.0;
	float s = UV.y;
	vec3 A = MODEL_MATRIX[3].xyz;
	vec3 axis = MODEL_MATRIX[1].xyz;
	vec3 arc = MODEL_MATRIX[0].xyz;
	vec3 prm = MODEL_MATRIX[2].xyz;
	float L = max(length(axis), 0.001);
	float flight = max(prm.y, 0.001);
	float head = 1.0;
	float tail = 0.0;
	if (mode == 0) {
		head = clamp(t / flight, 0.0, 1.0);
		tail = clamp(t / flight - prm.x / L, 0.0, 1.0);
	} else if (mode == 1 || mode == 6 || mode == 7) {
		head = clamp(t / flight, 0.0, 1.0);
	}
	float sp = mix(tail, head, s);
	vec3 P = A + axis * sp + arc * (4.0 * sp * (1.0 - sp));
	vec3 dP = axis + arc * (4.0 - 8.0 * sp);
	float point_age = 0.0;
	float w = ic.w;
	if (mode == 1 || mode == 6 || mode == 7) {
		point_age = clamp((t - sp * flight) / max(prm.z, 0.001), 0.0, 1.0);
		w *= (mode == 6) ? (1.0 + 5.0 * point_age) : (1.0 + 3.5 * sqrt(point_age));
	} else if (mode == 5) {
		w *= (1.0 - 0.75 * s);
	}
	vec3 vp = (VIEW_MATRIX * vec4(P, 1.0)).xyz;
	if (mode == 0 || mode == 2 || mode == 3 || mode == 4) {
		// keep thin streaks readable at any zoom: never narrower than min_px screen pixels
		float px_world = 2.0 * (-vp.z) / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
		w = max(w, px_world * min_px);
	}
	vec2 dv = (VIEW_MATRIX * vec4(dP, 0.0)).xy;
	float dl = length(dv);
	vec2 dir2 = dl > 0.0001 ? dv / dl : vec2(0.0, 1.0);
	vec2 perp = vec2(-dir2.y, dir2.x);
	float jit = 0.0;
	if (mode == 4) { // lightning: view-plane zig-zag re-rolled at 24 Hz
		float k = floor(fx_time * 24.0) + fx_hash(ic.z * 91.7) * 100.0;
		float seg = floor(s * SEGMENTS + 0.5);
		jit = (fx_hash(seg * 7.13 + k * 3.31) - 0.5) * 2.0 * ic.w * 2.6 * sin(s * PI);
	}
	v_inst = ic;
	v_geo = vec2(L, flight);
	v_data = vec4(across, s, point_age, age);
	v_sp = sp;
	VERTEX = vec3(vp.xy + perp * (across * 0.5 * w + jit), vp.z);
	if (dead) {
		VERTEX = vec3(0.0, 0.0, 100.0);
	}
}

void fragment() {
	float across = v_data.x;
	float a1 = abs(across);
	float s = v_data.y;
	float pa = v_data.z;
	float age = v_data.w;
	float L = v_geo.x;
	float pidx = floor(v_inst.z);
	float rnd = fract(v_inst.z);
	vec3 pal = texture(palette_tex, vec2((pidx + 0.5) / 8.0, 0.5)).rgb;
	vec3 col = vec3(0.0);
	float a = 0.0;

	if (mode == 0) { // TRACER: hot head, tapering tail
		float prof = 1.0 - a1 * a1;
		float body = pow(s, 2.5) * prof;
		float head = smoothstep(0.8, 1.0, s) * prof;
		col = pal * (body * 2.2 + head * 3.0) + vec3(1.0, 0.95, 0.85) * head * head * 2.5;
	} else if (mode == 1 || mode == 6) { // SMOKE_TRAIL / CONTRAIL (premultiplied)
		vec4 n = texture(noise_tex, vec2(v_sp * L * 0.14 + rnd * 5.0, across * 0.35 + 0.5 + rnd));
		float shape = (1.0 - a1) + (n.r - 0.5) * 0.9 - pa * 0.7;
		float m = smoothstep(0.0, 0.4, shape) * pow(1.0 - pa, 1.3);
		vec3 smoke = (mode == 6) ? mix(vec3(0.95, 0.96, 0.98), vec3(0.6, 0.62, 0.66), pa) : mix(vec3(0.82, 0.8, 0.77), vec3(0.3, 0.3, 0.32), pa);
		smoke *= tint.rgb;
		float hot = (mode == 1) ? exp(-pa * 30.0) * (1.0 - a1) : 0.0;
		float alpha = m * tint.a;
		col = smoke * alpha + vec3(4.0, 1.8, 0.5) * hot;
		a = alpha;
	} else if (mode == 7) { // FIRE_TRAIL: additive flame streak
		vec4 n = texture(noise_tex, vec2(v_sp * L * 0.2 - fx_time * 1.5, across * 0.4 + rnd));
		float shape = (1.0 - a1) + (n.g - 0.5) * 0.8 - pa * 0.9;
		float m = smoothstep(0.0, 0.35, shape) * pow(1.0 - pa, 2.2);
		col = mix(vec3(5.0, 2.2, 0.5), vec3(1.5, 0.3, 0.05), pa) * m;
	} else if (mode == 2) { // THERMAL_BEAM
		float flick = texture(noise_tex, vec2(v_sp * L * 0.12 - fx_time * 2.5, rnd)).r;
		float core = smoothstep(0.35, 0.0, a1);
		float body = pow(1.0 - a1, 1.6);
		float env = smoothstep(0.0, 0.05, age) * (1.0 - smoothstep(0.85, 1.0, age));
		vec3 hot = mix(vec3(4.0, 0.9, 0.12), vec3(9.0, 7.0, 4.5), core);
		col = hot * body * (0.6 + 0.7 * flick) * env;
	} else if (mode == 3) { // RAIL: white core + counter-rotating helix
		float core = exp(-a1 * a1 * 28.0);
		float ph = v_sp * L * 2.4 + age * 25.0;
		float h1 = exp(-pow(across - 0.65 * sin(ph), 2.0) * 70.0);
		float h2 = exp(-pow(across + 0.65 * sin(ph), 2.0) * 70.0);
		float env = pow(1.0 - age, 2.0) * smoothstep(0.0, 0.03, age);
		col = (vec3(7.0, 8.0, 10.0) * core + pal * 4.0 * (h1 + h2) * 0.8 + pal * exp(-a1 * 3.0) * 0.5) * env;
	} else if (mode == 4) { // ARC: lightning
		float core = exp(-a1 * a1 * 9.0);
		float env = smoothstep(0.0, 0.1, age) * (1.0 - smoothstep(0.6, 1.0, age));
		float flick = 0.65 + 0.35 * step(0.5, fract(fx_time * 31.0 + rnd * 7.0));
		col = (vec3(6.0, 7.0, 10.0) * core + pal * 2.5 * exp(-a1 * 2.5)) * env * flick;
	} else { // 5 FLASH_CONE: muzzle blast tongue
		float fall = pow(1.0 - s, 1.6);
		float prof = 1.0 - a1 * a1;
		float env = pow(1.0 - age, 1.5);
		col = mix(vec3(6.0, 3.0, 0.8), vec3(9.0, 8.0, 6.0), pow(1.0 - s, 4.0)) * fall * prof * env;
	}
	ALBEDO = col;
	ALPHA = a;
}
