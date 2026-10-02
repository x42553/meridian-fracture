shader_type spatial;
// Construction / selling scaffold cage (render spec 5.2 BUILDUP, art_direction 5.9.6). ONE unit BoxMesh (size 1) is scaled by the
// node transform to footprint x (height * ease(build)); the lattice is drawn procedurally in METRES from the scale, so posts,
// rails and braces keep their real size at any footprint. Alpha-scissor lattice (posts every ~2.2 m, rails every ~1.7 m, X braces
// per bay, construction netting on the lower panels, team-coloured corner lamps and a glowing weld line on the top rail).
// Bottom and top faces are dropped. No fog of war sampling here: the owner of the ViewScaffolds pool only shows visible structures.

render_mode cull_disabled, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

#include "res://assets/shaders/view_common.gdshaderinc"

uniform vec3 team_color : source_color = vec3(0.85, 0.23, 0.23);
uniform vec3 steel : source_color = vec3(0.70, 0.72, 0.74);
uniform vec3 hazard : source_color = vec3(1.0, 0.62, 0.12);
uniform vec3 netting : source_color = vec3(0.50, 0.55, 0.40);
uniform float weld_glow = 1.0;    // 0..1 strength of the glowing weld line on the top rail
uniform float bay_target_m = 2.2;
uniform float level_m = 1.7;
uniform float post_w = 0.11;
uniform float seed = 0.0;

varying vec3 v_pos;
varying vec3 v_size;
varying vec3 v_nrm;

void vertex() {
	// every vertex of a BoxMesh is a corner, so abs(VERTEX) * 2 is the mesh size (1 for the unit box, any size for stand-ins)
	vec3 sc = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	v_size = abs(VERTEX) * 2.0 * sc;
	v_pos = VERTEX * sc;
	v_nrm = NORMAL;
}

// 1 inside a stripe of width w (metres or pixels-corrected) centred on multiples of `period`
float stripe(float x, float period, float w, float aa) {
	float d = abs(x - period * floor(x / period + 0.5));
	return 1.0 - smoothstep(w - aa, w + aa, d);
}

void fragment() {
	vec3 n = normalize(v_nrm);
	if (abs(n.y) > 0.5) {
		// bottom and top faces: only a thin frame on the top edge, nothing else
		discard;
	}
	bool face_x = abs(n.x) > 0.5;                       // face whose normal is X: it spans z
	float len = face_x ? v_size.z : v_size.x;
	float u = (face_x ? v_pos.z : v_pos.x) + len * 0.5;  // 0 .. len along the face
	float h = v_pos.y + v_size.y * 0.5;                  // 0 .. height
	float bays = max(floor(len / bay_target_m + 0.5), 1.0);
	float bay = len / bays;
	float aa = max(fwidth(u), fwidth(h)) * 0.75;
	float w = max(post_w, aa * 1.6);
	// posts at bay boundaries
	float post = stripe(u, bay, w, aa);
	// rails every level_m from the ground, plus a rail on the very top edge
	float levels = max(floor(v_size.y / level_m + 0.5), 1.0);
	float lvl = v_size.y / levels;
	float rail = stripe(h, lvl, w * 0.85, aa);
	float top_rail = 1.0 - smoothstep(w - aa, w + aa, abs(h - v_size.y));
	// X braces inside each bay level
	float ub = fract(u / bay) * bay;
	float hb = h - lvl * floor(h / lvl);
	float diag_a = abs(ub / bay - hb / lvl);
	float diag_b = abs(ub / bay - (1.0 - hb / lvl));
	float dw = (w * 0.7) / max(min(bay, lvl), 0.5);
	float braces = 1.0 - smoothstep(dw - aa * 0.5, dw + aa * 0.5, min(diag_a, diag_b));
	// braces only in every second level so the cage stays airy
	float lvl_id = floor(h / lvl);
	braces *= step(0.5, mod(lvl_id + floor(u / bay) + seed, 2.0));
	float frame = max(max(post, rail), max(top_rail, braces * 0.9));
	// tarp: solid sheeting on some lower bays (never the top level), so the cage reads as a site and not as a wireframe
	float bay_id = floor(u / bay);
	float tarp_face = step(0.62, fract(sin((bay_id + 1.0) * 12.9898 + seed * 4.1 + (face_x ? 7.3 : 0.0)) * 43758.5453));
	tarp_face *= step(lvl_id, max(levels - 2.0, 0.0));
	float net = tarp_face * (1.0 - frame);
	float cover = max(frame, net);
	if (cover < 0.5) {
		discard;
	}
	vec3 col;
	float rough = 0.55;
	float metal = 0.0;
	vec3 emis = vec3(0.0);
	if (frame > 0.5) {
		bool orange = (mod(bay_id + lvl_id, 2.0) < 1.0);
		col = mix(steel, hazard, orange ? 0.85 : 0.0);
		if (post > 0.5 && rail < 0.5) {
			col = mix(steel, hazard, 0.55);
		}
		rough = 0.5;
		metal = 0.65;
	} else {
		float wv = 0.5 + 0.5 * sin(u * 9.0 + h * 1.7);
		col = mix(netting, netting * 1.35, wv * 0.35);
		rough = 0.95;
		emis += col * 0.22;
	}
	// weld line: hot glow on the top rail, brighter than the tone mapper knee
	float weld = top_rail * weld_glow * (0.6 + 0.4 * sin(fx_time * 22.0 + u * 3.0));
	emis += vec3(1.0, 0.62, 0.18) * weld * 1.4;
	// team-coloured lamp at each vertical corner near the top
	float corner = (1.0 - smoothstep(0.0, 0.5, min(u, len - u))) * (1.0 - smoothstep(0.15, 0.55, abs(h - v_size.y)));
	col = mix(col, team_color, corner * 0.9);
	emis += team_color * corner * 1.6;
	ALBEDO = col;
	METALLIC = metal;
	ROUGHNESS = rough;
	EMISSION = emis;
}
