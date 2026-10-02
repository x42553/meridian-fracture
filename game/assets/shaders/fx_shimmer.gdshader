// Heat-shimmer ribbon (thermal beam haze, rising heat over burning wrecks). Same instance encoding as
// fx_ribbon.gdshader (basis.y = path, origin = A, INSTANCE_CUSTOM.w = width). Refracts the screen texture.
// NOTE: the screen texture only contains what was rendered BEFORE the transparent pass, so this material
// must have a lower render_priority than smoke/fire or it would overwrite them with the opaque scene.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled, skip_vertex_transform;

#include "res://assets/shaders/fx_common.gdshaderinc"

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float strength = 1.0;

varying flat float v_len;
varying vec4 v_data; // across, s, 0, age

void vertex() {
	vec4 ic = INSTANCE_CUSTOM;
	float t = fx_time - ic.x;
	float age = t / max(ic.y, 0.001);
	bool dead = (t < 0.0 || age >= 1.0);
	age = clamp(age, 0.0, 0.999);
	float across = VERTEX.x * 2.0;
	float s = UV.y;
	vec3 A = MODEL_MATRIX[3].xyz;
	vec3 axis = MODEL_MATRIX[1].xyz;
	vec3 arc = MODEL_MATRIX[0].xyz;
	vec3 P = A + axis * s + arc * (4.0 * s * (1.0 - s));
	vec3 dP = axis + arc * (4.0 - 8.0 * s);
	vec3 vp = (VIEW_MATRIX * vec4(P, 1.0)).xyz;
	vec2 dv = (VIEW_MATRIX * vec4(dP, 0.0)).xy;
	float dl = length(dv);
	vec2 dir2 = dl > 0.0001 ? dv / dl : vec2(0.0, 1.0);
	vec2 perp = vec2(-dir2.y, dir2.x);
	v_len = length(axis);
	v_data = vec4(across, s, 0.0, age);
	VERTEX = vec3(vp.xy + perp * (across * 0.5 * ic.w), vp.z);
	if (dead) {
		VERTEX = vec3(0.0, 0.0, 100.0);
	}
}

void fragment() {
	float a1 = abs(v_data.x);
	float age = v_data.w;
	float env = smoothstep(0.0, 0.08, age) * (1.0 - smoothstep(0.85, 1.0, age));
	float mask = pow(1.0 - a1, 1.3) * env;
	vec2 nuv = vec2(v_data.y * v_len * 0.09 - fx_time * 0.8, v_data.x * 0.35 + fx_time * 0.25);
	vec2 off = (texture(noise_tex, nuv).rg - 0.5) * 0.09 * mask * strength;
	ALBEDO = texture(screen_tex, SCREEN_UV + off).rgb;
	ALPHA = clamp(mask * 2.0, 0.0, 1.0);
}
