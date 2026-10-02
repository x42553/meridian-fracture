// Benchmark twin of fx_sprites FIRE mode for GPUParticles3D / CPUParticles3D draw passes, so the
// fragment cost matches the MultiMesh path and only the particle-system overhead differs.
// Particle INSTANCE_CUSTOM: x = rotation, y = normalised age, z = anim frame.
shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, fog_disabled, skip_vertex_transform;

#include "res://shaders/fx_common.gdshaderinc"

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D ramp_tex : filter_linear, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;
uniform float soft_depth = 0.8;
uniform vec2 depth_ndc = vec2(1.0, 0.0);

varying vec4 v_rand;
varying vec3 v_data;
varying vec2 v_uv;

void vertex() {
	float age = clamp(INSTANCE_CUSTOM.y, 0.0, 1.0);
	float id = float(INSTANCE_ID);
	v_rand = vec4(fx_hash(id * 1.7 + 0.11), fx_hash(id * 3.1 + 0.37), fx_hash(id * 5.3 + 0.71), fx_hash(id * 7.9 + 0.93));
	float sc = length(MODEL_MATRIX[0].xyz);
	vec3 vc = (VIEW_MATRIX * vec4(MODEL_MATRIX[3].xyz, 1.0)).xyz;
	vec2 q = fx_rot(VERTEX.xy, INSTANCE_CUSTOM.x);
	VERTEX = vc + vec3(q * sc, 0.0);
	v_uv = UV;
	v_data = vec3(age, 0.0, -VERTEX.z);
}

void fragment() {
	float age = v_data.x;
	vec2 p = v_uv * 2.0 - 1.0;
	float sd = 1.0;
	if (soft_depth > 0.0) {
		float d = textureLod(depth_tex, SCREEN_UV, 0.0).r;
		vec4 sv = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d * depth_ndc.x + depth_ndc.y, 1.0);
		sd = clamp((-sv.z / sv.w - v_data.z) / soft_depth, 0.0, 1.0);
	}
	vec2 nuv = v_uv * 0.6 + v_rand.xy * 9.0 + vec2(0.0, -age * 0.4);
	vec4 n = texture(noise_tex, nuv);
	float shape = 1.0 - length(p) + (n.r - 0.5) * 1.0 + (n.g - 0.5) * 0.35;
	float dens = shape - age * 0.85;
	float m = smoothstep(0.0, 0.3, dens);
	float heat = clamp((shape - 0.15 + (n.b - 0.5) * 0.5) * 1.5, 0.0, 1.0) * pow(1.0 - age, 1.25);
	vec4 rc = texture(ramp_tex, vec2(heat, 0.5));
	float fade = 1.0 - smoothstep(0.7, 1.0, age);
	ALBEDO = rc.rgb * m * fade * sd;
	ALPHA = rc.a * m * fade * sd;
}
