shader_type spatial;
// Placement footprint grid (render spec 5.10). A ground-following mesh of (w + 2) x (h + 2) cells; UV = the cell coordinate
// relative to the footprint origin (the footprint spans [0, w] x [0, h], the outer ring is the gap-1 halo). A w x h R8 texture
// holds one ViewPlacementState CF_* code per footprint cell:
//   0 OK green | 1 TERRAIN, 2 STRUCTURE red | 3 UNIT, 5 DEBRIS orange | 4 DEPOSIT magenta | 6 APRON yellow | 7 SHORE cyan |
//   8 KEEPOUT light red hatch
// `verdict` 0 = the placement is valid, 1 = invalid: an OK cell is then drawn amber (the cell is fine, the placement is not).
// The footprint gets a bright outline in the verdict colour; the halo is a faint dashed outline so the player sees why a
// neighbour is refused.
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, fog_disabled, skip_vertex_transform;

#include "res://assets/shaders/view_common.gdshaderinc"

uniform sampler2D codes : filter_nearest, repeat_disable;
uniform vec2 fp_size = vec2(1.0, 1.0);
uniform float verdict = 0.0;
uniform float pull_m = 0.2;
uniform float intensity = 0.8;
uniform float pulse = 1.0;
uniform float alpha_scale = 1.0;  // the x-ray copy (cells hidden behind a structure) is drawn fainter

varying vec2 v_cell;

void vertex() {
	v_cell = UV;
	vec3 vp = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vp -= normalize(vp) * pull_m;
	VERTEX = vp;
}

vec3 code_color(int code, float valid_flag) {
	if (code == 0) {
		return valid_flag > 0.5 ? vec3(1.0, 0.72, 0.18) : vec3(0.25, 1.0, 0.40);
	} else if (code == 3 || code == 5) {
		return vec3(1.0, 0.55, 0.12);
	} else if (code == 4) {
		return vec3(1.0, 0.2, 0.9);
	} else if (code == 6) {
		return vec3(1.0, 0.92, 0.25);
	} else if (code == 7) {
		return vec3(0.25, 0.9, 1.0);
	} else if (code == 8) {
		return vec3(1.0, 0.45, 0.45);
	}
	return vec3(1.0, 0.22, 0.20);
}

void fragment() {
	vec2 c = v_cell;
	vec2 f = fract(c);
	vec2 fw = max(fwidth(c), vec2(0.0005));
	float edge = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
	float ew = max(fw.x, fw.y);
	float cell_line = 1.0 - smoothstep(ew * 0.8, ew * 2.2, edge);
	bool inside = c.x >= 0.0 && c.y >= 0.0 && c.x < fp_size.x && c.y < fp_size.y;
	vec3 col = vec3(0.0);
	float a = 0.0;
	if (inside) {
		int code = int(texelFetch(codes, ivec2(floor(c)), 0).r * 255.0 + 0.5);
		col = code_color(code, verdict);
		float fill = code == 0 ? 0.34 : 0.46;
		if (code == 8) {
			float hatch = step(0.5, fract((c.x + c.y) * 3.0));
			fill = 0.18 + 0.32 * hatch;
		}
		a = fill * pulse;
		// bright cell borders so the individual cells read at any zoom
		col = mix(col, vec3(1.0), cell_line * 0.55);
		a = max(a, cell_line * 0.75);
		// outer footprint outline in the verdict colour
		float d = min(min(c.x, fp_size.x - c.x), min(c.y, fp_size.y - c.y));
		float ol = 1.0 - smoothstep(ew * 1.2, ew * 3.6, d);
		vec3 ocol = verdict > 0.5 ? vec3(1.0, 0.3, 0.25) : vec3(0.6, 1.0, 0.6);
		col = mix(col, ocol, ol);
		a = max(a, ol * 0.95);
	} else {
		// halo: one cell around the footprint, faint outline only
		vec2 lo = vec2(-1.0);
		vec2 hi = fp_size + vec2(1.0);
		bool in_halo = c.x >= lo.x && c.y >= lo.y && c.x < hi.x && c.y < hi.y;
		if (!in_halo) {
			discard;
		}
		float dd = min(min(c.x - lo.x, hi.x - c.x), min(c.y - lo.y, hi.y - c.y));
		float outer = 1.0 - smoothstep(ew * 1.0, ew * 2.6, dd);
		float dash = step(0.5, fract((c.x + c.y) * 2.0));
		col = vec3(0.9, 0.95, 1.0);
		a = 0.03 + outer * 0.5 * dash;
	}
	if (a < 0.01) {
		discard;
	}
	a *= alpha_scale;
	ALBEDO = vc_to_lin(col) * intensity * a;
	ALPHA = a;
}
