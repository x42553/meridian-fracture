// Radial blob shadow quad (unlit, alpha-blended, no depth write): the Low-preset contact shadow (one MultiMesh, one draw call).
// Per-instance alpha comes from the instance colour (aircraft: 1 - altitude / 40).
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform float strength = 0.5;

varying float v_alpha;

void vertex() {
	v_alpha = COLOR.a;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float a = 1.0 - smoothstep(0.1, 1.0, length(p));
	ALBEDO = vec3(0.0);
	ALPHA = a * a * strength * v_alpha;
}
