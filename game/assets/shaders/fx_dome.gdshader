// Energy dome (microwave array, interception zone). Mesh: unit hemisphere (y >= 0) with normals.
// Instance transform = translate * uniform scale(R). INSTANCE_CUSTOM: x spawn, y lifetime, z palette+seed, w colour mode.
shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, fog_disabled;

#include "res://assets/shaders/fx_common.gdshaderinc"

// Colour: INSTANCE_CUSTOM.w > 0.5 = INTERCEPT (indigo lattice), else MICROWAVE (icy white-cyan); the uniform `mode` forces INTERCEPT when 1.
uniform int mode = 0;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

varying flat vec4 v_inst;
varying vec4 v_data; // age, local height 0..1

float hex_dist(vec2 p) {
	p = abs(p);
	float c = dot(p, normalize(vec2(1.0, 1.73)));
	return max(c, p.x);
}

// x,y = local cell coords, z = distance to nearest hex edge (0 on the edge), w = per-cell random
vec4 hex_coords(vec2 uv) {
	vec2 r = vec2(1.0, 1.73);
	vec2 h = r * 0.5;
	vec2 a = mod(uv, r) - h;
	vec2 b = mod(uv - h, r) - h;
	vec2 gv = dot(a, a) < dot(b, b) ? a : b;
	float y = 0.5 - hex_dist(gv);
	vec2 id = uv - gv;
	return vec4(gv, y, fx_hash(dot(id, vec2(12.9, 78.2))));
}

void vertex() {
	vec4 ic = INSTANCE_CUSTOM;
	float age = (fx_time - ic.x) / max(ic.y, 0.001);
	bool dead = (age < 0.0 || age >= 1.0);
	age = clamp(age, 0.0, 0.999);
	float grow = 1.0 - pow(1.0 - clamp(age / 0.22, 0.0, 1.0), 3.0);
	v_data = vec4(age, VERTEX.y, 0.0, 0.0);
	v_inst = ic;
	VERTEX *= dead ? 0.0 : grow;
}

void fragment() {
	float age = v_data.x;
	float h = v_data.y;
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float rim = pow(1.0 - facing, 3.0);
	vec4 hx = hex_coords(vec2(UV.x * 64.0, UV.y * 20.0));
	float line = 1.0 - smoothstep(0.0, 0.045, hx.z);
	float wave = exp(-pow((h - fract(fx_time * 0.28)) * 5.0, 2.0));
	float pulse = 0.5 + 0.5 * sin(fx_time * 6.0 + hx.w * 6.2831);
	float env = smoothstep(0.0, 0.08, age) * (1.0 - smoothstep(0.78, 1.0, age));
	// Microwave: cyan lattice with a pale #DFF3FF edge (art direction 5.13.4); interception: indigo lattice, saffron flashes come from the flash effect.
	bool intercept = !(mode == 0 && v_inst.w < 0.5);
	vec3 line_col = intercept ? vec3(0.30, 0.34, 1.0) : vec3(0.20, 0.72, 1.0);
	vec3 edge_col = intercept ? vec3(0.62, 0.66, 1.0) : vec3(0.87, 0.95, 1.0);
	// Additive glow only on thin lattice lines, the silhouette rim and the travelling wave: no flat fill, so the ground under the dome stays
	// readable at any zoom. The inner face (the camera is often inside a big dome) is much fainter than the outer one, and an extra fade
	// removes the glow where the camera is close to the shell (the "milky" look of the first version came from the fill + a white-hot line colour).
	float outer = FRONT_FACING ? 1.0 : 0.25;
	float near_fade = smoothstep(1.5, 9.0, length(VERTEX));
	vec3 glow = line_col * line * (0.16 + 0.75 * wave + 0.18 * pulse * hx.w) + edge_col * (rim * 0.34 + wave * 0.03) + line_col * hx.w * pulse * 0.012 * (1.0 - line);
	ALBEDO = glow * outer * near_fade * env;
	ALPHA = 0.015 * env;
}
