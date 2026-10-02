// Demo unit shader: shows how unit materials consume the GLOBAL fog-of-war texture.
// Enemy units are hidden unless their cell is visible; own/allied units are dimmed when fogged.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://shaders/fog_of_war.gdshaderinc"

// Team colour and enemy flag are plain per-material uniforms (one material per player colour), NOT instance uniforms:
// Compatibility caps instance-uniform users at ~4096 items (about 256 instances here) and Forward+ can only auto-instance
// meshes that share a material anyway, so 8 player materials are the cheap, portable choice.
uniform vec3 team_color : source_color = vec3(0.9, 0.2, 0.1);
uniform float hide_in_fog = 0.0;   // 1 for enemy units
uniform float fow_enabled = 1.0;

varying vec3 v_col;
varying float v_class;
varying float v_vis;

void vertex() {
	v_col = COLOR.rgb;
	v_class = UV.x;
	v_vis = fow_enabled > 0.5 ? fow_sample(NODE_POSITION_WORLD.xz).y : 1.0;
}

void fragment() {
	if (hide_in_fog > 0.5 && v_vis < 0.55) {
		discard;
	}
	float vis = smoothstep(0.3, 0.7, v_vis);
	vec3 col = v_col;
	if (v_class > 2.5) {
		col = mix(col, team_color * 0.38, 0.9);   // team colour panels use class 3
	}
	ALBEDO = col * mix(0.5, 1.0, vis);
	ROUGHNESS = 0.6;
	METALLIC = v_class > 2.5 ? 0.3 : 0.5;
}
