// Radial blob shadow quad (unlit, alpha-blended, no depth write).
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform float strength = 0.5;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float a = 1.0 - smoothstep(0.1, 1.0, length(p));
	ALBEDO = vec3(0.0);
	ALPHA = a * a * strength;
}
