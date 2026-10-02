shader_type spatial;
// Ground zones without models (render spec 5.9.7, VIEW-W2): smoke Dust Screen, debris-slow field, repair station, sensor puck,
// shelter, portable cover, decoy hologram, buff aura, scan ping, interception ground ring. The mesh is a terrain-conforming grid
// (ViewGroundMesh) whose UV is the position in the zone's local frame in metres; the zone shape is a capsule (half length `hl`,
// radius `r`; hl = 0 is a disc) evaluated as a signed distance. Smoke uses several stacked sheets (COLOR.r = layer 0..1).
//   kind (DefEnums.ZoneKind): 0 BUFF 1 SMOKE 2 INTERCEPT(ground ring) 3 DEBRIS 4 DECOY 5 PUCK 6 SHELTER 7 COVER 8 REPAIR 9 REVEAL
//   geom = (hl, r, layer_count, charge01)   tm = (t_anim s, age s, fade 0..1, warmup 0/1)   hostile 0 friendly .. 1 enemy
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, fog_disabled, skip_vertex_transform;

#include "res://assets/shaders/view_common.gdshaderinc"
#include "res://assets/shaders/fog_of_war.gdshaderinc"

uniform int kind = 0;
uniform vec4 geom = vec4(0.0, 6.0, 1.0, 1.0);
uniform vec4 tm = vec4(0.0, 0.0, 1.0, 0.0);
uniform vec3 tint : source_color = vec3(0.4, 0.8, 1.0);
uniform float hostile = 0.0;
uniform float use_fog = 0.0;      // 1: fade with the fog of war (zones of other teams)
uniform float pull_m = 0.12;
uniform float intensity = 0.9;

varying vec2 v_uv;
varying vec3 v_w;
varying float v_layer;

void vertex() {
	v_uv = UV;
	v_layer = COLOR.r;
	v_w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 vp = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vp -= normalize(vp) * pull_m;
	VERTEX = vp;
}

float sd_caps(vec2 p, float hl, float r) {
	vec2 q = vec2(max(abs(p.x) - hl, 0.0), p.y);
	return length(q) - r;
}

float sd_box(vec2 p, vec2 b) {
	vec2 d = abs(p) - b;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = vc_hash21(i);
	float b = vc_hash21(i + vec2(1.0, 0.0));
	float c = vc_hash21(i + vec2(0.0, 1.0));
	float d = vc_hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	return vnoise(p) * 0.5 + vnoise(p * 2.03 + vec2(7.1, 3.7)) * 0.3 + vnoise(p * 4.1 + vec2(1.3, 9.2)) * 0.2;
}

// position along the outline (metres), for dash patterns
float perimeter(vec2 p, float hl, float r) {
	float cx = clamp(p.x, -hl, hl);
	return cx + r * atan(p.y, p.x - cx);
}

void fragment() {
	vec2 p = v_uv;
	float hl = geom.x;
	float r = geom.y;
	float t = tm.x;
	float d = sd_caps(p, hl, r);
	float aa = max(fwidth(d) * 1.2, 0.03);
	float inside = 1.0 - smoothstep(-aa, aa, d);
	vec3 rimc = mix(tint, vec3(1.0, 0.32, 0.26), hostile);
	vec3 col = tint;
	float a = 0.0;
	float per = perimeter(p, hl, r);
	float rd = -d;  // depth inside the outline (>= 0 inside)

	if (kind == 1) {
		// SMOKE: stacked drifting cloud sheets, dark stain on the ground sheet
		float L = v_layer;
		vec2 drift = vec2(t * 0.06 * (1.0 + L), t * 0.035 * (1.0 - 0.5 * L));
		float n = fbm(p * 0.28 + drift + vec2(L * 5.0, L * 3.0));
		float n2 = fbm(p * 0.7 - drift * 1.7 + vec2(3.0, L * 9.0));
		float edge = smoothstep(-0.3, -r * 0.55, d + (n - 0.5) * r * 0.5);
		float dens = smoothstep(0.22, 0.72, n * 0.75 + n2 * 0.4) * edge;
		float layer_a = mix(0.62, 0.34, L);
		float ground = step(L, 0.001);
		a = dens * layer_a * (1.0 - ground * 0.25);
		vec3 lo = vec3(0.34, 0.32, 0.29);
		vec3 hi = vec3(0.86, 0.83, 0.76);
		col = mix(lo, hi, clamp(L * 0.8 + n2 * 0.35, 0.0, 1.0));
		col = vc_to_lin(col);
		// a faint outline so the extent stays readable from above
		float rim = 1.0 - smoothstep(0.0, aa * 2.0 + 0.05, abs(d + 0.12));
		float dash = step(0.5, fract(per / 1.6 - t * 0.2));
		a = max(a, rim * dash * 0.28 * (1.0 - L));
	} else if (kind == 8) {
		// REPAIR STATION: cyan ring, rising crosses, an outward pulse
		float rim = 1.0 - smoothstep(0.0, aa * 2.0 + 0.05, abs(d + 0.14));
		float fill = inside * (0.05 + 0.10 * smoothstep(-3.0, 0.0, d));
		float ph = fract(t * 0.4);
		float pr = ph * r;
		float pd = abs(sd_caps(p, hl, max(pr, 0.01)));
		float pulse = (1.0 - smoothstep(0.0, 0.55, pd)) * (1.0 - ph) * inside * step(0.0, r - pr);
		float cell_s = 2.6;
		vec2 cell = floor(p / cell_s);
		vec2 f = fract(p / cell_s) - 0.5;
		float h = vc_hash21(cell);
		float tt = fract(t * 0.35 + h);
		vec2 mp = (f - vec2((vc_hash21(cell + vec2(3.0, 5.0)) - 0.5) * 0.3, -0.5 + tt)) * cell_s;
		float plus = min(sd_box(mp, vec2(0.22, 0.06)), sd_box(mp, vec2(0.06, 0.22)));
		float pm = (1.0 - smoothstep(-0.02, 0.03, plus)) * sin(tt * 3.14159) * step(0.35, h) * smoothstep(0.4, 1.2, rd);
		col = mix(tint, vec3(0.8, 1.0, 0.95), pm);
		a = max(rim * 0.9, fill) + pulse * 0.5 + pm * 0.9;
		col = mix(col, rimc, rim * hostile);
	} else if (kind == 5) {
		// SENSOR PUCK: range rings, a rotating sweep wedge, blips
		float ring1 = 1.0 - smoothstep(0.0, aa * 2.0 + 0.04, abs(length(p) - r * 0.34));
		float ring2 = 1.0 - smoothstep(0.0, aa * 2.0 + 0.04, abs(length(p) - r * 0.67));
		float rim = 1.0 - smoothstep(0.0, aa * 2.0 + 0.06, abs(d + 0.14));
		float ang = atan(p.y, p.x) / VC_TAU + 0.5;
		float sweep = fract(ang - t * 0.35);
		float wedge = pow(1.0 - sweep, 5.0) * inside;
		vec2 bc = floor(p / 3.4);
		float bh = vc_hash21(bc);
		vec2 bp = (fract(p / 3.4) - 0.5) * 3.4;
		float blip = (1.0 - smoothstep(0.0, 0.25, length(bp - (vec2(vc_hash21(bc + 5.0), vc_hash21(bc + 9.0)) - 0.5) * 1.6))) * step(0.72, bh);
		blip *= pow(1.0 - fract(ang - t * 0.35 - bh), 3.0) * inside;
		col = tint;
		a = rim * 0.9 + (ring1 + ring2) * 0.28 + wedge * 0.42 + blip * 0.95 + inside * 0.04;
		col = mix(col, rimc, rim * hostile);
	} else if (kind == 3) {
		// DEBRIS-SLOW FIELD (Horizon): dusty haze, scattered rubble, hazard-dash border
		float n = fbm(p * 0.32 + vec2(t * 0.03, 0.0));
		float haze = inside * smoothstep(0.3, 0.8, n) * 0.30;
		vec2 c = floor(p / 0.95);
		float ch = vc_hash21(c);
		vec2 cp = (fract(p / 0.95) - 0.5 + (vec2(vc_hash21(c + 4.0), vc_hash21(c + 8.0)) - 0.5) * 0.5) * 0.95;
		float speck = (1.0 - smoothstep(0.05, 0.2 + ch * 0.12, length(cp))) * step(0.55, ch) * inside * smoothstep(0.2, 0.8, rd);
		float rim = 1.0 - smoothstep(0.0, aa * 2.0 + 0.05, abs(d + 0.18));
		float dash = step(0.5, fract(per / 1.1 + 0.25));
		vec3 hazard = mix(vec3(0.05), vec3(1.0, 0.72, 0.16), dash);
		vec3 dust = vc_to_lin(vec3(0.62, 0.46, 0.30));
		vec3 rock = vc_to_lin(vec3(0.16, 0.14, 0.12));
		col = mix(dust, rock, speck);
		col = mix(col, vc_to_lin(hazard), rim);
		a = max(max(haze, speck * 0.9), rim * 0.85);
		a = max(a, inside * 0.08);
	} else if (kind == 6 || kind == 7) {
		// SHELTER / PORTABLE COVER: dashed ring, faint hex plate, a pulsing core
		float rim = 1.0 - smoothstep(0.0, aa * 2.0 + 0.04, abs(d + 0.1));
		float dash = kind == 7 ? step(0.5, fract(per / 0.7 - t * 0.5)) : step(0.35, fract(per / 1.3 + t * 0.15));
		vec2 hp = p * 1.6;
		vec2 hq = abs(fract(hp / vec2(1.732, 1.0) ) - 0.5);
		float hexl = 1.0 - smoothstep(0.42, 0.5, max(hq.x * 1.15, hq.y));
		float core = (1.0 - smoothstep(0.0, r * 0.9, length(p))) * (0.5 + 0.5 * sin(t * 2.4));
		a = rim * dash * 0.95 + inside * (0.10 + hexl * 0.06) + core * 0.18;
		col = mix(tint, rimc, rim * hostile);
	} else if (kind == 4) {
		// DECOY hologram (own team only): scanlines climbing, glitch flicker, dashed border
		float rim = 1.0 - smoothstep(0.0, aa * 2.0 + 0.04, abs(d + 0.1));
		float scan = smoothstep(0.35, 0.5, abs(fract(p.y * 1.6 - t * 0.7) - 0.5));
		float glitch = step(0.93, fract(sin(floor(t * 8.0) * 12.9898) * 43758.5));
		float dash = step(0.5, fract(per / 0.9 + t * 0.4));
		a = rim * dash * 0.9 + inside * (0.05 + scan * 0.10) + glitch * inside * 0.10;
		col = mix(tint, vec3(0.9, 0.5, 1.0), 0.35 * scan);
	} else if (kind == 9) {
		// REVEAL (wideband scan): expanding rings, warm-up = dashed ring
		float ph = fract(t * 0.5);
		float ring = 1.0 - smoothstep(0.0, 0.5, abs(length(p) - ph * r));
		float ring2 = 1.0 - smoothstep(0.0, 0.5, abs(length(p) - fract(ph + 0.5) * r));
		float rim = 1.0 - smoothstep(0.0, aa * 2.0 + 0.06, abs(d + 0.14));
		float dash = tm.w > 0.5 ? step(0.5, fract(per / 1.2 - t)) : 1.0;
		a = rim * dash * 0.9 + (ring * (1.0 - ph) + ring2 * ph) * inside * 0.55 + inside * 0.05;
		col = mix(tint, rimc, rim * hostile);
	} else if (kind == 2) {
		// INTERCEPTION ground ring (the dome is a separate mesh)
		float rim = 1.0 - smoothstep(0.0, aa * 2.0 + 0.08, abs(d + 0.2));
		float rim2 = 1.0 - smoothstep(0.0, aa * 2.0 + 0.04, abs(d + 0.7));
		vec2 hp = p * 0.5;
		vec2 hq = abs(fract(hp / vec2(1.732, 1.0)) - 0.5);
		float hexl = 1.0 - smoothstep(0.44, 0.5, max(hq.x * 1.15, hq.y));
		float charge = clamp(geom.w, 0.0, 1.0);
		a = (rim * 0.95 + rim2 * 0.35 + inside * (0.06 + hexl * 0.05)) * mix(0.45, 1.0, charge);
		col = mix(vec3(1.0, 0.62, 0.15), tint, smoothstep(0.1, 0.4, charge));
	} else {
		// BUFF aura: soft pulsing ring
		float rim = 1.0 - smoothstep(0.0, aa * 2.0 + 0.06, abs(d + 0.14));
		float pulse = 0.65 + 0.35 * sin(t * 2.6);
		a = rim * 0.75 * pulse + inside * 0.07 * pulse;
		col = mix(tint, rimc, rim * hostile);
	}

	a *= tm.z;
	if (use_fog > 0.5) {
		float vis = fow_sample(v_w.xz).y;
		float expl = fow_sample(v_w.xz).x;
		a *= mix(0.0, mix(0.35, 1.0, vis), expl);
	}
	if (a < 0.004) {
		discard;
	}
	// premultiplied output (zone colours stay saturated under the tone mapper)
	ALBEDO = col * intensity * a;
	ALPHA = a;
}
