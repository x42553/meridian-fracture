shader_type spatial;
// Status glyphs and capture rings (render spec 5.9.7, VIEW-W2). Two modes on one shader:
//   mode 0 GLYPH   a constant-screen-size billboard (like health_bar.gdshader): the quad origin is projected, the size is in pixels.
//                  COLOR = (glyph tint rgb, alpha)   INSTANCE_CUSTOM = (glyph id, slot x offset px, y offset px, phase)
//                  ids: 0 EMP bolt, 1 suppressed chevrons, 2 cloak (dashed ring), 3 no power (plug), 4 decoy identified (lens),
//                  5 repair (wrench), 6 buff (up arrow), 7 marked (crosshair)
//   mode 1 RING    a terrain-aligned quad around a structure footprint: the capture progress ring in the capturer's colour.
//                  COLOR = (capturer colour, alpha)   INSTANCE_CUSTOM = (progress 0..1, half x m, half z m, seed); quad = 2 x 2 scaled
//                  to the footprint half extents + margin (basis scale), stroke 0.4 m.
// The ring variant is compiled with `#define RING 1` prepended (ViewStatusMarks): it keeps the depth test so structures cover it.
#ifdef RING
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, fog_disabled;
#else
render_mode unshaded, blend_premul_alpha, depth_test_disabled, depth_draw_never, cull_disabled, fog_disabled;
#endif

#include "res://assets/shaders/view_common.gdshaderinc"

uniform int mode = 0;
uniform float glyph_px = 22.0;
uniform float intensity = 1.1;
uniform float ring_margin = 0.8;
uniform float pull_m = 0.2;

varying vec2 v_q;
varying vec4 v_col;
varying vec4 v_cus;
varying vec2 v_p;

void vertex() {
	v_col = COLOR;
	v_cus = INSTANCE_CUSTOM;
	v_q = VERTEX.xy * 2.0;
	v_p = VERTEX.xz;
	if (mode == 0) {
		vec4 clip = PROJECTION_MATRIX * (VIEW_MATRIX * (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)));
		vec2 px = VERTEX.xy * glyph_px + vec2(INSTANCE_CUSTOM.y, INSTANCE_CUSTOM.z);
		vec2 ndc = px * 2.0 / VIEWPORT_SIZE;
		if (clip.w <= 0.01) {
			POSITION = vec4(3.0, 3.0, 1.0, 1.0);
		} else {
			POSITION = vec4(clip.xy + ndc * clip.w, clip.z, clip.w);
		}
	} else {
		vec3 vp = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
		vp -= normalize(vp) * pull_m;
		POSITION = PROJECTION_MATRIX * vec4(vp, 1.0);
	}
}

float sd_box(vec2 p, vec2 b) {
	vec2 d = abs(p) - b;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

float sd_seg(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

// signed distance of each glyph in the [-1, 1] quad (negative inside the ink), thickness folded in
float glyph_sd(int id, vec2 q, float phase) {
	if (id == 0) {  // lightning bolt
		float d = sd_seg(q, vec2(0.25, 0.95), vec2(-0.25, 0.05)) - 0.20;
		d = min(d, sd_seg(q, vec2(-0.25, 0.05), vec2(0.25, -0.05)) - 0.20);
		d = min(d, sd_seg(q, vec2(0.25, -0.05), vec2(-0.25, -0.95)) - 0.20);
		return d;
	} else if (id == 1) {  // two down chevrons
		float d = sd_seg(q, vec2(-0.7, 0.55), vec2(0.0, 0.05)) - 0.17;
		d = min(d, sd_seg(q, vec2(0.7, 0.55), vec2(0.0, 0.05)) - 0.17);
		d = min(d, sd_seg(q, vec2(-0.7, -0.05), vec2(0.0, -0.55)) - 0.17);
		d = min(d, sd_seg(q, vec2(0.7, -0.05), vec2(0.0, -0.55)) - 0.17);
		return d;
	} else if (id == 2) {  // dashed ring
		float r = length(q);
		float a = atan(q.y, q.x) / VC_TAU * 8.0;
		float dash = step(0.5, fract(a + phase * 0.3));
		float ring = abs(r - 0.7) - 0.17;
		return mix(0.6, ring, dash);
	} else if (id == 3) {  // crossed-out bolt: no power
		float d = sd_seg(q, vec2(0.22, 0.85), vec2(-0.22, 0.05)) - 0.17;
		d = min(d, sd_seg(q, vec2(-0.22, 0.05), vec2(0.22, -0.05)) - 0.17);
		d = min(d, sd_seg(q, vec2(0.22, -0.05), vec2(-0.22, -0.85)) - 0.17);
		float slash = sd_seg(q, vec2(-0.9, 0.9), vec2(0.9, -0.9)) - 0.11;
		return min(d, slash);
	} else if (id == 4) {  // lens
		float ring = abs(length(q - vec2(-0.12, 0.12)) - 0.5) - 0.15;
		float handle = sd_seg(q, vec2(0.24, -0.24), vec2(0.8, -0.8)) - 0.17;
		return min(ring, handle);
	} else if (id == 5) {  // wrench
		float d = sd_seg(q, vec2(-0.55, -0.55), vec2(0.3, 0.3)) - 0.17;
		d = min(d, length(q - vec2(0.42, 0.42)) - 0.42);
		float cut = sd_box((mat2(vec2(0.7071, 0.7071), vec2(-0.7071, 0.7071)) * (q - vec2(0.42, 0.42))) - vec2(0.0, 0.34), vec2(0.15, 0.3));
		return max(d, -cut);
	} else if (id == 6) {  // up arrow
		float d = sd_seg(q, vec2(0.0, -0.8), vec2(0.0, 0.5)) - 0.17;
		d = min(d, sd_seg(q, vec2(-0.6, 0.0), vec2(0.0, 0.8)) - 0.17);
		d = min(d, sd_seg(q, vec2(0.6, 0.0), vec2(0.0, 0.8)) - 0.17);
		return d;
	}
	// crosshair
	float ring2 = abs(length(q) - 0.55) - 0.12;
	float cross = min(sd_box(q, vec2(0.95, 0.09)), sd_box(q, vec2(0.09, 0.95)));
	return min(ring2, cross);
}

void fragment() {
	vec3 col = vc_to_lin(v_col.rgb);
	if (mode == 0) {
		int id = int(v_cus.x + 0.5);
		vec2 q = v_q;
		float aa = max(fwidth(q.x) * 1.4, 0.05);
		float sd = glyph_sd(id, q, v_cus.w);
		float ink = 1.0 - smoothstep(-aa, aa, sd);
		float halo = (1.0 - smoothstep(-aa, aa, sd - 0.28)) - ink;
		float plate = (1.0 - smoothstep(0.86, 1.0, length(q))) * 0.5;
		float pulse = 0.85 + 0.15 * sin(v_cus.w * 6.0 + view_time * 6.0);
		float a = ink * v_col.a;
		float dark = max(max(halo, 0.0) * 0.85, plate) * v_col.a;
		if (a + dark < 0.01) {
			discard;
		}
		ALBEDO = col * intensity * pulse * a;
		ALPHA = a + dark * (1.0 - a);
	} else {
		vec2 hxz = v_cus.yz + vec2(ring_margin);
		vec2 m = v_p * hxz;
		float d = sd_box(m, v_cus.yz + vec2(0.1)) - 0.2;
		float aa = max(fwidth(d) * 1.4, 0.03);
		float ring = 1.0 - smoothstep(0.2, 0.2 + aa, abs(d));
		float halo = (1.0 - smoothstep(0.2, 0.2 + aa * 3.0 + 0.25, abs(d))) - ring;
		float a01 = fract(atan(m.x, -m.y) / VC_TAU);
		float lit = a01 <= v_cus.x ? 1.0 : 0.22;
		float a = ring * lit * v_col.a;
		float dark = max(halo, 0.0) * 0.6 * v_col.a;
		if (a + dark < 0.01) {
			discard;
		}
		ALBEDO = col * intensity * a;
		ALPHA = a + dark * (1.0 - a);
	}
}
