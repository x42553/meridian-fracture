// Decoration shader for MultiMesh trees / rocks / crystals / scrap: vertex-shader wind sway (world-space gust
// direction, per-instance phase from INSTANCE_CUSTOM.x), foliage palette from the mood, emissive crystals,
// fog of war (hidden in shroud, dimmed in fog). Sway also runs in the shadow pass so shadows move with the crowns.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_back;

#include "res://shaders/fog_of_war.gdshaderinc"
#include "res://shaders/atmosphere.gdshaderinc"

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
varying vec2 v_fow;

void vertex() {
	mat3 m3 = mat3(MODEL_MATRIX[0].xyz, MODEL_MATRIX[1].xyz, MODEL_MATRIX[2].xyz);
	vec3 origin = MODEL_MATRIX[3].xyz;
	float w = COLOR.a;
	float ph = INSTANCE_CUSTOM.x;
	float g1 = sin(TIME * wind_speed + dot(origin.xz, wind_dir) * wind_gust_scale * 6.2831 + ph * 0.25);
	float g2 = sin(TIME * wind_speed * 0.47 + dot(origin.xz, vec2(-wind_dir.y, wind_dir.x)) * wind_gust_scale * 3.1);
	float flutter = sin(TIME * wind_speed * 4.3 + dot(VERTEX, vec3(2.1, 3.3, 2.7)) + ph) * 0.18;
	float amt = (g1 * 0.6 + g2 * 0.4 + 0.35 + flutter * step(0.01, w)) * wind_strength * w;
	vec3 world_off = vec3(wind_dir.x, 0.0, wind_dir.y) * amt;
	float s2 = max(dot(m3[0], m3[0]), 1e-4);
	VERTEX += (transpose(m3) * world_off) / s2;
	v_col = clamp(COLOR.rgb, vec3(0.0), vec3(1.0));
	v_class = UV.x;
	v_var = clamp(INSTANCE_CUSTOM.y, 0.0, 1.0);
	v_em = INSTANCE_CUSTOM.z;
	v_fow = fow_enabled > 0.5 ? fow_sample(origin.xz) : vec2(1.0);
}

void fragment() {
	if (v_fow.x < 0.5) {
		discard;
	}
	vec3 col = v_col;
	float rough = 0.85;
	float metal = 0.0;
	vec3 emis = vec3(0.0);
	if (v_class > 0.5 && v_class < 1.5) {
		col *= mix(foliage_a, foliage_b, v_var);
		rough = 0.8;
	} else if (v_class > 1.5 && v_class < 2.5) {
		vec3 hue = mix(vec3(0.0, 0.9, 0.7), vec3(0.55, 0.12, 1.0), step(0.62, v_var));
		col = hue * 0.12;
		rough = 0.10;
		metal = 0.25;
		emis = hue * v_em * 1.9 * (0.85 + 0.35 * sin(TIME * 1.7 + v_var * 20.0)) * mix(0.55, 1.0, v_col.g);
	} else if (v_class > 2.5) {
		rough = 0.5;
		metal = 0.55;
	}
	float vis = smoothstep(0.3, 0.7, v_fow.y);
	col *= mix(0.45, 1.0, vis);
	emis *= vis;
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = emis;
}
