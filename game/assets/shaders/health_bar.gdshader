shader_type spatial;
// Constant-screen-size health bar with a per-player shape pip (render spec 5.10). One quad per bar, POSITION is written in the
// vertex stage from the projected anchor (the instance origin), so the size in pixels never depends on zoom.
//   COLOR = (player rgb sRGB, a = (shape id + 8 * outlined) / 16)
//   INSTANCE_CUSTOM = (hp fraction, bar width px, colour id, pips mask)   colour id 0 green, 1 yellow, 2 red, 3 construction cyan
//   instance basis scale = fade 0..1 (the instance origin is the anchor)
//   pips mask: bits 0-3 = squad members - 1 (tick marks at member thresholds), higher bits reserved for status pips (VIEW-W2)
render_mode unshaded, blend_mix, depth_test_disabled, depth_draw_never, cull_disabled, fog_disabled;

#include "res://assets/shaders/view_common.gdshaderinc"

uniform float bar_h_px = 5.0;
uniform float pip_px = 9.0;
uniform float intensity = 1.3;

varying vec2 v_px;
varying vec4 v_col;
varying vec4 v_cus;
varying float v_fade;

void vertex() {
	vec4 clip = PROJECTION_MATRIX * (VIEW_MATRIX * (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)));
	float w = max(INSTANCE_CUSTOM.y, 8.0);
	float x0 = -(w * 0.5 + 2.0 + pip_px + 1.0);
	float x1 = w * 0.5 + 2.0;
	float hh = bar_h_px * 0.5 + 2.0;
	vec2 uv = VERTEX.xy + 0.5;
	vec2 px = vec2(mix(x0, x1, uv.x), mix(-hh, hh, uv.y));
	v_px = px;
	v_col = COLOR;
	v_cus = INSTANCE_CUSTOM;
	v_fade = length(MODEL_MATRIX[0].xyz);  // instance fade rides in the (otherwise unused) basis scale
	vec2 ndc = px * 2.0 / VIEWPORT_SIZE;
	if (clip.w <= 0.01) {
		POSITION = vec4(3.0, 3.0, 1.0, 1.0);
	} else {
		POSITION = vec4(clip.xy + ndc * clip.w, clip.z, clip.w);
	}
}

float sd_box(vec2 p, vec2 b) {
	vec2 d = abs(p) - b;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// distance-like field of the eight pip shapes in a unit disc (negative inside)
float pip_sd(int shape, vec2 q) {
	if (shape == 0) {
		return length(q) - 0.9;
	} else if (shape == 1) {   // triangle, point up
		q.y += 0.15;
		vec2 k = vec2(0.866, 0.5);
		float d = max(abs(q.x) * k.x + q.y * k.y, -q.y) - 0.62;
		return d * 1.2;
	} else if (shape == 2) {   // square
		return sd_box(q, vec2(0.72));
	} else if (shape == 3) {   // diamond
		return (abs(q.x) + abs(q.y)) - 0.95;
	} else if (shape == 4) {   // cross
		return min(sd_box(q, vec2(0.9, 0.3)), sd_box(q, vec2(0.3, 0.9)));
	} else if (shape == 5) {   // hexagon
		vec2 a = abs(q);
		return max(a.x * 0.866 + a.y * 0.5, a.y) - 0.82;
	} else if (shape == 6) {   // star (pinched diamond + cross)
		float d1 = (abs(q.x) + abs(q.y)) - 1.0;
		float d2 = max(abs(q.x), abs(q.y)) - 0.5;
		return min(d1 * 0.9, d2 + 0.12);
	}
	return sd_box(q, vec2(0.95, 0.32));   // bar
}

void fragment() {
	vec2 px = v_px;
	float w = max(v_cus.y, 8.0);
	float frac = clamp(v_cus.x, 0.0, 1.0);
	int cid = int(v_cus.z + 0.5);
	int members = (int(v_cus.w + 0.5) & 15) + 1;
	float aa = 0.75;
	vec3 fill = vec3(0.20, 0.90, 0.30);
	if (cid == 1) {
		fill = vec3(0.95, 0.85, 0.20);
	} else if (cid == 2) {
		fill = vec3(0.95, 0.20, 0.15);
	} else if (cid == 3) {
		fill = vec3(0.65, 0.92, 1.0);
	}
	fill = vc_to_lin(fill);
	float hh = bar_h_px * 0.5;
	// bar box: border 1 px around the fill area
	float d_bar = sd_box(px, vec2(w * 0.5, hh));
	float d_border = sd_box(px, vec2(w * 0.5 + 1.0, hh + 1.0));
	float inside_bar = 1.0 - smoothstep(-aa, 0.0, d_bar);
	float inside_border = 1.0 - smoothstep(-aa, 0.0, d_border);
	float fill_x = -w * 0.5 + w * frac;
	float filled = inside_bar * (1.0 - smoothstep(fill_x - aa * 0.5, fill_x + aa * 0.5, px.x));
	vec3 back = vec3(0.06, 0.07, 0.08);
	vec3 col = mix(back, fill, filled);
	// slight vertical shading on the fill
	float sh = 0.85 + 0.25 * (1.0 - (px.y + hh) / (2.0 * hh));
	col = mix(col, col * sh, filled);
	// squad member tick marks
	if (members > 1) {
		float u = (px.x + w * 0.5) / w * float(members);
		float tick = 1.0 - smoothstep(0.0, 1.2 / w * float(members), abs(u - floor(u + 0.5)));
		float is_tick = step(0.5, u) * step(u, float(members) - 0.5);
		col = mix(col, vec3(0.03), tick * is_tick * inside_bar * 0.85);
	}
	float a = inside_border;
	col = mix(vec3(0.02, 0.02, 0.03), col, inside_bar);
	// player shape pip
	float pcx = -(w * 0.5 + 2.0 + pip_px * 0.5 + 0.5);
	vec2 q = (px - vec2(pcx, 0.0)) / (pip_px * 0.5);
	int shape = int(floor(v_col.a * 16.0 + 0.5)) & 7;
	bool outlined = int(floor(v_col.a * 16.0 + 0.5)) >= 8;
	float sd = pip_sd(shape, q) * pip_px * 0.5;
	float in_pip = 1.0 - smoothstep(-aa, 0.0, sd);
	float in_pip_out = 1.0 - smoothstep(-aa, 0.0, sd - 1.2);
	vec3 pcol = vc_to_lin(v_col.rgb);
	if (outlined) {
		float ring = in_pip - (1.0 - smoothstep(-aa, 0.0, sd + 1.6));
		pcol = mix(vec3(0.03), pcol, 1.0 - (in_pip - ring));
	}
	col = mix(col, pcol * 1.0, in_pip);
	a = max(a, in_pip_out * 0.9);
	col = mix(col, vec3(0.02), (in_pip_out - in_pip) * step(in_pip, 0.999));
	if (a < 0.01) {
		discard;
	}
	ALBEDO = col * vec3(1.0) * mix(1.0, intensity, filled + in_pip);
	ALPHA = a * clamp(v_fade, 0.0, 1.0);
}
