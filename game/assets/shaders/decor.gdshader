// Decoration shader for MultiMesh trees / rocks / crystals / scrap / reeds / palms / urban buildings (VIEW-04): vertex-shader wind
// sway (world-space gust direction, per-instance phase from INSTANCE_CUSTOM.x, also in the shadow pass), foliage palette from the
// mood, emissive crystals, procedural building windows (lit at night from atm_night), fog of war (hidden in shroud, dimmed in fog).
// Vertex layout (ViewDecorMeshes): COLOR.rgb baked albedo + AO, COLOR.a wind weight, UV.x material class, UV.y building variant.
// Instance layout (ViewDecor): INSTANCE_CUSTOM = (phase, variation, emissive, unused); INSTANCE_COLOR is white (Compatibility
// needs both enabled).
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_back;

#include "res://assets/shaders/view_common.gdshaderinc"
#include "res://assets/shaders/fog_of_war.gdshaderinc"
#include "res://assets/shaders/atmosphere.gdshaderinc"

uniform float wind_strength = 0.30;
uniform float wind_speed = 1.3;
uniform vec2 wind_dir = vec2(0.86, 0.5);
uniform float wind_gust_scale = 0.05;
uniform vec3 foliage_a : source_color = vec3(0.16, 0.34, 0.10);
uniform vec3 foliage_b : source_color = vec3(0.34, 0.50, 0.14);
uniform float fow_enabled = 1.0;

varying vec3 v_col;
varying float v_class;
varying float v_var;
varying float v_em;
varying float v_variant;
varying vec2 v_fow;
varying vec3 v_wpos;
varying vec3 v_wnrm;
varying float v_base_y;
varying float v_height;

void vertex() {
	mat3 m3 = mat3(MODEL_MATRIX[0].xyz, MODEL_MATRIX[1].xyz, MODEL_MATRIX[2].xyz);
	vec3 origin = MODEL_MATRIX[3].xyz;
	float w = COLOR.a;
	float ph = INSTANCE_CUSTOM.x;
	float t = view_time;
	float g1 = sin(t * wind_speed + dot(origin.xz, wind_dir) * wind_gust_scale * 6.2831 + ph * 0.25);
	float g2 = sin(t * wind_speed * 0.47 + dot(origin.xz, vec2(-wind_dir.y, wind_dir.x)) * wind_gust_scale * 3.1);
	float flutter = sin(t * wind_speed * 4.3 + dot(VERTEX, vec3(2.1, 3.3, 2.7)) + ph) * 0.18;
	float amt = (g1 * 0.6 + g2 * 0.4 + 0.35 + flutter * step(0.01, w)) * wind_strength * w;
	vec3 world_off = vec3(wind_dir.x, 0.0, wind_dir.y) * amt;
	float s2 = max(dot(m3[0], m3[0]), 1e-4);
	VERTEX += (transpose(m3) * world_off) / s2;
	v_col = clamp(COLOR.rgb, vec3(0.0), vec3(1.0));
	v_class = UV.x;
	v_variant = UV.y;
	v_var = clamp(INSTANCE_CUSTOM.y, 0.0, 1.0);
	v_em = INSTANCE_CUSTOM.z;
	v_fow = fow_enabled > 0.5 ? fow_sample(origin.xz) : vec2(1.0);
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnrm = normalize(m3 * NORMAL);
	v_base_y = origin.y;
	v_height = length(MODEL_MATRIX[1].xyz);
}

// Window mask on a vertical facade: x = window coverage 0..1, y = lit random 0..1 (per window).
vec2 facade_windows(vec3 P, vec3 N, float variant, float base_y, float height, float seed) {
	float along = abs(N.x) > abs(N.z) ? P.z : P.x;
	float face = abs(N.x) > abs(N.z) ? (N.x > 0.0 ? 1.0 : 2.0) : (N.z > 0.0 ? 3.0 : 4.0);
	float rel = P.y - base_y;
	vec2 g;
	vec2 half_size;
	if (variant < 0.5) {         // office: wide ribbon windows, 3 m floors
		g = vec2(along / 3.0, rel / 3.0);
		half_size = vec2(0.46, 0.27);
	} else if (variant < 1.5) {  // apartment: punched windows, 3 m bays, 2.8 m floors
		g = vec2(along / 3.0, rel / 2.8);
		half_size = vec2(0.22, 0.24);
	} else {                     // warehouse: one clerestory row near the top
		g = vec2(along / 4.0, (rel - height * 0.55) / 2.4);
		half_size = vec2(0.36, 0.22);
	}
	vec2 id = floor(g);
	vec2 f = fract(g) - 0.5;
	float inside = step(abs(f.x), half_size.x) * step(abs(f.y - 0.05), half_size.y);
	float band = step(1.2, rel) * (1.0 - step(height - 0.9, rel));
	if (variant > 1.5) {
		band *= step(0.0, id.y) * (1.0 - step(0.5, id.y));
	}
	float lit = vc_hash21(id + vec2(seed * 17.0 + face * 3.1, id.x * 0.37));
	return vec2(inside * band, lit);
}

void fragment() {
	if (v_fow.x < 0.5) {
		discard;
	}
	vec3 col = v_col;
	float rough = 0.85;
	float metal = 0.0;
	vec3 emis = vec3(0.0);
	float night = atm_night;
	if (v_class > 0.5 && v_class < 1.5) {
		col *= mix(foliage_a, foliage_b, v_var);
		rough = 0.8;
	} else if (v_class > 1.5 && v_class < 2.5) {
		vec3 hue = mix(vec3(0.0, 0.9, 0.7), vec3(0.55, 0.12, 1.0), step(0.62, v_var));
		col = hue * 0.22;
		rough = 0.10;
		metal = 0.25;
		emis = hue * v_em * 1.9 * (0.85 + 0.35 * sin(view_time * 1.7 + v_var * 20.0)) * mix(0.55, 1.0, v_col.g) * (1.0 + 1.2 * night);
	} else if (v_class > 2.5 && v_class < 3.5) {
		rough = 0.5;
		metal = 0.55;
	} else if (v_class > 3.5) {
		col *= 0.85 + 0.3 * v_var;
		rough = 0.9;
		if (abs(v_wnrm.y) < 0.35) {
			vec2 win = facade_windows(v_wpos, v_wnrm, v_variant, v_base_y, v_height, v_var);
			if (win.x > 0.5) {
				// lit windows at night (about 55 % of them), dark reflective glass by day
				float on = step(win.y, 0.55) * night;
				vec3 warm = mix(vec3(1.0, 0.52, 0.18), vec3(0.55, 0.72, 1.0), step(0.86, win.y));
				col = mix(vec3(0.05, 0.08, 0.12), vec3(0.03), on);
				rough = 0.12;
				metal = 0.35;
				emis = warm * on * 1.0;
			}
		}
	}
	float vis = smoothstep(0.3, 0.7, v_fow.y);
	float dim = mix(1.0, 0.45, fow_fog_dim);
	col *= mix(dim, 1.0, vis);
	emis *= vis;
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = emis;
}
