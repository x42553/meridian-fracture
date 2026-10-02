// Cluster / single-sprite effects. One MultiMesh instance == one whole effect; the mesh holds N pre-baked
// quads and this shader moves every quad analytically from (fx_time - spawn). Zero per-frame CPU work.
//
// INSTANCE_CUSTOM: x spawn time, y lifetime, z palette index (integer part) + random seed (fraction), w param.
// Instance transform: origin = effect centre, uniform basis scale = radius in metres (diameter for the
// single-quad modes 8..10).  Vertex COLOR = 4 per-particle randoms, UV = quad uv, UV2.x = particle index 0..1.
shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, fog_disabled, skip_vertex_transform;

#include "res://shaders/fx_common.gdshaderinc"

// 0 FIRE, 1 SMOKE, 2 DEBRIS, 3 SPARKS, 4 DUST_RING, 5 DUST_COLUMN, 6 PUFF, 7 SPLASH, 8 STAR_FLASH, 9 GLOW, 10 GROUND_GLOW
uniform int mode = 0;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D ramp_tex : filter_linear, repeat_disable;
uniform sampler2D palette_tex : filter_nearest, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;
uniform vec4 tint = vec4(1.0, 1.0, 1.0, 1.0);
uniform float soft_depth = 0.8;
uniform float intensity = 1.0;
uniform float land_seconds = 0.0;
uniform float fade_from = 0.85;
uniform float rise = 0.6;
// depth texture -> NDC z: Vulkan/Metal store NDC z directly (1, 0); OpenGL (Compatibility) stores 0..1 window depth (2, -1)
uniform vec2 depth_ndc = vec2(1.0, 0.0);

#ifdef NODE_MODE
instance uniform vec4 inst_data = vec4(-1000.0, 1.0, 0.0, 1.0);
#endif

varying flat vec4 v_inst;
varying vec4 v_rand;
varying vec3 v_data; // x age, y unused, z view-space distance
varying vec2 v_uv;

void vertex() {
#ifdef NODE_MODE
	vec4 ic = inst_data;
#else
	vec4 ic = INSTANCE_CUSTOM;
#endif
	float life = max(ic.y, 0.001);
	float age = (fx_time - ic.x) / life;
	// 'return' is illegal in vertex() (Godot 4.7): dead instances are collapsed behind the camera at the end.
	bool dead = (age < 0.0 || age >= 1.0 || UV2.x > fx_lod);
	age = clamp(age, 0.0, 0.999);
	vec4 r = COLOR;
	float sc = length(MODEL_MATRIX[0].xyz);
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 c = vec3(0.0);
	float size = 1.0;
	float rot = 0.0;
	vec2 sdir = vec2(0.0, 1.0);
	float slen = 0.0;

	if (mode == 0) { // FIRE: burst outward, buoyant rise, noise-eroded billows
		vec3 dir = fx_hemi(r.x, r.y, 0.05);
		float sp = mix(0.25, 1.0, r.z);
		float burst = 1.0 - exp(-5.0 * age);
		c = vec3(dir.x, dir.y * 0.7, dir.z) * (0.85 * sp * burst) + vec3(0.0, 0.2 + 0.7 * age * age, 0.0);
		size = mix(0.8, 1.35, r.w) * (0.3 + 0.7 * pow(age, 0.4));
		rot = r.x * TAU + (r.w - 0.5) * 2.0 * age;
	} else if (mode == 1) { // SMOKE: slower spread, strong rise
		vec3 dir = fx_hemi(r.x, r.y, 0.1);
		float sp = mix(0.3, 1.0, r.z);
		float spread = 1.0 - exp(-2.4 * age);
		c = vec3(dir.x, 0.0, dir.z) * (0.6 * sp * spread) + vec3(0.0, 0.25 + (0.5 + 1.2 * r.z) * age, 0.0);
		size = mix(0.6, 1.15, r.w) * (0.3 + 0.85 * sqrt(age));
		rot = r.y * TAU + (r.z - 0.5) * age;
	} else if (mode == 2) { // DEBRIS: ballistic chunks that land and rest (rubble when land_seconds > 0)
		float tl = mix(0.3, 0.6, r.z);
		if (land_seconds > 0.0) {
			tl = clamp(land_seconds * mix(0.6, 1.0, r.z) / life, 0.001, 0.95);
		}
		float k = min(age / tl, 1.0);
		float apex = mix(0.35, 1.1, r.y);
		float dist = mix(0.7, 2.2, r.y) * k * (1.0 - 0.3 * k);
		float ang = r.x * TAU;
		c = vec3(cos(ang) * dist, apex * 4.0 * k * (1.0 - k) + 0.012, sin(ang) * dist);
		size = max(mix(0.045, 0.11, r.w) * ic.w, 0.05 / sc);
		rot = k * (r.x - 0.5) * 40.0;
	} else if (mode == 3) { // SPARKS: velocity-aligned streaks with gravity
		vec3 dir = fx_hemi(r.x, r.y, 0.08);
		float speed = mix(1.0, 3.2, r.z);
		vec3 vel = dir * speed;
		vec3 grav = vec3(0.0, -4.0, 0.0);
		vec3 pos = vel * age + 0.5 * grav * age * age;
		pos.y = max(pos.y, 0.0);
		c = pos;
		vec2 vv = (VIEW_MATRIX * vec4(vel + grav * age, 0.0)).xy;
		float vl = length(vv);
		sdir = vl > 0.0001 ? vv / vl : vec2(0.0, 1.0);
		slen = clamp(vl * sc / life * 0.05, 0.10, 1.6 + 0.1 * sc);
		size = max(0.055, 0.012 * sc) / sc * ic.w;
	} else if (mode == 4) { // DUST_RING: low outward-rolling dust
		float ang = r.x * TAU;
		float rad = mix(0.35, 1.0, r.y) * (1.0 - exp(-3.2 * age));
		c = vec3(cos(ang) * rad, 0.05 + 0.25 * age * r.z, sin(ang) * rad);
		size = mix(0.28, 0.5, r.w) * (0.45 + 0.9 * age);
		rot = r.z * TAU;
	} else if (mode == 5) { // DUST_COLUMN: rising cloud above the blast
		float ang = r.x * TAU;
		float rad = r.y * 0.28 * (0.4 + age);
		float h = (0.1 + r.z * 1.7) * (1.0 - exp(-2.2 * age));
		c = vec3(cos(ang) * rad, h, sin(ang) * rad);
		size = mix(0.45, 0.85, r.w) * (0.3 + 0.9 * sqrt(age));
		rot = r.z * TAU;
	} else if (mode == 6) { // PUFF: single drifting billboard
		c = vec3((r.x - 0.5) * 0.3 * age, (0.1 + rise * (0.4 + 0.6 * r.y)) * age, (r.z - 0.5) * 0.3 * age);
		size = mix(0.7, 1.0, r.w) * (0.35 + 0.75 * sqrt(age));
		rot = r.x * TAU + (r.y - 0.5) * age;
	} else if (mode == 7) { // SPLASH droplets
		float ang = r.x * TAU;
		float hv = mix(0.9, 1.9, r.z);
		float rad = mix(0.05, 0.5, r.y) * min(age * 2.0, 1.0);
		c = vec3(cos(ang) * rad, max(hv * age - 1.7 * age * age, 0.0), sin(ang) * rad);
		size = mix(0.07, 0.16, r.w);
	}

	vec3 cw = origin + c * sc;
	vec2 q = VERTEX.xy;
	if (mode == 10) { // ground glow lies flat on the terrain
		cw.y += 0.15;
		vec3 wp = cw + vec3(q.x, 0.0, q.y) * sc;
		VERTEX = (VIEW_MATRIX * vec4(wp, 1.0)).xyz;
	} else {
		vec3 vc = (VIEW_MATRIX * vec4(cw, 1.0)).xyz;
		if (mode == 8 || mode == 9) {
			vc.z += sc * 0.6; // pull additive flashes toward the camera so the ground plane never clips them
		}
		// world size of one screen pixel at this depth: used to keep thin streaks >= min_px wide at any zoom
		float px_world = 2.0 * (-vc.z) / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
		if (mode == 3) {
			float wd = max(size * sc, px_world * 1.6);
			vec2 o = sdir * (q.y * max(slen, px_world * 4.0)) + vec2(-sdir.y, sdir.x) * (q.x * wd);
			VERTEX = vc + vec3(o, 0.0);
		} else {
			float rr = (mode >= 8) ? ic.z * TAU : rot;
			VERTEX = vc + vec3(fx_rot(q, rr) * size * sc, 0.0);
		}
	}
	v_inst = ic;
	v_rand = r;
	v_uv = UV;
	v_data = vec3(age, 0.0, -VERTEX.z);
	if (dead) {
		VERTEX = vec3(0.0, 0.0, 100.0);
	}
}

void fragment() {
	float age = v_data.x;
	vec2 p = v_uv * 2.0 - 1.0;
	float par = v_inst.w;
	float pidx = floor(v_inst.z);
	float rnd = fract(v_inst.z);
	vec3 pc = texture(palette_tex, vec2((pidx + 0.5) / 8.0, 0.5)).rgb;
	vec3 col = vec3(0.0);
	float a = 0.0;

	float sd = 1.0;
	if (soft_depth > 0.0 && (mode <= 1 || mode == 4 || mode == 5 || mode == 6)) {
		float d = textureLod(depth_tex, SCREEN_UV, 0.0).r;
		vec4 sv = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d * depth_ndc.x + depth_ndc.y, 1.0);
		float scene_z = -sv.z / sv.w;
		sd = clamp((scene_z - v_data.z) / soft_depth, 0.0, 1.0);
	}

	if (mode == 0) { // FIRE
		vec2 nuv = v_uv * 0.6 + v_rand.xy * 9.0 + vec2(0.0, -age * 0.4);
		vec4 n = texture(noise_tex, nuv);
		float shape = 1.0 - length(p) + (n.r - 0.5) * 1.0 + (n.g - 0.5) * 0.35;
		float dens = shape - age * 0.85;
		float m = smoothstep(0.0, 0.3, dens);
		float heat = clamp((shape - 0.15 + (n.b - 0.5) * 0.5) * 1.5, 0.0, 1.0) * pow(1.0 - age, 1.25);
		vec4 rc = texture(ramp_tex, vec2(heat, 0.5));
		float fade = 1.0 - smoothstep(0.7, 1.0, age);
		col = rc.rgb * m * fade * par * intensity * sd;
		a = rc.a * m * fade * sd;
	} else if (mode == 1) { // SMOKE
		vec2 nuv = v_uv * 0.5 + v_rand.xy * 5.0 + vec2(age * 0.05, -age * 0.12);
		vec4 n = texture(noise_tex, nuv);
		float shape = 1.0 - length(p) + (n.r - 0.5) * 0.9;
		float dens = shape - age * 0.55;
		float m = smoothstep(0.0, 0.4, dens);
		float n2 = texture(noise_tex, nuv + vec2(-0.03, 0.03)).r;
		float lit = clamp(0.5 + (n.r - n2) * 6.0 + p.y * 0.25, 0.0, 1.0);
		vec3 base = mix(vec3(0.07, 0.065, 0.06), vec3(0.5, 0.47, 0.44), lit * (0.35 + 0.65 * age));
		vec3 glow = vec3(1.6, 0.55, 0.12) * exp(-age * 7.0) * smoothstep(0.2, 0.9, shape);
		float alpha = m * 0.88 * (1.0 - smoothstep(0.55, 1.0, age)) * sd;
		col = base * alpha + glow * m * sd;
		a = alpha;
	} else if (mode == 2) { // DEBRIS
		float d = length(p * vec2(1.0, 0.8 + 0.5 * v_rand.y));
		float m = 1.0 - smoothstep(0.55, 0.95, d);
		vec3 rock = mix(vec3(0.045, 0.038, 0.03), vec3(0.2, 0.17, 0.14), v_rand.w);
		rock *= 0.5 + 0.6 * (0.5 - p.x * 0.5 + p.y * 0.5);
		vec3 hot = vec3(1.8, 0.5, 0.08) * exp(-age * 12.0) * v_rand.z;
		float fade = 1.0 - smoothstep(fade_from, 1.0, age);
		col = (rock + hot) * m * fade;
		a = m * fade;
	} else if (mode == 3) { // SPARKS (additive)
		float across = abs(p.x);
		float along = v_uv.y;
		float body = (1.0 - across * across) * pow(along, 1.6);
		float head = smoothstep(0.8, 1.0, along) * (1.0 - across);
		float fade = (1.0 - age);
		fade *= fade;
		vec3 hotc = mix(pc * 3.0, vec3(6.0, 4.5, 2.2), 1.0 - age);
		col = hotc * (body + head) * fade * par * intensity;
	} else if (mode == 4 || mode == 5 || mode == 6) { // DUST / PUFF
		vec2 nuv = v_uv * 0.55 + v_rand.xy * 7.0 + vec2(age * 0.08, -age * 0.1);
		vec4 n = texture(noise_tex, nuv);
		float shape = 1.0 - length(p) + (n.r - 0.5) * 0.95;
		float dens = shape - age * 0.5;
		float m = smoothstep(0.0, 0.45, dens);
		float n2 = texture(noise_tex, nuv + vec2(-0.02, 0.03)).r;
		float lit = clamp(0.8 + (n.r - n2) * 4.0 + p.y * 0.15, 0.5, 1.0);
		float fade = pow(1.0 - age, 1.4) * smoothstep(0.0, 0.06, age);
		float alpha = m * fade * tint.a * par * sd;
		col = tint.rgb * lit * alpha;
		a = alpha;
	} else if (mode == 7) { // SPLASH droplets
		float m = smoothstep(1.0, 0.25, length(p));
		float fade = 1.0 - smoothstep(0.55, 1.0, age);
		col = vec3(0.85, 0.93, 1.0) * m * fade * 0.9;
		a = m * fade * 0.8;
	} else if (mode == 8) { // STAR_FLASH (additive)
		float r = length(p);
		float ang = atan(p.y, p.x);
		float core = exp(-r * r * 22.0);
		float spikes = pow(abs(cos(ang * 3.0 + rnd * 6.2831)), 14.0) * exp(-r * 2.6) * (1.0 - smoothstep(0.75, 1.0, r));
		float halo = exp(-r * r * 6.0) * 0.16;
		float env = smoothstep(0.0, 0.1, age) * (1.0 - age);
		col = (pc * (halo + spikes * 1.6) + vec3(1.0, 0.95, 0.85) * core * 1.3) * env * 3.0 * par * intensity;
	} else if (mode == 9) { // GLOW (additive billboard)
		float g = exp(-dot(p, p) * 8.0);
		float env = (1.0 - age) * (1.0 - age);
		col = pc * g * env * 1.8 * par * intensity;
	} else { // 10 GROUND_GLOW (additive, flat)
		float g = smoothstep(1.0, 0.0, length(p));
		g = g * g * g;
		float env = (1.0 - age) * (1.0 - age);
		col = pc * g * env * 0.9 * par * intensity;
	}
	ALBEDO = col;
	ALPHA = a;
}
