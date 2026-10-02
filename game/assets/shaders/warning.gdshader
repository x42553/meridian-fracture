shader_type spatial;
// Strategic warning geometry (superweapons and strike powers, render spec 5.9.5 / art_direction 5.9.4, VIEW-O3). The mesh is a
// terrain-conforming grid whose UV is the local frame of the shape in metres (ViewGroundMesh); the shape is a capsule (half length
// `hl`, radius `r`, hl = 0 a disc). One draw per primitive:
//   mode 0 AREA     dashed (friendly) or solid (hostile) outline, hazard stripes, a clock arc that drains as the countdown runs
//   mode 1 CORE     the same, filled (Perun core)
//   mode 2 IMPACT   thin ring with a cross (Atlas rods, Horizon strikes); geom.z = 1 flashes when the packet has landed
//   mode 3 LINE     capsule with flowing chevrons, a sweep bar during execution (Helios) and a progress bar on the outline
//   mode 4 TRAIL    thin dashed line only (Tempest approach path): drawn as a capsule of radius r with hl half length
// Colours: WARN amber for the owner's team, DANGER red for hostile viewers (never colour alone: dash vs solid outline, corner ticks).
//   geom = (hl, r, sweep01 / hit, 0)    st = (t_anim, remaining01, phase 0 warn 1 exec 2 done 3 cancelled, hostile)
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, fog_disabled, skip_vertex_transform;

#include "res://assets/shaders/view_common.gdshaderinc"

uniform int mode = 0;
uniform vec4 geom = vec4(0.0, 6.0, 0.0, 0.0);
uniform vec4 st = vec4(0.0, 1.0, 0.0, 0.0);
uniform float fade = 1.0;
uniform vec3 warn_col : source_color = vec3(1.0, 0.72, 0.15);
uniform vec3 danger_col : source_color = vec3(1.0, 0.20, 0.16);
uniform float pull_m = 0.16;
uniform float intensity = 1.0;

varying vec2 v_uv;

void vertex() {
	v_uv = UV;
	vec3 vp = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vp -= normalize(vp) * pull_m;
	VERTEX = vp;
}

float sd_caps(vec2 p, float hl, float r) {
	vec2 q = vec2(max(abs(p.x) - hl, 0.0), p.y);
	return length(q) - r;
}

float perimeter(vec2 p, float hl, float r) {
	float cx = clamp(p.x, -hl, hl);
	return cx + r * atan(p.y, p.x - cx);
}

float band(float x, float w, float aa) {
	return 1.0 - smoothstep(w, w + aa, abs(x));
}

void fragment() {
	vec2 p = v_uv;
	float hl = geom.x;
	float r = geom.y;
	float t = st.x;
	float remaining = clamp(st.y, 0.0, 1.0);
	float phase = st.z;
	float hostile = st.w;
	float d = sd_caps(p, hl, r);
	float aa = max(fwidth(d) * 1.3, 0.04);
	float inside = 1.0 - smoothstep(-aa, aa, d);
	vec3 col = mix(warn_col, danger_col, hostile);
	float exec = phase > 0.5 && phase < 1.5 ? 1.0 : 0.0;
	float speed = phase < 0.5 ? 3.0 + 9.0 * (1.0 - remaining) : 10.0;
	float pulse = 0.72 + 0.28 * sin(t * speed);
	float stroke_w = 0.34;
	float rim = band(d + stroke_w * 0.5, stroke_w * 0.5, aa);
	float halo = band(d + stroke_w * 0.5, stroke_w * 0.5 + 0.22, aa * 2.0) - rim;
	halo = max(halo, 0.0);
	float per = perimeter(p, hl, r);
	// friendly = dashed outline, hostile = solid + corner ticks every quarter of the perimeter
	float dash = mix(step(0.32, fract(per / 1.5 - t * 0.35)), 1.0, hostile);
	float a = 0.0;
	float dark = 0.0;

	if (mode == 2) {
		// IMPACT circle: ring, cross, flash when hit
		float ring = band(d + 0.12, 0.12, aa);
		float cross = min(band(p.x, 0.07, aa), 1.0) * step(abs(p.y), r * 0.55) + min(band(p.y, 0.07, aa), 1.0) * step(abs(p.x), r * 0.55);
		cross = min(cross, 1.0) * inside;
		float hit = clamp(geom.z, 0.0, 1.0);
		a = ring * 0.95 * mix(pulse, 1.0, hit) + cross * 0.5 + inside * (0.10 * pulse + hit * hit * 0.22);  // the landing flash is a soft disc, not an opaque cream plate
		col = mix(col, vec3(1.0, 0.92, 0.75), hit * 0.4);
		dark = halo * 0.5;
	} else if (mode == 4) {
		float dsh = step(0.5, fract(p.x / 1.2 - t * 0.8));
		a = inside * dsh * 0.8;
	} else {
		// clock arc: the outline is bright for the remaining fraction of the countdown and dim for the elapsed part
		float lit = 1.0;
		if (hl < 0.01) {
			float a01 = fract(atan(p.y, p.x) / VC_TAU + 0.25);
			lit = a01 <= remaining || phase > 0.5 ? 1.0 : 0.30;
		} else {
			float u01 = clamp((p.x + hl + r) / (2.0 * (hl + r)), 0.0, 1.0);
			lit = (u01 >= 1.0 - remaining || phase > 0.5) ? 1.0 : 0.30;
			lit = p.y > 0.0 ? lit : 1.0;
		}
		float rim_a = rim * dash * lit;
		// hazard stripes scrolling slowly
		float stripes = step(0.5, fract((p.x + p.y) * 0.32 - t * 0.12));
		float fill = inside * (0.06 + stripes * (0.07 + 0.08 * hostile)) * pulse;
		if (mode == 1) {
			fill = inside * (0.20 + 0.10 * stripes) * pulse;
			float core_glow = (1.0 - smoothstep(0.0, r, length(p))) * 0.25 * pulse;
			fill += core_glow * inside;
		}
		float ticks = 0.0;
		if (hostile > 0.5) {
			float q = fract(per / (max(6.2831 * r + 4.0 * hl, 1.0)) * 4.0);
			ticks = band(d + 0.9, 0.55, aa) * (1.0 - smoothstep(0.0, 0.05, q)) * 0.9;
		}
		a = max(rim_a * 0.95, fill) + ticks;
		if (mode == 3) {
			// flowing chevrons along the axis, a sweep bar in execution
			float cv = fract((p.x - abs(p.y) * 0.75 - t * 2.2) / 3.0);
			float chev = (1.0 - smoothstep(0.0, 0.10, cv)) * inside * step(abs(p.y), r * 0.85) * (1.0 - exec * 0.7);
			a += chev * 0.55;
			float sweep = clamp(geom.z, 0.0, 1.0);
			float sx = -hl + (2.0 * hl) * sweep;
			float bar = band(p.x - sx, 0.9, 0.5) * inside;
			float trail = (1.0 - smoothstep(0.0, 6.0, sx - p.x)) * step(p.x, sx) * inside * 0.25;
			a += exec * (bar * 0.85 + trail);
			col = mix(col, vec3(1.0, 0.95, 0.8), bar * exec * 0.7);
		}
		dark = halo * 0.55;
		if (exec > 0.5) {
			a += inside * 0.10 * pulse;
		}
	}
	if (phase > 1.5) {
		// done / cancelled: a quick fade, cancelled flashes white once
		a *= phase > 2.5 ? 0.7 : 1.0;
	}
	a *= fade;
	dark *= fade;
	if (a + dark < 0.004) {
		discard;
	}
	vec3 c = col * intensity;
	ALBEDO = c * a;
	ALPHA = clamp(a + dark * (1.0 - a), 0.0, 1.0);
}
